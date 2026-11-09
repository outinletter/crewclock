import 'widgets/width_aware_title.dart';
import 'widgets/alarm_time_visuals.dart';
import 'widgets/relative_alarm_editor.dart';
import 'widgets/flight_schedule_summary.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/crewclock_store.dart';
import 'services/alarm_scheduler.dart';
import 'widgets/inline_reminder_editor.dart';
import 'widgets/crewclock_theme.dart';

class NativeRosterPage extends StatefulWidget {
  const NativeRosterPage({super.key, required this.store, this.section = 0});
  final CrewClockStore store;
  final int section;
  @override
  State<NativeRosterPage> createState() => _NativeRosterPageState();
}

class _NativeRosterPageState extends State<NativeRosterPage> {
  CrewClockStore get store => widget.store;
  int get _tab => widget.section;
  bool _followUpcoming = true;
  String get _personalZone => store.personalZone;
  final Map<String, List<String>> _editingPresetOrder = {};
  late String _personalId, _intervalId;
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  @override
  void initState() {
    super.initState();
    if (_tab == 2) FocusManager.instance.addListener(_presetFocusChanged);
    _personalId = store.id();
    _intervalId = 'interval_${store.id()}';
    if (widget.section == 0) store.openTools = _open;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.section == 0 && store.pendingToolsAction != null) {
        _open(store.pendingToolsAction!, store.selectedFlight);
      }
    });
  }

  @override
  void dispose() {
    if (_tab == 2) FocusManager.instance.removeListener(_presetFocusChanged);
    if (widget.section == 0) store.openTools = null;
    super.dispose();
  }

  void _presetFocusChanged() {
    if (mounted) setState(() {});
  }

  void _open(String action, String? flight) {
    if (!mounted) return;
    store.pendingToolsAction = null;
    final f = store.flightById(flight);
    setState(() {
      if (f != null) {
        _followUpcoming = false;
        _day = DateUtils.dateOnly(
            store.zoned(store.departure(f), store.displayZone(f['depApt'])));
      }
    });
    if (action == 'import') _import();
    if (action == 'addAlarm' && f != null) _alarm(flight: f);
  }

  void _message(String text, {VoidCallback? onUndo}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(MaterialBanner(content: Text(text), actions: [
      if (onUndo != null)
        TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              onUndo();
            },
            child: const Text('Undo')),
      TextButton(
          onPressed: messenger.hideCurrentMaterialBanner,
          child: const Text('Close')),
    ]));
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) {
        _message('$e');
      }
    }
  }

  Future<void> _flight([Map<String, dynamic>? flight]) async {
    final f = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => FlightEditor(store: store, flight: flight));
    if (f != null) await _run(() => store.importFlights([f]));
  }

  Future<void> _alarm(
      {Map<String, dynamic>? flight, Map<String, dynamic>? alarm}) async {
    final a = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) =>
            AlarmEditor(store: store, flight: flight, alarm: alarm));
    if (a != null) await _run(() => store.saveAlarm(a));
  }

  Future<void> _import() async {
    final kind = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        builder: (c) => SafeArea(
            child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Add flight',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      ListTile(
                          leading: const Icon(Icons.calendar_month),
                          title: const Text('Import PDF / ICS calendar'),
                          subtitle: const Text(
                              'PDF / ICS / ICAL / text · stays on this device'),
                          onTap: () => Navigator.pop(c, 'file')),
                      ListTile(
                          leading: const Icon(Icons.image_outlined),
                          title: const Text('Import roster image'),
                          subtitle: const Text(
                              'Read a full monthly calendar · review before saving'),
                          onTap: () => Navigator.pop(c, 'image')),
                      ListTile(
                          leading: const Icon(Icons.content_paste),
                          title: const Text('Paste schedule text (manual)'),
                          subtitle: const Text(
                              'Paste calendar content or dated flight lines'),
                          onTap: () => Navigator.pop(c, 'text')),
                      ListTile(
                          leading: const Icon(Icons.edit_calendar),
                          title: const Text('Enter flight manually'),
                          onTap: () => Navigator.pop(c, 'manual')),
                    ])))));
    if (kind == null || !mounted) return;
    if (kind == 'manual') {
      await _flight();
      return;
    }
    await _run(() async {
      List<Map<String, dynamic>> flights;
      String? text;
      if (kind == 'file' || kind == 'image') {
        final file = await NativeAlarmScheduler.channel
            .invokeMapMethod<String, dynamic>(
                kind == 'image' ? 'pickRosterImage' : 'pickRosterFile');
        text = file?['text'] as String?;
      } else if (mounted) {
        text = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (c) => const TextRosterEditor());
      }
      if (text == null || text.trim().isEmpty) return;
      final nonFlights = store.parser.nonFlightDays(text);
      try {
        flights = store.parser.parse(text);
      } on FormatException catch (e) {
        if (nonFlights.isNotEmpty && e.message.startsWith('No dated flights')) {
          flights = [];
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      final accepted = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (c) => SafeArea(
              child: SizedBox(
                  height: MediaQuery.sizeOf(c).height * .75,
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Review roster changes',
                                style: TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text(
                                '${flights.length} flights · ${nonFlights.length} non-flight entries. Matching dated routes will be updated; other existing flights are retained. Confirm airport-local times before scheduling.'),
                            Expanded(
                                child: ListView(
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    children: flights
                                        .map((f) => ListTile(
                                            leading: const Icon(
                                                Icons.flight_takeoff),
                                            title: Text(
                                                '${store.importChange(f)} · ${store.flightLabel(f)}'),
                                            subtitle: Text(
                                                '${store.matchingFlight(f) == null ? '' : 'Before: ${store.importTimes(store.matchingFlight(f)!)}\n'}After: ${store.importTimes(f)}')))
                                        .toList())),
                            FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child:
                                    const Text('Confirm and request alarms')),
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel')),
                          ])))));
      if (accepted == true) {
        await store.importFlights(flights, nonFlights: nonFlights);
      }
    });
  }

  Widget _rosterClock(List<Map<String, dynamic>> flights) {
    final times = [
      for (final f in flights)
        for (final a in store.flightAlarms(f))
          store.zoned(DateTime.parse(a['time']), store.displayZone(f['depApt']))
    ];
    void move(int delta) => setState(() {
          _followUpcoming = false;
          _day = _day.add(Duration(days: delta));
        });
    return Card(
        child: Column(children: [
      Row(children: [
        IconButton(
            tooltip: 'Previous day',
            onPressed: () => move(-1),
            icon: const Icon(Icons.chevron_left)),
        Expanded(
            child: TextButton(
                onPressed: () async {
                  final date = await showDatePicker(
                      context: context,
                      initialDate: _day,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (date != null && mounted) {
                    setState(() {
                      _followUpcoming = false;
                      _day = date;
                    });
                  }
                },
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(store.displayDate(_day), maxLines: 1)))),
        IconButton(
            tooltip: 'Next day',
            onPressed: () => move(1),
            icon: const Icon(Icons.chevron_right)),
      ]),
      if (times.isNotEmpty)
        AlarmTimeDial(
            times: times,
            caption: 'First alarm',
            hourCycle: 12,
            emphasizeNumbers: true)
      else
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No flight alarms on this day')),
    ]));
  }

  Widget _flightCard(Map<String, dynamic> f) {
    final local =
        store.zoned(store.departure(f), store.displayZone(f['depApt']));
    final arrival = DateTime.tryParse('${f['arrivalUtc']}');
    return Card(
        color: Color.alphaBlend(const Color(0xff679bcf).withValues(alpha: .055),
            Theme.of(context).colorScheme.surface),
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlightScheduleSummary(
                      date:
                          '${store.two(local.month)}/${store.two(local.day)} ${[
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun'
                      ][local.weekday - 1]}',
                      departure: store.clock(local),
                      arrival: arrival == null
                          ? ''
                          : store.clock(store.zoned(
                              arrival, store.displayZone(f['arrApt']))),
                      number: '${f['flight']}',
                      route: '${f['depApt']} → ${f['arrApt']}',
                      timeSuffix: store.timeSuffix),
                  for (final a in store.flightAlarms(f))
                    _alarmRow(a, flight: f),
                ])));
  }

  Widget _alarmRow(Map<String, dynamic> a, {Map<String, dynamic>? flight}) {
    final at = DateTime.parse(a['time']);
    final zone = flight == null
        ? '${a['zone'] ?? store.personalZone}'
        : store.airportZone(flight['depApt']) ?? 'UTC';
    final local = store.zoned(at, store.displayUTC ? 'UTC' : zone);
    final isPastUncancelled =
        !store.flag(a['dism']) && at.isBefore(DateTime.now());

    Widget content;
    if (flight == null) {
      final isTimer = store.flag(a['elapsedAlarm']) || '${a['lbl']}' == 'Timer';
      content = Card.outlined(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${store.clock(local)} (${store.timeSuffix})',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary)),
                      Text(
                          '${store.displayDate(local)}${[
                            'Personal alarm',
                            '',
                            'null'
                          ].contains('${a['lbl']}') ? '' : ' · ${a['lbl']}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                      if (isTimer)
                        IntervalCountdown(
                            next: at,
                            minutes:
                                (a['durationMinutes'] as num?)?.toInt() ?? 60,
                            enabled: !store.flag(a['dism'])),
                    ])),
                PopupMenuButton<String>(
                    tooltip: 'Alarm actions',
                    onSelected: (value) async {
                      if (value == 'edit') await _alarm(alarm: a);
                      if (value == 'delete') {
                        await _run(() => store.deleteAlarm(a));
                      }
                    },
                    itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete'))
                        ]),
              ])));
    } else {
      final offset = store.departure(flight).difference(at).inMinutes;
      final status = store.status(a);
      content = Card.outlined(
          key: ValueKey('alarm-${a['id']}'),
          margin: const EdgeInsets.only(top: 8),
          child: Semantics(
            label: '${a['lbl']}, ${store.clock(local)}, $status',
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(children: [
                  Text('${store.clock(local)}(${store.timeSuffix})',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 17,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Tooltip(
                          message: '${a['lbl']}',
                          child: Text('${a['lbl']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)))),
                  const SizedBox(width: 8),
                  Text(CrewClockStore.offsetText(offset),
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (!['Scheduled', 'Done', 'Paused'].contains(status)) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                        message: status,
                        child: Icon(Icons.info_outline,
                            size: 16,
                            color: CrewClockTheme.statusColor(status,
                                dark: Theme.of(context).brightness ==
                                    Brightness.dark))),
                  ],
                ])),
          ));
    }
    final item =
        isPastUncancelled ? Opacity(opacity: 0.4, child: content) : content;
    return item;
  }

  Widget _roster() {
    if (_followUpcoming) {
      final next = store
          .sortedFlights()
          .where((f) => store.departure(f).isAfter(DateTime.now()))
          .firstOrNull;
      if (next != null) {
        _day = DateUtils.dateOnly(store.zoned(
            store.departure(next), store.airportZone(next['depApt'])));
      }
    }
    final selected = store
        .sortedFlights()
        .where((f) =>
            store.date(store.zoned(
                store.departure(f), store.airportZone(f['depApt']))) ==
            store.date(_day))
        .toList();
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Column(children: [
      if (!landscape)
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: _rosterClock(selected)),
      Expanded(
          child: RefreshIndicator(
              onRefresh: () => store.refresh(),
              child: ListView(
                  key: const ValueKey('roster-schedule-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (landscape) _rosterClock(selected),
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                            '${store.displayDate(_day)} · Departure local date',
                            maxLines: 1)),
                    if (selected.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'No flights on this day. Choose another date or import your roster.')),
                    for (final duty in store.duties
                        .where((d) => d['date'] == store.date(_day)))
                      Card(
                          child: ListTile(
                              leading: Icon(duty['category'] == 'Off / leave'
                                  ? Icons.weekend_outlined
                                  : Icons.event_note),
                              title: Text('${duty['category']}'),
                              subtitle: Text('${duty['label']}'))),
                    ...selected.map(_flightCard),
                  ]))),
    ]);
  }

  Widget _alarmSwitch(
          {required bool value, required ValueChanged<bool>? onChanged}) =>
      SizedBox(
        width: 48,
        height: 44,
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: onChanged == null ? null : () => onChanged(!value),
            child: Center(
                child: Transform.scale(
                    scale: .85,
                    child: Switch.adaptive(
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        value: value,
                        onChanged: onChanged)))),
      );

  DateTime? _intervalDate(Map a) {
    final status = store.statuses['${a['id']}'];
    if (a['enabled'] != true || status is! Map || status['next'] is! num) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch((status['next'] as num).toInt(),
        isUtc: true);
  }

  String _intervalTitle(Map a) {
    final every =
        'Every ${(a['minutes'] as num).toInt() ~/ 60}h ${(a['minutes'] as num).toInt() % 60}m';
    return ['Repeating reminder', 'Repeating reminders', '']
            .contains('${a['label']}')
        ? every
        : '${a['label']} · $every';
  }

  Widget _alarms() => ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            InlineReminderEditor(
                key: ValueKey('new-personal-$_personalId'),
                saveLabel: 'Add alarm',
                label: '',
                date: store.date(store.zoned(
                    DateTime.now().add(const Duration(hours: 1)),
                    _personalZone)),
                time: store.clock(store.zoned(
                    DateTime.now().add(const Duration(hours: 1)),
                    _personalZone)),
                zone: _personalZone,
                onSave: (label, _, date, time) async {
                  final at =
                      store.parser.localInstant(date!, time!, _personalZone);
                  if (!at.isAfter(DateTime.now())) {
                    throw const FormatException(
                        'Choose a future reminder time.');
                  }
                  await store.saveAlarm({
                    'id': _personalId,
                    'lbl': label,
                    'time': at.toUtc().toIso8601String(),
                    'type': 'direct',
                    'armed': true,
                    'dism': false,
                    'missed': false,
                    'timeBasis': 'home',
                    'wallDate': date,
                    'wallTime': time,
                    'zone': _personalZone
                  });
                  if (mounted) setState(() => _personalId = store.id());
                }),
            for (final a in store.alarms.where((a) =>
                a['type'] == 'direct' &&
                !store.flag(a['elapsedAlarm']) &&
                '${a['lbl']}' != 'Timer'))
              _alarmRow(a),
            _heading('Timer'),
            RelativeAlarmEditor(onAdd: store.addRelativeAlarm),
            for (final a in store.alarms.where((a) =>
                a['type'] == 'timer' ||
                store.flag(a['elapsedAlarm']) ||
                '${a['lbl']}' == 'Timer'))
              _alarmRow(a),
            _heading('Create repeating reminder'),
            const Text(
                'After Stop, the next reminder is scheduled for the selected interval.'),
            InlineReminderEditor(
                key: ValueKey('new-interval-$_intervalId'),
                saveLabel: 'Add reminder',
                label: '',
                minutesBefore: 60,
                repeat: true,
                onSave: (label, minutes, _, __) async {
                  if (store.intervals.length >= 16) {
                    throw const FormatException(
                        'Up to 16 repeating reminders are supported.');
                  }
                  await store.saveIntervals([
                    ...store.intervals.where((a) => a['id'] != _intervalId),
                    {
                      'id': _intervalId,
                      'label': label,
                      'minutes': minutes,
                      'enabled': true,
                      'anchor': DateTime.now().millisecondsSinceEpoch
                    }
                  ]);
                  if (mounted) {
                    setState(() => _intervalId = 'interval_${store.id()}');
                  }
                }),
            if (store.intervals.isNotEmpty)
              _heading('Saved repeating reminders'),
            for (final a in store.intervals)
              Card.outlined(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      (store.intervalNext(a) ??
                                              (a['enabled'] == false
                                                  ? 'Paused'
                                                  : 'No upcoming alarm reserved'))
                                          .replaceFirst('Next: ', ''),
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_intervalTitle(a),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                        IntervalCountdown(
                                            next: _intervalDate(a),
                                            minutes:
                                                (a['minutes'] as num).toInt(),
                                            enabled: a['enabled'] == true),
                                      ]),
                                ])),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              _alarmSwitch(
                                  value: a['enabled'] == true,
                                  onChanged: store.busy
                                      ? null
                                      : (value) => _run(() =>
                                          store.saveIntervals(store.intervals
                                              .map((x) => x['id'] == a['id']
                                                  ? {
                                                      ...x,
                                                      'enabled': value,
                                                      'anchor': DateTime.now()
                                                          .millisecondsSinceEpoch
                                                    }
                                                  : x)
                                              .toList()))),
                              PopupMenuButton<String>(
                                  tooltip: 'Repeating reminder actions',
                                  onSelected: (value) async {
                                    if (value == 'delete') {
                                      await _run(() => store.saveIntervals(store
                                          .intervals
                                          .where((x) => x['id'] != a['id'])
                                          .toList()));
                                    }
                                    if (value == 'edit' && mounted) {
                                      final next = await showModalBottomSheet<
                                              Map<String, dynamic>>(
                                          context: context,
                                          isScrollControlled: true,
                                          showDragHandle: true,
                                          builder: (_) => IntervalEditor(
                                              store: store, record: a));
                                      if (next != null) {
                                        await _run(() => store.saveIntervals(
                                            store.intervals
                                                .map((x) => x['id'] == a['id']
                                                    ? next
                                                    : x)
                                                .toList()));
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'edit', child: Text('Edit')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'))
                                      ]),
                            ])
                          ]))),
          ]);
  Widget _heading(String text, {bool minor = false}) => Padding(
      padding: EdgeInsets.only(top: minor ? 12 : 20, bottom: 8),
      child: WidthAwareTitle(text,
          style: TextStyle(
              fontSize: minor ? 17 : 20, fontWeight: FontWeight.bold)));
  Future<void> _deletePreset(String group, Map<String, dynamic> preset) async {
    final key = '${group}Offs';
    final original =
        store.maps(store.settings[key] ?? CrewClockStore.defaults[key]);
    final index = original.indexWhere((p) => p['id'] == preset['id']);
    await store.saveSettings({
      ...store.settings,
      key: original.where((p) => p['id'] != preset['id']).toList()
    });
    if (!mounted) return;
    _message('${preset['lbl']} deleted',
        onUndo: () => _run(() async {
              final current = store
                  .maps(store.settings[key] ?? CrewClockStore.defaults[key]);
              if (current.any((p) => p['id'] == preset['id'])) return;
              current.insert(index.clamp(0, current.length),
                  Map<String, dynamic>.from(preset));
              await store.saveSettings({...store.settings, key: current});
            }));
  }

  List<Map<String, dynamic>> _orderedPresets(String group) {
    final sorted = store.preparationPresets(group);
    final editing = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<PreparationPresetRow>() !=
        null;
    if (!editing) {
      _editingPresetOrder.remove(group);
      return sorted;
    }
    final ids = _editingPresetOrder.putIfAbsent(
        group, () => sorted.map((p) => '${p['id']}').toList());
    int index(Map p) {
      final i = ids.indexOf('${p['id']}');
      return i < 0 ? ids.length : i;
    }

    sorted.sort((a, b) => index(a).compareTo(index(b)));
    return sorted;
  }

  Future<void> _clearRoster() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Delete all roster?'),
              content: Text(
                  'Delete all ${store.flights.length} flights, their flight alarms and preparation lists? Personal alarms, repeating reminders and settings will be kept. This cannot be undone.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(c).colorScheme.error),
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Delete all'))
              ],
            ));
    if (confirmed == true && mounted) {
      await _run(() async {
        await store.clearRoster();
        if (mounted) _message('Roster deleted');
      });
    }
  }

  Widget _settings() => ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          children: [
            _heading('Appearance & sound'),
            Card.outlined(
                child: Row(children: [
              Expanded(
                  child: ListTile(
                      leading: Icon(store.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined),
                      title: const Text('Appearance'),
                      subtitle: Text(store.dark ? 'Dark' : 'Light'),
                      onTap: store.busy
                          ? null
                          : () => _run(() => store.saveSettings(
                              {...store.settings, 'dark': !store.dark})))),
              Expanded(
                  child: ListTile(
                      leading: const Icon(Icons.volume_up_outlined),
                      title: const Text('Alarm sound'),
                      subtitle: const Text('Choose sound'),
                      onTap: store.busy
                          ? null
                          : () => _run(() async {
                                if (await store.scheduler.chooseAlarmSound()) {
                                  await store.retryScheduling();
                                }
                              })))
            ])),
            Card.outlined(
                child: SwitchListTile.adaptive(
                    title: const Text('Live Activity'),
                    subtitle:
                        const Text('Show the next alarm on the Lock Screen'),
                    value: store.settings['liveActivity'] == true,
                    onChanged: store.busy
                        ? null
                        : (value) => _run(() => store.saveSettings(
                            {...store.settings, 'liveActivity': value})))),
            _heading('Home bases'),
            InlineHomeBaseEditor(store: store),
            InlineHomeBaseEditor(store: store, domestic: true),
            _heading('Flight preparation presets'),
            const Text('Auto-save · Swipe to reveal Delete.'),
            for (final group in ['base', 'dom', 'intl']) ...[
              _heading(
                  {
                    'base': 'Home-base international',
                    'dom': 'Home-base domestic',
                    'intl': 'Overseas'
                  }[group]!,
                  minor: true),
              for (final preset in _orderedPresets(group))
                PreparationPresetRow(
                  key: ValueKey('preset-$group-${preset['id']}'),
                  label: '${preset['lbl']}',
                  minutesBefore: (preset['h'] as num).toInt() * 60 +
                      (preset['m'] as num).toInt(),
                  onSave: (label, minutes, _, __) async {
                    final list = store.maps(store.settings['${group}Offs'] ??
                        CrewClockStore.defaults['${group}Offs']);
                    final index =
                        list.indexWhere((p) => p['id'] == preset['id']);
                    if (index < 0) return;
                    list[index] = {
                      ...list[index],
                      'lbl': label,
                      'h': minutes! ~/ 60,
                      'm': minutes % 60
                    };
                    await store.saveSettings(
                        {...store.settings, '${group}Offs': list});
                  },
                  onDelete: () => _deletePreset(group, preset),
                ),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: store.busy
                          ? null
                          : () => store.saveSettings({
                                ...store.settings,
                                '${group}Offs': [
                                  ...store.maps(store
                                          .settings['${group}Offs'] ??
                                      CrewClockStore.defaults['${group}Offs']),
                                  {
                                    'id': 'p${store.id()}',
                                    'lbl': 'New reminder',
                                    'h': 1,
                                    'm': 0
                                  }
                                ]
                              }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add preparation preset'))),
            ],
            _heading('Reset roster data'),
            Card.outlined(
                child: ListTile(
              leading: Icon(Icons.delete_sweep_outlined,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete all roster',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle:
                  const Text('Remove flights and their linked flight alarms'),
              enabled: !store.busy && store.flights.isNotEmpty,
              onTap: _clearRoster,
            )),
            _heading('Privacy & support'),
            const Text(
                'Schedules and preparation notes stay on this device. Paste text using iPhone Live Text, or import a calendar file. No photo-library access is requested.'),
            ListTile(
                title: const Text('Privacy policy'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => launchUrl(
                    Uri.parse(
                        'https://outinletter.github.io/crewclock/privacy.html'),
                    mode: LaunchMode.externalApplication)),
            ListTile(
                title: const Text('Support'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => launchUrl(
                    Uri.parse(
                        'https://outinletter.github.io/crewclock/support.html'),
                    mode: LaunchMode.externalApplication)),
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'Personal organization only. Use your airline’s official procedures and roster.')),
          ]);
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (c, _) => SafeArea(
              child: Column(children: [
            if (store.error != null)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(store.error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error))),
            if (store.migrationNotice != null)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(store.migrationNotice!)),
            if (_tab != 2)
              SizedBox(
                  height: 4,
                  child: store.busy ? const LinearProgressIndicator() : null),
            const SizedBox(height: 2),
            Expanded(
                child: ClipRect(
                    child: _tab == 0
                        ? _roster()
                        : _tab == 1
                            ? _alarms()
                            : _settings())),
          ])));
}

