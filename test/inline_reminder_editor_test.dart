import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crewclock/widgets/inline_reminder_editor.dart';

void main() {
  testWidgets(
      '255 minute preset is shown as 4 hours 15 minutes and saves inline',
      (tester) async {
    int? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InlineReminderEditor(
                label: 'Depart for Airport',
                minutesBefore: 255,
                onSave: (label, minutes, _, __) async {
                  saved = minutes;
                }))));
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Hours'))
            .controller!
            .text,
        '4');
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Minutes'))
            .controller!
            .text,
        '15');
    await tester.enterText(find.widgetWithText(TextField, 'Hours'), '3');
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '40');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved, 220);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('invalid minute part does not save or silently roll over',
      (tester) async {
    var saved = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InlineReminderEditor(
                label: 'Prepare',
                minutesBefore: 60,
                onSave: (_, __, ___, ____) async {
                  saved = true;
                }))));
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '60');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.textContaining('0–59 minutes'), findsOneWidget);
  });
  testWidgets('entry forms keep a visible gap before action buttons',
      (tester) async {
    for (final timed in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: InlineReminderEditor(
                  key: ValueKey(timed),
                  label: '',
                  minutesBefore: timed ? null : 60,
                  date: '2099-11-02',
                  time: '13:55',
                  zone: timed ? 'Asia/Seoul' : null,
                  onSave: (_, __, ___, ____) async {}))));
      final button = find.widgetWithText(FilledButton, 'Save changes');
      final fields = timed
          ? find.byType(CupertinoDatePicker)
          : find.widgetWithText(TextField, 'Hours');
      expect(tester.getTopLeft(button).dy - tester.getBottomLeft(fields).dy,
          greaterThanOrEqualTo(14));
      if (timed) {
        final picker = tester.widget<CupertinoDatePicker>(fields);
        expect(picker.itemExtent, 28);
        expect(tester.getSize(fields).height, 120);
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'repeating reminders allow an empty name and retain minimum duration validation',
      (tester) async {
    String? savedLabel;
    int? savedMinutes;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InlineReminderEditor(
                label: '',
                minutesBefore: 90,
                repeat: true,
                onSave: (label, minutes, _, __) async {
                  savedLabel = label;
                  savedMinutes = minutes;
                }))));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(savedLabel, 'Repeating reminder');
    expect(savedMinutes, 90);
    savedMinutes = null;
    await tester.enterText(find.widgetWithText(TextField, 'Hours'), '0');
    await tester.enterText(find.widgetWithText(TextField, 'Minutes'), '0');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(savedMinutes, isNull);
    expect(find.textContaining('at least 1 minute'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
