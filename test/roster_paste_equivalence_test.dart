import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:crewclock/services/roster_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pasted local departure and dated arrival match ICS across date line',
      () async {
    tz_data.initializeTimeZones();
    final parser = RosterParser();
    await parser.initialize();
    final ics = parser
        .parse(
            'BEGIN:VEVENT\nSUMMARY:CC101 ICN-DFW\nDTSTART:20261017T092000\nDTEND:20261017T081000\nEND:VEVENT')
        .single;
    final pasted =
        parser.parse('2026-10-17 CC101 ICN DFW 09:20 2026-10-17 08:10').single;
    for (final key in [
      'flight',
      'depApt',
      'arrApt',
      'departureUtc',
      'arrivalUtc'
    ]) {
      expect(pasted[key], ics[key]);
    }
  });
}
