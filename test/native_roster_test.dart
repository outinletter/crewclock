import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:crewclock/services/roster_parser.dart';
import 'package:crewclock/services/crewclock_store.dart';

class SnapshotStore extends CrewClockStore {
  @override
  Future<void> saveAlarm(Map<String, dynamic> record) async {
    alarms.removeWhere((a) => a['id'] == record['id']);
    alarms.add(record);
  }

  @override
  Future<void> refresh({bool notify = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RosterParser parser;
  setUpAll(() async {
    tz_data.initializeTimeZones();
    parser = RosterParser();
    await parser.initialize();
  });
  String calendar(String start,
          {String end = 'DTEND:20261102T170500Z', String extra = ''}) =>
      'BEGIN:VCALENDAR\n$extra\nBEGIN:VEVENT\nUID:flight-one\nSUMMARY:KE955 ICN-IST\n$start\n$end\nEND:VEVENT\nEND:VCALENDAR';
  test('UTC ICS and time zones preserve one instant', () {
    final f = parser.parse(calendar('DTSTART:20261102T045500Z')).single;
    expect(f['departureUtc'], '2026-11-02T04:55:00.000Z');
    expect(f['depApt'], 'ICN');
    expect(f['arrApt'], 'IST');
  });
  test('TZID calendar uses departure-local time', () {
    expect(
        parser
            .parse(calendar('DTSTART;TZID=Asia/Seoul:20261102T135500'))
            .single['departureUtc'],
        '2026-11-02T04:55:00.000Z');
  });
  test('calendar-level time zone and airport fallback are honored', () {
    expect(
        parser
            .parse(calendar('DTSTART:20261102T135500',
                extra: 'X-WR-TIMEZONE:Asia/Seoul'))
            .single['departureUtc'],
        '2026-11-02T04:55:00.000Z');
    expect(
        parser
            .parse(calendar('DTSTART:20261102T135500'))
            .single['departureUtc'],
        '2026-11-02T04:55:00.000Z');
  });
  test('reject nonexistent and ambiguous daylight-saving times', () {
    expect(() => parser.localInstant('2026-03-08', '02:30', 'America/Chicago'),
        throwsFormatException);
    expect(() => parser.localInstant('2026-11-01', '01:30', 'America/Chicago'),
        throwsFormatException);
  });
  test('reject invalid civil dates instead of rolling into next month', () {
    expect(() => parser.localInstant('2026-02-30', '13:55', 'Asia/Seoul'),
        throwsFormatException);
    expect(() => parser.localInstant('2026-11-02', '24:55', 'Asia/Seoul'),
        throwsFormatException);
  });
  test('text roster parses and deduplicates flights', () {
    final rows = parser.parse(
        '2026-11-02 KE955 ICN IST 13:55\n2026-11-02 KE955 ICN IST 13:55');
    expect(rows.length, 1);
    expect(rows.single['departureUtc'], '2026-11-02T04:55:00.000Z');
  });
  test(
      'unknown airports, all-day events and unexpanded recurrence are rejected',
      () {
    expect(() => parser.parse('2026-11-02 KE955 ZZZ IST 13:55'),
        throwsFormatException);
    expect(() => parser.parse(calendar('DTSTART:20261102')),
        throwsFormatException);
    expect(
        () => parser
            .parse(calendar('DTSTART:20261102T045500Z\nRRULE:FREQ=WEEKLY')),
        throwsFormatException);
  });
  test('unfolds calendar lines and ignores non-flight events', () {
    final f = parser.parse(calendar('DTSTART:20261102T045500Z')
        .replaceFirst('SUMMARY:KE955 ICN-IST', 'SUMMARY:KE955 ICN-\n IST'));
    expect(f.single['arrApt'], 'IST');
    expect(
        () => parser.parse(calendar('DTSTART:20261102T045500Z')
            .replaceFirst('KE955 ICN-IST', 'OFF')),
        throwsFormatException);
  });
  test('native snapshot uses actual saved reminder times and offsets',
      () async {
    final s = SnapshotStore();
    s.parser.zones = parser.zones;
    s.ready = true;
    s.settings = {'baseApt': 'ICN'};
    final f = {
      'id': 'saved',
      'flight': 'KE955',
      'depApt': 'ICN',
      'arrApt': 'IST',
      'departureUtc': '2099-11-02T04:55:00.000Z',
      'arrivalUtc': '2099-11-02T17:05:00.000Z'
    };
    s.flights = [f];
    s.alarms = [
      {
        'id': 'saved_b1',
        'fnum': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'dep': f['departureUtc'],
        'time': '2099-11-02T00:25:00.000Z',
        'lbl': 'Prepare for Duty',
        'armed': 1,
        'dism': 0,
        'missed': 0
      }
    ];
    s.statuses = {
      'saved_b1': {'state': 'scheduled'}
    };
    final data = await s.snapshot(null);
    final step = (data['steps'] as List).single;
    expect(step['clock'], '09:25');
    expect(step['offset'], '-4h30m');
    expect(step['status'], 'Scheduled');
    expect((data['flight'] as Map)['departureTime'], '13:55');
    expect((data['clocks'] as List)[2]['time'], '04:55');
    expect((data['tasks'] as List).map((t) => t['label']),
        contains('Passport & VISA'));
  });
  test('native snapshot preserves preparation completion and custom items',
      () async {
    final s = SnapshotStore();
    s.parser.zones = parser.zones;
    s.ready = true;
    final f = {
      'id': 'saved',
      'flight': 'KE955',
      'depApt': 'ICN',
      'arrApt': 'IST',
      'departureUtc': '2099-11-02T04:55:00.000Z'
    };
    s.flights = [f];
    s.briefings[s.key(f)] = {
      'tasks': [
        {
          'label': 'Airport transport arranged',
          'checkedAt': '2026-10-30T01:00:00Z'
        },
        {'label': 'My item', 'checkedAt': null}
      ],
      'note': 'Pickup 07:00'
    };
    final snap = await s.snapshot(null);
    expect((snap['tasks'] as List)[0]['label'], 'Passport & VISA');
    expect((snap['tasks'] as List)[0]['checkedAt'], '2026-10-30T01:00:00Z');
    expect(snap['note'], 'Pickup 07:00');
  });
  test('inline reminder edits convert hours/minutes to a fixed UTC instant',
      () async {
    final s = SnapshotStore();
    s.parser.zones = parser.zones;
    s.ready = true;
    final f = {
      'id': 'saved',
      'flight': 'KE955',
      'depApt': 'ICN',
      'arrApt': 'IST',
      'departureUtc': '2099-11-02T04:55:00.000Z'
    };
    s.flights = [f];
    s.alarms = [
      {
        'id': 'saved_b1',
        'fnum': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'dep': f['departureUtc'],
        'time': '2099-11-02T00:25:00.000Z',
        'lbl': 'Depart for Airport',
        'armed': 1,
        'dism': 0
      }
    ];
    await s.action('editReminder', s.key(f),
        {'id': 'saved_b1', 'label': 'Depart for Airport', 'minutes': 255});
    expect(s.alarms.single['time'], '2099-11-02T00:40:00.000Z');
  });
  test('retrying an inline new reminder does not duplicate it', () async {
    final s = SnapshotStore();
    s.parser.zones = parser.zones;
    s.ready = true;
    final f = {
      'id': 'saved',
      'flight': 'KE955',
      'depApt': 'ICN',
      'arrApt': 'IST',
      'departureUtc': '2099-11-02T04:55:00.000Z'
    };
    s.flights = [f];
    final args = {'id': 'new-1', 'label': 'Passport check', 'minutes': 60};
    await s.action('addReminder', s.key(f), args);
    await s.action('addReminder', s.key(f), args);
    expect(s.alarms.length, 1);
    expect(s.alarms.single['id'], 'saved_new-1');
  });
}
