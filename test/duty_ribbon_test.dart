import 'package:crewclock/widgets/duty_ribbon.dart';
import 'package:crewclock/widgets/crewclock_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> ribbon({int? overlap = 95, int? block = 730}) => {
      'dep': .3,
      'arr': block == null ? null : .95,
      'prep': .05,
      'steps': [.05, .15],
      'axes': [
        for (final label in ['DFW', 'ICN', 'UTC'])
          {
            'label': label,
            'ticks': [
              for (var i = 0; i < 7; i++) {'x': i / 7, 'text': '${i * 3}'}
            ]
          }
      ],
      'wocl': [
        [.5, .75]
      ],
      'home': 'ICN',
      'woclFlightMinutes': overlap,
      'blockMinutes': block,
      'now': .1
    };

Future<void> pump(WidgetTester tester, Map<String, dynamic> data,
    {double width = 320, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: CrewClockTheme.data(dark: false),
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: SingleChildScrollView(
                  child: DutyRibbon(data: data, dark: false))))));
}

void main() {
  testWidgets('shows block time and WOCL overlap', (tester) async {
    await pump(tester, ribbon());
    expect(find.text('Block 12h 10m'), findsOneWidget);
    expect(find.text('WOCL in flight 1h 35m'), findsOneWidget);
    expect(find.text('WOCL · ICN 02–06'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles missing arrival and large text on a narrow screen',
      (tester) async {
    await pump(tester, ribbon(overlap: null, block: null),
        width: 280, scale: 2);
    expect(find.text('Arrival time not in roster'), findsOneWidget);
    expect(find.byKey(const ValueKey('duty-ribbon-wocl')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports no overlap without warning colour text', (tester) async {
    await pump(tester, ribbon(overlap: 0));
    expect(find.text('No WOCL in flight'), findsOneWidget);
  });
}
