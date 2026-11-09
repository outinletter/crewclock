import 'package:crewclock/widgets/duration_wheels.dart';
import 'package:crewclock/widgets/relative_alarm_editor.dart';
import 'package:crewclock/widgets/inline_reminder_editor.dart';
import 'package:crewclock/widgets/alarm_time_visuals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> choose(WidgetTester t, int h, int m) async {
  final wheels = find.byType(CupertinoPicker);
  t.widget<CupertinoPicker>(wheels.at(0)).scrollController!.jumpToItem(h);
  t.widget<CupertinoPicker>(wheels.at(1)).scrollController!.jumpToItem(m);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('editing a repeating reminder uses rollers and saves changes',
      (t) async {
    int? saved;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InlineReminderEditor(
      label: 'Reminder',
      repeat: true,
      minutesBefore: 80,
      onSave: (_, m, __, ___) async {
        saved = m;
      },
    ))));
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    await choose(t, 2, 35);
    await t.tap(find.byTooltip('Save changes'));
    await t.pumpAndSettle();
    expect(saved, 155);
    expect(t.takeException(), isNull);
  });
  testWidgets('duration hour rollers stop at 24 hours', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InlineReminderEditor(
                label: 'Reminder',
                repeat: true,
                minutesBefore: 60,
                onSave: (_, __, ___, ____) async {}))));
    expect(maxDurationHours, 24);
    t.widget<CupertinoPicker>(find.byType(CupertinoPicker).first)
        .scrollController!
        .jumpToItem(24);
    await t.pumpAndSettle();
    expect(find.text('24'), findsOneWidget);
    expect(find.text('25'), findsNothing);
  });
  testWidgets(
      'timer and repeating alarms share rollers and save the selected duration without a label',
      (t) async {
    await t.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    int? saved;
    String? name;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: RelativeAlarmEditor(onAdd: (l, m) async {
      name = l;
      saved = m;
    }))));
    expect(find.textContaining('nap'), findsNothing);
    expect(find.byType(DurationAlarmCard), findsOneWidget);
    await choose(t, 2, 15);
    await t.tap(find.byTooltip('Add timer'));
    await t.pumpAndSettle();
    expect(saved, 135);
    expect(name, 'Timer');
    expect(t.takeException(), isNull);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: InlineReminderEditor(
                label: '',
                repeat: true,
                minutesBefore: 60,
                saveLabel: 'Add reminder',
                onSave: (l, m, _, __) async {
                  name = l;
                  saved = m;
                }))));
    await t.pumpAndSettle();
    await choose(t, 1, 20);
    await t.tap(find.byTooltip('Add reminder'));
    await t.pumpAndSettle();
    expect(saved, 80);
    expect(name, 'Repeating reminder');
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'preparation presets use the same roller card and autosave after scrolling',
      (t) async {
    int? saved;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PreparationPresetRow(
                label: 'Prepare for Duty',
                minutesBefore: 270,
                onSave: (_, m, __, ___) async {
                  saved = m;
                },
                onDelete: () async {}))));
    expect(find.byType(DurationAlarmCard), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    await choose(t, 3, 40);
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(saved, 220);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
      'roster dial can use 12 hours while preserving 24-hour alarm times',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AlarmTimeDial(
                hourCycle: 12,
                caption: 'First alarm',
                times: [DateTime(2099, 1, 1, 18, 45)]))));
    expect(find.textContaining('12h · First alarm · 18:45'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
