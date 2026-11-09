import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crewclock/widgets/flight_schedule_summary.dart';
import 'package:crewclock/widgets/width_aware_title.dart';

void main() {
  for (final width in [320.0, 375.0, 390.0]) {
    testWidgets('flight times stay on one line at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(children: [
                    WidthAwareTitle('Home base · International',
                        style: TextStyle(fontSize: 18)),
                    FlightScheduleSummary(
                        date: '11/20 Fri',
                        departure: '13:55',
                        arrival: '20:05',
                        number: 'KE955',
                        route: 'ICN → IST'),
                  ])))));
      expect(tester.getCenter(find.text('13:55')).dy,
          closeTo(tester.getCenter(find.text('20:05')).dy, .1));
      expect(tester.getCenter(find.text('13:55')).dy,
          closeTo(tester.getCenter(find.text('KE955  ICN → IST')).dy, .1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large accessibility text remains readable without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.7)),
            child: Scaffold(
                body: Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(children: [
                      WidthAwareTitle('Home base · International',
                          style: TextStyle(fontSize: 18)),
                      FlightScheduleSummary(
                          date: '11/20 Fri',
                          departure: '13:55',
                          arrival: '20:05',
                          number: 'KE955',
                          route: 'ICN → IST'),
                    ]))))));
    expect(tester.takeException(), isNull);
  });
}
