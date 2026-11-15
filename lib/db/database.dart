// db/database.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _db;

  AppDatabase._init();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('crewclock.db');
    return _db!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await _createDB(db, version);
        await db.execute(
            'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
      onUpgrade: (db, old, version) async {
        if (old < 2) {
          await db.execute(
              'CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        }
        if (old < 3) {
          await db.execute('ALTER TABLE alarms ADD COLUMN extra TEXT');
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE alarms (
        id   TEXT PRIMARY KEY,
        time TEXT NOT NULL,
        dep  TEXT,
        lbl  TEXT,
        type TEXT,
        armed    INTEGER NOT NULL DEFAULT 0,
        dism     INTEGER NOT NULL DEFAULT 0,
        missed   INTEGER NOT NULL DEFAULT 0,
        fnum     TEXT,
        depApt   TEXT,
        arrApt   TEXT,
        arrTime  TEXT,
        savedAt  TEXT NOT NULL,
        extra    TEXT
      )
    ''');
  }

  Future<Map<String, dynamic>?> loadNativeState() async {
    final db = await database;
    final rows =
        await db.query('app_state', where: 'key = ?', whereArgs: ['native']);
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(jsonDecode(rows.first['value'] as String));
  }

  Future<void> saveNativeState(Map<String, dynamic> state) async {
    final db = await database;
    await db.insert('app_state', {'key': 'native', 'value': jsonEncode(state)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveAlarmsState(String jsonString) async {
    final db = await database;

    final List<dynamic> list = _parseJson(jsonString);

    final batch = db.batch();
    batch.delete('alarms');

    for (final a in list) {
      batch.insert('alarms', alarmRow(a as Map));
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAlarmsState() async {
    final db = await database;
    return (await db.query('alarms', orderBy: 'time ASC'))
        .map(alarmFromRow)
        .toList();
  }

  static const _alarmColumns = {
    'id',
    'time',
    'dep',
    'lbl',
    'type',
    'armed',
    'dism',
    'missed',
    'fnum',
    'depApt',
    'arrApt',
    'arrTime',
    'savedAt',
    'extra'
  };

  /// Table row for an alarm record. Fields without a column of their own
  /// (time basis, wall time, zone, timer duration…) are kept as JSON in
  /// `extra` so they survive a reload.
  static Map<String, Object?> alarmRow(Map a) {
    int flag(dynamic v) => v == true || v == 1 ? 1 : 0;
    final extra = {
      for (final e in a.entries)
        if (!_alarmColumns.contains(e.key) && e.value != null)
          '${e.key}': e.value
    };
    return {
      'id': a['id']?.toString() ?? '',
      'time': a['time']?.toString() ?? '',
      'dep': a['dep']?.toString(),
      'lbl': a['lbl']?.toString(),
      'type': a['type']?.toString(),
      'armed': flag(a['armed']),
      'dism': flag(a['dism']),
      'missed': flag(a['missed']),
      'fnum': a['fnum']?.toString(),
      'depApt': a['depApt']?.toString(),
      'arrApt': a['arrApt']?.toString(),
      'arrTime': a['arrTime']?.toString(),
      'savedAt': DateTime.now().toIso8601String(),
      'extra': extra.isEmpty ? null : jsonEncode(extra),
    };
  }

  /// Inverse of [alarmRow]; column values win over anything in `extra`.
  static Map<String, dynamic> alarmFromRow(Map row) {
    Map extra = const {};
    try {
      final decoded = jsonDecode('${row['extra'] ?? '{}'}');
      if (decoded is Map) extra = decoded;
    } on FormatException {
      // Unreadable extras are dropped; the alarm itself is still valid.
    }
    return {
      for (final e in extra.entries)
        if (!_alarmColumns.contains(e.key)) '${e.key}': e.value,
      for (final e in row.entries)
        if (e.key != 'extra') '${e.key}': e.value
    };
  }

  Future<void> dismissAlarms(List<String> ids) async {
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('alarms',
          where: 'id = ? AND type = ?', whereArgs: [id, 'direct']);
      batch.update('alarms', {'dism': 1, 'armed': 0},
          where: 'id = ? AND (type IS NULL OR type != ?)',
          whereArgs: [id, 'direct']);
    }
    await batch.commit(noResult: true);
  }

  List<dynamic> _parseJson(String raw) {
    try {
      return List<dynamic>.from(jsonDecode(raw) as List);
    } catch (e) {
      throw FormatException(
          'Invalid alarm data; existing alarms were preserved.', raw);
    }
  }
}
