import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/crewclock_store.dart';
import 'services/alarm_scheduler.dart';
import 'widgets/inline_reminder_editor.dart';
import 'widgets/crewclock_theme.dart';
import 'widgets/alarm_status_badge.dart';

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
  late String _personalId, _intervalId;
  DateTime _day = DateUtils.dateOnly(DateTime.now()),
      _month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  void initState() {
    super.initState();
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
    if (widget.section == 0) store.openTools = null;
    super.dispose();
  }

  void _open(String action, String? flight) {
    if (!mounted) return;
    store.pendingToolsAction = null;
    final f = store.flightById(flight);
    setState(() {
      if (f != null) {
        _followUpcoming = false;
        _day = DateUtils.dateOnly(
            store.zoned(store.departure(f), store.airportZone(f['depApt'])));
        _month = DateTime(_day.year, _day.month);
      }
    });
    if (action == 'import') _import();
    if (action == 'addAlarm' && f != null) _alarm(flight: f);
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Delete'))
              ])) ??
      false;
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
                          title: const Text('Import ICS / calendar file'),
                          subtitle: const Text(
                              'ICS / ICAL / plain text · stays on this device'),
                          onTap: () => Navigator.pop(c, 'file')),
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
      if (kind == 'file') {
        final file = await NativeAlarmScheduler.channel
            .invokeMapMethod<String, dynamic>('pickRosterFile');
        text = file?['text'] as String?;
      } else if (mounted) {
        text = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (c) => const TextRosterEditor());
      }
      if (text == null || text.trim().isEmpty) return;
      flights = store.parser.parse(text);
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
                                '${flights.length} flights. Matching dated routes will be updated; other existing flights are retained. Confirm airport-local times before scheduling.'),
                            Expanded(
                                child: ListView(
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    children: flights
                                        .map((f) => ListTile(
                                            leading: const Icon(
                                                Icons.flight_takeoff),
                                            title: Text(store.flightLabel(f)),
                                            subtitle: Text(
                                                'Departure ${store.stamp(store.departure(f), store.airportZone(f['depApt']))} · ${store.airportZone(f['depApt']) ?? 'TIME ZONE REQUIRED'}')))
                                        .toList())),
                            FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child:
                                    const Text('Confirm and request alarms')),
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel')),
                          ])))));
      if (accepted == true) await store.importFlights(flights);
    });
  }

  Widget _calendar() {
    final first = DateTime(_month.year, _month.month),
        days = DateUtils.getDaysInMonth(_month.year, _month.month),
        offset = first.weekday % 7;
    final flightDays = store.flights
        .map((f) => store.date(
            store.zoned(store.departure(f), store.airportZone(f['depApt']))))
        .toSet();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => setState(() {
                          _followUpcoming = false;
                          _month = DateTime(_month.year, _month.month - 1);
                        }),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                    child: TextButton(
                        onPressed: () => setState(() {
                              _followUpcoming = false;
                              _day = DateUtils.dateOnly(DateTime.now());
                              _month = DateTime(_day.year, _day.month);
                            }),
                        child: Text(
                            '${_month.year} · ${store.two(_month.month)}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)))),
                IconButton(
                    tooltip: 'Next month',
                    onPressed: () => setState(() {
                          _followUpcoming = false;
                          _month = DateTime(_month.year, _month.month + 1);
                        }),
                    icon: const Icon(Icons.chevron_right))
              ]),
              Row(
                  children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                      .map((s) => Expanded(child: Center(child: Text(s))))
                      .toList()),
              GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ((days + offset) / 7).ceil() * 7,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, childAspectRatio: 1.05),
                  itemBuilder: (c, i) {
                    final number = i - offset + 1;
                    if (number < 1 || number > days) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime(_month.year, _month.month, number),
                        selected = DateUtils.isSameDay(_day, date);
                    return Semantics(
                        label:
                            '${store.date(date)}${flightDays.contains(store.date(date)) ? ', flights scheduled' : ''}',
                        selected: selected,
                        child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() {
                                  _followUpcoming = false;
                                  _day = date;
                                }),
                            child: Container(
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                    color: selected
                                        ? Theme.of(c)
                                            .colorScheme
                                            .primaryContainer
                                        : null,
                                    borderRadius: BorderRadius.circular(14)),
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('$number',
                                          style: TextStyle(
                                              fontWeight: selected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal)),
                                      if (flightDays.contains(store.date(date)))
                                        const Text('•',
                                            style: TextStyle(
                                                height: .7,
                                                color: CrewClockTheme.blue))
                                    ]))));
                  }),
            ])));
  }

  Widget _flightCard(Map<String, dynamic> f) {
    final local =
        store.zoned(store.departure(f), store.airportZone(f['depApt']));
    final arrival = DateTime.tryParse('${f['arrivalUtc']}');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                            label: Text(
                                '${store.two(local.month)}/${store.two(local.day)}')),
                        Text(
                            '${store.clock(local)} ${f['flight']} ${f['depApt']} → ${f['arrApt']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        if (arrival != null)
                          Text(store.clock(store.zoned(
                              arrival, store.airportZone(f['arrApt'])))),
                        TextButton(
                            onPressed:
                                store.busy ? null : () => _alarm(flight: f),
                            child: const Text('+ Add')),
                        PopupMenuButton<String>(
                            tooltip: 'Flight actions',
                            onSelected: (value) async {
                              if (value == 'edit') _flight(f);
                              if (value == 'delete' &&
                                  await _confirm('Delete flight?',
                                      'Its reminders and personal preparation notes will also be removed.')) {
                                await _run(() => store.deleteFlight(f));
                              }
                            },
                            itemBuilder: (c) => [
                                  const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit flight')),
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete flight'))
                                ])
                      ]),
                  Text(
                      'Times at ${f['depApt']} · ${store.airportZone(f['depApt']) ?? 'Confirm airport time zone'}',
                      style: Theme.of(context).textTheme.bodySmall),
                  for (final a in store.flightAlarms(f))
                    _alarmRow(a, flight: f),
                ])));
  }

  Widget _alarmRow(Map<String, dynamic> a, {Map<String, dynamic>? flight}) {
    final at = DateTime.parse(a['time']);
    final zone = store.airportZone(flight?['depApt'] ?? store.home) ?? 'UTC';
    final local = store.zoned(at, zone);
    if (flight == null) {
      return Card.outlined(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(store.clock(local),
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary)),
                      Text('${a['lbl']}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${store.date(local)} · $zone',
                          style: Theme.of(context).textTheme.bodySmall),
                      AlarmStatusBadge(label: store.status(a)),
                    ])),
                Switch.adaptive(
                    value: store.flag(a['armed']) && !store.flag(a['dism']),
                    onChanged: store.busy
                        ? null
                        : (value) => _run(() => store.toggleAlarm(a, value))),
                PopupMenuButton<String>(
                    tooltip: 'Alarm actions',
                    onSelected: (value) async {
                      if (value == 'edit') await _alarm(alarm: a);
                      if (value == 'retry') {
                        await _run(() => store.retryScheduling());
                      }
                      if (value == 'delete') {
                        await _run(() => store.deleteAlarm(a));
                      }
                    },
                    itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                              value: 'retry', child: Text('Retry reservation')),
                          PopupMenuItem(value: 'delete', child: Text('Delete'))
                        ]),
              ])));
    }
    final offset = store.departure(flight).difference(at).inMinutes;
    final status = store.status(a);
    return Card.outlined(
        key: ValueKey('alarm-${a['id']}'),
        margin: const EdgeInsets.only(top: 8),
        child: Semantics(
          label: '${a['lbl']}, ${store.clock(local)}, $status',
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Text('${store.clock(local)}(L)',
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
                Text('${offset ~/ 60}h ${offset % 60}m',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

  Widget _roster() {
    if (_followUpcoming) {
      final next = store
          .sortedFlights()
          .where((f) => store.departure(f).isAfter(DateTime.now()))
          .firstOrNull;
      if (next != null) {
        _day = DateUtils.dateOnly(store.zoned(
            store.departure(next), store.airportZone(next['depApt'])));
        _month = DateTime(_day.year, _day.month);
      }
    }
    final selected = store
        .sortedFlights()
        .where((f) =>
            store.date(store.zoned(
                store.departure(f), store.airportZone(f['depApt']))) ==
            store.date(_day))
        .toList();
    return RefreshIndicator(
        onRefresh: () => store.refresh(),
        child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(12),
            children: [
              _calendar(),
              const SizedBox(height: 12),
              Text('${store.date(_day)} · Departure-airport local dates'),
              if (selected.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'No flights on this day. Choose a marked date or import your roster.')),
              ...selected.map(_flightCard),
              FilledButton.icon(
                  onPressed: store.busy ? null : _import,
                  icon: const Icon(Icons.add),
                  label: const Text('Add flight')),
            ]));
  }

  Widget _alarms() => ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(12),
          children: [
            _heading('Personal alarms'),
            for (final a in store.alarms.where((a) => a['type'] == 'direct'))
              _alarmRow(a),
            InlineReminderEditor(
                key: ValueKey('new-personal-$_personalId'),
                saveLabel: 'Add alarm',
                label: '',
                date: store.date(store.zoned(
                    DateTime.now().add(const Duration(hours: 1)),
                    store.airportZone(store.home))),
                time: store.clock(store.zoned(
                    DateTime.now().add(const Duration(hours: 1)),
                    store.airportZone(store.home))),
                zone: store.airportZone(store.home) ?? 'UTC',
                onSave: (label, _, date, time) async {
                  final at = store.parser.localInstant(
                      date!, time!, store.airportZone(store.home) ?? 'UTC');
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
                    'missed': false
                  });
                  if (mounted) setState(() => _personalId = store.id());
                }),
            _heading('Repeating reminders'),
            const Text(
                'The next cycle is reserved after Stop. Waiting reminders are not yet scheduled.'),
            for (final a in store.intervals)
              Card.outlined(
                  child: ListTile(
                      leading: const Icon(Icons.repeat),
                      title: Text('${a['label']}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Every ${(a['minutes'] as num).toInt() ~/ 60}h ${(a['minutes'] as num).toInt() % 60}m'),
                            AlarmStatusBadge(label: store.intervalStatus(a)),
                            Text(
                                store.intervalNext(a) ??
                                    'Next cycle is reserved after Stop',
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch.adaptive(
                            value: a['enabled'] == true,
                            onChanged: store.busy
                                ? null
                                : (value) => _run(() => store.saveIntervals(
                                    store.intervals
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
                                  await _run(() => store.saveIntervals(store
                                      .intervals
                                      .map((x) => x['id'] == a['id'] ? next : x)
                                      .toList()));
                                }
                              }
                            },
                            itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Delete'))
                                ]),
                      ]))),
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
          ]);
  Widget _heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${preset['lbl']} deleted'),
      action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _run(() async {
                final current = store
                    .maps(store.settings[key] ?? CrewClockStore.defaults[key]);
                if (current.any((p) => p['id'] == preset['id'])) return;
                current.insert(index.clamp(0, current.length),
                    Map<String, dynamic>.from(preset));
                await store.saveSettings({...store.settings, key: current});
              })),
    ));
  }

  Widget _settings() => ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(12),
          children: [
            InlineHomeBaseEditor(store: store),
            SwitchListTile.adaptive(
                title: const Text('Dark appearance'),
                value: store.dark,
                onChanged: store.busy
                    ? null
                    : (v) => _run(() =>
                        store.saveSettings({...store.settings, 'dark': v}))),
            SwitchListTile.adaptive(
                title: const Text('Private alarm labels'),
                subtitle: const Text('Use a generic label on the lock screen'),
                value: store.scheduler.privateLabels,
                onChanged:
                    store.busy ? null : (v) => _run(() => store.setPrivacy(v))),
            ListTile(
                title: const Text('Alarm sound'),
                trailing: const Icon(Icons.volume_up),
                onTap: store.busy
                    ? null
                    : () => _run(() async {
                          if (await store.scheduler.chooseAlarmSound()) {
                            await store.retryScheduling();
                          }
                        })),
            _heading('Flight preparation presets'),
            const Text(
                'Changes save automatically for future imports. Swipe left to delete. Existing alarms keep their times.'),
            for (final group in ['base', 'dom', 'intl']) ...[
              _heading({
                'base': 'Home-base international',
                'dom': 'Home-base domestic',
                'intl': 'Overseas'
              }[group]!),
              for (final preset in store.maps(store.settings['${group}Offs'] ??
                  CrewClockStore.defaults['${group}Offs']))
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
              TextButton.icon(
                  onPressed: store.busy
                      ? null
                      : () => store.saveSettings({
                            ...store.settings,
                            '${group}Offs': [
                              ...store.maps(store.settings['${group}Offs'] ??
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
                  label: const Text('Add preparation preset')),
            ],
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
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
                child: Row(children: [
                  Expanded(
                      child: Text(['Roster', 'Alarms', 'Settings'][_tab],
                          style: const TextStyle(
                              fontSize: 23, fontWeight: FontWeight.w700))),
                  if (_tab == 0)
                    IconButton(
                        tooltip: 'Import roster',
                        onPressed: store.busy ? null : _import,
                        icon: const Icon(Icons.file_open_outlined)),
                ])),
            if (store.error != null)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(store.error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error))),
            if (store.migrationNotice != null)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(store.migrationNotice!)),
            if (store.busy) const LinearProgressIndicator(),
            const SizedBox(height: 10),
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
                        'Paste ICS calendar content, or one flight per line:\n2026-11-02 KE955 ICN IST 13:55\nTimes in text lines are departure-airport local. For other roster formats use manual entry.'),
                    const SizedBox(height: 12),
                    TextField(
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        controller: input,
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
    final zone = store.airportZone(flight?['depApt'] ?? store.home) ?? 'UTC';
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
                          'id': alarm?['id'] ?? store.id(),
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
  const InlineHomeBaseEditor({super.key, required this.store});
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
    input = TextEditingController(text: widget.store.home);
  }

  @override
  void didUpdateWidget(covariant InlineHomeBaseEditor old) {
    super.didUpdateWidget(old);
    if (!dirty) input.text = widget.store.home;
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
            const Text('Home base',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                controller: input,
                enabled: !widget.store.busy,
                maxLength: 3,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() => dirty = true),
                decoration: InputDecoration(
                    labelText: 'Airport code',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none))),
            Text(widget.store.airportZone(input.text.trim().toUpperCase()) ??
                'Enter a known three-letter airport code.'),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                    onPressed: !dirty || widget.store.busy
                        ? null
                        : () async {
                            final code = input.text.trim().toUpperCase();
                            if (widget.store.airportZone(code) == null) {
                              setState(() => error =
                                  'Enter a known three-letter airport code.');
                              return;
                            }
                            try {
                              await widget.store.saveSettings(
                                  {...widget.store.settings, 'baseApt': code});
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
                    child: const Text('Save home base'))),
          ])));
}
