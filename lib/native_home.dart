import 'dart:async';
import 'package:flutter/material.dart';

class CrewClockBriefingBridge extends ChangeNotifier {
  Future<Map<String, dynamic>> Function(String?)? _load;
  Future<void> Function(String, String?, Object?)? _action;
  Future<void> _pending = Future<void>.value();
  bool get ready => _load != null;

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
      {super.key, required this.tools, required this.briefing});
  final Widget tools;
  final CrewClockBriefingBridge briefing;

  @override
  State<CrewClockShell> createState() => _CrewClockShellState();
}

class _CrewClockShellState extends State<CrewClockShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  Map<String, dynamic>? _data;
  String? _selected, _error;
  bool _busy = false, _refreshing = false;
  Timer? _timer;
  final _newTask = TextEditingController();
  final _note = TextEditingController();
  static const _navy = Color(0xff10253a);
  static const _teal = Color(0xff008594);

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
      if (action == 'import' || action == 'review') setState(() => _tab = 1);
      await _refresh();
      if (mounted && action == 'note') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note saved on this device')));
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not complete action. Retry; preparation supports up to 12 items.')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.briefing.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    _newTask.dispose();
    _note.dispose();
    super.dispose();
  }

  Widget _title(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );

  ColorScheme get _colors => ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: _data?['dark'] == true ? Brightness.dark : Brightness.light);

  Widget _clock(Map clock, bool accent) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accent ? _teal : _colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: accent ? Colors.white : null),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${clock['label']}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text('${clock['time']}',
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${clock['date']}'),
            Text('${clock['zone']}'),
          ]),
        ),
      );

  Widget _briefing(Map<String, dynamic> data) {
    final flight = data['flight'] as Map;
    final choices = data['flights'] as List;
    final clocks = data['clocks'] as List;
    final tasks = data['tasks'] as List;
    final next = data['next'] as Map?;
    final pending = tasks.where((t) => t['checkedAt'] == null);
    final departure = DateTime.parse(flight['departure'] as String);
    final minutes =
        (departure.difference(DateTime.now()).inSeconds / 60).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: _navy, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              data['demo'] == true
                  ? 'FICTIONAL DEMO · NO ALARMS SCHEDULED'
                  : 'FLIGHT PREPARATION',
              style: const TextStyle(
                  color: Color(0xff86d9cc),
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text('${flight['number']} · ${flight['from']} → ${flight['to']}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
              minutes > 0
                  ? 'Departs in ${minutes ~/ 60}h ${minutes % 60}m'
                  : 'Departure has passed',
              style: const TextStyle(color: Color(0xffb9cbd9), fontSize: 18)),
          if (data['demo'] == true)
            TextButton(
                onPressed: _busy ? null : () => _act('exitDemo'),
                child: const Text('Exit demo',
                    style: TextStyle(color: Colors.white))),
        ]),
      ),
      if (choices.length > 1) ...[
        _title('Flight'),
        DropdownButtonFormField<String>(
          key: ValueKey(data['key']),
          initialValue: data['key'] as String,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: choices
              .map((f) => DropdownMenuItem<String>(
                  value: f['key'] as String,
                  child: Text('${f['label']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: _busy
              ? null
              : (key) async {
                  if (_note.text != (_data?['note'] ?? '')) {
                    if (!await _act('note', _note.text)) return;
                  }
                  _selected = key;
                  await _refresh();
                },
        ),
      ],
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, size) {
        final width =
            size.maxWidth >= 320 ? (size.maxWidth - 16) / 3 : size.maxWidth;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < clocks.length; i++)
            SizedBox(width: width, child: _clock(clocks[i] as Map, i == 0)),
        ]);
      }),
      const SizedBox(height: 14),
      Text(
          'Same departure instant in three time zones. Flight reminders stay on ${flight['from']} local time when you travel.'),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: _colors.primaryContainer,
            borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Next preparation',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(next == null
              ? 'No upcoming preparation times for this flight.'
              : '${next['label']} · ${next['time']}'),
          const SizedBox(height: 12),
          Text(pending.isEmpty
              ? 'Personal preparation complete'
              : 'To do: ${pending.first['label']}'),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed:
                  _busy || data['demo'] == true ? null : () => _act('review'),
              child: const Text('Review flight alarms')),
        ]),
      ),
      _title('Departure preparation timeline'),
      for (final step in data['steps'] as List)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule, color: _teal),
          title: Text('${step['label']}'),
          subtitle: Text('${step['time']}\n${step['status']}'),
        ),
      _title('Personal preparation'),
      Text(
          '${tasks.where((t) => t['checkedAt'] != null).length} / ${tasks.length} checked'),
      for (var i = 0; i < tasks.length; i++)
        Row(children: [
          Expanded(
              child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: tasks[i]['checkedAt'] != null,
            title: Text('${tasks[i]['label']}'),
            subtitle: tasks[i]['checkedText'] == null
                ? null
                : Text('Checked ${tasks[i]['checkedText']}'),
            onChanged: _busy ? null : (_) => _act('toggle', i),
          )),
          IconButton(
              tooltip: 'Delete preparation item',
              onPressed: _busy ? null : () => _act('delete', i),
              icon: const Icon(Icons.close)),
        ]),
      TextField(
          controller: _newTask,
          maxLength: 100,
          decoration: const InputDecoration(
              labelText: 'New preparation item', border: OutlineInputBorder())),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: _busy || tasks.length >= 12
                  ? null
                  : () => _act('add', _newTask.text),
              child: const Text('Add item'))),
      _title('Layover / pickup note'),
      TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
              hintText: 'Hotel pickup, terminal or personal reminder',
              border: OutlineInputBorder())),
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
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Next flight',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!)),
              if (_data == null && _error == null)
                const Center(child: CircularProgressIndicator())
              else if (_data?['flight'] != null)
                _briefing(_data!)
              else ...[
                _title('Your next duty, in one place.'),
                const Text(
                    'Import your roster to connect departure-local alarms, time-zone checks and a personal preparation list.'),
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

  @override
  Widget build(BuildContext context) {
    final dark = _data?['dark'] == true;
    return Theme(
      data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: _teal,
              brightness: dark ? Brightness.dark : Brightness.light),
          useMaterial3: true),
      child: Builder(
          builder: (context) => Scaffold(
                body: IndexedStack(index: _tab, children: [
                  Builder(builder: (context) => _home()),
                  widget.tools
                ]),
                bottomNavigationBar: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (index) {
                      setState(() => _tab = index);
                      if (index == 0) _refresh();
                    },
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.flight_takeoff),
                          label: 'Next flight'),
                      NavigationDestination(
                          icon: Icon(Icons.calendar_month),
                          label: 'Roster & alarms'),
                    ]),
              )),
    );
  }
}
