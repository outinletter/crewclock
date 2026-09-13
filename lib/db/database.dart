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
      version: 1,
      onCreate: _createDB,
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
        savedAt  TEXT NOT NULL
      )
    ''');
  }

  Future<void> saveAlarmsState(String jsonString) async {
    final db = await database;

    final List<dynamic> list = _parseJson(jsonString);

    final batch = db.batch();
    batch.delete('alarms');

    for (final a in list) {
      batch.insert('alarms', {
        'id': a['id']?.toString() ?? '',
        'time': a['time']?.toString() ?? '',
        'dep': a['dep']?.toString(),
        'lbl': a['lbl']?.toString(),
        'type': a['type']?.toString(),
        'armed': _boolToInt(a['armed']),
        'dism': _boolToInt(a['dism']),
        'missed': _boolToInt(a['missed']),
        'fnum': a['fnum']?.toString(),
        'depApt': a['depApt']?.toString(),
        'arrApt': a['arrApt']?.toString(),
        'arrTime': a['arrTime']?.toString(),
        'savedAt': DateTime.now().toIso8601String(),
      });
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAlarmsState() async {
    final db = await database;
    return db.query('alarms', orderBy: 'time ASC');
  }

  Future<void> dismissAlarms(List<String> ids) async {
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('alarms', {'dism': 1}, where: 'id = ?', whereArgs: [id]);
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

  int _boolToInt(dynamic v) {
    if (v == null) return 0;
    if (v is bool) return v ? 1 : 0;
    if (v is int) return v;
    return 0;
  }
}
