import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../db/database.dart';

class NativeAlarmScheduler {
  NativeAlarmScheduler();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel channel = MethodChannel('crewclock/native_alarm');
  bool _initialized = false;
  bool systemAlarmEnabled = false;
  String? _iosSound;
  bool privateLabels = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory('crewclock_alarm', actions: [
          DarwinNotificationAction.plain('crewclock.stop', 'Stop'),
        ]),
      ],
    );

    await _notifications.initialize(
      InitializationSettings(
        iOS: darwinSettings,
      ),
    );

    if (Platform.isIOS) {
      privateLabels =
          await channel.invokeMethod<bool>('getAlarmPrivacy') ?? false;
    }
    _initialized = true;
  }

  Future<void> requestStartupPermissions() async {
    await init();
    if (!Platform.isIOS) return;
    await _requestNotificationPermissions();
    systemAlarmEnabled =
        await channel.invokeMethod<bool>('requestAlarmPermission') ?? false;
  }

  Future<void> scheduleFromJsonString(
    String raw, {
    bool requestExactPermissions = true,
  }) async {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return;
      await scheduleFromRecords(
        parsed.cast<dynamic>(),
        requestExactPermissions: requestExactPermissions,
      );
    } catch (e) {
      debugPrint('[NativeAlarmScheduler] invalid alarm payload: $e');
      rethrow;
    }
  }

  Future<void> scheduleFromRecords(
    List<dynamic> records, {
    bool requestExactPermissions = false,
  }) async {
    await init();
    if (Platform.isIOS) {
      if (requestExactPermissions && records.isNotEmpty) {
        await _requestNotificationPermissions();
      }
      systemAlarmEnabled = await channel.invokeMethod<bool>(
            'scheduleAlarms',
            {'records': records, 'requestPermission': requestExactPermissions},
          ) ??
          false;
      _iosSound = await channel.invokeMethod<String>('getAlarmSound');
      // Keep delivered reminders; only replace pending schedules.
      await channel.invokeMethod<void>('cancelPending');
      if (systemAlarmEnabled) return;
    } else {
      await _notifications.cancelAll();
    }

    final availableSlots = Platform.isIOS
        ? await channel.invokeMethod<int>('getAvailableNotificationSlots') ?? 0
        : 64;
    final now = DateTime.now().toUtc();
    final sorted = records.whereType<Map>().toList()
      ..sort((a, b) =>
          (DateTime.tryParse(a['time']?.toString() ?? '') ?? DateTime(9999))
              .compareTo(DateTime.tryParse(b['time']?.toString() ?? '') ??
                  DateTime(9999)));
    var scheduledCount = 0;
    for (final record in sorted) {
      final time = DateTime.tryParse(record['time']?.toString() ?? '');
      if (time == null) continue;

      final alarmTime = time.toUtc();
      if (!alarmTime.isAfter(now)) continue;
      if (!_asBool(record['armed'])) continue;
      if (_asBool(record['dism']) || _asBool(record['missed'])) continue;
      if (Platform.isIOS && scheduledCount >= availableSlots) break;

      final id = _stableNotificationId(record['id']?.toString() ?? '');
      final label = privateLabels
          ? 'CrewClock reminder'
          : (record['lbl']?.toString().trim().isNotEmpty ?? false)
              ? record['lbl'].toString()
              : 'CrewClock Alarm';
      final route = privateLabels ? '' : _routeText(record);
      final body = route.isEmpty
          ? 'Scheduled for ${_formatLocal(alarmTime)}'
          : '$route\n${_formatLocal(alarmTime)}';

      await _scheduleOne(
        id: id,
        title: label,
        body: body,
        alarmTimeUtc: alarmTime,
        payload: record['id']?.toString(),
      );
      scheduledCount++;
    }
  }

  Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime alarmTimeUtc,
    required String? payload,
  }) async {
    final scheduledAt = tz.TZDateTime.from(alarmTimeUtc, tz.UTC);
    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: _iosSound,
        categoryIdentifier: 'crewclock_alarm',
      ),
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledAt,
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> _requestNotificationPermissions() async {
    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<bool> chooseAlarmSound() async {
    if (!Platform.isIOS) return false;
    final selected = await channel.invokeMethod<String>('chooseAlarmSound');
    return selected != null;
  }

  Future<void> stopRingingAlarm() async {
    if (!Platform.isIOS) return;
    await channel.invokeMethod<void>('stopAlarm');
  }

  Future<void> reconcileDismissals() async {
    if (!Platform.isIOS) return;
    final ids = await channel.invokeListMethod<String>('getDismissedAlarmIds');
    if (ids == null || ids.isEmpty) return;
    await AppDatabase.instance.dismissAlarms(ids);
    await channel.invokeMethod<void>('acknowledgeDismissals', ids);
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  int _stableNotificationId(String source) {
    var hash = 0x811c9dc5;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  String _routeText(Map<dynamic, dynamic> record) {
    final fnum = record['fnum']?.toString() ?? '';
    final dep = record['depApt']?.toString() ?? '';
    final arr = record['arrApt']?.toString() ?? '';
    if (fnum.isEmpty && dep.isEmpty && arr.isEmpty) return '';
    final route = dep.isEmpty && arr.isEmpty ? '' : '$dep -> $arr';
    return [fnum, route].where((part) => part.trim().isNotEmpty).join(' ');
  }

  String _formatLocal(DateTime utc) {
    final local = utc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