class TextRosterEditor extends StatefulWidget {
  const TextRosterEditor({super.key});
  @override
  State<TextRosterEditor> createState() => _TextRosterEditorState();
}

class _TextRosterEditorState extends State<TextRosterEditor> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Paste roster',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text(
                        'Paste ICS, or text copied from a full monthly roster (include month/year and date headings). For calendar images, Import roster image preserves date columns more reliably.\nFlight lines: 2026-11-02 KE955 ICN IST 13:55\nOptional arrival: 2026-11-02 20:05. All times are airport-local.'),
                    const SizedBox(height: 12),
                    TextField(
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        controller: input,
                        textAlignVertical: TextAlignVertical.center,
                        maxLines: 8,
                        decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none),
                            labelText: 'Roster text')),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, input.text),
                        child: const Text('Preview flights')),
                  ]))));
}

class FlightEditor extends StatefulWidget {
  const FlightEditor({super.key, required this.store, this.flight});
  final CrewClockStore store;
  final Map<String, dynamic>? flight;
  @override
  State<FlightEditor> createState() => _FlightEditorState();
}

class _FlightEditorState extends State<FlightEditor> {
  final _form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String? error;
  CrewClockStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    final f = widget.flight;
    final from = f?['depApt'] ?? store.home, to = f?['arrApt'] ?? '';
    final local = f == null
        ? store.zoned(DateTime.now().add(const Duration(days: 2)),
            store.airportZone(from))
        : store.zoned(store.departure(f), store.airportZone(from));
    final arr = DateTime.tryParse('${f?['arrivalUtc']}');
    final arrival =
        arr == null ? null : store.zoned(arr, store.airportZone(to));
    for (final entry in {
      'flight': f?['flight'] ?? '',
      'from': from,
      'to': to,
      'date': store.date(local),
      'time': store.clock(local),
      'zone': store.airportZone(from) ?? '',
      'arrDate': arrival == null ? '' : store.date(arrival),
      'arrTime': arrival == null ? '' : store.clock(arrival),
      'arrZone': store.airportZone(to) ?? ''
    }.entries) {
      fields[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String value(String k) => fields[k]!.text.trim();
  Future<void> _pickDateTime(String key) async {
    if (key.toLowerCase().contains('date')) {
      final initial = DateTime.tryParse(fields[key]!.text) ?? DateTime.now();
      final chosen = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100));
      if (chosen != null && mounted) {
        setState(() => fields[key]!.text = store.date(chosen));
      }
    } else {
      final parts = fields[key]!.text.split(':');
      final chosen = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
              hour: int.tryParse(parts.first) ?? 12,
              minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0),
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
              child: child!));
      if (chosen != null && mounted) {
        setState(() => fields[key]!.text =
            '${store.two(chosen.hour)}:${store.two(chosen.minute)}');
      }
    }
  }

  Widget field(String key, String label, {bool required = true, int? length}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              controller: fields[key],
              readOnly: ['date', 'time', 'arrDate', 'arrTime'].contains(key),
              onTap: ['date', 'time', 'arrDate', 'arrTime'].contains(key)
                  ? () => _pickDateTime(key)
                  : null,
              maxLength: length,
              textCapitalization: ['flight', 'from', 'to'].contains(key)
                  ? TextCapitalization.characters
                  : TextCapitalization.none,
              decoration: InputDecoration(
                  labelText: label,
                  suffixIcon: ['date', 'arrDate'].contains(key)
                      ? const Icon(Icons.calendar_month)
                      : ['time', 'arrTime'].contains(key)
                          ? const Icon(Icons.schedule)
                          : null,
                  border: const OutlineInputBorder()),
              validator: (v) =>
                  required && (v?.trim().isEmpty ?? true) ? 'Required' : null,
              onChanged: (v) {
                if (key == 'from' || key == 'to') {
                  final zone = store.airportZone(v.trim().toUpperCase());
                  setState(() => fields[key == 'from' ? 'zone' : 'arrZone']!
                      .text = zone ?? '');
                }
              }));
  void save() {
    if (!_form.currentState!.validate()) return;
    try {
      final number = value('flight').toUpperCase(),
          from = value('from').toUpperCase(),
          to = value('to').toUpperCase();
      if (!RegExp(r'^[A-Z0-9]{2,10}$').hasMatch(number) ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(from) ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(to)) {
        throw const FormatException(
            'Use a flight number and three-letter IATA airport codes.');
      }
      final dep = store.parser
          .localInstant(value('date'), value('time'), value('zone'));
      DateTime? arrival;
      if (value('arrDate').isNotEmpty || value('arrTime').isNotEmpty) {
        arrival = store.parser
            .localInstant(value('arrDate'), value('arrTime'), value('arrZone'));
        if (!arrival.isAfter(dep)) {
          throw const FormatException('Arrival must be after departure.');
        }
      }
      Navigator.pop(context, {
        'id': widget.flight?['id'] ?? store.id(),
        'flight': number,
        'depApt': from,
        'arrApt': to,
        'departureUtc': dep.toIso8601String(),
        'arrivalUtc': arrival?.toIso8601String(),
        'departureZone': value('zone'),
        'arrivalZone': value('arrZone')
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.flight == null ? 'Add flight' : 'Edit flight',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    field('flight', 'Flight number'),
                    Row(children: [
                      Expanded(child: field('from', 'Departure', length: 3)),
                      const SizedBox(width: 12),
                      Expanded(child: field('to', 'Arrival', length: 3))
                    ]),
                    field('date', 'Departure date'),
                    field('time', 'Departure time'),
                    if (store.airportZone(value('from').toUpperCase()) == null)
                      field('zone', 'Departure time zone'),
                    const Text(
                        'Arrival is optional. Enter its local date, time and time zone together.'),
                    const SizedBox(height: 12),
                    field('arrDate', 'Arrival date', required: false),
                    field('arrTime', 'Arrival time', required: false),
                    if (store.airportZone(value('to').toUpperCase()) == null)
                      field('arrZone', 'Arrival time zone', required: false),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: save,
                        child: const Text('Save flight and request alarms'))
                  ]))));
}

