import 'package:crewclock/native_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sample(String key) => {
      'key': key,
      'dark': false,
      'demo': false,
      'flight': {
        'number': key,
        'from': 'DFW',
        'to': 'ICN',
        'departure': '2099-03-10T17:00:00Z'
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
      'steps': [],
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
    final bridge = CrewClockBriefingBridge();
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(
            briefing: bridge, tools: const Text('Roster tools'))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    bridge.connect(
        (key) async => sample(key ?? 'CC101'), (_, __, ___) async {});
    await tester.pumpAndSettle();
    expect(find.text('CC101 · DFW → ICN'), findsOneWidget);
    expect(find.text('America/Chicago'), findsOneWidget);
    expect(find.text('Asia/Seoul'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Next preparation'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('To do: Documents packed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('flight selection and review pass selected flight to roster',
      (tester) async {
    final bridge = CrewClockBriefingBridge();
    final actions = <String>[];
    bridge.connect((key) async => sample(key ?? 'CC101'),
        (action, key, value) async => actions.add('$action:$key'));
    await tester.pumpWidget(MaterialApp(
        home: CrewClockShell(
            briefing: bridge, tools: const Text('Roster tools'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CC102 DFW → ICN').last);
    await tester.pumpAndSettle();
    expect(find.text('CC102 · DFW → ICN'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Review flight alarms'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review flight alarms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review flight alarms'));
    await tester.pumpAndSettle();
    expect(actions, contains('review:CC102'));
    expect(find.text('Roster tools'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('bridge serializes reads and writes without blocking after failure',
      () async {
    final bridge = CrewClockBriefingBridge();
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
