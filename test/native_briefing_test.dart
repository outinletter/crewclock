import 'package:crewclock/native_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sample(String key) => {
      'key': key,
      'dark': false,
      'demo': false,
      'flight': {
        'number': key,
        'from': 'DFW',
        'to': 'ICN',
        'departure': '2099-03-10T17:00:00Z',
        'dateBadge': '03/10 Tue',
        'departureTime': '12:00',
        'arrivalTime': '20:05'
      },
      'flights': [
        {'key': 'CC101', 'label': 'CC101 DFW → ICN'},
        {'key': 'CC102', 'label': 'CC102 DFW → ICN'}
      ],
      'clocks': [
        {
          'label': 'DFW departure',
          'time': '12:00',
          'date': '2099-03-10',
          'zone': 'America/Chicago'
        },
        {
          'label': 'ICN home',
          'time': '02:00',
          'date': '2099-03-11',
          'zone': 'Asia/Seoul'
        },
        {'label': 'UTC', 'time': '17:00', 'date': '2099-03-10', 'zone': 'UTC'}
      ],
      'next': {'label': 'Prepare for Duty', 'time': '2099-03-10 08:00 DFW'},
      'steps': [
        {
          'id': 'flight_b1',
          'minutesBefore': 270,
          'armed': true,
          'label': 'Prepare for Duty',
          'clock': '09:25',
          'offset': '-4h30m',
          'time': '2099-03-10 09:25 DFW',
          'status': 'Scheduled'
        }
      ],
      'tasks': [
        {'label': 'Documents packed', 'checkedAt': null, 'checkedText': null}
      ],
      'note': '',
    };

