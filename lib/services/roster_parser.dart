import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

class RosterParser {
  Map<String, String> zones = {};
  Future<void> initialize() async {
    zones = Map<String, String>.from(jsonDecode(
        await rootBundle.loadString('assets/data/airport_timezones.json')));
  }

  String? zone(String airport) => zones[airport.toUpperCase()];
  tz.Location location(String name) => tz.getLocation(name);
  DateTime localInstant(String date, String time, String zone) {
    final day = DateTime.tryParse(date);
    if (day == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}' !=
            date) {
      throw const FormatException(
          'Enter an existing calendar date as YYYY-MM-DD.');
    }
    final parts = time.split(':');
    final h = int.tryParse(parts.first),
        m = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      throw const FormatException('Enter a valid date and 24-hour time.');
    }
    final z = location(zone);
    final at = tz.TZDateTime(z, day.year, day.month, day.day, h, m);
    if (at.hour != h || at.minute != m || at.day != day.day) {
      throw const FormatException(
          'This local time does not exist due to a daylight-saving change. Use UTC.');
    }
    for (final delta in [-60, 60]) {
      final other = tz.TZDateTime.from(at.add(Duration(minutes: delta)), z);
      if (other.year == at.year &&
          other.month == at.month &&
          other.day == at.day &&
          other.hour == h &&
          other.minute == m) {
        throw const FormatException(
            'This local time occurs twice due to daylight saving. Import an explicit UTC time.');
      }
    }
    return at.toUtc();
  }

  List<Map<String, dynamic>> parse(String text) {
    if (text.length > 5000000) {
      throw const FormatException('Choose a roster smaller than 5 MB.');
    }
    return text.contains('BEGIN:VEVENT') ? _calendar(text) : _lines(text);
  }

  List<Map<String, dynamic>> _calendar(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n[ \t]'), '')
        .split('\n');
    final flights = <Map<String, dynamic>>[];
    Map<String, String>? event;
    String? calendarZone;
    for (final line in lines) {
      if (line.startsWith('X-WR-TIMEZONE:')) {
        calendarZone = line.substring('X-WR-TIMEZONE:'.length).trim();
      }
      if (line.trim() == 'BEGIN:VEVENT') {
        event = {};
        continue;
      }
      if (line.trim() == 'END:VEVENT') {
        if (event != null) {
          final summary = (event['SUMMARY'] ?? '').toUpperCase();
          final number = RegExp(r'\b([A-Z]{2,3}\s?\d{1,4})\b')
              .firstMatch(summary)
              ?.group(1)
              ?.replaceAll(' ', '');
          final route =
              RegExp(r'\b([A-Z]{3})\s*(?:[-–—/→]|TO|\s)\s*([A-Z]{3})\b')
                  .firstMatch(summary);
          if (number != null &&
              route != null &&
              !RegExp(r'\b(OFF|STANDBY|SICK|RESERVE)\b').hasMatch(summary)) {
            if (event.containsKey('RRULE')) {
              throw const FormatException(
                  'Recurring calendar events need individual dated flights.');
            }
            final from = route.group(1)!, to = route.group(2)!;
            final dep = _icsDate(event['DTSTART'] ?? '',
                event['DTSTART_ZONE'] ?? calendarZone ?? zone(from));
            final arrival = event['DTEND'] == null
                ? null
                : _icsDate(event['DTEND']!,
                    event['DTEND_ZONE'] ?? calendarZone ?? zone(to));
            if (arrival != null && !arrival.isAfter(dep)) {
              throw FormatException('$number arrival must be after departure.');
            }
            flights.add({
              'id': event['UID'] ?? '$number|$from|${dep.toIso8601String()}',
              'flight': number,
              'depApt': from,
              'arrApt': to,
              'departureUtc': dep.toIso8601String(),
              'arrivalUtc': arrival?.toIso8601String()
            });
          }
        }
        event = null;
        continue;
      }
      if (event == null) continue;
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final header = line.substring(0, colon),
          key = header.split(';').first.toUpperCase();
      event[key] = line
          .substring(colon + 1)
          .trim()
          .replaceAll(r'\,', ',')
          .replaceAll(r'\n', ' ');
      final zoneMatch = RegExp(r'TZID="?([^;"\r\n]+)').firstMatch(header);
      if (zoneMatch != null) event['${key}_ZONE'] = zoneMatch.group(1)!;
    }
    return _deduplicate(flights);
  }

  DateTime _icsDate(String value, String? zoneName) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$')
        .firstMatch(value);
    if (m == null) {
      throw const FormatException(
          'Use timed calendar flights, not all-day events.');
    }
    final date = '${m[1]}-${m[2]}-${m[3]}', time = '${m[4]}:${m[5]}';
    if (m[7] == 'Z') {
      return localInstant(date, time, 'UTC')
          .add(Duration(seconds: int.parse(m[6] ?? '0')));
    }
    if (zoneName == null) {
      throw const FormatException(
          'Calendar time zone is missing. Import UTC or specify the airport time zone.');
    }
    return localInstant(date, time, zoneName)
        .add(Duration(seconds: int.parse(m[6] ?? '0')));
  }

  List<Map<String, dynamic>> _lines(String raw) {
    final flights = <Map<String, dynamic>>[];
    for (final line in raw.split('\n').where((l) => l.trim().isNotEmpty)) {
      final m = RegExp(
              r'^(\d{4}-\d{2}-\d{2})[\s,]+([A-Za-z]{2,3}\d{1,4})[\s,]+([A-Za-z]{3})[\s,→/-]+([A-Za-z]{3})[\s,]+(\d{2}:\d{2})\s*$')
          .firstMatch(line.trim());
      if (m == null) {
        throw const FormatException(
            'Text format: YYYY-MM-DD KE955 ICN IST 13:55. Use manual entry for other formats.');
      }
      final from = m[3]!.toUpperCase(), to = m[4]!.toUpperCase();
      final z = zone(from);
      if (z == null) {
        throw FormatException(
            'Unknown airport $from. Use manual entry with an explicit time zone.');
      }
      final dep = localInstant(m[1]!, m[5]!, z);
      flights.add({
        'id': '${m[2]}|$from|${dep.toIso8601String()}',
        'flight': m[2]!.toUpperCase(),
        'depApt': from,
        'arrApt': to,
        'departureUtc': dep.toIso8601String(),
        'arrivalUtc': null
      });
    }
    return _deduplicate(flights);
  }

  List<Map<String, dynamic>> _deduplicate(List<Map<String, dynamic>> flights) {
    if (flights.isEmpty) {
      throw const FormatException(
          'No dated flights were found. Try manual flight entry.');
    }
    final unique = <String, Map<String, dynamic>>{};
    for (final f in flights) {
      unique['${f['flight']}|${f['depApt']}|${f['departureUtc']}'] = f;
    }
    return unique.values.toList()
      ..sort(
          (a, b) => '${a['departureUtc']}'.compareTo('${b['departureUtc']}'));
  }
}