class AlarmEditor extends StatelessWidget {
  const AlarmEditor({super.key, required this.store, this.flight, this.alarm});
  final CrewClockStore store;
  final Map<String, dynamic>? flight, alarm;
  @override
  Widget build(BuildContext context) {
    final zone = flight == null
        ? '${alarm?['zone'] ?? store.personalZone}'
        : store.airportZone(flight!['depApt']) ?? 'UTC';
    final at = DateTime.tryParse('${alarm?['time']}') ??
        DateTime.now().add(const Duration(hours: 1));
    final local = store.zoned(at, zone);
    final offset = flight == null
        ? null
        : alarm == null
            ? 60
            : store.departure(flight!).difference(at).inMinutes.clamp(0, 10080);
    return SafeArea(
        child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(alarm == null ? 'Add alarm' : 'Edit alarm',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  InlineReminderEditor(
                      label: alarm?['lbl'] ?? '',
                      minutesBefore: offset,
                      date: store.date(local),
                      time: store.clock(local),
                      zone: zone,
                      onSave: (label, minutes, date, time) async {
                        final instant = flight == null
                            ? store.parser.localInstant(date!, time!, zone)
                            : store
                                .departure(flight!)
                                .subtract(Duration(minutes: minutes!));
                        if (!instant.isAfter(DateTime.now())) {
                          throw const FormatException(
                              'Choose a future reminder time.');
                        }
                        Navigator.pop(context, {
                          ...?alarm,
                          'id': alarm?['id'] ?? store.id(),
                          if (flight == null) ...{
                            'zone': zone,
                            'wallDate': date,
                            'wallTime': time,
                            'timeBasis': alarm?['timeBasis'] ??
                                store.settings['personalTimeBasis'] ??
                                'home'
                          },
                          'time': instant.toUtc().toIso8601String(),
                          'dep': flight == null
                              ? null
                              : store.departure(flight!).toIso8601String(),
                          'lbl': label,
                          'type': flight == null
                              ? 'direct'
                              : flight!['depApt'] == store.home
                                  ? 'base'
                                  : 'intl',
                          'armed': true,
                          'dism': false,
                          'missed': false,
                          'fnum': flight?['flight'],
                          'depApt': flight?['depApt'],
                          'arrApt': flight?['arrApt'],
                          'arrTime': flight?['arrTime']
                        });
                      }),
                ])));
  }
}

