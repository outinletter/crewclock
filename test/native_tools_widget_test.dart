import 'package:crewclock/native_roster.dart';
import 'package:crewclock/widgets/crewclock_header.dart';
import 'package:crewclock/services/crewclock_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

class ToolsStore extends CrewClockStore {
  Map<String, dynamic>? savedAlarm;
  List<Map<String, dynamic>>? imported;
  @override
  Future<void> saveSettings(Map<String, dynamic> next) async {
    settings = next;
    notifyListeners();
  }

  @override
  Future<void> saveAlarm(Map<String, dynamic> record) async {
    savedAlarm = record;
  }

  @override
  Future<void> importFlights(List<Map<String, dynamic>> flights) async {
    imported = flights;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);
  Future<ToolsStore> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = ToolsStore();
    s.parser.zones = {
      'ICN': 'Asia/Seoul',
      'DFW': 'America/Chicago',
      'IST': 'Europe/Istanbul'
    };
    s.ready = true;
    var section = 0;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, set) => Scaffold(
                  body: NativeRosterPage(
                      key: ValueKey(section), store: s, section: section),
                  bottomNavigationBar: CupertinoTabBar(
                      currentIndex: section,
                      onTap: (value) => set(() => section = value),
                      items: const [
                        BottomNavigationBarItem(
                            icon: Icon(Icons.calendar_month), label: 'Roster'),
                        BottomNavigationBarItem(
                            icon: Icon(Icons.alarm), label: 'Alarms'),
                        BottomNavigationBarItem(
                            icon: Icon(Icons.settings), label: 'Settings'),
                      ]),
                ))));
    await tester.pumpAndSettle();
    return s;
  }

  testWidgets('native roster, alarms and settings fit an iPhone viewport',
      (tester) async {
    final s = await open(tester);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Home base'), findsOneWidget);
    await tester.tap(find.text('Alarms').first);
    await tester.pumpAndSettle();
    expect(find.text('Add personal alarm'), findsNothing);
    expect(find.text('Check / retry alarms'), findsNothing);
    expect(find.text('Stop ringing'), findsNothing);
    expect(find.text('iOS alarm / notification permissions'), findsNothing);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('System alarms enabled'), findsNothing);
    final personal = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('new-personal-'));
    final label = find.descendant(
        of: personal,
        matching: find.widgetWithText(TextField, 'Reminder label'));
    await tester.ensureVisible(label);
    await tester.enterText(label, 'Passport check');
    final save =
        find.descendant(of: personal, matching: find.text('Add alarm'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(s.savedAlarm?['lbl'], 'Passport check');
    expect(s.savedAlarm?['type'], 'direct');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('presets edit hours and minutes directly in Settings',
      (tester) async {
    final store = await open(tester);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('preset-base-b2'));
    await tester.scrollUntilVisible(card, 300,
        scrollable: find.byType(Scrollable).first);
    final hours = find.descendant(
        of: card, matching: find.widgetWithText(TextField, 'Hours'));
    final minutes = find.descendant(
        of: card, matching: find.widgetWithText(TextField, 'Minutes'));
    await tester.ensureVisible(hours);
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(hours).dy, closeTo(tester.getTopLeft(minutes).dy, 1));
    final label = find.descendant(
        of: card, matching: find.widgetWithText(TextField, 'Reminder'));
    expect(tester.getCenter(label).dy, closeTo(tester.getCenter(hours).dy, 1));
    expect(tester.getSize(hours).width, lessThanOrEqualTo(90));
    expect(tester.getSize(card).height, lessThanOrEqualTo(120));
    await tester.enterText(hours, '4');
    await tester.enterText(minutes, '15');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.descendant(of: card, matching: find.byType(Checkbox)),
        findsNothing);
    expect(find.descendant(of: card, matching: find.byType(IconButton)),
        findsNothing);
    final preset = store
        .maps(store.settings['baseOffs'])
        .firstWhere((p) => p['id'] == 'b2');
    expect(preset['h'], 4);
    expect(preset['m'], 15);
    expect(find.byType(AlertDialog), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.dragFrom(
        tester.getTopRight(card) + const Offset(-5, 20), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(store.maps(store.settings['baseOffs']).any((p) => p['id'] == 'b2'),
        isFalse);
    expect(card, findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.maps(store.settings['baseOffs']).any((p) => p['id'] == 'b2'),
        isTrue);
    expect(card, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('native document picker previews calendar before confirming',
      (tester) async {
    final s = await open(tester);
    const channel = MethodChannel('crewclock/native_alarm');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickRosterFile') {
        return {
          'name': 'roster.ics',
          'text':
              'BEGIN:VEVENT\nSUMMARY:KE955 ICN-IST\nDTSTART:20991102T045500Z\nDTEND:20991102T170500Z\nEND:VEVENT'
        };
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.ensureVisible(find.text('Add flight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add flight'));
    await tester.pumpAndSettle();
    expect(find.text('Preview sample roster'), findsNothing);
    await tester.tap(find.text('Import ICS / calendar file'));
    await tester.pumpAndSettle();
    expect(find.text('Review roster changes'), findsOneWidget);
    expect(s.imported, isNull);
    await tester.tap(find.text('Confirm and request alarms'));
    await tester.pumpAndSettle();
    expect(s.imported?.single['flight'], 'KE955');
    expect(s.imported?.single['departureUtc'], '2099-11-02T04:55:00.000Z');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Add flight exposes and completes manual text import',
      (tester) async {
    final store = await open(tester);
    await tester.ensureVisible(find.text('Add flight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add flight'));
    await tester.pumpAndSettle();
    expect(find.text('Import ICS / calendar file'), findsOneWidget);
    expect(find.text('Enter flight manually'), findsOneWidget);
    await tester.tap(find.text('Paste schedule text (manual)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Roster text'),
        '2099-11-02 KE955 ICN IST 13:55');
    await tester.ensureVisible(find.text('Preview flights'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview flights'));
    await tester.pumpAndSettle();
    expect(find.text('Review roster changes'), findsOneWidget);
    await tester.tap(find.text('Confirm and request alarms'));
    await tester.pumpAndSettle();
    expect(store.imported?.single['flight'], 'KE955');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Add flight opens individual manual flight entry',
      (tester) async {
    final store = await open(tester);
    await tester.ensureVisible(find.text('Add flight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add flight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter flight manually'));
    await tester.pumpAndSettle();
    expect(find.byType(CrewClockHeader), findsNothing);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Flight number'), 'KE955');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Arrival'), 'IST');
    await tester.ensureVisible(find.text('Save flight and request alarms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save flight and request alarms'));
    await tester.pumpAndSettle();
    expect(store.imported?.single['flight'], 'KE955');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('roster reminder rows do not open an editor', (tester) async {
    final store = await open(tester);
    final at = store.parser
        .localInstant(store.date(DateTime.now()), '23:55', 'Asia/Seoul');
    store.flights = [
      {
        'id': 'readonly',
        'flight': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'departureUtc': at.toIso8601String()
      }
    ];
    store.alarms = [
      {
        'id': 'readonly-alarm',
        'fnum': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'dep': at.toIso8601String(),
        'time': at.subtract(const Duration(hours: 1)).toIso8601String(),
        'lbl': 'Prepare for Duty',
        'armed': true,
        'type': 'base'
      }
    ];
    store.notifyListeners();
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('alarm-readonly-alarm'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare for Duty'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.widgetWithText(TextField, 'Hours'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('roster automatically focuses the next imported flight date',
      (tester) async {
    final store = await open(tester);
    final at = DateTime.now().toUtc().add(const Duration(days: 5));
    store.flights = [
      {
        'id': 'next',
        'flight': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'departureUtc': at.toIso8601String()
      }
    ];
    store.alarms = [
      {
        'id': 'next-alarm',
        'fnum': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'dep': at.toIso8601String(),
        'time': at.subtract(const Duration(hours: 1)).toIso8601String(),
        'lbl': 'Upcoming flight preparation',
        'armed': true,
        'type': 'base'
      }
    ];
    store.notifyListeners();
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('alarm-next-alarm'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(find.text('Upcoming flight preparation'), findsOneWidget);
    expect(
        find.text(
            '${store.date(store.zoned(at, 'Asia/Seoul'))} · Departure-airport local dates'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
