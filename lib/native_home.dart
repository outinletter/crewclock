import 'widgets/preparation_task_row.dart';
import 'widgets/width_aware_title.dart';
import 'widgets/flight_schedule_summary.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'widgets/crewclock_header.dart';
import 'widgets/crewclock_theme.dart';

class FlightBriefingController extends ChangeNotifier {
  Future<Map<String, dynamic>> Function(String?)? _load;
  Future<void> Function(String, String?, Object?)? _action;
  Future<void> _pending = Future<void>.value();
  int? requestedTab;
  void openAlarms() {
    requestedTab = 2;
    notifyListeners();
  }

  bool get ready => _load != null;
  void invalidate() => notifyListeners();

  void connect(Future<Map<String, dynamic>> Function(String?) load,
      Future<void> Function(String, String?, Object?) action) {
    _load = load;
    _action = action;
    notifyListeners();
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _pending.then((_) => work());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, dynamic>> load(String? key) => _serial(() => _load!(key));
  Future<void> action(String action, String? key, [Object? value]) =>
      _serial(() => _action!(action, key, value));
}

class CrewClockShell extends StatefulWidget {
  const CrewClockShell(
      {super.key,
      required this.tools,
      required this.briefing,
      this.alarms,
      this.settings,
      this.headerActions,
      this.alarmWarning,
      this.onOpenSettings});
  final String? alarmWarning;
  final VoidCallback? onOpenSettings;
  final Widget tools;
  final Widget? alarms, settings;
  final List<Widget> Function(int)? headerActions;
  final FlightBriefingController briefing;

