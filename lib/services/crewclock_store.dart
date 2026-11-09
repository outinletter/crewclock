import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import '../db/database.dart';
import 'alarm_scheduler.dart';
import 'roster_parser.dart';

class CrewClockStore extends ChangeNotifier {
  final NativeAlarmScheduler scheduler = NativeAlarmScheduler();
  final RosterParser parser = RosterParser();
  final AppDatabase db = AppDatabase.instance;
  List<Map<String, dynamic>> flights = [],
      alarms = [],
      intervals = [],
      duties = [];
  Map<String, dynamic> settings = {}, briefings = {}, statuses = {};
  bool ready = false, busy = false;
  Map<String, dynamic> alarmDiagnostics = {};
  String? get alarmWarning => alarmDiagnostics['alarmAllowed'] == false
      ? 'System alarms are disabled. Enable CrewClock alarms in iPhone Settings.'
      : alarmDiagnostics['notificationsAllowed'] == false
          ? 'Notifications are off. System alarms remain available, but notification alerts are disabled.'
          : null;
  String? error, migrationNotice, selectedFlight, pendingToolsAction;
  void Function(String action, String? flight)? openTools;
  Map<String, dynamic>? _demo, _demoState;
  Future<void> _tail = Future<void>.value();

  static const preparation = [
    'Roster and departure time',
    'Crew documents packed',
    'Passport & VISA',
    'Personal bag ready'
  ];
  static const defaults = {
    'baseOffs': [
      {'id': 'b1', 'h': 4, 'm': 30, 'lbl': 'Prepare for Duty'},
      {'id': 'b2', 'h': 4, 'm': 0, 'lbl': 'Depart for Airport'},
      {'id': 'b3', 'h': 0, 'm': 40, 'lbl': 'Boarding time'}
    ],
    'domOffs': [
      {'id': 'd1', 'h': 3, 'm': 30, 'lbl': 'Prepare for Duty'},
      {'id': 'd2', 'h': 3, 'm': 30, 'lbl': 'Depart for Airport'},
      {'id': 'd3', 'h': 0, 'm': 30, 'lbl': 'Boarding time'}
    ],
    'intlOffs': [
      {'id': 'i1', 'h': 3, 'm': 0, 'lbl': 'Wake Up (Overseas)'},
      {'id': 'i2', 'h': 2, 'm': 0, 'lbl': 'Hotel Checkout'},
      {'id': 'i3', 'h': 0, 'm': 40, 'lbl': 'Boarding time'}
    ],
  };
  List<String> baseAirports(
      {bool domestic = false, Map<String, dynamic>? configuration}) {
    final config = configuration ?? settings;
    final raw = config[domestic ? 'domesticBaseApt' : 'baseApt'];
    final codes = '${raw ?? (domestic ? 'GMP' : 'ICN')}'
        .toUpperCase()
        .split(RegExp(r'[,;\s]+'))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    return codes.isEmpty ? [domestic ? 'GMP' : 'ICN'] : codes;
  }

  bool get displayUTC => false;
  String deviceZone = 'UTC';
  String get personalZone => airportZone(home) ?? 'UTC';
  String? displayZone(String airport) =>
      displayUTC ? 'UTC' : airportZone(airport);
  String get timeSuffix => displayUTC ? 'Z' : 'L';
  List<Map<String, dynamic>> get schedulingRecords {
    final delay = (settings['backupMinutes'] as num?)?.toInt() ?? 0;
    return [
      ...alarms,
      if (delay > 0)
        for (final a in alarms)
          if (flag(a['armed']) &&
              !flag(a['dism']) &&
              DateTime.parse(a['time'])
                  .add(Duration(minutes: delay))
                  .isAfter(DateTime.now()))
            {
              ...a,
              'id': 'backup_${a['id']}',
              'backupOf': a['id'],
              'lbl': 'Backup · ${a['lbl']}',
              'time': DateTime.parse(a['time'])
                  .add(Duration(minutes: delay))
                  .toUtc()
                  .toIso8601String(),
            }
    ];
  }

  Future<void> setDisplayUTC(bool value) => change(() async {
        settings['displayUTC'] = value;
        await _persist();
        await publishSurfaces();
      });
  Future<void> addRelativeAlarm(String label, int minutes) async {
    if (minutes < 1 || minutes > 10080) {
      throw const FormatException('Choose 1 minute to 7 days.');
    }
    await saveAlarm({
      'id': 'timer_${id()}',
      'lbl': label,
      'time': DateTime.now()
          .toUtc()
          .add(Duration(minutes: minutes))
          .toIso8601String(),
      // Timers are fixed, one-shot alarms. Keep them distinct from both
      // personal alarms (`direct`) and repeating reminders (`intervals`).
      'type': 'timer',
      'armed': true,
      'dism': false,
      'missed': false,
      'elapsedAlarm': true,
      'durationMinutes': minutes,
      'oneShot': true
    });
  }

