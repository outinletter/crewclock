import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:crewclock/services/roster_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);
  test('monthly calendar joins overnight arrival and ignores non-flight duties',
      () async {
    final p = RosterParser();
    await p.initialize();
    final actual = p.parse(
        'November 2026\nNov 01\nRESERVE\nNov 02\nCC 955 ICN 13:55 - IST 20:05\nLO IST\nNov 04\nCC 956 IST 21:55 - ICN\nNov 05\nCC 956 IST - ICN 13:55\nNov 26\nKCRM1.5 GMP 09:00 - GMP 10:30');
    final expected = p.parse(
        'BEGIN:VEVENT\nSUMMARY:CC955 ICN-IST\nDTSTART:20261102T045500Z\nDTEND:20261102T170500Z\nEND:VEVENT\nBEGIN:VEVENT\nSUMMARY:CC956 IST-ICN\nDTSTART:20261104T185500Z\nDTEND:20261105T045500Z\nEND:VEVENT');
    expect(actual.length, 2);
    for (var i = 0; i < 2; i++) {
      for (final key in [
        'flight',
        'depApt',
        'arrApt',
        'departureUtc',
        'arrivalUtc'
      ]) {
        expect(actual[i][key], expected[i][key]);
      }
    }
  });
  test('missing arrival cell is rejected instead of guessing next day',
      () async {
    final p = RosterParser();
    await p.initialize();
    expect(() => p.parse('November 2026\nNov 04\nCC956 IST 21:55 - ICN'),
        throwsFormatException);
  });
  test('month header is not limited to the supplied November image', () async {
    final p = RosterParser();
    await p.initialize();
    final f =
        p.parse('December 2026\nDec 02\nCC955 ICN 13:55 - IST 20:05').single;
    expect(f['departureUtc'], '2026-12-02T04:55:00.000Z');
  });
  test('copied compact text can list arrival cell before departure cell',
      () async {
    final p = RosterParser();
    await p.initialize();
    final flights = p.parse(
        'November 2026\nNov 05\nCC956IST‑ICN13.55\nNov 04\nCC956IST21:55-ICN');
    expect(flights.single['departureUtc'], '2026-11-04T18:55:00.000Z');
    expect(flights.single['arrivalUtc'], '2026-11-05T04:55:00.000Z');
  });
}
