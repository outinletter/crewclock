import 'package:crewclock/widgets/crewclock_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('brand height stays fixed without page subtitles at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final title in [
        'Briefing',
        'Roster',
        'Personal Alarm',
        'Settings'
      ]) {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                appBar: CrewClockHeader(pageTitle: title, actions: [
          if (title == 'Roster')
            IconButton(
                onPressed: () {}, icon: const Icon(Icons.file_open_outlined)),
          if (title == 'Settings') ...[
            IconButton(
                onPressed: () {}, icon: const Icon(Icons.dark_mode_outlined)),
            IconButton(
                onPressed: () {}, icon: const Icon(Icons.volume_up_outlined))
          ],
        ]))));
        await tester.pumpAndSettle();
        final brand = tester.widget<Text>(find.text('CrewClock'));
        expect(brand.style!.fontSize, 26);
        expect(find.byKey(const ValueKey('header-page-title')), findsNothing);
        expect(find.byType(Image), findsNothing);
        final header = tester.widget<CrewClockHeader>(find.byType(CrewClockHeader));
        expect(header.preferredSize.height, 64);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
