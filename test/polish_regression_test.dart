import 'package:crewclock/services/crewclock_store.dart';
import 'package:crewclock/widgets/crewclock_theme.dart';
import 'package:crewclock/widgets/inline_reminder_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);
  test('repeating reminders show only an operating-system confirmed next time',
      () {
    final store = CrewClockStore();
    store.parser.zones = {'ICN': 'Asia/Seoul'};
    final row = <String, dynamic>{'id': 'repeat', 'enabled': true};
    expect(store.intervalStatus(row), 'Not scheduled');
    expect(store.intervalNext(row), isNull);
    store.statuses = {
      'repeat': {'state': 'waiting', 'next': 1000}
    };
    expect(store.intervalNext(row), isNull);
    store.statuses = {
      'repeat': {
        'state': 'scheduled',
        'next': DateTime.utc(2099, 1, 1).millisecondsSinceEpoch
      }
    };
    expect(store.intervalStatus(row), 'Scheduled');
    expect(store.intervalNext(row), contains('09:00'));
    row['enabled'] = false;
    expect(store.intervalStatus(row), 'Paused');
    expect(store.intervalNext(row), isNull);
    store.dispose();
  });
  test('status text retains readable contrast in light and dark themes', () {
    for (final dark in [false, true]) {
      final background =
          CrewClockTheme.colors(dark: dark).surface.computeLuminance();
      for (final status in [
        'Scheduled',
        'Not scheduled',
        'Waiting',
        'Paused'
      ]) {
        final foreground =
            CrewClockTheme.statusColor(status, dark: dark).computeLuminance();
        final ratio =
            (foreground > background ? foreground + .05 : background + .05) /
                (foreground > background ? background + .05 : foreground + .05);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$status, dark=$dark');
      }
    }
  });
  testWidgets('preset adapts to large text and keeps saves visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? saved;
    await tester.pumpWidget(MaterialApp(
        theme: CrewClockTheme.data(dark: true),
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 700), textScaler: TextScaler.linear(1.7)),
            child: Scaffold(
                body: PreparationPresetRow(
                    label: 'Prepare for Duty',
                    minutesBefore: 270,
                    onSave: (_, minutes, __, ___) async => saved = minutes,
                    onDelete: () async {})))));
    final minutes = find.widgetWithText(TextField, 'Minutes');
    await tester.enterText(minutes, '15');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(saved, 255);
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