void main() {
  testWidgets(
      'waits for roster readiness, then shows three zones and next preparation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bridge = FlightBriefingController();
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(
            briefing: bridge, tools: const Text('Roster tools'))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    bridge.connect(
        (key) async => sample(key ?? 'CC101'), (_, __, ___) async {});
    await tester.pumpAndSettle();
    expect(find.text('CC101 · DFW → ICN'), findsOneWidget);
    expect(find.text('CrewClock'), findsOneWidget);
    expect(find.text('Next flight'), findsNothing);
    expect(find.text('America/Chicago'), findsOneWidget);
    expect(find.text('Asia/Seoul'), findsOneWidget);
    final heights = ['DFW departure', 'ICN home', 'UTC']
        .map((label) => tester
            .getSize(find.byKey(ValueKey('briefing-clock-$label')))
            .height)
        .toList();
    expect(heights[1], heights[0]);
    expect(heights[2], heights[0]);
    expect(find.text('Next preparation'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('flight selection updates briefing without redundant review card',
      (tester) async {
    final bridge = FlightBriefingController();
    final actions = <String>[];
    bridge.connect((key) async => sample(key ?? 'CC101'),
        (action, key, value) async => actions.add('$action:$key'));
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(
            briefing: bridge, tools: const Text('Roster tools'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-flight')));
    await tester.pumpAndSettle();
    expect(find.text('Choose flight'), findsOneWidget);
    await tester.tap(find.text('CC102 DFW → ICN').first);
    await tester.pumpAndSettle();
    expect(find.text('CC102 · DFW → ICN'), findsOneWidget);
    expect(find.text('Review flight alarms'), findsNothing);
    expect(actions, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native pages swipe both ways and retain selection',
      (tester) async {
    final bridge = FlightBriefingController();
    bridge.connect(
        (key) async => sample(key ?? 'CC101'), (_, __, ___) async {});
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(
            briefing: bridge,
            tools: const Center(child: Text('Native roster')))));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('crewclock-pages')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Native roster'), findsOneWidget);
    expect(
        tester
            .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
            .currentIndex,
        1);
    await tester.drag(
        find.byKey(const ValueKey('crewclock-pages')), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('CC101 · DFW → ICN'), findsOneWidget);
    expect(
        tester
            .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
            .currentIndex,
        0);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('preparation-flight-list')), 300,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('briefing-scroll')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('09:25(L)'), findsOneWidget);
    await tester.ensureVisible(find.text('Prepare for Duty'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prepare for Duty'));
    await tester.pumpAndSettle();
    final hours = find.descendant(
        of: find.byKey(const ValueKey('timeline-flight_b1')),
        matching: find.widgetWithText(TextField, 'Hours'));
    expect(hours, findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preparation deletion requires edit mode, not a swipe',
      (tester) async {
    final data = sample('CC101');
    final actions = <String>[];
    final bridge = FlightBriefingController();
    bridge.connect((_) async => data, (action, _, value) async {
      actions.add(action);
      if (action == 'delete') data['tasks'] = <Map<String, dynamic>>[];
    });
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(briefing: bridge, tools: const SizedBox())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Edit preparation'), 250,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('briefing-scroll')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.byType(Dismissible), findsNothing);
    expect(find.byTooltip('Delete preparation item'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Edit preparation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit preparation'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Delete preparation item'));
    await tester.tap(find.byTooltip('Delete preparation item'));
    await tester.pumpAndSettle();
    expect(actions, contains('delete'));
    expect(find.text('Documents packed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('four primary tabs are directly reachable and swipeable',
      (tester) async {
    final bridge = FlightBriefingController();
    bridge.connect((_) async => sample('CC101'), (_, __, ___) async {});
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(
            briefing: bridge,
            tools: const Text('Roster content'),
            alarms: const Text('Alarms content'),
            settings: const Text('Settings content'))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
            .items
            .length,
        4);
    await tester.fling(find.byKey(const ValueKey('crewclock-pages')),
        const Offset(-60, 0), 1500);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
            .currentIndex,
        0);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings content'), findsOneWidget);
    await tester.tap(find.text('Alarms'));
    await tester.pumpAndSettle();
    expect(find.text('Alarms content'), findsOneWidget);
    await tester.drag(
        find.byKey(const ValueKey('crewclock-pages')), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(find.text('Roster content'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('picker pins upcoming flights above past flights',
      (tester) async {
    final bridge = FlightBriefingController();
    final now = DateTime.now();
    final data = sample('old');
    data['flights'] = [
      {
        'key': 'old',
        'label': 'Past flight',
        'departure': now.subtract(const Duration(days: 1)).toIso8601String()
      },
      {
        'key': 'later',
        'label': 'Later flight',
        'departure': now.add(const Duration(days: 2)).toIso8601String()
      },
      {
        'key': 'next',
        'label': 'Upcoming flight',
        'departure': now.add(const Duration(days: 1)).toIso8601String()
      },
    ];
    bridge.connect((_) async => data, (_, __, ___) async {});
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(briefing: bridge, tools: const SizedBox())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choose-flight')));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    Finder entry(String title) =>
        find.descendant(of: sheet, matching: find.text(title)).first;
    expect(tester.getTopLeft(entry('Upcoming flight')).dy,
        lessThan(tester.getTopLeft(entry('Later flight')).dy));
    expect(tester.getTopLeft(entry('Later flight')).dy,
        lessThan(tester.getTopLeft(entry('Past flight')).dy));
    await tester.pumpWidget(const SizedBox());
  });

  test('bridge serializes reads and writes without blocking after failure',
      () async {
    final bridge = FlightBriefingController();
    final events = <String>[];
    bridge.connect((key) async {
      events.add('load');
      return sample('CC101');
    }, (action, key, value) async {
      events.add(action);
      if (action == 'fail') throw StateError('save failed');
    });
    final write = bridge.action('note', 'CC101');
    final read = bridge.load('CC101');
    await write;
    await read;
    expect(events, ['note', 'load']);
    await expectLater(bridge.action('fail', 'CC101'), throwsStateError);
    expect((await bridge.load(null))['key'], 'CC101');
  });
}
