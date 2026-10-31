import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'widgets/crewclock_header.dart';
import 'widgets/crewclock_theme.dart';
import 'widgets/inline_reminder_editor.dart';

class FlightBriefingController extends ChangeNotifier {
  Future<Map<String, dynamic>> Function(String?)? _load;
  Future<void> Function(String, String?, Object?)? _action;
  Future<void> _pending = Future<void>.value();
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
      this.settings});
  final Widget tools;
  final Widget? alarms, settings;
  final FlightBriefingController briefing;

  @override
  State<CrewClockShell> createState() => _CrewClockShellState();
}

class _CrewClockShellState extends State<CrewClockShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  final _pages = PageController();
  Map<String, dynamic>? _data;
  String? _selected, _error, _newReminderId;
  bool _busy = false,
      _refreshing = false,
      _addingReminder = false,
      _editingTasks = false;
  Timer? _timer;
  final _newTask = TextEditingController();
  final _note = TextEditingController();
  static const _teal = CrewClockTheme.blue;

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
    if (!widget.briefing.ready || _refreshing) return;
    _refreshing = true;
    try {
      final data = await widget.briefing.load(_selected);
      if (!mounted) return;
      if (_data?['key'] != data['key']) {
        _note.text = data['note'] as String? ?? '';
        _addingReminder = false;
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
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: _teal, borderRadius: BorderRadius.circular(12)),
                    child: Text('${flight['dateBadge'] ?? ''}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700))),
                Text(
                    '${flight['departureTime'] ?? ''} ${flight['number']} ${flight['from']} → ${flight['to']} ${flight['arrivalTime'] ?? ''}',
                    style: const TextStyle(
                        color: _teal,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ])),
          TextButton(
              onPressed: _busy || data['demo'] == true
                  ? null
                  : () => setState(() {
                        _addingReminder = !_addingReminder;
                        _newReminderId = null;
                      }),
              child: const Text('+ Add')),
        ]),
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
                            Text('${step['clock'] ?? step['time']}(L)',
                                style: TextStyle(
                                    color: _colors.primary,
                                    fontSize: 17,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                    fontWeight: FontWeight.w700)),
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
        if (_addingReminder)
          InlineReminderEditor(
            key: ValueKey('add-timeline-${data['key']}'),
            label: '',
            minutesBefore: 60,
            busy: _busy,
            onCancel: () => setState(() => _addingReminder = false),
            onSave: (label, minutes, _, __) async {
              if (!await _act('addReminder', {
                'id': _newReminderId ??=
                    DateTime.now().microsecondsSinceEpoch.toString(),
                'label': label,
                'minutes': minutes
              })) {
                throw StateError('Unable to add reminder.');
              }
              if (mounted) setState(() => _addingReminder = false);
            },
          ),
        if ((data['steps'] as List).isEmpty)
          const Padding(
              padding: EdgeInsets.all(12),
              child:
                  Text('No preparation reminders. Tap + Add to create one.')),
      ]),
    );
  }

  Widget _title(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(title,
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
          style: TextStyle(color: accent ? Colors.white : _colors.onSurface),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Text('${clock['label']}'.replaceAll(' departure', ''),
                    maxLines: 2,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 6),
            Text('${clock['time']}',
                style: const TextStyle(
                    fontSize: 24,
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                '${clock['date']}${clock['dayOffset'] == null || clock['dayOffset'] == 0 ? '' : ' (${clock['dayOffset'] > 0 ? '+' : ''}${clock['dayOffset']}d)'}'),
            Text('${clock['zone']}'),
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

  Widget _briefing(Map<String, dynamic> data) {
    final flight = data['flight'] as Map;
    final choices = data['flights'] as List;
    final clocks = data['clocks'] as List;
    final tasks = data['tasks'] as List;
    final departure = DateTime.parse(flight['departure'] as String);
    final minutes =
        (departure.difference(DateTime.now()).inSeconds / 60).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            width: 30,
            child: Column(children: [
              Container(
                  key: const ValueKey('flight-plane-badge'),
                  width: 28,
                  height: 28,
                  decoration:
                      const BoxDecoration(color: _teal, shape: BoxShape.circle),
                  child: const Icon(CupertinoIcons.airplane,
                      size: 17, color: Colors.white)),
              const SizedBox(height: 6),
              Expanded(
                  child:
                      Container(width: 2, color: _teal.withValues(alpha: .4))),
            ])),
        const SizedBox(width: 10),
        Expanded(
            child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _colors.surface, borderRadius: BorderRadius.circular(18)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                data['demo'] == true
                    ? 'FICTIONAL DEMO · NO ALARMS SCHEDULED'
                    : 'FLIGHT PREPARATION',
                style: const TextStyle(
                    color: _teal,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('${flight['number']} · ${flight['from']} → ${flight['to']}',
                style: TextStyle(
                    color: _colors.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
                minutes > 0
                    ? 'Departs in ${minutes ~/ 60}h ${minutes % 60}m'
                    : 'Departure has passed',
                style:
                    TextStyle(color: _colors.onSurfaceVariant, fontSize: 17)),
            if (data['demo'] == true)
              TextButton(
                  onPressed: _busy ? null : () => _act('exitDemo'),
                  child: const Text('Exit demo',
                      style: TextStyle(color: Colors.white))),
          ]),
        )),
      ])),
      if (choices.length > 1) ...[
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
            const Icon(Icons.flight_takeoff, color: _teal),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    '${choices.firstWhere((f) => f['key'] == data['key'])['label']}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.start)),
            const SizedBox(width: 8),
            const Icon(Icons.unfold_more),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      _title('Departure time across zones'),
      LayoutBuilder(builder: (context, size) {
        if (size.maxWidth < 320 ||
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
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < clocks.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _clock(clocks[i] as Map, i == 0)),
            ],
          ]),
        );
      }),
      const SizedBox(height: 14),
      Text(
          'Same departure instant in three time zones. Flight reminders stay on ${flight['from']} local time when you travel.'),
      const SizedBox(height: 16),
      _timeline(data),
      const SizedBox(height: 12),
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
      for (var i = 0; i < tasks.length; i++)
        Row(children: [
          Expanded(
              child: CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  value: tasks[i]['checkedAt'] != null,
                  title: Text('${tasks[i]['label']}'),
                  subtitle: tasks[i]['checkedText'] == null
                      ? null
                      : Text('Checked ${tasks[i]['checkedText']}'),
                  onChanged: _busy ? null : (_) => _act('toggle', i))),
          if (_editingTasks)
            IconButton(
                tooltip: 'Delete preparation item',
                onPressed: _busy ? null : () => _act('delete', i),
                icon: const Icon(Icons.remove_circle_outline)),
        ]),
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
      _title('Layover / pickup note'),
      TextField(
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          controller: _note,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(
              hintText: 'Hotel pickup, terminal or personal reminder',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none))),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: _busy ? null : () => _act('note', _note.text),
              child: const Text('Save note on this device'))),
      const Text(
          'Personal organization only. Use your airline’s official operational procedures and roster.'),
      const SizedBox(height: 16),
      FilledButton.icon(
          onPressed: _busy ? null : () => _act('export'),
          icon: const Icon(Icons.ios_share),
          label: const Text('Save / share briefing PDF')),
    ]);
  }

  Widget _home() => SafeArea(
          child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            key: const ValueKey('briefing-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
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
                FilledButton(
                    onPressed: _busy || !widget.briefing.ready
                        ? null
                        : () => _act('import'),
                    child: const Text('Import roster')),
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
        activeIcon:
            Icon(icon, key: ValueKey('selected-tab-$label'), color: _teal),
      );

  @override
  Widget build(BuildContext context) {
    final dark = _data?['dark'] == true;
    return Theme(
      data: CrewClockTheme.data(dark: dark),
      child: Builder(
          builder: (context) => Scaffold(
                appBar: const CrewClockHeader(),
                body: PageView(
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
                ),
                bottomNavigationBar: DecoratedBox(
                    decoration: BoxDecoration(
                        color: _colors.surface,
                        border: Border(
                            top: BorderSide(color: _colors.outlineVariant))),
                    child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: CupertinoTabBar(
                            border: const Border(),
                            height: 52,
                            currentIndex: _tab,
                            activeColor: _colors.onSurfaceVariant,
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
