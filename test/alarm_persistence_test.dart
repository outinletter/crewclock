import 'dart:convert';
import 'package:crewclock/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alarm fields without their own column survive a save and reload', () {
    final timer = {
      'id': 'timer_1',
      'lbl': 'Handover',
      'time': '2099-11-02T05:00:00.000Z',
      'type': 'timer',
      'armed': true,
      'dism': false,
      'missed': false,
      'elapsedAlarm': true,
      'durationMinutes': 200,
      'oneShot': true
    };
    final row = AppDatabase.alarmRow(timer);
    expect(row['armed'], 1);
    expect(jsonDecode(row['extra'] as String),
        {'elapsedAlarm': true, 'durationMinutes': 200, 'oneShot': true});
    final restored = AppDatabase.alarmFromRow(row);
    expect(restored['durationMinutes'], 200);
    expect(restored['elapsedAlarm'], true);
    expect(restored['lbl'], 'Handover');
    expect(restored.containsKey('extra'), isFalse);

    final personal = AppDatabase.alarmFromRow(AppDatabase.alarmRow({
      'id': 'p1',
      'time': '2099-11-02T05:00:00.000Z',
      'type': 'direct',
      'armed': 1,
      'timeBasis': 'device',
      'wallDate': '2099-11-02',
      'wallTime': '14:00',
      'zone': 'Asia/Seoul'
    }));
    expect(personal['timeBasis'], 'device');
    expect(personal['wallTime'], '14:00');
    expect(personal['zone'], 'Asia/Seoul');
  });

  test('rows saved before the extra column and bad extras still load', () {
    final legacy = AppDatabase.alarmFromRow(
        {'id': 'a', 'time': 't', 'armed': 1, 'dism': 0, 'extra': null});
    expect(legacy, {'id': 'a', 'time': 't', 'armed': 1, 'dism': 0});
    final broken = AppDatabase.alarmFromRow(
        {'id': 'a', 'time': 't', 'extra': '{not json'});
    expect(broken['id'], 'a');
    // A column value is never overridden by a same-named extra.
    final clash = AppDatabase.alarmFromRow(
        {'id': 'a', 'armed': 0, 'extra': '{"armed":1,"zone":"UTC"}'});
    expect(clash['armed'], 0);
    expect(clash['zone'], 'UTC');
    expect(AppDatabase.alarmRow({'id': 'x', 'time': 't'})['extra'], isNull);
  });
}
