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
  List<Map<String, dynamic>> flights = [], alarms = [], intervals = [];
  Map<String, dynamic> settings = {}, briefings = {}, statuses = {};
  bool ready = false, busy = false;
  String? error, migrationNotice, selectedFlight, pendingToolsAction;
  void Function(String action, String? flight)? openTools;
  Map<String, dynamic>? _demo, _demoState;
  Future<void> _tail = Future<void>.value();

  static const preparation = [
    'Roster and departure time checked',
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
      {'id': 'd1', 'h': 3, 'm': 0, 'lbl': 'Prepare for Duty'},
      {'id': 'd2', 'h': 2, 'm': 30, 'lbl': 'Depart for Airport'},
      {'id': 'd3', 'h': 0, 'm': 30, 'lbl': 'Boarding time'}
    ],
    'intlOffs': [
      {'id': 'i1', 'h': 3, 'm': 0, 'lbl': 'Wake Up (Overseas)'},
      {'id': 'i2', 'h': 2, 'm': 0, 'lbl': 'Hotel Checkout'},
      {'id': 'i3', 'h': 0, 'm': 40, 'lbl': 'Boarding time'}
    ],
  };
  String get home => settings['baseApt'] as String? ?? 'ICN';
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
      await _persist();
      try {
        await scheduler.requestStartupPermissions();
        await scheduler.scheduleFromRecords(alarms);
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

  Future<void> refresh({bool notify = true}) async {
    await scheduler.reconcileDismissals();
    alarms = maps(await db.getAlarmsState());
    statuses = Map<String, dynamic>.from(await NativeAlarmScheduler.channel
            .invokeMethod<Map>('getAlarmStatus', alarms) ??
        {});
    if (notify) notifyListeners();
  }

  Future<void> _saveAlarms({bool request = false}) async {
    await db.saveAlarmsState(jsonEncode(alarms));
    await _persist();
    try {
      await scheduler.scheduleFromRecords(alarms,
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
    return 'Next: ${stamp(at, airportZone(home))} $home';
  }

  String presetGroup(Map f) {
    final domestic = (settings['domesticAirports'] as List? ??
            [
              'ICN',
              'GMP',
              'PUS',
              'CJU',
              'TAE',
              'KWJ',
              'CJJ',
              'RSU',
              'USN',
              'KPO',
              'MWX',
              'YNY',
              'HIN',
              'KUV',
              'WJU'
            ])
        .contains(f['arrApt']);
    final group = f['depApt'] == home ? (domestic ? 'dom' : 'base') : 'intl';
    return group;
  }

  List<Map<String, dynamic>> offsets(Map f) => maps(
      settings['${presetGroup(f)}Offs'] ?? defaults['${presetGroup(f)}Offs']);

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

  Future<void> importFlights(List<Map<String, dynamic>> imported) =>
      change(() async {
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
        settings = next;
        await _persist();
        notifyListeners();
        // Existing departure instants and custom alarms remain fixed when changing the home base.
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
    for (final task in result['tasks']) {
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
    Map<String, dynamic>? f = _demo;
    for (final candidate in sorted) {
      if (key(candidate) == selected) {
        f = candidate;
        break;
      }
    }
    f ??= sorted
        .where((x) =>
            DateTime.tryParse('${x['arrivalUtc']}')?.isAfter(DateTime.now()) ??
            departure(x).isAfter(DateTime.now()))
        .firstOrNull;
    f ??= sorted.lastOrNull;
    if (f == null) return {'flight': null, 'flights': [], 'dark': dark};
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
        'clock': clock(zoned(at, zone)),
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
        'departureTime': clock(local),
        'arrivalTime': arrival == null
            ? (f['arrTime'] ?? '—')
            : clock(zoned(arrival, airportZone(f['arrApt'])))
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
    return '${minutes >= 0 ? '-' : '+'}${value ~/ 60}h${value % 60}m';
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
        tasks.add({'label': label, 'checkedAt': null});
        break;
      case 'note':
        state['note'] = '$value'.substring(0, '$value'.length.clamp(0, 1000));
        break;
      case 'export':
        final snap = await snapshot(selected),
            lines = <String>[
              _demo == null
                  ? 'Personal flight preparation'
                  : 'FICTIONAL DEMO — no alarms scheduled',
              flightLabel(f),
              ...((snap['clocks'] as List).map((c) =>
                  '${c['label']}: ${c['date']} ${c['time']} (${c['zone']})')),
              ...((snap['steps'] as List)
                  .map((s) => '${s['time']} — ${s['label']} · ${s['status']}')),
              ...tasks.map((t) =>
                  '${t['checkedAt'] == null ? '[ ]' : '[Checked ${t['checkedAt']}]'} ${t['label']}'),
              'Layover / pickup note: ${state['note'] ?? ''}',
              'Personal organization only. Follow your airline’s official procedures.'
            ];
        await NativeAlarmScheduler.channel.invokeMethod<void>(
            'shareDutyBriefing', {
          'title': 'CrewClock Flight Preparation',
          'lines': lines.take(50).toList()
        });
        return;
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
