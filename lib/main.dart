import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'db/database.dart';

class NativeAlarmScheduler {
  NativeAlarmScheduler();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _nativeAlarmChannel =
      MethodChannel('crewclock/native_alarm');
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );

    _initialized = true;
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
    await _notifications.cancelAll();

    if (requestExactPermissions && records.isNotEmpty) {
      await _requestNotificationPermissions();
      await _requestAlarmPermissions();
    }

    if (Platform.isAndroid) {
      await _nativeAlarmChannel.invokeMethod<void>(
        'scheduleAlarms',
        jsonEncode(records),
      );
      return;
    }

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
      if (Platform.isIOS && scheduledCount >= 64) break;

      final id = _stableNotificationId(record['id']?.toString() ?? '');
      final label = (record['lbl']?.toString().trim().isNotEmpty ?? false)
          ? record['lbl'].toString()
          : 'CrewClock Alarm';
      final route = _routeText(record);
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
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'crewclock_alarm_channel_continuous',
        'CrewClock Alarms',
        channelDescription: 'Flight and direct alarm notifications',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduledAt,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (_) {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduledAt,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }

  Future<void> _requestNotificationPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _notifications
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _requestAlarmPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestExactAlarmsPermission();
    await android?.requestFullScreenIntentPermission();

    if (Platform.isAndroid) {
      const channel = MethodChannel('crewclock/battery_optimization');
      try {
        await channel.invokeMethod('requestIgnoreBatteryOptimizations');
      } catch (e) {
        debugPrint('Battery optimization request failed: $e');
      }
    }
  }

  Future<bool> chooseAlarmSound() async {
    if (!Platform.isAndroid) return false;
    final selected =
        await _nativeAlarmChannel.invokeMethod<String>('chooseAlarmSound');
    return selected != null;
  }

  Future<void> stopRingingAlarm() async {
    if (!Platform.isAndroid) return;
    await _nativeAlarmChannel.invokeMethod<void>('stopAlarm');
  }

  Future<void> reconcileDismissals() async {
    if (!Platform.isAndroid) return;
    final ids = await _nativeAlarmChannel
        .invokeListMethod<String>('getDismissedAlarmIds');
    if (ids == null || ids.isEmpty) return;
    await AppDatabase.instance.dismissAlarms(ids);
    await _nativeAlarmChannel.invokeMethod<void>('acknowledgeDismissals', ids);
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CrewClockApp());
}

class CrewClockApp extends StatelessWidget {
  const CrewClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CrewClockHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CrewClockHome extends StatefulWidget {
  const CrewClockHome({super.key});

  @override
  State<CrewClockHome> createState() => _CrewClockHomeState();
}

class _CrewClockHomeState extends State<CrewClockHome>
    with WidgetsBindingObserver {
  late final WebViewController controller;
  final NativeAlarmScheduler _alarmScheduler = NativeAlarmScheduler();
  Future<void> _bridgeQueue = Future<void>.value();
  bool _pageReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pageReady) {
      _enqueue(_initNativeAlarms);
    }
  }

  void _enqueue(Future<void> Function() action) {
    _bridgeQueue =
        _bridgeQueue.then((_) => action()).catchError((Object e) async {
      debugPrint('[CrewClock] $e');
      if (!mounted) return;
      await controller.runJavaScript(
        "toast('Could not schedule alarms. Check notification and exact alarm permissions in Settings.', 'er');",
      );
    });
  }

  Future<void> _initNativeAlarms() async {
    await _alarmScheduler.init();
    await _alarmScheduler.reconcileDismissals();
    final data = await AppDatabase.instance.getAlarmsState();
    await controller.runJavaScript('syncAlarmsFromDB(${jsonEncode(data)});');
    await _alarmScheduler.scheduleFromRecords(data);
  }

  void _initWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.url.startsWith('file:') || request.url == 'about:blank'
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent,
          onWebResourceError: (WebResourceError error) {
            debugPrint('[WebView] Error: ${error.description}');
          },
          onPageFinished: (String url) async {
            _pageReady = true;
            _enqueue(() async {
              await _alarmScheduler.reconcileDismissals();
              final data = await AppDatabase.instance.getAlarmsState();
              await controller.runJavaScript(
                'syncAlarmsFromDB(${jsonEncode(data)});',
              );
              if (Platform.isIOS) {
                await controller.runJavaScript(
                  "document.getElementById('platformAlarmGuide').textContent = "
                  "'On iPhone, background reminders use notification sounds, not a continuous alarm. Silent mode and Focus may silence them. Only the next 64 reminders are scheduled; reopen CrewClock regularly to schedule later reminders.';",
                );
              }
              await _alarmScheduler.scheduleFromRecords(data);
            });
          },
        ),
      )
      ..addJavaScriptChannel(
        'crewclock',
        onMessageReceived: (message) async {
          _enqueue(() async {
            if (await _handleCrewClockCommand(message.message)) return;

            await AppDatabase.instance.saveAlarmsState(message.message);
            await _alarmScheduler.scheduleFromJsonString(message.message);
          });
        },
      )
      ..loadFlutterAsset('assets/html/index.html');

    _initFilePicker();
  }

  Future<bool> _handleCrewClockCommand(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;

      switch (decoded['type']) {
        case 'CHOOSE_ALARM_SOUND':
          if (!Platform.isAndroid) {
            await controller.runJavaScript(
              "toast('iPhone reminders use the default notification sound', 'in');",
            );
            return true;
          }
          final selected = await _alarmScheduler.chooseAlarmSound();
          if (!selected) return true;
          await controller.runJavaScript(
            "toast('Alarm sound selected', 'ok');",
          );
          return true;
        case 'STOP_RINGING_ALARM':
          await _alarmScheduler.stopRingingAlarm();
          if (decoded['silent'] != true) {
            await controller.runJavaScript(
              "toast('Alarm stopped', 'ok');",
            );
          }
          return true;
        default:
          return false;
      }
    } on FormatException {
      return false;
    }
  }

  void _initFilePicker() {
    final platformController = controller.platform;

    if (platformController is AndroidWebViewController) {
      platformController.setOnShowFileSelector((params) async {
        try {
          FilePickerResult? result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['ics', 'ical', 'txt'],
          );

          if (result == null || result.files.single.path == null) {
            return [];
          }

          final file = File(result.files.single.path!);
          final content = await file.readAsString();

          final safeContent = jsonEncode(content);

          await controller.runJavaScript('''
            (function() {
              try {
              var newFlights = parseICS($safeContent);

              if (newFlights && newFlights.length) {
                var addedCount = replaceMonthFlights(newFlights);

                if (addedCount > 0) {
                  initFlightToggles();
                  autoRegisterAll();
                  saveFlights();
                  renderHomeFlightList();
                  renderSheetFalWrap();
                  renderCal();
                  renderDaySchedule(calSelDate);
                  toast('Schedule updated! ' + addedCount + ' flights applied', 'ok');
                }
              } else {
                toast('No valid flights found', 'er');
              }

              closeUploadSheet();
              } catch (error) {
                toast('Could not import calendar: ' + error.message, 'er');
              }
            })();
          ''');
        } catch (e) {
          debugPrint("FilePicker error: $e");
        }

        return [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: WebViewWidget(controller: controller),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload CrewClock',
                  onPressed: () => controller.reload(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
