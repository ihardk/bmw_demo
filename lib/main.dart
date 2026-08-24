import 'package:bmw_demo/screens/start_screen.dart';
import 'package:flutter/material.dart';

import 'constants/my_colors.dart';
import 'data/day_counter_bridge.dart';
import 'screens/counter/event_detail_screen.dart';
import 'screens/counter/events_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A tap on the home-screen widget carries the counter's id, so the app can
  // open straight onto that counter instead of the usual start screen.
  final launchEventId = await DayCounterBridge.takeLaunchEventId();
  runApp(MyApp(launchEventId: launchEventId));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.launchEventId});

  final String? launchEventId;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.launchEventId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openCounter(widget.launchEventId!),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The app is often already running when the widget is tapped; the host
    // parks the id and we pick it up here.
    if (state == AppLifecycleState.resumed) {
      DayCounterBridge.takeLaunchEventId().then((id) {
        if (id != null) _openCounter(id);
      });
    }
  }

  void _openCounter(String id) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMW Demo',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: kcPrimary,
          secondary: kcSecondaryEnd,
          tertiary: kcSecondaryStart,
        ),
        scaffoldBackgroundColor: kcBG,
      ),
      home: widget.launchEventId == null
          ? const StartPage()
          : const EventsScreen(),
    );
  }
}
