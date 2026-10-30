import 'dart:async';
import 'package:flutter/material.dart';
import 'db/database.dart';

class CrewClockShell extends StatefulWidget {
  const CrewClockShell({super.key, required this.tools});
  final Widget tools;

  @override
  State<CrewClockShell> createState() => _CrewClockShellState();
}

class _CrewClockShellState extends State<CrewClockShell>
    with WidgetsBindingObserver {
  int _tab = 0;
  List<Map<String, dynamic>> _alarms = [];
  Timer? _timer;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_tab == 0) _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final rows = await AppDatabase.instance.getAlarmsState();
      if (!mounted) return;
      setState(() {
        _alarms = rows;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load flights. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime? _date(dynamic value) => DateTime.tryParse(value?.toString() ?? '');
  String _clock(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  String _stamp(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${_clock(date)}';

  Widget _home() {
    final now = DateTime.now();
    final flights = _alarms.where((a) {
      final dep = _date(a['dep']);
      return dep != null && dep.isAfter(now);
    }).toList()
      ..sort((a, b) => _date(a['dep'])!.compareTo(_date(b['dep'])!));
    final flight = flights.isEmpty ? null : flights.first;
    final dep = flight == null ? null : _date(flight['dep']);
    final steps = flight == null
        ? <Map<String, dynamic>>[]
        : flights
            .where((a) =>
                _date(a['dep']) == dep &&
                a['fnum'] == flight['fnum'] &&
                a['depApt'] == flight['depApt'] &&
                a['arrApt'] == flight['arrApt'])
            .toList();
    steps.sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));
    final minutes = dep?.difference(now).inMinutes;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text('Flight briefing',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Device ${_clock(now)}  •  UTC ${_clock(now.toUtc())}'),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!)
            else if (flight == null) ...[
              const Icon(Icons.flight_takeoff, size: 64),
              const SizedBox(height: 20),
              const Text('Your next flight starts here',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                  'Import your roster or choose “Preview sample roster” in Roster & alarms to explore a flight briefing.'),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: const Text('Open roster & alarms')),
            ] else ...[
              Card(
                  child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NEXT DEPARTURE'),
                      const SizedBox(height: 12),
                      Text('${flight['fnum'] ?? 'Flight'}',
                          style: Theme.of(context).textTheme.headlineMedium),
                      Text(
                          '${flight['depApt'] ?? '—'} → ${flight['arrApt'] ?? '—'}',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      Text('Departs in ${minutes! ~/ 60}h ${minutes % 60}m'),
                      Text('Device: ${_stamp(dep!.toLocal())}'),
                      Text('UTC: ${_stamp(dep.toUtc())}'),
                    ]),
              )),
              const SizedBox(height: 24),
              Text('Preparation timeline',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'Status reflects saved reminders; confirm system alarm permissions in Roster & alarms.'),
              const SizedBox(height: 12),
              for (final step in steps) _step(step, now),
            ],
          ],
        ),
      ),
    );
  }

  Widget _step(Map<String, dynamic> step, DateTime now) {
    final time = _date(step['time']);
    final done = step['dism'] == 1;
    final missed = step['missed'] == 1;
    final armed = step['armed'] == 1;
    final status = done
        ? 'Done'
        : missed
            ? 'Missed'
            : !armed
                ? 'Off'
                : time != null && !time.isAfter(now)
                    ? 'Elapsed'
                    : 'Scheduled';
    return Card(
        child: ListTile(
      leading: Icon(done
          ? Icons.check_circle
          : armed
              ? Icons.alarm
              : Icons.alarm_off),
      title: Text('${step['lbl'] ?? 'Reminder'}'),
      subtitle: Text(time == null
          ? 'Invalid reminder time'
          : '${_stamp(time.toLocal())} • Device time'),
      trailing: Text(status),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [_home(), widget.tools]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            setState(() => _tab = index);
            if (index == 0) _refresh();
          },
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.flight_takeoff), label: 'Next flight'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month), label: 'Roster & alarms'),
          ],
        ),
      );
}