class IntervalEditor extends StatelessWidget {
  const IntervalEditor({super.key, required this.store, this.record});
  final CrewClockStore store;
  final Map<String, dynamic>? record;
  @override
  Widget build(BuildContext context) => SafeArea(
      child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Repeating reminder',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            InlineReminderEditor(
                label: record?['label'] ?? '',
                minutesBefore: (record?['minutes'] as num?)?.toInt() ?? 60,
                repeat: true,
                onSave: (label, minutes, _, __) async =>
                    Navigator.pop(context, {
                      'id': record?['id'] ?? 'interval_${store.id()}',
                      'label': label,
                      'minutes': minutes,
                      'enabled': record?['enabled'] ?? true,
                      'anchor': record?['anchor'] ??
                          DateTime.now().millisecondsSinceEpoch
                    })),
          ])));
}

class InlineHomeBaseEditor extends StatefulWidget {
  const InlineHomeBaseEditor(
      {super.key, required this.store, this.domestic = false});
  final bool domestic;
  final CrewClockStore store;
  @override
  State<InlineHomeBaseEditor> createState() => _InlineHomeBaseEditorState();
}

class _InlineHomeBaseEditorState extends State<InlineHomeBaseEditor> {
  late final TextEditingController input;
  bool dirty = false;
  String? error;
  @override
  void initState() {
    super.initState();
    input = TextEditingController(
        text: widget.store.baseAirports(domestic: widget.domestic).join(', '));
  }

