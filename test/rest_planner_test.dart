import 'package:crewclock/services/crewclock_store.dart';
import 'package:crewclock/widgets/crewclock_theme.dart';
import 'package:crewclock/widgets/rest_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class RestStore extends CrewClockStore {
  Map<String, dynamic>? savedConfig;
  var cleared = false;
  @override
  Future<void> saveRestPlan(Map f, Map<String, dynamic>? config) async {
    alarms.removeWhere((a) => '${a['id']}'.startsWith('rest_'));
    if (config == null) {
      cleared = true;
    } else {
      savedConfig = config;
      alarms.addAll(restPlan(f, config).alarms);
    }
    notifyListeners();
  }
}

final flight = <String, dynamic>{
  'flight': 'KE081',
  'depApt': 'ICN',
  'arrApt': 'JFK',
  'departureUtc': '2099-11-02T01:00:00.000Z',
  'arrivalUtc': '2099-11-02T15:00:00.000Z'
};

RestStore store() => RestStore()
  ..parser.zones = {'ICN': 'Asia/Seoul', 'JFK': 'America/New_York'}
  ..flights = [flight];

Future<void> pump(WidgetTester tester, RestStore s,
    {double width = 390, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: CrewClockTheme.data(dark: false),
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: SingleChildScrollView(
                  child: AnimatedBuilder(
                      animation: s,
                      builder: (_, __) => RestPlanner(store: s)))))));
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('splits available time equally on five-minute changeovers', () {
    final periods = CrewClockStore.restPeriods(
        DateTime.utc(2099, 11, 2, 1), DateTime.utc(2099, 11, 2, 15),
        periods: 3, after: 30, before: 60);
    expect(periods.first.first, DateTime.utc(2099, 11, 2, 1, 30));
    expect(periods.last.last, DateTime.utc(2099, 11, 2, 14));
    // 12h30m / 3 = 4h10m.
    expect(periods[0][1], DateTime.utc(2099, 11, 2, 5, 40));
    expect(periods[1][1], DateTime.utc(2099, 11, 2, 9, 50));
    expect(periods[1][0], periods[0][1]);
    final uneven = CrewClockStore.restPeriods(
        DateTime.utc(2099, 11, 2, 1), DateTime.utc(2099, 11, 2, 11, 7),
        periods: 4, after: 30, before: 60);
    for (final p in uneven.skip(1)) {
      expect(p[0].minute % 5, 0);
    }
    expect(
        () => CrewClockStore.restPeriods(
            DateTime.utc(2099, 11, 2, 1), DateTime.utc(2099, 11, 2, 3),
            periods: 3, after: 30, before: 60),
        throwsFormatException);
  });

  test('plans alarms for my rest or for every changeover with a delay', () {
    final s = store();
    final mine = s.restPlan(flight, {...CrewClockStore.restDefaults, 'mine': 1});
    expect(mine.alarms.map((a) => a['lbl']), [
      'KE081 · My rest starts (2/3)',
      'KE081 · My rest ends (2/3)'
    ]);
    expect(mine.alarms.first['time'], '2099-11-02T05:40:00.000Z');
    expect(mine.alarms.every((a) => a['type'] == 'timer'), isTrue);
    final all = s.restPlan(flight,
        {...CrewClockStore.restDefaults, 'mine': 1, 'all': true, 'delay': 20});
    expect(all.alarms.length, 4);
    expect(all.alarms.first['time'], '2099-11-02T01:50:00.000Z');
    expect(all.alarms[1]['lbl'], 'KE081 · My rest starts (2/3)');
    expect(all.alarms.map((a) => a['id']).toSet().length, 4);
  });

  testWidgets('shows periods, saves the chosen rest and clears it',
      (tester) async {
    final s = store();
    await pump(tester, s);
    expect(find.text('KE081  ICN → JFK'), findsOneWidget);
    expect(find.text('01:30–05:40 Z'), findsOneWidget);
    expect(find.text('10:30–14:40 ICN time'), findsOneWidget);
    expect(find.text('MINE'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('rest-mine-control')),
        matching: find.text('2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set 2 rest alarms'));
    await tester.pumpAndSettle();
    expect(s.savedConfig!['mine'], 1);
    expect(find.text('2 alarms set'), findsOneWidget);
    expect(find.text('Update rest alarms'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rest-clear')));
    await tester.pumpAndSettle();
    expect(s.cleared, isTrue);
    expect(find.byKey(const ValueKey('rest-saved')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports too-short flights and fits large text', (tester) async {
    final s = store()
      ..flights = [
        {...flight, 'arrivalUtc': '2099-11-02T03:00:00.000Z'}
      ];
    await pump(tester, s, width: 320, scale: 1.6);
    expect(find.byKey(const ValueKey('rest-error')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('rest-save')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains when no flight has an arrival time', (tester) async {
    final s = store()
      ..flights = [
        {...flight, 'arrivalUtc': null}
      ];
    await pump(tester, s);
    expect(find.textContaining('Add a flight with an arrival time'),
        findsOneWidget);
  });
}
