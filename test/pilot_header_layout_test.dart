import 'package:crewclock/native_home.dart';
import 'package:crewclock/widgets/crewclock_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'native_briefing_test.dart' show sample;

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('roster entry fits header at $width and chooser stays below it',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = FlightBriefingController();
      String? action;
      controller.connect((_) async => sample('CC101'), (a, _, __) async {
        action = a;
      });
      await tester.pumpWidget(MaterialApp(
          home: CrewClockShell(
              briefing: controller,
              tools: const SizedBox(),
              headerActions: (_) => const [])));
      await tester.pumpAndSettle();
      final header = find.byType(CrewClockHeader),
          brand = find.text('CrewClock'),
          chooser = find.byKey(const ValueKey('choose-flight'));
      expect(tester.getTopLeft(chooser).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(header).dy));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('briefing-add-roster')));
      await tester.pumpAndSettle();
      expect(action, 'import');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