  @override
  void didUpdateWidget(covariant InlineHomeBaseEditor old) {
    super.didUpdateWidget(old);
    if (!dirty) {
      input.text =
          widget.store.baseAirports(domestic: widget.domestic).join(', ');
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card.outlined(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WidthAwareTitle(
                widget.domestic
                    ? 'Home base · Domestic'
                    : 'Home base · International',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      controller: input,
                      textAlignVertical: TextAlignVertical.center,
                      enabled: !widget.store.busy,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() => dirty = true),
                      decoration: InputDecoration(
                          labelText: 'Airport codes',
                          hintText: widget.domestic ? 'GMP, CJU' : 'ICN, PUS',
                          counterText: '',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none)))),
              const SizedBox(width: 12),
              if (dirty)
                Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                        onPressed: !dirty || widget.store.busy
                            ? null
                            : () async {
                                final codes = input.text
                                    .toUpperCase()
                                    .split(',')
                                    .map((s) => s.trim())
                                    .where((s) => s.isNotEmpty)
                                    .toSet()
                                    .toList();
                                if (codes.isEmpty ||
                                    codes.any((code) =>
                                        code.length != 3 ||
                                        widget.store.airportZone(code) ==
                                            null)) {
                                  setState(() => error =
                                      'Enter known airport codes separated by commas.');
                                  return;
                                }
                                try {
                                  await widget.store.saveSettings({
                                    ...widget.store.settings,
                                    (widget.domestic
                                        ? 'domesticBaseApt'
                                        : 'baseApt'): codes.join(', ')
                                  });
                                  if (mounted) {
                                    setState(() {
                                      dirty = false;
                                      error = null;
                                    });
                                  }
                                } catch (e) {
                                  if (mounted) setState(() => error = '$e');
                                }
                              },
                        child: const Text('Save'))),
            ]),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])));
}

class NativePageActions extends StatelessWidget {
  const NativePageActions(
      {super.key, required this.store, required this.section});
  final CrewClockStore store;
  final int section;
  Future<void> _run(
      BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentMaterialBanner();
        messenger
            .showMaterialBanner(MaterialBanner(content: Text('$e'), actions: [
          TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: const Text('Close'))
        ]));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            if (section == 0)
              TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  label:
                      const Text('Add Roster', style: TextStyle(fontSize: 13)),
                  onPressed: store.busy
                      ? null
                      : () => store.openTools?.call('import', null),
                  icon: const Icon(Icons.add, size: 18)),
          ]));
}
