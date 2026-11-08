import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps a scan running when the user leaves the app.
///
/// Android freezes background apps within seconds, which would pause the
/// on-device model. While scans run, this holds a foreground service with
/// an ongoing "Reading your notes…" notification; when they finish it turns
/// into "Note ready" until the user comes back to the app. Does nothing on
/// iOS (which stops GPU work in the background) and in tests.
class BackgroundKeeper {
  BackgroundKeeper({bool enabled = true})
    : _enabled = enabled && Platform.isAndroid;

  final bool _enabled;
  bool _initialized = false;
  bool _running = false;
  bool _finished = false;
  bool _inForeground = true;
  AppLifecycleListener? _lifecycle;

  bool get inForeground => _inForeground;

  void init() {
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _inForeground = state == AppLifecycleState.resumed;
        // Back in the app: the "Note ready" notification has done its job.
        if (_inForeground && _finished) stop();
      },
    );
    if (!_enabled) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'scans',
        channelName: 'Note scans',
        channelDescription: 'Shows progress while notes are read on the phone.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true, // keep reading with the screen off
        allowAutoRestart:
            false, // a restarted service would have no scan to run
        stopWithTask: true,
      ),
    );
    _initialized = true;
  }

  /// Asks for the notification permission (Android 13+) once, before the
  /// first background scan. Scans still run if the user says no; the
  /// notification just stays hidden.
  Future<void> ensurePermission() async {
    if (!_initialized) return;
    try {
      final p = await FlutterForegroundTask.checkNotificationPermission();
      if (p != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (e) {
      debugPrint('Notification permission: $e');
    }
  }

  Future<void> progress(String title, String text) async {
    if (!_initialized) return;
    _finished = false;
    try {
      if (_running && await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 4711,
          serviceTypes: const [ForegroundServiceTypes.dataSync],
          notificationTitle: title,
          notificationText: text,
        );
        _running = true;
      }
    } catch (e) {
      debugPrint('Background service: $e');
    }
  }

  /// All scans are done. Leaves a "done" notification only if the user is
  /// away; otherwise the in-app message is enough.
  Future<void> finished(String title, String text) async {
    if (!_initialized || !_running) return;
    if (_inForeground) return stop();
    _finished = true;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (e) {
      debugPrint('Background service: $e');
    }
  }

  Future<void> stop() async {
    _finished = false;
    if (!_initialized || !_running) return;
    _running = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('Background service: $e');
    }
  }

  void dispose() => _lifecycle?.dispose();
}
