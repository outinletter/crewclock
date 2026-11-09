import 'package:crewclock/widgets/centered_date_time_picker.dart';
import 'package:crewclock/native_home.dart';
import 'native_briefing_test.dart' show sample;
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
  List<Map<String, dynamic>>? savedIntervals;
  @override
  Future<void> saveIntervals(List<Map<String, dynamic>> next) async {
    savedIntervals = next;
    intervals = next;
    notifyListeners();
  }

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
  Future<void> importFlights(List<Map<String, dynamic>> flights,
      {List<Map<String, dynamic>>? nonFlights}) async {
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
      'GMP': 'Asia/Seoul',
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
    await tester.ensureVisible(find.text('Add flight'));
    expect(tester.getCenter(find.text('Add flight')).dx, greaterThan(195));
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Home base · International'), findsOneWidget);
    expect(find.text('Home base · Domestic'), findsOneWidget);
    expect(find.text('Private alarm labels'), findsNothing);
    await tester.tap(find.text('Alarms').first);
    await tester.pumpAndSettle();
    expect(find.text('Add personal alarm'), findsNothing);
    expect(find.text('Check / retry alarms'), findsNothing);
    expect(find.text('Stop ringing'), findsNothing);
    expect(find.text('iOS alarm / notification permissions'), findsNothing);
    expect(find.byType(CenteredDateTimePicker), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('System alarms enabled'), findsNothing);
    final personal = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('new-personal-'));
    final label = find.descendant(
        of: personal,
        matching: find.widgetWithText(TextField, 'Reminder label (optional)'));
    await tester.ensureVisible(label);
    await tester.enterText(label, 'Passport check');
    final save =
        find.descendant(of: personal, matching: find.text('Add alarm'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(tester.getCenter(save).dx, greaterThan(195));
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
    final wheels =
        find.descendant(of: card, matching: find.byType(CupertinoPicker));
    final hours = wheels.at(0), minutes = wheels.at(1);
    await tester.ensureVisible(hours);
    await tester.pumpAndSettle();
    final label =
        find.descendant(of: card, matching: find.byType(TextField)).first;
    expect(tester.getCenter(label).dy, closeTo(tester.getCenter(hours).dy, 1));
    expect(tester.getSize(card).height, lessThanOrEqualTo(120));
    tester.widget<CupertinoPicker>(hours).scrollController!.jumpToItem(4);
    tester.widget<CupertinoPicker>(minutes).scrollController!.jumpToItem(15);
    await tester.pumpAndSettle();
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
        isTrue);
    await tester.tap(find.byTooltip('Delete reminder'));
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
    final label =
        find.descendant(of: row, matching: find.text('Prepare for Duty'));
    final offset = find.descendant(of: row, matching: find.text('1h 0m'));
    expect(tester.getCenter(label).dy, closeTo(tester.getCenter(offset).dy, 1));
    expect(tester.getSize(row).height, lessThan(65));
    expect(
        find.descendant(of: row, matching: find.byType(Column)), findsNothing);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare for Duty'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('preset-hours')), findsNothing);
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
            '${store.date(store.zoned(at, 'Asia/Seoul'))} · Departure local date'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'unnamed repeating alarm sends a valid iOS identifier and duration',
      (tester) async {
    final store = await open(tester);
    await tester.tap(find.text('Alarms').last);
    await tester.pumpAndSettle();
    final form = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('new-interval-'));
    final button =
        find.descendant(of: form, matching: find.text('Add reminder'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    final record = store.savedIntervals!.single;
    expect(record['id'], matches(RegExp(r'^interval_[0-9]+$')));
    expect(record['label'], 'Repeating reminder');
    expect(record['minutes'], 60);
    expect(record['enabled'], isTrue);
    expect(find.textContaining('Invalid repeating reminder'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('roster calendar stays fixed when schedule list scrolls',
      (tester) async {
    final s = await open(tester);
    final dep = DateTime.now().toUtc().add(const Duration(days: 2));
    s.flights = [
      {
        'id': 'fixed',
        'flight': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'departureUtc': dep.toIso8601String()
      }
    ];
    s.alarms = List.generate(
        12,
        (i) => {
              'id': 'a$i',
              'fnum': 'KE955',
              'depApt': 'ICN',
              'arrApt': 'IST',
              'dep': dep.toIso8601String(),
              'time': dep.subtract(Duration(minutes: i + 1)).toIso8601String(),
              'lbl': 'Prepare $i',
              'armed': true
            });
    s.notifyListeners();
    await tester.pumpAndSettle();
    final calendar = find.byKey(const ValueKey('roster-calendar'));
    final before = tester.getTopLeft(calendar);
    expect(tester.getSize(calendar).height, lessThan(310));
    final list = find.byKey(const ValueKey('roster-schedule-list'));
    await tester.drag(list, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(calendar), before);
    final position = tester
        .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first)
        .position;
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('home base accepts multiple comma separated airports',
      (tester) async {
    final s = await open(tester);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    final editor = find.byType(InlineHomeBaseEditor).first;
    final input = find.descendant(of: editor, matching: find.byType(TextField));
    await tester.enterText(input, 'icn, DFW, ICN');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: editor, matching: find.text('Save')));
    await tester.pumpAndSettle();
    expect(s.settings['baseApt'], 'ICN, DFW');
    expect(s.presetGroup({'depApt': 'DFW'}), 'base');
    expect(s.home, 'ICN');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('personal and repeating lists appear below their creation forms',
      (tester) async {
    final s = await open(tester);
    s.alarms = [
      {
        'id': 'personal-list',
        'type': 'direct',
        'lbl': 'Saved personal',
        'time': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String(),
        'armed': true
      }
    ];
    s.intervals = [
      {
        'id': 'interval_123',
        'label': 'Repeating reminder',
        'minutes': 90,
        'enabled': true
      }
    ];
    await tester.tap(find.text('Alarms').first);
    await tester.pumpAndSettle();
    final personalForm = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('new-personal-'));
    expect(tester.getTopLeft(find.text('Saved personal')).dy,
        greaterThan(tester.getBottomLeft(personalForm).dy));
    final repeatForm = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('new-interval-'));
    await tester.scrollUntilVisible(find.text('Every 1h 30m'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getTopLeft(find.text('Every 1h 30m')).dy,
        greaterThan(tester.getBottomLeft(repeatForm).dy));
    final tile = find
        .ancestor(
            of: find.text('Every 1h 30m'), matching: find.byType(ListTile))
        .first;
    expect(
        find
            .descendant(of: tile, matching: find.byType(Text))
            .evaluate()
            .length,
        2);
    expect(find.descendant(of: tile, matching: find.text('Scheduled')),
        findsNothing);
    expect(find.text('Repeating reminder'), findsNothing);
    expect(find.byIcon(Icons.repeat), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'keyboard keeps reminder label visible while time controls use rollers',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await open(tester);
    final bridge = FlightBriefingController()
      ..connect((_) async => sample('CC101'), (_, __, ___) async {});
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(
            briefing: bridge,
            tools: NativeRosterPage(store: s),
            alarms: NativeRosterPage(store: s, section: 1),
            settings: NativeRosterPage(store: s, section: 2))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final field = find.descendant(
        of: find.byKey(const ValueKey('preset-base-b1')),
        matching: find.byType(TextField));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    final editable =
        find.descendant(of: field, matching: find.byType(EditableText));
    final before = tester.getTopLeft(editable).dy - tester.getTopLeft(field).dy;
    final height = tester.getSize(field).height;
    await tester.showKeyboard(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(844 - 300));
    expect(tester.getTopLeft(editable).dy - tester.getTopLeft(field).dy,
        closeTo(before, 1));
    expect(tester.getSize(field).height, height);
    final position = tester.getTopLeft(field).dy;
    await tester.enterText(field, '1');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(field).dy, closeTo(position, 1));
    expect(tester.getTopLeft(editable).dy - tester.getTopLeft(field).dy,
        closeTo(before, 1));
    expect(find.byTooltip('Close keyboard'), findsNothing);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('preset-base-b1')),
            matching: find.byType(CupertinoPicker)),
        findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
}
