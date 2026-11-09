import 'package:flutter/material.dart';
import 'native_home.dart';
import 'widgets/crewclock_header.dart';
import 'widgets/crewclock_theme.dart';
import 'native_roster.dart';
import 'services/crewclock_store.dart';
import 'services/alarm_scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CrewClockApp());
}

class CrewClockApp extends StatefulWidget {
  const CrewClockApp({super.key});
  @override
  State<CrewClockApp> createState() => _CrewClockAppState();
}

class _CrewClockAppState extends State<CrewClockApp>
    with WidgetsBindingObserver {
  final store = CrewClockStore();
  final briefing = FlightBriefingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(briefing.invalidate);
    NativeAlarmScheduler.channel.setMethodCallHandler((call) async {
      if (call.method == 'alarmDismissed') await store.refresh();
      if (call.method == 'openAlarms') briefing.openAlarms();
    });
    _initialize();
  }

  Future<void> _initialize() async {
    await store.initialize();
    if (!mounted || !store.ready) return;
    briefing.connect(store.snapshot, store.action);
    if (await NativeAlarmScheduler.channel
            .invokeMethod<bool>('consumeSurfaceRoute') ==
        true) {
      briefing.openAlarms();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && store.ready) store.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NativeAlarmScheduler.channel.setMethodCallHandler(null);
    store.removeListener(briefing.invalidate);
    store.dispose();
    briefing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (c, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'CrewClock',
            builder: (context, child) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: child!),
            theme: CrewClockTheme.data(dark: store.dark),
            home: store.ready
                ? CrewClockShell(
                    briefing: briefing,
                    headerActions: (index) => [
                          if (index == 1 || index == 3)
                            NativePageActions(
                                store: store, section: index == 1 ? 0 : 2),
                        ],
                    tools: NativeRosterPage(store: store),
                    alarms: NativeRosterPage(store: store, section: 1),
                    settings: NativeRosterPage(store: store, section: 2))
                : Scaffold(
                    appBar: const CrewClockHeader(),
                    body: SafeArea(
                        child: Center(
                            child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 20),
                                      if (store.error == null)
                                        const CircularProgressIndicator()
                                      else ...[
                                        Text(store.error!),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                            onPressed: _initialize,
                                            child: const Text('Retry'))
                                      ],
                                    ]))))),
          ));
}
