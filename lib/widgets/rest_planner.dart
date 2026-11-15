import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/crewclock_store.dart';
import 'crewclock_theme.dart';
import 'ios_controls.dart';

/// Plans equal in-flight rest periods for a roster flight and reserves
/// one-shot alarms for the changeovers.
class RestPlanner extends StatefulWidget {
  const RestPlanner({super.key, required this.store});
  final CrewClockStore store;
  @override
  State<RestPlanner> createState() => _RestPlannerState();
}

class _RestPlannerState extends State<RestPlanner> {
  String? _key;
  Map<String, dynamic>? _config;
  String? _error;
  bool _saving = false;

  CrewClockStore get store => widget.store;

  static String _span(int minutes) =>
      '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

  void _set(String name, Object value) => setState(() {
        _config = {..._config!, name: value};
        _error = null;
      });

  Future<void> _save(Map<String, dynamic> flight, bool clear) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await store.saveRestPlan(flight, clear ? null : _config);
      if (clear && mounted) setState(() => _config = null);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not reserve the rest alarms. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stepper(String label, String name,
      {required int min, required int max, bool signed = false}) {
    final value = (_config![name] as num).toInt();
    Widget button(IconData icon, int next, String tip) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed:
            _saving || next < min || next > max ? null : () => _set(name, next),
        icon: Icon(icon));
    return Row(children: [
      Expanded(child: Text(label)),
      button(CupertinoIcons.minus_circle, value - 5, 'Decrease $label'),
      SizedBox(
          width: 58,
          child: Text(
              '${signed && value > 0 ? '+' : ''}${value.abs() >= 60 ? _span(value.abs()) : '${value}m'}',
              key: ValueKey('rest-$name'),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()]))),
      button(CupertinoIcons.plus_circle, value + 5, 'Increase $label'),
    ]);
  }

  Widget _segments(String label, String name, int from, int to) =>
      Row(children: [
        Expanded(child: Text(label)),
        CupertinoSlidingSegmentedControl<int>(
            key: ValueKey('rest-$name-control'),
            // Explicit colours so the selected number stays legible in dark.
            backgroundColor: Theme.of(context).colorScheme.outlineVariant,
            thumbColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff31557d)
                : Colors.white,
            groupValue: (_config![name] as num).toInt().clamp(from, to),
            onValueChanged: (v) {
              if (v == null || _saving) return;
              if (name == 'periods') {
                final mine = (_config!['mine'] as num).toInt();
                _config = {..._config!, 'mine': mine.clamp(0, v - 1)};
              }
              _set(name, v);
            },
            children: {
              for (var i = from; i <= to; i++)
                i: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('${name == 'mine' ? i + 1 : i}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface)))
            }),
      ]);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rest = CrewClockTheme.rest(
        dark: Theme.of(context).brightness == Brightness.dark);
    final flights = store.restFlights();
    final decoration = BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CrewClockTheme.cardRadius));
    final heading = Text('IN-FLIGHT REST',
        style: TextStyle(
            color: rest, letterSpacing: 1.5, fontWeight: FontWeight.w700));
    if (flights.isEmpty) {
      return Container(
          key: const ValueKey('rest-planner'),
          padding: const EdgeInsets.all(14),
          decoration: decoration,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            heading,
            const SizedBox(height: 6),
            Text('Add a flight with an arrival time to split its rest periods.',
                style: TextStyle(color: colors.onSurfaceVariant)),
          ]));
    }
    final flight = flights.firstWhere((f) => store.key(f) == _key,
        orElse: () => flights.first);
    if (_key != store.key(flight) || _config == null) {
      _key = store.key(flight);
      _config = store.restConfig(flight);
    }
    final config = _config!;
    final saved = store.restAlarms(flight);
    final count = (config['periods'] as num).toInt();
    final mine = (config['mine'] as num).toInt().clamp(0, count - 1);
    final zone = store.airportZone('${flight['depApt']}');
    String clock(DateTime t, String? z) => store.clock(store.zoned(t, z));

    List<List<DateTime>>? periods;
    var planned = 0;
    String? problem = _error;
    try {
      final plan = store.restPlan(flight, config);
      periods = plan.periods;
      planned = plan.alarms.length;
    } on FormatException catch (e) {
      problem ??= e.message;
    }
    final delay = Duration(minutes: (config['delay'] as num).toInt());
    final dep = store.departure(flight).add(delay);
    final arr = DateTime.parse('${flight['arrivalUtc']}').toUtc().add(delay);

    return Container(
        key: const ValueKey('rest-planner'),
        padding: const EdgeInsets.all(14),
        decoration: decoration,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: heading),
            if (saved.isNotEmpty)
              Text('${saved.length} alarm${saved.length == 1 ? '' : 's'} set',
                  key: const ValueKey('rest-saved'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant)),
          ]),
          const SizedBox(height: 4),
          IosMenuButton<String>(
              key: const ValueKey('rest-flight'),
              enabled: flights.length > 1 && !_saving,
              tooltip: 'Choose flight',
              title: 'Flight',
              onSelected: (k) => setState(() {
                    _key = k;
                    _config = null;
                    _error = null;
                  }),
              items: [
                for (final f in flights.take(12))
                  IosMenuItem(store.key(f), store.flightLabel(f))
              ],
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            '${flight['flight']}  ${flight['depApt']} → ${flight['arrApt']}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700))),
                    if (flights.length > 1)
                      Icon(CupertinoIcons.chevron_up_chevron_down,
                          size: 16, color: colors.onSurfaceVariant),
                  ]))),
          Text(
              'Block ${clock(dep, 'UTC')}–${clock(arr, 'UTC')} Z · ${_span(arr.difference(dep).inMinutes)}',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          const SizedBox(height: 10),
          if (periods != null) ...[
            ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                    height: 14,
                    child: Row(children: [
                      Expanded(
                          flex: periods.first[0].difference(dep).inMinutes + 1,
                          child: ColoredBox(color: colors.outlineVariant)),
                      for (var i = 0; i < count; i++)
                        Expanded(
                            flex: periods[i][1]
                                .difference(periods[i][0])
                                .inMinutes,
                            child: Container(
                                margin: const EdgeInsets.only(left: 2),
                                color: i == mine
                                    ? rest
                                    : rest.withValues(alpha: .3))),
                      Expanded(
                          flex: arr.difference(periods.last[1]).inMinutes + 1,
                          child: Container(
                              margin: const EdgeInsets.only(left: 2),
                              color: colors.outlineVariant)),
                    ]))),
            const SizedBox(height: 8),
            for (var i = 0; i < count; i++)
              Container(
                  key: ValueKey('rest-period-$i'),
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      color: i == mine
                          ? rest.withValues(alpha: .14)
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(CrewClockTheme.innerRadius)),
                  child: Row(children: [
                    SizedBox(
                        width: 44,
                        child: Text(i == mine ? 'MINE' : 'Rest ${i + 1}',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: i == mine
                                    ? rest
                                    : colors.onSurfaceVariant))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              '${clock(periods[i][0], 'UTC')}–${clock(periods[i][1], 'UTC')} Z',
                              style: CrewClockTheme.timeSmall),
                          Text(
                              '${clock(periods[i][0], zone)}–${clock(periods[i][1], zone)} ${flight['depApt']} time',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant)),
                        ])),
                    Text(
                        _span(
                            periods[i][1].difference(periods[i][0]).inMinutes),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ])),
            const SizedBox(height: 8),
          ],
          _segments('Rest periods', 'periods', 2, 4),
          const SizedBox(height: 8),
          _segments('My rest', 'mine', 0, count - 1),
          _stepper('Start after departure', 'after', min: 0, max: 180),
          _stepper('End before arrival', 'before', min: 0, max: 180),
          _stepper('Departure delay', 'delay',
              min: -60, max: 600, signed: true),
          Row(children: [
            const Expanded(child: Text('Alarm at every changeover')),
            Switch.adaptive(
                key: const ValueKey('rest-all'),
                value: config['all'] == true,
                onChanged: _saving ? null : (v) => _set('all', v)),
          ]),
          if (problem != null)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(problem,
                    key: const ValueKey('rest-error'),
                    style: TextStyle(color: colors.error))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: FilledButton(
                    key: const ValueKey('rest-save'),
                    onPressed: _saving || periods == null || planned == 0
                        ? null
                        : () => _save(flight, false),
                    child: Text(saved.isEmpty
                        ? 'Set $planned rest alarm${planned == 1 ? '' : 's'}'
                        : 'Update rest alarms'))),
            if (saved.isNotEmpty) ...[
              const SizedBox(width: 8),
              TextButton(
                  key: const ValueKey('rest-clear'),
                  onPressed: _saving ? null : () => _save(flight, true),
                  child: const Text('Clear')),
            ],
          ]),
          const SizedBox(height: 6),
          Text(
              'Uses roster block times. Adjust the delay after the actual departure. Personal reminder only.',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ]));
  }
}
