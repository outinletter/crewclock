import 'package:flutter/material.dart';
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
}
