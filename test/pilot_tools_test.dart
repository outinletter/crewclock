import 'package:crewclock/services/crewclock_store.dart';
import 'package:crewclock/services/roster_parser.dart';
import 'package:crewclock/widgets/alarm_time_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

class BriefingZoneStore extends CrewClockStore {
  @override
  Future<void> refresh({bool notify = true}) async {}
}

void main() {
  test('briefing selection follows departure airport local date and time',
      () async {
    final s = BriefingZoneStore();
    await s.parser.initialize();
    s.ready = true;
    s.settings = {'baseApt': 'ICN'};
    s.flights = [
      {
        'id': 'a',
        'flight': 'CC101',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'departureUtc': '2099-11-02T01:50:00Z'
      },
      {
        'id': 'b',
        'flight': 'CC102',
        'depApt': 'IST',
        'arrApt': 'ICN',
        'departureUtc': '2099-11-03T22:55:00Z'
      },
    ];
    final first = await s.snapshot(s.key(s.flights.first));
    final second = await s.snapshot(s.key(s.flights.last));
    expect(first['clocks'][0]['zone'], 'Asia/Seoul');
    expect(first['clocks'][0]['time'], '10:50');
    expect(second['flight']['from'], 'IST');
    expect(second['clocks'][0]['zone'], 'Europe/Istanbul');
    expect(second['clocks'][0]['date'], '2099-11-04');
    expect(second['clocks'][0]['time'], '01:55');
    expect(second['flight']['departureTime'], '01:55');
    s.dispose();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);
  test('backup remains pending after primary time until Stop', () {
    final s = CrewClockStore();
    s.settings = {'backupMinutes': 5};
    final time = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    s.alarms = [
      {
        'id': 'a',
        'lbl': 'Duty',
        'type': 'direct',
        'time': time.toIso8601String(),
        'armed': true,
        'dism': false
      }
    ];
    expect(s.schedulingRecords.length, 2);
    expect(
        DateTime.parse(s.schedulingRecords.last['time'])
            .difference(time)
            .inMinutes,
        5);
    s.alarms.first['dism'] = true;
    expect(s.schedulingRecords.length, 1);
    s.dispose();
  });
  test('display time basis never changes stored departure or alarm instants',
      () async {
    final s = CrewClockStore();
    await s.parser.initialize();
    s.settings = {'baseApt': 'ICN', 'personalTimeBasis': 'home'};
    s.deviceZone = 'Europe/Prague';
    expect(s.personalZone, 'Asia/Seoul');
    s.settings['personalTimeBasis'] = 'device';
    expect(s.personalZone, 'Asia/Seoul');
    final f = {
      'flight': 'CC101',
      'depApt': 'ICN',
      'arrApt': 'PRG',
      'departureUtc': '2099-11-02T01:50:00.000Z'
    };
    s.flights = [f];
    final before = s.departure(f);
    s.settings['displayUTC'] = true;
    expect(s.displayZone('ICN'), 'Asia/Seoul');
    expect(s.departure(f), before);
    s.dispose();
  });
  test('preview identifies changed times and pairing connects layover legs',
      () async {
    final s = CrewClockStore();
    await s.parser.initialize();
    s.settings = {'baseApt': 'ICN'};
    final outbound = {
      'id': 'a',
      'flight': 'CC101',
      'depApt': 'ICN',
      'arrApt': 'PRG',
      'departureUtc': '2099-11-02T01:50:00.000Z',
      'arrivalUtc': '2099-11-02T15:20:00.000Z'
    };
    final inbound = {
      'id': 'b',
      'flight': 'CC102',
      'depApt': 'PRG',
      'arrApt': 'ICN',
      'departureUtc': '2099-11-04T17:30:00.000Z',
      'arrivalUtc': '2099-11-05T04:50:00.000Z'
    };
    s.flights = [outbound, inbound];
    expect(s.pairingFor(outbound).length, 2);
    expect(
        s.importChange(
            {...outbound, 'departureUtc': '2099-11-02T02:00:00.000Z'}),
        'Changed');
    expect(s.importChange(outbound), 'Unchanged');
    s.dispose();
  });
  test('off reserve and training days are retained separately', () {
    final p = RosterParser();
    final duties = p.nonFlightDays(
        'November 2026\nNov 01\nRESERVE\nNov 02\nDO\nNov 03\nKCRM1.5 GMP 09:00 - GMP 10:30');
    expect(duties.map((d) => d['category']),
        ['Reserve', 'Off / leave', 'Training']);
  });
  testWidgets('dial shows a 24 hour next alarm without layout overflow',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AlarmTimeDial(times: [
      DateTime(2099, 1, 1, 18, 45),
      DateTime(2099, 1, 1, 21, 30)
    ]))));
    expect(find.textContaining('18:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
