import 'package:crewclock/widgets/alarm_time_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 393.0]) {
    testWidgets('roster clock paints and fits at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final next = DateTime.now().add(const Duration(hours: 1));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('clock-preview'),
            child: Column(children: [
              AlarmTimeDial(
                times: [next.subtract(const Duration(hours: 3)), next],
                armedTimes: [next],
                date: DateTime(2026, 11, 13),
                hourCycle: 12,
                emphasizeNumbers: true,
              ),
              const Text('Departure local date'),
            ]),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final time = tester.getRect(find.textContaining('(L)'));
      final below = tester.getRect(find.text('Departure local date'));
      expect(time.bottom, lessThanOrEqualTo(below.top));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