  String get home => baseAirports().first;
  String get domesticHome => baseAirports(domestic: true).first;
  bool get dark => settings['dark'] == true;
  bool flag(dynamic value) => value == true || value == 1 || value == 'true';
  String id() => DateTime.now().microsecondsSinceEpoch.toString();
  List<Map<String, dynamic>> maps(dynamic value) => (value as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x as Map))
      .toList();
  DateTime departure(Map f) =>
      DateTime.parse(f['departureUtc'] as String).toUtc();
  String key(Map f) =>
      '${f['flight']}|${f['depApt']}|${departure(f).toIso8601String()}';
  String? airportZone(String airport) =>
      (settings['airportZones'] as Map?)?[airport] as String? ??
      parser.zone(airport);
  DateTime zoned(DateTime time, String? zone) =>
      tz.TZDateTime.from(time, tz.getLocation(zone ?? 'UTC'));
  String two(int n) => n.toString().padLeft(2, '0');
  String date(DateTime at) => '${at.year}-${two(at.month)}-${two(at.day)}';
  String displayDate(DateTime at) => '${date(at)} ${[
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun'
      ][at.weekday - 1]}';
  String clock(DateTime at) => '${two(at.hour)}:${two(at.minute)}';
  String stamp(DateTime at, String? zone) {
    final d = zoned(at, zone);
    return '${date(d)} ${clock(d)}';
  }

  String flightLabel(Map f) =>
      '${date(zoned(departure(f), airportZone('${f['depApt']}')))} ${f['flight']} ${f['depApt']} → ${f['arrApt']}';
  List<Map<String, dynamic>> sortedFlights() =>
      [...flights]..sort((a, b) => departure(a).compareTo(departure(b)));
  Map<String, dynamic>? flightById(String? id) {
    for (final f in flights) {
      if (f['id'] == id) return f;
    }
    return null;
  }

  List<Map<String, dynamic>> flightAlarms(Map f) => alarms
      .where((a) =>
          a['fnum'] == f['flight'] &&
          a['depApt'] == f['depApt'] &&
          a['arrApt'] == f['arrApt'] &&
          DateTime.tryParse('${a['dep']}') == departure(f))
      .toList()
    ..sort((a, b) =>
        DateTime.parse(a['time']).compareTo(DateTime.parse(b['time'])));

  Future<void> initialize() async {
    error = null;
    try {
      await scheduler.init();
      await parser.initialize();
      alarms = maps(await db.getAlarmsState());
      final saved = await db.loadNativeState();
      if (saved != null) {
        flights = maps(saved['flights']);
        duties = maps(saved['duties']);
        settings = Map<String, dynamic>.from(saved['settings'] as Map? ?? {});
        briefings = Map<String, dynamic>.from(saved['briefings'] as Map? ?? {});
        intervals = maps(saved['intervals']);
      } else {
        final legacy = await NativeAlarmScheduler.channel
                .invokeMapMethod<String, dynamic>('readLegacyData') ??
            {};
        dynamic read(String k, dynamic fallback) {
          try {
            return jsonDecode(legacy[k] as String? ?? 'null') ?? fallback;
          } catch (_) {
            return fallback;
          }
        }

        settings = Map<String, dynamic>.from(read('crewclock_v5', {}));
        settings['dark'] = legacy['crewclock_dark'] == '1';
        settings['airportZones'] = read('crewclock_airport_zones', {});
        briefings =
            Map<String, dynamic>.from(read('crewclock_briefings_v1', {}));
        intervals = maps(read('crewclock_intervals', []));
        for (final f in maps(read('crewclock_flights', []))) {
          try {
            f['departureUtc'] ??= parser
                .localInstant(
                    f['date'],
                    f['depTime'],
                    airportZone(f['depApt']) ??
                        (throw const FormatException(
                            'Missing departure time zone')))
                .toIso8601String();
            f['departureUtc'] = departure(f).toIso8601String();
            flights.add(f);
          } catch (_) {
            migrationNotice =
                'Check your roster dates and home base after updating.';
          }
        }
        if (flights.isEmpty && alarms.any((a) => a['dep'] != null)) {
          final seen = <String>{};
          for (final a in alarms.where((a) => a['dep'] != null)) {
            final dep = DateTime.tryParse('${a['dep']}');
            if (dep == null) continue;
            final identity = '${a['fnum']}|${a['depApt']}|$dep';
            if (!seen.add(identity)) continue;
            flights.add({
              'id': 'restored_${a['id']}',
              'flight': a['fnum'] ?? 'Flight',
              'depApt': a['depApt'] ?? '',
              'arrApt': a['arrApt'] ?? '',
              'departureUtc': dep.toUtc().toIso8601String(),
              'arrivalUtc': null,
              'arrTime': a['arrTime'],
              'type': a['type']
            });
          }
          migrationNotice =
              'Your saved alarms were restored. Check your home base and preparation items.';
        }
      }
      intervals = maps(await NativeAlarmScheduler.channel
          .invokeMethod<List<dynamic>>('readIntervalAlarms'));
      for (final flight in flights) {
        flight['id'] = '${flight['id'] ?? id()}';
      }
      final overrides = <String, String>{};
      for (final entry in ((settings['airportZones'] as Map?) ?? {}).entries) {
        try {
          parser.location('${entry.value}');
          overrides['${entry.key}'] = '${entry.value}';
        } catch (_) {}
      }
      settings['airportZones'] = overrides;
      settings.putIfAbsent('baseApt', () => 'ICN');
      for (final removed in [
        'displayUTC',
        'personalTimeBasis',
        'backupMinutes'
      ]) {
        settings.remove(removed);
      }
      for (final a in alarms) {
        if (a['timeBasis'] == 'device') a['timeBasis'] = 'fixed';
      }
      await db.saveAlarmsState(jsonEncode(alarms));
      await _persist();
      try {
        await scheduler.requestStartupPermissions();
        final domestic = maps(settings['domOffs']);
        final oldDefault = domestic.any((p) =>
            '${p['lbl']}'.trim().toLowerCase() == 'prepare for duty' &&
            p['h'] == 4 &&
            p['m'] == 0);
        if (oldDefault) {
          await saveSettings({
            ...settings,
            'domOffs': domestic
                .map((p) =>
                    '${p['lbl']}'.trim().toLowerCase() == 'prepare for duty' &&
                            p['h'] == 4 &&
                            p['m'] == 0
                        ? {...p, 'h': 3, 'm': 30}
                        : p)
                .toList()
          });
        } else {
          await scheduler.scheduleFromRecords(schedulingRecords);
        }
      } catch (_) {
        error =
            'Your schedules are available, but alarm reservations could not be restored. Check CrewClock permissions in iPhone Settings and reopen the app.';
      }
      await refresh();
      ready = true;
    } catch (e) {
      error = 'Unable to load CrewClock: $e';
    }
    notifyListeners();
  }

  Future<void> _persist() => db.saveNativeState({
        'flights': flights,
        'duties': duties,
        'settings': settings,
        'briefings': briefings,
        'intervals': intervals
      });
  Future<T> change<T>(Future<T> Function() body) {
    final result = _tail.then((_) async {
      busy = true;
      notifyListeners();
      try {
        return await body();
      } finally {
        busy = false;
        notifyListeners();
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  String? surfaceError;
  Future<void> publishSurfaces() async {
    final upcoming = <Map<String, dynamic>>[];
    for (final alarm in schedulingRecords) {
      final status = statuses['${alarm['id']}'] as Map?;
      if (!['scheduled', 'alerting'].contains(status?['state'])) continue;
      final at = DateTime.tryParse('${alarm['time']}');
      if (at == null || !at.isAfter(DateTime.now())) continue;
      final dep =
          alarm['dep'] == null ? null : DateTime.tryParse('${alarm['dep']}');
      upcoming.add({
        'id': '${alarm['id']}',
        'label': '${alarm['lbl']}',
        'at': at.millisecondsSinceEpoch / 1000.0,
        'flightDeparture':
            dep == null ? null : dep.millisecondsSinceEpoch / 1000.0,
        'zone': displayUTC
            ? 'UTC'
            : alarm['zone'] ??
                airportZone('${alarm['depApt'] ?? home}') ??
                personalZone
      });
    }
    for (final alarm in intervals) {
      final status = statuses['${alarm['id']}'] as Map?;
      if (alarm['enabled'] != true ||
          !['scheduled', 'alerting'].contains(status?['state']) ||
          status?['next'] is! num) {
        continue;
      }
      upcoming.add({
        'id': '${alarm['id']}',
        'label': '${alarm['label']}',
        'at': (status!['next'] as num).toDouble() / 1000,
        'flightDeparture': null,
        'zone': displayUTC ? 'UTC' : personalZone
      });
    }
    upcoming.sort((a, b) => (a['at'] as num).compareTo(b['at'] as num));
    final nextFlight = sortedFlights()
        .where((f) => departure(f).isAfter(DateTime.now()))
        .firstOrNull;
    try {
      await NativeAlarmScheduler.channel
          .invokeMethod<void>('syncSystemSurfaces', {
        'payload': {
          'updatedAt': DateTime.now().millisecondsSinceEpoch / 1000.0,
          'alarms': upcoming,
          'flight': nextFlight == null ? '' : flightLabel(nextFlight),
          'flightNumber': nextFlight?['flight'],
          'departureDate': nextFlight == null
              ? null
              : date(zoned(
                  departure(nextFlight), airportZone(nextFlight['depApt']))),
          'departureAirport': nextFlight?['depApt'],
          'arrivalAirport': nextFlight?['arrApt'],
          'departureTime': nextFlight == null
              ? null
              : clock(zoned(
                  departure(nextFlight), airportZone(nextFlight['depApt']))),
          'arrivalTime': nextFlight == null || nextFlight['arrivalUtc'] == null
              ? null
              : clock(zoned(DateTime.parse('${nextFlight['arrivalUtc']}'),
                  airportZone(nextFlight['arrApt']))),
          'allowed': alarmDiagnostics['alarmAllowed'] == true
        },
        'liveActivity': settings['liveActivity'] == true
      });
      surfaceError = null;
    } catch (_) {
      surfaceError =
          'Unable to update a system surface. Check Live Activities permission in iPhone Settings. Alarm reservations are separate.';
    }
  }

  Future<void> refresh({bool notify = true}) async {
    alarmDiagnostics = Map<String, dynamic>.from(await NativeAlarmScheduler
            .channel
            .invokeMethod<Map>('getAlarmDiagnostics') ??
        {});
    deviceZone = '${alarmDiagnostics['deviceTimeZone'] ?? deviceZone}';
    await scheduler.reconcileDismissals();
    intervals = maps(await NativeAlarmScheduler.channel
        .invokeMethod<List<dynamic>>('readIntervalAlarms'));
    alarms = maps(await db.getAlarmsState());
    alarms.removeWhere((a) =>
        (a['type'] == 'direct' || a['type'] == 'timer') && flag(a['dism']));
    var floatingChanged = false;
    for (final alarm in alarms.where((a) =>
        a['type'] == 'direct' &&
        a['timeBasis'] == 'device' &&
        a['wallDate'] != null &&
        a['wallTime'] != null &&
        flag(a['armed']) &&
        !flag(a['dism']))) {
      if (alarm['zone'] == deviceZone) continue;
      try {
        final at = parser.localInstant(
            '${alarm['wallDate']}', '${alarm['wallTime']}', deviceZone);
        alarm['time'] = at.toIso8601String();
        alarm['zone'] = deviceZone;
        if (!at.isAfter(DateTime.now())) {
          alarm['armed'] = false;
          alarm['missed'] = true;
        }
        floatingChanged = true;
      } catch (_) {
        error =
            'A device-local alarm needs a valid local time after the time-zone change. Review Personal Alarms.';
      }
    }
    if (floatingChanged) {
      await db.saveAlarmsState(jsonEncode(alarms));
      await scheduler.scheduleFromRecords(schedulingRecords);
    }

    statuses = Map<String, dynamic>.from(await NativeAlarmScheduler.channel
            .invokeMethod<Map>('getAlarmStatus', schedulingRecords) ??
        {});
    await publishSurfaces();
    if (notify) notifyListeners();
  }

  Future<void> _saveAlarms({bool request = false}) async {
    await db.saveAlarmsState(jsonEncode(alarms));
    await _persist();
    try {
      await scheduler.scheduleFromRecords(schedulingRecords,
          requestExactPermissions: request);
      error = null;
    } catch (e) {
      error =
          'Alarms were saved but could not be reserved. Check CrewClock in iPhone Settings, then retry. $e';
      rethrow;
    } finally {
      await refresh();
    }
  }

  Future<void> retryScheduling() => change(() => _saveAlarms(request: true));
  String status(Map a) {
    if (flag(a['dism'])) return 'Done';
    if (flag(a['missed'])) return 'Missed';
    if (!flag(a['armed'])) return 'Paused';
    if (DateTime.parse(a['time']).isBefore(DateTime.now())) {
      return 'Time passed';
    }
    final s = (statuses['${a['id']}'] as Map?)?['state'];
    return {
          'scheduled': 'Scheduled',
          'alerting': 'Ringing',
          'notification': 'Notification only · sound depends on settings',
          'waiting': 'Waiting · not scheduled',
          'permission': 'Alarm permission required',
          'error': 'Scheduling failed'
        }[s] ??
        'Not scheduled';
  }

  String intervalStatus(Map a) {
    if (a['enabled'] != true) return 'Paused';
    final state = (statuses['${a['id']}'] as Map?)?['state'];
    return {
          'scheduled': 'Scheduled',
          'alerting': 'Ringing',
          'notification': 'Notification only',
          'waiting': 'Waiting · not scheduled',
          'permission': 'Alarm permission required',
          'error': 'Scheduling failed'
        }[state] ??
        'Not scheduled';
  }

  String? intervalNext(Map a) {
    if (a['enabled'] != true) return null;
    final status = statuses['${a['id']}'] as Map?;
    if (!['scheduled', 'alerting'].contains(status?['state']) ||
        status?['next'] is! num) {
      return null;
    }
    final at = DateTime.fromMillisecondsSinceEpoch(
        (status!['next'] as num).toInt(),
        isUtc: true);
    return 'Next: ${stamp(at, displayUTC ? 'UTC' : personalZone)} ($timeSuffix)';
  }

  String presetGroup(Map f, {Map<String, dynamic>? configuration}) {
    final config = configuration ?? settings;
    if (baseAirports(domestic: true, configuration: config)
        .contains(f['depApt'])) {
      return 'dom';
    }
    if (baseAirports(configuration: config).contains(f['depApt'])) {
      return 'base';
    }
    return 'intl';
  }

  List<Map<String, dynamic>> preparationPresets(String group) {
    final list = maps(settings['${group}Offs'] ?? defaults['${group}Offs']);
    int duration(Map p) =>
        (p['h'] as num).toInt() * 60 + (p['m'] as num).toInt();
    list.sort((a, b) {
      final order = duration(b).compareTo(duration(a));
      return order == 0 ? '${a['id']}'.compareTo('${b['id']}') : order;
    });
    return list;
  }

  List<Map<String, dynamic>> offsets(Map f) =>
      preparationPresets(presetGroup(f));

  List<Map<String, dynamic>> buildFlightAlarms(Map<String, dynamic> f) =>
      offsets(f)
          .map((o) => {
                'id': '${f['id']}_${o['id']}',
                'time': departure(f)
                    .subtract(Duration(
                        minutes: (o['h'] as num).toInt() * 60 +
                            (o['m'] as num).toInt()))
                    .toIso8601String(),
                'dep': departure(f).toIso8601String(),
                'lbl': o['lbl'],
                'type': f['depApt'] == home ? 'base' : 'intl',
                'armed': (settings['${presetGroup(f)}On'] as Map?)?[o['id']] !=
                    false,
                'dism': false,
                'missed': false,
                'fnum': f['flight'],
                'depApt': f['depApt'],
                'arrApt': f['arrApt'],
                'arrTime': f['arrTime'],
              })
          .toList();

  List<Map<String, dynamic>> pairingFor(Map flight) {
    final groups = <List<Map<String, dynamic>>>[];
    for (final current in sortedFlights()) {
      final previous = groups.isEmpty ? null : groups.last.last;
      final arrival = previous == null
          ? null
          : DateTime.tryParse('${previous['arrivalUtc']}');
      final gap =
          arrival == null ? null : departure(current).difference(arrival);
      final connects = previous != null &&
          previous['arrApt'] == current['depApt'] &&
          ![...baseAirports(), ...baseAirports(domestic: true)]
              .contains(previous['arrApt']) &&
          gap != null &&
          !gap.isNegative &&
          gap.inHours <= 96;
      if (connects) {
        groups.last.add(current);
      } else {
        groups.add([current]);
      }
    }
    return groups
            .where((g) => g.any((f) => key(f) == key(flight)))
            .firstOrNull ??
        [Map<String, dynamic>.from(flight)];
  }

  String scheduledGapBefore(Map flight) {
    final previous = sortedFlights()
        .where((f) => departure(f).isBefore(departure(flight)))
        .lastOrNull;
    final arrival = DateTime.tryParse('${previous?['arrivalUtc']}');
    if (arrival == null) return 'Ground gap unavailable';
    final gap = departure(flight).difference(arrival);
    if (gap.isNegative) return 'Overlapping flight times';
    return 'Scheduled ground gap: ${gap.inHours}h ${gap.inMinutes % 60}m · excludes duty/reporting';
  }

  Map<String, dynamic>? matchingFlight(Map<String, dynamic> f) {
    final exact = flightById(f['id']);
    final matches = exact != null
        ? [exact]
        : flights
            .where((old) =>
                old['flight'] == f['flight'] &&
                old['depApt'] == f['depApt'] &&
                old['arrApt'] == f['arrApt'] &&
                date(zoned(departure(old), airportZone(old['depApt']))) ==
                    date(zoned(departure(f), airportZone(f['depApt']))))
            .toList();
    if (matches.length > 1) {
      throw const FormatException(
          'Multiple flights match. Edit those flights individually.');
    }
    return matches.firstOrNull;
  }

  String importChange(Map<String, dynamic> f) {
    final old = matchingFlight(f);
    if (old == null) return 'New';
    return old['departureUtc'] == f['departureUtc'] &&
            old['arrivalUtc'] == f['arrivalUtc'] &&
            old['depApt'] == f['depApt'] &&
            old['arrApt'] == f['arrApt']
        ? 'Unchanged'
        : 'Changed';
  }

  String importTimes(Map<String, dynamic> f) {
    final arrival = DateTime.tryParse('${f['arrivalUtc']}');
    return '${stamp(departure(f), airportZone(f['depApt']))} ${f['depApt']} (L) → ${arrival == null ? 'arrival unknown' : stamp(arrival, airportZone(f['arrApt']))} ${f['arrApt']} (L)';
  }

  Future<void> importFlights(List<Map<String, dynamic>> imported,
          {List<Map<String, dynamic>>? nonFlights}) =>
      change(() async {
        if (nonFlights != null) {
          final dates = nonFlights.map((d) => d['date']).toSet();
          duties.removeWhere((d) => dates.contains(d['date']));
          duties.addAll(nonFlights);
        }
        for (final incoming in imported) {
          final zone = incoming['departureZone'] as String? ??
              airportZone(incoming['depApt']);
          if (zone == null) {
            throw const FormatException(
                'Confirm the departure airport time zone.');
          }
          parser.location(zone);
          departure(incoming);
        }
        for (final incoming in imported) {
          final f = Map<String, dynamic>.from(incoming);
          f['id'] = '${f['id'] ?? id()}';
          for (final pair in [
            ['depApt', 'departureZone'],
            ['arrApt', 'arrivalZone']
          ]) {
            final zone = f[pair[1]] as String?;
            if (zone != null && zone.isNotEmpty) {
              parser.location(zone);
              settings['airportZones'] = {
                ...((settings['airportZones'] as Map?) ?? {}),
                f[pair[0]]: zone
              };
            }
          }
          if (airportZone(f['depApt']) == null) {
            throw FormatException(
                'Confirm the departure airport time zone for ${f['depApt']} using manual entry.');
          }
          final match = matchingFlight(f);
          final matches = match == null ? <Map<String, dynamic>>[] : [match];
          if (matches.isNotEmpty) {
            final old = matches.first,
                records = flightAlarms(old),
                oldKey = key(old);
            f['id'] = old['id'];
            flights[flights.indexOf(old)] = f;
            final shift = departure(f).difference(departure(old));
            for (final a in records) {
              a['time'] =
                  DateTime.parse(a['time']).add(shift).toIso8601String();
              a['dep'] = f['departureUtc'];
              a['arrApt'] = f['arrApt'];
              a['depApt'] = f['depApt'];
              a['fnum'] = f['flight'];
            }
            if (briefings.containsKey(oldKey)) {
              briefings[key(f)] = briefings.remove(oldKey);
            }
            if (records.isEmpty) alarms.addAll(buildFlightAlarms(f));
          } else {
            f['id'] ??= id();
            flights.add(f);
            alarms.addAll(buildFlightAlarms(f));
          }
        }
        await _saveAlarms(request: true);
      });
  Future<void> deleteFlight(Map f) => change(() async {
        final rows = flightAlarms(f);
        alarms.removeWhere((a) => rows.contains(a));
        flights.remove(f);
        briefings.remove(key(f));
        await _saveAlarms();
      });
  Future<void> clearRoster() => change(() async {
        final ids = flights.expand(flightAlarms).map((a) => a['id']).toSet();
        alarms.removeWhere((a) =>
            ids.contains(a['id']) ||
            a['type'] == 'base' ||
            a['type'] == 'intl');
        flights.clear();
        duties.clear();
        briefings.clear();
        selectedFlight = null;
        pendingToolsAction = null;
        _demo = null;
        _demoState = null;
        await _saveAlarms();
      });
  Future<void> saveAlarm(Map<String, dynamic> record) => change(() async {
        alarms.removeWhere((a) => a['id'] == record['id']);
        alarms.add(record);
        await _saveAlarms(request: true);
      });
  Future<void> toggleAlarm(Map<String, dynamic> record, bool armed) =>
      change(() async {
        record['armed'] = armed;
        if (armed) {
          record['dism'] = false;
          record['missed'] = false;
        }
        await _saveAlarms(request: armed);
      });
  Future<void> deleteAlarm(Map record) => change(() async {
        alarms.removeWhere((a) => a['id'] == record['id']);
        await _saveAlarms();
      });
  Future<void> saveIntervals(List<Map<String, dynamic>> next) =>
      change(() async {
        final result = await NativeAlarmScheduler.channel
            .invokeMethod<List<dynamic>>('syncIntervalAlarms',
                {'records': next, 'requestPermission': true});
        intervals = maps(result ?? next);
        await _persist();
        await refresh();
      });
  Future<void> saveSettings(Map<String, dynamic> next) => change(() async {
        final previous = settings;
        settings = next;
        for (final f in flights) {
          final group = presetGroup(f);
          final oldGroup = presetGroup(f, configuration: previous);
          if (jsonEncode(
                      previous['${group}Offs'] ?? defaults['${group}Offs']) ==
                  jsonEncode(
                      next['${group}Offs'] ?? defaults['${group}Offs']) &&
              previous['baseApt'] == next['baseApt'] &&
              previous['domesticBaseApt'] == next['domesticBaseApt']) {
            continue;
          }
          final generated = buildFlightAlarms(f);
          final ids = generated.map((a) => a['id']).toSet();
          for (final updated in generated) {
            final index = alarms.indexWhere((a) => a['id'] == updated['id']);
            if (index >= 0) {
              // Preserve completion, pause state and manually added reminders.
              alarms[index]['time'] = updated['time'];
              alarms[index]['lbl'] = updated['lbl'];
            } else if (departure(f).isAfter(DateTime.now())) {
              alarms.add(updated);
            }
          }
          final prefix = '${f['id']}_';
          final oldIds =
              maps(previous['${oldGroup}Offs'] ?? defaults['${oldGroup}Offs'])
                  .map((p) => '$prefix${p['id']}')
                  .toSet();
          alarms.removeWhere(
              (a) => oldIds.contains(a['id']) && !ids.contains(a['id']));
        }
        await _saveAlarms(request: true);
      });
  Future<void> setPrivacy(bool value) => change(() async {
        await NativeAlarmScheduler.channel
            .invokeMethod<void>('setAlarmPrivacy', value);
        scheduler.privateLabels = value;
        await _saveAlarms();
        if (intervals.isNotEmpty) {
          intervals = maps(await NativeAlarmScheduler.channel
              .invokeMethod<List<dynamic>>('syncIntervalAlarms',
                  {'records': intervals, 'requestPermission': false}));
          await _persist();
        }
      });

  Map<String, dynamic> _preparation(Map f) {
    final state = _demo != null ? _demoState : briefings[key(f)];
    final result = state is Map
        ? Map<String, dynamic>.from(state)
        : {
            'tasks': preparation
                .map((s) => {'label': s, 'checkedAt': null})
                .toList(),
            'note': ''
          };
    result['tasks'] = maps(result['tasks']);
    for (var i = 0; i < (result['tasks'] as List).length; i++) {
      final task = result['tasks'][i];
      task['id'] ??= 'task_$i';
      if (task['label'] == 'Roster and departure time checked') {
        task['label'] = 'Roster and departure time';
      }
      if (['airport transport arranged', 'airport transit']
          .contains('${task['label']}'.toLowerCase())) {
        task['label'] = 'Passport & VISA';
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> snapshot(String? selected) async {
    if (!ready) throw StateError('Roster is loading');
    await refresh(notify: false);
    final sorted = sortedFlights();
    final now = DateTime.now();
    Map<String, dynamic>? f = _demo;
    for (final candidate in sorted) {
      if (key(candidate) == selected && departure(candidate).isAfter(now)) {
        f = candidate;
        break;
      }
    }
    f ??= sorted.where((x) => departure(x).isAfter(now)).firstOrNull;
    if (f == null) {
      return {
        'flight': null,
        'flights': [],
        'dark': dark,
        'hasSchedules': sorted.isNotEmpty
      };
    }
    final dep = departure(f),
        zone = airportZone(f['depApt']),
        state = _preparation(f);
    final rows = _demo == null ? flightAlarms(f) : buildFlightAlarms(f);
    final steps = rows.map((a) {
      final at = DateTime.parse(a['time']);
      final minutes = dep.difference(at).inMinutes;
      return {
        'id': a['id'],
        'minutesBefore': minutes,
        'armed': flag(a['armed']) && !flag(a['dism']),
        'label': a['lbl'],
        'at': at.toIso8601String(),
        'clock': clock(zoned(at, displayUTC ? 'UTC' : zone)),
        'offset': offsetText(minutes),
        'time': '${stamp(at, zone)} ${f!['depApt']}',
        'status': _demo == null ? status(a) : 'Preview'
      };
    }).toList();
    final upcoming = steps
        .where((s) =>
            s['armed'] == true &&
            DateTime.parse(s['at'] as String).isAfter(DateTime.now()))
        .toList();
    Map<String, dynamic> clockBox(String label, String? z) => {
          'label': label,
          'time': clock(zoned(dep, z)),
          'date': date(zoned(dep, z)),
          'dayOffset': DateTime.utc(
                  zoned(dep, z).year, zoned(dep, z).month, zoned(dep, z).day)
              .difference(DateTime.utc(zoned(dep, zone).year,
                  zoned(dep, zone).month, zoned(dep, zone).day))
              .inDays,
          'zone': z ?? 'UTC · confirm airport time zone'
        };
    final local = zoned(dep, zone);
    final arrival = DateTime.tryParse('${f['arrivalUtc']}');
    return {
      'key': key(f),
      'dark': dark,
      'timeSuffix': timeSuffix,
      'demo': _demo != null,
      'flight': {
        'number': f['flight'],
        'from': f['depApt'],
        'to': f['arrApt'],
        'departure': dep.toIso8601String(),
        'dateBadge': '${two(local.month)}/${two(local.day)} ${[
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun'
        ][local.weekday - 1]}',
        'departureTime': clock(zoned(dep, displayZone(f['depApt']))),
        'arrivalTime': arrival == null
            ? (f['arrTime'] ?? '—')
            : clock(zoned(arrival, displayZone(f['arrApt'])))
      },
      'flights': _demo != null
          ? []
          : sorted
              .map((x) => {
                    'key': key(x),
                    'departure': departure(x).toIso8601String(),
                    'label': flightLabel(x),
                    'date': date(zoned(departure(x), airportZone(x['depApt']))),
                    'number': x['flight'],
                    'from': x['depApt'],
                    'to': x['arrApt']
                  })
              .toList(),
      'clocks': [
        clockBox('${f['depApt']} departure', zone),
        clockBox('$home home', airportZone(home)),
        clockBox('UTC', 'UTC')
      ],
      'next': upcoming.firstOrNull,
      'steps': steps,
      'tasks': maps(state['tasks'])
          .map((t) => {
                ...t,
                'checkedText': t['checkedAt'] == null
                    ? null
                    : '${stamp(DateTime.parse(t['checkedAt']), zone)} ${f!['depApt']}'
              })
          .toList(),
      'note': state['note'] ?? ''
    };
  }

  static String offsetText(int minutes) {
    final value = minutes.abs();
    return '${minutes >= 0 ? '-' : '+'}${value ~/ 60}h ${value % 60}m';
  }

  Future<void> action(String action, String? selected, Object? value) async {
    Map<String, dynamic>? f = _demo;
    for (final candidate in flights) {
      if (key(candidate) == selected) f = candidate;
    }
    if (action == 'import') {
      pendingToolsAction = 'import';
      openTools?.call('import', null);
      return;
    }
    if (action == 'demo') {
      final day = DateTime.now().toUtc().add(const Duration(days: 2));
      _demo = {
        'id': 'demo',
        'flight': 'CC102',
        'depApt': 'DFW',
        'arrApt': 'ICN',
        'departureUtc': day.toIso8601String(),
        'arrivalUtc': day.add(const Duration(hours: 14)).toIso8601String()
      };
      _demoState = null;
      return;
    }
    if (action == 'exitDemo') {
      _demo = null;
      _demoState = null;
      return;
    }
    if (f == null) throw StateError('Flight no longer available');
    if (action == 'review' || action == 'addAlarm') {
      selectedFlight = f['id'];
      pendingToolsAction = action;
      openTools?.call(action, selectedFlight);
      return;
    }
    if (['editReminder', 'addReminder', 'toggleReminder'].contains(action)) {
      if (_demo != null) {
        throw StateError('Demo reminders cannot be scheduled.');
      }
      final args = Map<String, dynamic>.from(value as Map);
      if (action == 'toggleReminder') {
        final alarm = flightAlarms(f).firstWhere((a) => a['id'] == args['id']);
        await toggleAlarm(alarm, args['enabled'] == true);
        return;
      }
      final label = '${args['label']}'.trim(), minutes = args['minutes'];
      if (label.isEmpty ||
          label.length > 100 ||
          minutes is! int ||
          minutes < 0 ||
          minutes > 10080) {
        throw const FormatException(
            'Enter a reminder label and a valid hours/minutes offset.');
      }
      final at = departure(f).subtract(Duration(minutes: minutes));
      if (!at.isAfter(DateTime.now())) {
        throw const FormatException('Choose a future reminder time.');
      }
      final old = action == 'editReminder'
          ? flightAlarms(f).firstWhere((a) => a['id'] == args['id'])
          : <String, dynamic>{};
      await saveAlarm({
        ...old,
        'id': old['id'] ?? '${f['id']}_${args['id'] ?? id()}',
        'time': at.toIso8601String(),
        'dep': departure(f).toIso8601String(),
        'lbl': label,
        'type': f['depApt'] == home ? 'base' : 'intl',
        'armed': old['armed'] ?? true,
        'dism': false,
        'missed': false,
        'fnum': f['flight'],
        'depApt': f['depApt'],
        'arrApt': f['arrApt'],
        'arrTime': f['arrTime']
      });
      return;
    }
    final state = _preparation(f), tasks = maps(state['tasks']);
    switch (action) {
      case 'renameTask':
        final args = Map<String, dynamic>.from(value as Map);
        if (args['flightKey'] != null && args['flightKey'] != key(f)) {
          throw StateError('Flight changed while editing.');
        }
        final label = '${args['label']}'.trim();
        if (label.isEmpty || label.length > 100) {
          throw const FormatException(
              'Use a preparation name within 100 characters.');
        }
        tasks.firstWhere((t) => t['id'] == args['id'])['label'] = label;
        break;
      case 'reorderTasks':
        final ids = List<String>.from(value as List);
        if (ids.length != tasks.length ||
            ids.toSet().length != tasks.length ||
            !tasks.every((t) => ids.contains(t['id']))) {
          throw const FormatException('Preparation list changed. Try again.');
        }
        tasks.sort(
            (a, b) => ids.indexOf(a['id']).compareTo(ids.indexOf(b['id'])));
        break;
      case 'toggle':
        final task = tasks[value as int];
        task['checkedAt'] = task['checkedAt'] == null
            ? DateTime.now().toUtc().toIso8601String()
            : null;
        break;
      case 'delete':
        tasks.removeAt(value as int);
        break;
      case 'add':
        final label = '$value'.trim();
        if (tasks.length >= 12 || label.isEmpty || label.length > 100) {
          throw const FormatException(
              'Use up to 12 items, each within 100 characters.');
        }
        tasks.add({'id': 'task_${id()}', 'label': label, 'checkedAt': null});
        break;
      case 'note':
        state['note'] = '$value'.substring(0, '$value'.length.clamp(0, 1000));
        break;
      default:
        throw StateError('Unsupported action');
    }
    state['tasks'] = tasks;
    if (_demo != null) {
      _demoState = state;
    } else {
      briefings[key(f)] = state;
      await _persist();
    }
    notifyListeners();
  }
}
