import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Memory figures, all in megabytes.
class MemorySnapshot {
  const MemorySnapshot({
    required this.appMb,
    required this.appPeakMb,
    this.deviceTotalMb,
    this.deviceAvailableMb,
  });

  /// This app's resident memory now and at its highest. Includes the
  /// parts of the model file the runtime has loaded.
  final int appMb;
  final int appPeakMb;

  /// The whole phone: total RAM and what the system could still give out.
  final int? deviceTotalMb;
  final int? deviceAvailableMb;

  int? get deviceUsedMb => deviceTotalMb == null || deviceAvailableMb == null
      ? null
      : deviceTotalMb! - deviceAvailableMb!;
}

/// Reads app and device memory about every 1.5 s, only while something on
/// screen is listening.
class MemoryMonitor extends ChangeNotifier {
  MemoryMonitor({MemorySnapshot Function()? reader})
    : _reader = reader ?? readNow;

  final MemorySnapshot Function() _reader;
  Timer? _timer;
  MemorySnapshot? _latest;

  MemorySnapshot? get latest => _latest;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer == null) {
      _poll();
      _timer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _poll(),
      );
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _poll() {
    try {
      _latest = _reader();
      notifyListeners();
    } catch (e) {
      debugPrint('Memory read failed: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static MemorySnapshot readNow() {
    int? total, available;
    try {
      // World-readable on Android and Linux; missing on iOS.
      final info = parseMeminfo(File('/proc/meminfo').readAsStringSync());
      total = info.totalMb;
      available = info.availableMb;
    } catch (_) {}
    final now = ProcessInfo.currentRss;
    // The kernel's peak can trail the current figure slightly.
    final peak = ProcessInfo.maxRss > now ? ProcessInfo.maxRss : now;
    return MemorySnapshot(
      appMb: now ~/ (1024 * 1024),
      appPeakMb: peak ~/ (1024 * 1024),
      deviceTotalMb: total,
      deviceAvailableMb: available,
    );
  }

  /// Total and available RAM in MB from the text of `/proc/meminfo`.
  @visibleForTesting
  static ({int? totalMb, int? availableMb}) parseMeminfo(String text) {
    int? kb(String key) {
      final m = RegExp(
        '^$key:\\s+(\\d+)\\s*kB',
        multiLine: true,
      ).firstMatch(text);
      return m == null ? null : int.parse(m.group(1)!);
    }

    final total = kb('MemTotal');
    // Older kernels lack MemAvailable: estimate it the way `free` used to.
    final available =
        kb('MemAvailable') ??
        ((kb('MemFree') ?? 0) + (kb('Cached') ?? 0) + (kb('Buffers') ?? 0));
    return (
      totalMb: total == null ? null : total ~/ 1024,
      availableMb: available ~/ 1024,
    );
  }
}
