import 'package:crewclock/services/crewclock_store.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_test/flutter_test.dart';

class SettingsStore extends CrewClockStore {
  @override
  Future<void> refresh({bool notify = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('preparation settings place earlier alarms above later alarms', () {
    final s = CrewClockStore();
    s.settings = {
      'baseOffs': [
        {'id': 'later', 'lbl': 'Airport', 'h': 4, 'm': 15},
        {'id': 'earlier', 'lbl': 'Prepare', 'h': 4, 'm': 30},
        {'id': 'latest', 'lbl': 'Boarding', 'h': 0, 'm': 40},
      ]
    };
    expect(s.preparationPresets('base').map((p) => p['id']),
        ['earlier', 'later', 'latest']);
    expect(s.offsets({'depApt': 'ICN'}).map((p) => p['m']), [30, 15, 40]);
    s.dispose();
  });
  test('every comma separated base airport uses its own presets', () {
    final s = CrewClockStore();
    s.settings = {'baseApt': 'ICN, PUS', 'domesticBaseApt': 'GMP, CJU'};
    expect(s.presetGroup({'depApt': 'PUS'}), 'base');
    expect(s.presetGroup({'depApt': 'CJU'}), 'dom');
    expect(s.home, 'ICN');
    final presets = s.offsets({'depApt': 'CJU'});
    expect((presets[0]['h'], presets[0]['m']), (3, 30));
    expect((presets[1]['h'], presets[1]['m']), (3, 30));
    s.dispose();
  });
  test('departure airport selects independent international and domestic bases',
      () {
    final s = CrewClockStore();
    s.settings = {'baseApt': 'ICN', 'domesticBaseApt': 'GMP'};
    expect(s.presetGroup({'depApt': 'GMP', 'arrApt': 'HND'}), 'dom');
    expect(s.presetGroup({'depApt': 'ICN', 'arrApt': 'CJU'}), 'base');
    expect(s.presetGroup({'depApt': 'IST', 'arrApt': 'ICN'}), 'intl');
    expect(s.offsets({'depApt': 'GMP'}).first['h'], 3);
    expect(s.offsets({'depApt': 'GMP'})[1]['h'], 3);
    expect(s.offsets({'depApt': 'GMP'})[1]['m'], 30);
    s.dispose();
  });
  test(
      'preset changes update saved flights while preserving custom and completed alarms',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'),
            (call) async {
      if (call.method == 'getDatabasesPath') return '/tmp';
      if (call.method == 'openDatabase') return {'id': 1};
      if (call.method == 'query') return <Map<String, Object?>>[];
      if (call.method == 'batch') return <Object>[];
      if (call.method == 'insert') return 1;
      return null;
    });
    databaseFactory = databaseFactorySqflitePlugin;
    final s = SettingsStore();
    s.settings = {'baseApt': 'ICN'};
    s.flights = [
      {
        'id': 'f1',
        'flight': 'KE955',
        'depApt': 'ICN',
        'arrApt': 'IST',
        'departureUtc': '2099-11-02T04:55:00.000Z'
      }
    ];
    s.alarms = s.buildFlightAlarms(s.flights.single);
    s.alarms.first['dism'] = true;
    s.alarms.first['armed'] = false;
    s.alarms.add({
      'id': 'custom',
      'lbl': 'Custom',
      'time': '2099-11-02T01:00:00.000Z',
      'type': 'direct'
    });
    final next = s.maps(CrewClockStore.defaults['baseOffs']);
    next.first['h'] = 5;
    try {
      await s.saveSettings({'baseApt': 'ICN', 'baseOffs': next});
    } on ArgumentError {
      // The iOS-only scheduler cannot initialize on the host test platform.
    }
    expect(s.alarms.first['time'], '2099-11-01T23:25:00.000Z');
    expect(s.alarms.first['dism'], true);
    expect(s.alarms.first['armed'], false);
    expect(s.alarms.last['id'], 'custom');
    s.dispose();
  });
}
