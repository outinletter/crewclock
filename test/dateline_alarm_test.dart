import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:crewclock/services/roster_parser.dart';
import 'package:crewclock/services/crewclock_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);
  test(
      'local dates can move backward across the dateline while instants move forward',
      () async {
    final parser = RosterParser();
    await parser.initialize();
    final flights = parser.parse(
        'BEGIN:VEVENT\nSUMMARY:CC101 ICN-DFW\nDTSTART:20261017T092000\nDTEND:20261017T081000\nEND:VEVENT');
    expect(flights.single['departureUtc'], '2026-10-17T00:20:00.000Z');
    expect(flights.single['arrivalUtc'], '2026-10-17T13:10:00.000Z');
  });
  test(
      'preparation alarm can fall on the previous local date and stays fixed during travel',
      () async {
    final store = CrewClockStore();
    await store.parser.initialize();
    final dep =
        store.parser.localInstant('2026-10-19', '01:10', 'America/Chicago');
    final flight = <String, dynamic>{
      'id': 'dateline',
      'flight': 'CC102',
      'depApt': 'DFW',
      'arrApt': 'ICN',
      'departureUtc': dep.toIso8601String()
    };
    final original = tz.local;
    try {
      for (final zone in [
        'Asia/Seoul',
        'America/Chicago',
        'Pacific/Honolulu'
      ]) {
        tz.setLocalLocation(tz.getLocation(zone));
        final at =
            DateTime.parse(store.buildFlightAlarms(flight).first['time']);
        expect(at.toUtc().toIso8601String(), '2026-10-19T03:10:00.000Z');
        expect(store.stamp(at, 'America/Chicago'), '2026-10-18 22:10');
        expect(store.stamp(at, 'Asia/Seoul'), '2026-10-19 12:10');
      }
    } finally {
      tz.setLocalLocation(original);
      store.dispose();
    }
  });
}
