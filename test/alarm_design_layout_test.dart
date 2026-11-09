import 'package:crewclock/widgets/crewclock_theme.dart';
import 'package:crewclock/widgets/inline_reminder_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'compact reminder entry fits narrow screen and adds without label',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? savedMinutes;
    await tester.pumpWidget(MaterialApp(
        theme: CrewClockTheme.data(dark: false),
        home: Scaffold(
            body: InlineReminderEditor(
          repeat: true,
          label: '',
          minutesBefore: 90,
          saveLabel: 'Add reminder',
          onSave: (_, minutes, __, ___) async {
            savedMinutes = minutes;
          },
        ))));
    expect(tester.takeException(), isNull);
    final wheels = find.byType(CupertinoPicker);
    tester
        .widget<CupertinoPicker>(wheels.at(0))
        .scrollController!
        .jumpToItem(12);
    tester
        .widget<CupertinoPicker>(wheels.at(1))
        .scrollController!
        .jumpToItem(45);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add reminder'));
    await tester.pumpAndSettle();
    expect(savedMinutes, 765);
    expect(tester.takeException(), isNull);
  });
}