  @override
  State<CrewClockShell> createState() => _CrewClockShellState();
}

class _CrewClockShellState extends State<CrewClockShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  final _pages = PageController();
  Map<String, dynamic>? _data;
  String? _selected, _error;
  bool _busy = false, _refreshing = false, _editingTasks = false;
  Timer? _timer;
  final _newTask = TextEditingController();
  final _note = TextEditingController();
  Color get _teal => _colors.primary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.briefing.addListener(_refresh);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_tab == 0 && !_busy) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (widget.briefing.requestedTab case final int tab) {
      widget.briefing.requestedTab = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showTab(tab);
      });
    }

    if (!widget.briefing.ready || _refreshing) return;
    _refreshing = true;
    try {
      final data = await widget.briefing.load(_selected);
      if (!mounted) return;
      if (_data?['key'] != data['key']) {
        _note.text = data['note'] as String? ?? '';
      }
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load briefing. Pull down to retry.');
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<bool> _act(String action, [Object? value]) async {
    if (_busy || !widget.briefing.ready) return false;
    setState(() => _busy = true);
    try {
      await widget.briefing.action(action, _data?['key'] as String?, value);
      if (!mounted) return false;
      if (action == 'add') _newTask.clear();
      if (action == 'demo' || action == 'exitDemo') _selected = null;
      if (action == 'import' || action == 'review' || action == 'addAlarm') {
        _showTab(1);
      }
      await _refresh();
      if (mounted && action == 'note') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note saved on this device')));
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save changes. $error')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    widget.briefing.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    _newTask.dispose();
    _note.dispose();
    super.dispose();
  }

  void _showTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_pages.hasClients) {
      _pages.animateToPage(index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    }
  }

  Widget _timeline(Map<String, dynamic> data) {
    final flight = data['flight'] as Map;
    return Container(
      key: const ValueKey('preparation-flight-list'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _colors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FlightScheduleSummary(
            date: '${flight['dateBadge'] ?? ''}',
            departure: '${flight['departureTime'] ?? ''}',
            arrival: '${flight['arrivalTime'] ?? ''}',
            number: '${flight['number']}',
            route: '${flight['from']} → ${flight['to']}',
            timeSuffix: '${data['timeSuffix'] ?? 'L'}'),
        const SizedBox(height: 8),
        for (final step in data['steps'] as List)
          Container(
              key: ValueKey('timeline-${step['id']}'),
              decoration: BoxDecoration(
                  color: (data['next'] as Map?)?['id'] == step['id']
                      ? _teal.withValues(alpha: .06)
                      : null,
                  borderRadius: BorderRadius.circular(10)),
              child: IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    SizedBox(
                        width: 16,
                        child: Stack(children: [
                          Positioned(
                              top: 0,
                              bottom: 0,
                              left: 7,
                              width: 2,
                              child: ColoredBox(color: _colors.outlineVariant)),
                          Align(
                              alignment: Alignment.center,
                              child: Container(
                                  key: ValueKey(
                                      'preparation-marker-${step['id']}'),
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (data['next'] as Map?)?['id'] ==
                                              step['id']
                                          ? _teal
                                          : _colors.surface,
                                      border: Border.all(
                                          width: 2,
                                          color:
                                              (data['next'] as Map?)?['id'] ==
                                                      step['id']
                                                  ? _teal
                                                  : _colors.outline)))),
                        ])),
                    Expanded(
                        child: Semantics(
                      label:
                          '${step['label']}, ${step['clock']}, ${step['offset']}, ${step['status']}',
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          child: Row(children: [
                            SizedBox(
                                width: 80,
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        '${step['clock'] ?? step['time']}(${data['timeSuffix'] ?? 'L'})',
                                        style: TextStyle(
                                            color: _colors.primary,
                                            fontSize: 17,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures()
                                            ],
                                            fontWeight: FontWeight.w700)))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Tooltip(
                                    message: '${step['label']}',
                                    child: Text('${step['label']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)))),
                            const SizedBox(width: 8),
                            Text('${step['offset'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _colors.onSurfaceVariant)),
                            if (!['Scheduled', 'Done', 'Preview', 'Paused']
                                .contains(step['status'])) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                  message: '${step['status']}',
                                  child: Icon(Icons.info_outline,
                                      size: 16,
                                      color: CrewClockTheme.statusColor(
                                          '${step['status']}',
                                          dark: _data?['dark'] == true))),
                            ],
                          ])),
                    ))
                  ]))),
        if ((data['steps'] as List).isEmpty)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'No preparation reminders. Configure them in Settings.')),
      ]),
    );
  }

  Widget _title(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: WidthAwareTitle(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );

  ColorScheme get _colors =>
      CrewClockTheme.colors(dark: _data?['dark'] == true);

  Widget _clock(Map clock, bool accent) => Container(
        key: ValueKey('briefing-clock-${clock['label']}'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent ? _teal : _colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: DefaultTextStyle.merge(
          style:
              TextStyle(color: accent ? _colors.onPrimary : _colors.onSurface),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Text('${clock['label']}'.replaceAll(' departure', ''),
                    maxLines: 2,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 6),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                    '${clock['time']} (${clock['zone'] == 'UTC' ? 'Z' : 'L'})',
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                        fontSize: 24,
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w700))),
          ]),
        ),
      );

  Future<void> _chooseFlight(List choices, String currentKey) async {
    final now = DateTime.now();
    final ordered = List<dynamic>.from(choices);
    DateTime? departure(dynamic f) =>
        DateTime.tryParse('${f['departure'] ?? '${f['key']}'.split('|').last}');
    ordered.sort((a, b) {
      final da = departure(a), db = departure(b);
      if (da == null || db == null) {
        return choices.indexOf(a).compareTo(choices.indexOf(b));
      }
      final upcomingA = !da.isBefore(now), upcomingB = !db.isBefore(now);
      if (upcomingA != upcomingB) return upcomingA ? -1 : 1;
      return upcomingA ? da.compareTo(db) : db.compareTo(da);
    });
    final key = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _colors.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => Theme(
        data: ThemeData(colorScheme: _colors, useMaterial3: true),
        child: SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .7,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 12, 16),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const Text('Choose flight',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                    '${ordered.length} flights · Upcoming flights first'),
                              ])),
                          IconButton(
                              tooltip: 'Close flight list',
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close)),
                        ])),
                    Expanded(
                        child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: ordered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final f = ordered[index] as Map;
                        final selected = f['key'] == currentKey;
                        return Material(
                          color: selected
                              ? _colors.primaryContainer
                              : _colors.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                  color:
                                      selected ? _teal : _colors.outlineVariant,
                                  width: selected ? 1.5 : 1)),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            selected: selected,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            leading: CircleAvatar(
                                backgroundColor: selected
                                    ? _teal
                                    : _colors.surfaceContainerHighest,
                                child: Icon(Icons.flight_takeoff,
                                    color: selected
                                        ? Colors.white
                                        : _colors.onSurfaceVariant)),
                            title: Text(
                                f['number'] == null
                                    ? '${f['label']}'
                                    : '${f['number']} · ${f['from']} → ${f['to']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                    '${f['date'] ?? f['label']}${selected ? ' · Selected' : ''}')),
                            trailing: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.chevron_right,
                                color: selected
                                    ? _teal
                                    : _colors.onSurfaceVariant),
                            onTap: () =>
                                Navigator.pop(sheetContext, f['key'] as String),
                          ),
                        );
                      },
                    )),
                  ]),
            )),
      ),
    );
    if (!mounted || key == null || key == currentKey) return;
    if (_note.text != (_data?['note'] ?? '')) {
      if (!await _act('note', _note.text)) return;
    }
    _selected = key;
    await _refresh();
  }

  Widget _section(List<Widget> children, Color tone) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color:
                Color.alphaBlend(tone.withValues(alpha: .065), _colors.surface),
            border: Border.all(color: _colors.outlineVariant),
            borderRadius: BorderRadius.circular(18)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _briefing(Map<String, dynamic> data) {
    final flight = data['flight'] as Map;
    final choices = data['flights'] as List;
    final clocks = List<dynamic>.from(data['clocks'] as List);
    final tasks = data['tasks'] as List;
    final departure = DateTime.parse(flight['departure'] as String);
    final minutes =
        (departure.difference(DateTime.now()).inSeconds / 60).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (choices.isNotEmpty) ...[
        _title('Flight'),
        OutlinedButton(
          key: const ValueKey('choose-flight'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            side: BorderSide(color: _colors.outlineVariant),
            foregroundColor: _colors.onSurface,
          ),
          onPressed: _busy
              ? null
              : () => _chooseFlight(choices, data['key'] as String),
          child: Row(children: [
            Icon(Icons.flight_takeoff, color: _teal),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    '${choices.firstWhere((f) => f['key'] == data['key'])['label']}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                    maxLines: 2)),
            const SizedBox(width: 8),
            const Icon(Icons.unfold_more),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Container(
          key: const ValueKey('flight-preparation-card'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _colors.surface, borderRadius: BorderRadius.circular(18)),
          child: IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SizedBox(
                    width: 30,
                    child: Column(children: [
                      Container(
                          key: const ValueKey('flight-plane-badge'),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              color: _teal, shape: BoxShape.circle),
                          child: Icon(CupertinoIcons.airplane,
                              size: 17, color: _colors.onPrimary)),
                      const SizedBox(height: 6),
                      Expanded(
                          child: Container(
                              width: 2, color: _teal.withValues(alpha: .4))),
                    ])),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          data['demo'] == true
                              ? 'FICTIONAL DEMO · NO ALARMS SCHEDULED'
                              : 'FLIGHT PREPARATION',
                          style: TextStyle(
                              color: _teal,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 7),
                                decoration: BoxDecoration(
                                    color: _teal,
                                    borderRadius: BorderRadius.circular(10)),
                                child: Text('${flight['dateBadge']}',
                                    maxLines: 1,
                                    style: TextStyle(
                                        color: _colors.onPrimary,
                                        fontSize: 16,
                                        letterSpacing: -.3,
                                        fontWeight: FontWeight.w700))),
                            const SizedBox(width: 8),
                            Text(
                                '${flight['number']} · ${flight['from']} → ${flight['to']}',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                    color: _colors.onSurface,
                                    fontSize: 24,
                                    letterSpacing: -.5,
                                    fontWeight: FontWeight.w700))
                          ])),
                      const SizedBox(height: 12),
                      Text(
                          'Departs ${flight['departureTime']} · Arrives ${flight['arrivalTime']}',
                          style: TextStyle(
                              color: _colors.onSurfaceVariant, fontSize: 17)),
                      if (data['demo'] == true)
                        TextButton(
                            onPressed: _busy ? null : () => _act('exitDemo'),
                            child: const Text('Exit demo',
                                style: TextStyle(color: Colors.white))),
                    ])),
              ]))),
      const SizedBox(height: 16),
      _section([
        _title('Departure time across zones'),
        LayoutBuilder(builder: (context, size) {
          if (size.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < clocks.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _clock(clocks[i] as Map, i == 0),
                  ],
                ]);
          }
          return IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < clocks.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _clock(clocks[i] as Map, i == 0)),
              ],
            ]),
          );
        }),
        const SizedBox(height: 14),
        Text(
            'Same departure instant across the displayed time zones. Flight reminders stay on ${flight['from']} local time when you travel.'),
        const SizedBox(height: 16),
      ], const Color(0xff5aaca4)),
      _timeline(data),
      const SizedBox(height: 12),
      _section([
        Row(children: [
          Expanded(child: _title('Personal preparation')),
          IconButton(
              tooltip: _editingTasks
                  ? 'Finish editing preparation'
                  : 'Edit preparation',
              onPressed: () => setState(() => _editingTasks = !_editingTasks),
              icon: Icon(_editingTasks ? Icons.check : Icons.edit_outlined)),
        ]),
        Text(
            '${tasks.where((t) => t['checkedAt'] != null).length} / ${tasks.length} checked'),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) async {
            if (!_editingTasks || _busy) return;
            final ordered = List<Map>.from(data['tasks'] as List);
            final moved = ordered.removeAt(oldIndex);
            ordered.insert(newIndex, moved);
            setState(() => data['tasks'] = ordered);
            await _act(
                'reorderTasks', ordered.map((t) => '${t['id']}').toList());
          },
          children: [
            for (var i = 0; i < tasks.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(
                    'preparation-task-${data['key']}-${tasks[i]['id'] ?? i}'),
                index: i,
                enabled: _editingTasks && !_busy,
                child: PreparationTaskRow(
                  label: '${tasks[i]['label']}',
                  checked: tasks[i]['checkedAt'] != null,
                  checkedText: tasks[i]['checkedText'] as String?,
                  editing: _editingTasks,
                  onToggle: _busy ? null : () => _act('toggle', i),
                  onDelete: _busy ? null : () => _act('delete', i),
                  onRename: (text) => _act('renameTask', {
                    'id': tasks[i]['id'],
                    'label': text,
                    'flightKey': data['key']
                  }),
                ),
              ),
          ],
        ),
        TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: _newTask,
            maxLength: 100,
            decoration: InputDecoration(
                labelText: 'New preparation item',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none))),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: _busy || tasks.length >= 12
                    ? null
                    : () => _act('add', _newTask.text),
                child: const Text('Add item'))),
      ], const Color(0xff9293cd)),
      const Text(
          'Personal organization only. Use your airline’s official operational procedures and roster.'),
    ]);
  }

  Widget _home() => SafeArea(
          child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            key: const ValueKey('briefing-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!)),
              if (_data == null && _error == null)
                const Center(child: CircularProgressIndicator())
              else if (_data?['flight'] != null)
                _briefing(_data!)
              else ...[
                _title(_data?['hasSchedules'] == true
                    ? 'No upcoming flights'
                    : 'Your next duty, in one place.'),
                Text(_data?['hasSchedules'] == true
                    ? 'All registered flights have departed. Add your next roster to see its preparation alarms.'
                    : 'Import your roster to connect departure-local alarms, time-zone checks and a personal preparation list.'),
                const SizedBox(height: 20),
                OutlinedButton(
                    onPressed: _busy || !widget.briefing.ready
                        ? null
                        : () => _act('demo'),
                    child: const Text('Explore flight briefing')),
              ],
            ]),
      ));

  BottomNavigationBarItem _tabItem(IconData icon, String label) =>
      BottomNavigationBarItem(
        icon: Icon(icon),
        label: label,
        activeIcon: Icon(icon,
            key: ValueKey('selected-tab-$label'),
            color: _teal,
            shadows: [
              Shadow(color: _teal, offset: const Offset(.3, 0)),
              Shadow(color: _teal, offset: const Offset(-.3, 0)),
              Shadow(color: _teal, offset: const Offset(0, .3)),
              Shadow(color: _teal, offset: const Offset(0, -.3)),
            ]),
      );

  @override
  Widget build(BuildContext context) {
    final dark = _data?['dark'] == true;
    return Theme(
      data: CrewClockTheme.data(dark: dark),
      child: Builder(
          builder: (context) => Scaffold(
                resizeToAvoidBottomInset: true,
                appBar: CrewClockHeader(
                    pageTitle: [
                      'Briefing',
                      'Roster',
                      if (widget.alarms != null) 'Personal Alarm',
                      if (widget.settings != null) 'Settings'
                    ][_tab],
                    actions: [
                      if (_tab == 0)
                        TextButton.icon(
                          key: const ValueKey('briefing-add-roster'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white38,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onPressed: _busy || !widget.briefing.ready
                              ? null
                              : () => _act('import'),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Roster',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ...?widget.headerActions?.call(_tab),
                    ]),
                body: Column(children: [
                  if (widget.alarmWarning != null)
                    MaterialBanner(
                        content: Text(widget.alarmWarning!),
                        actions: [
                          TextButton(
                              onPressed: widget.onOpenSettings,
                              child: const Text('Settings'))
                        ]),
                  Expanded(
                      child: PageView(
                    key: const ValueKey('crewclock-pages'),
                    physics: const _DeliberatePagePhysics(),
                    controller: _pages,
                    onPageChanged: (index) {
                      setState(() => _tab = index);
                      if (index == 0) _refresh();
                    },
                    children: [
                      _RetainedPage(
                          child: Builder(builder: (context) => _home())),
                      _RetainedPage(child: widget.tools),
                      if (widget.alarms != null)
                        _RetainedPage(child: widget.alarms!),
                      if (widget.settings != null)
                        _RetainedPage(child: widget.settings!),
                    ],
                  )),
                ]),
                bottomNavigationBar: DecoratedBox(
                    decoration: BoxDecoration(
                        color: _colors.surface,
                        border: Border(
                            top: BorderSide(color: _colors.outlineVariant))),
                    child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: CupertinoTabBar(
                            backgroundColor: _colors.surface,
                            border: const Border(),
                            height: 52,
                            currentIndex: _tab,
                            activeColor: _teal,
                            inactiveColor: _colors.onSurfaceVariant,
                            onTap: _showTab,
                            items: [
                              _tabItem(CupertinoIcons.airplane, 'Briefing'),
                              _tabItem(CupertinoIcons.calendar, 'Roster'),
                              if (widget.alarms != null)
                                _tabItem(CupertinoIcons.alarm, 'Alarms'),
                              if (widget.settings != null)
                                _tabItem(CupertinoIcons.settings, 'Settings'),
                            ]))),
              )),
    );
  }
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({required this.child});
  final Widget child;
  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _DeliberatePagePhysics extends PageScrollPhysics {
  const _DeliberatePagePhysics({super.parent});
  @override
  _DeliberatePagePhysics applyTo(ScrollPhysics? ancestor) =>
      _DeliberatePagePhysics(parent: buildParent(ancestor));
  @override
  double get minFlingDistance => 96;
  @override
  double get minFlingVelocity => 1200;
  @override
  double get dragStartDistanceMotionThreshold => 32;
}
