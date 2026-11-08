import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/screens/activity_screen.dart';
import 'package:notes_scanner/services/memory_monitor.dart';

void main() {
  test('parses total and available RAM from /proc/meminfo', () {
    const text = '''
MemTotal:        7864320 kB
MemFree:          512000 kB
MemAvailable:    3145728 kB
Buffers:           10240 kB
Cached:          2048000 kB
''';
    final r = MemoryMonitor.parseMeminfo(text);
    expect(r.totalMb, 7680);
    expect(r.availableMb, 3072);
  });

  test('estimates available RAM on kernels without MemAvailable', () {
    const text = '''
MemTotal:        4194304 kB
MemFree:          524288 kB
Buffers:          102400 kB
Cached:           921600 kB
''';
    final r = MemoryMonitor.parseMeminfo(text);
    expect(r.totalMb, 4096);
    expect(r.availableMb, 512 + 100 + 900);
  });

  test('reads the real process memory on this machine', () {
    final s = MemoryMonitor.readNow();
    expect(s.appMb, greaterThan(0));
    expect(s.appPeakMb, greaterThanOrEqualTo(s.appMb));
  });

  test('polls only while someone listens', () {
    fakeAsync((async) {
      var reads = 0;
      final m = MemoryMonitor(
        reader: () {
          reads++;
          return const MemorySnapshot(appMb: 1, appPeakMb: 1);
        },
      );
      async.elapse(const Duration(seconds: 5));
      expect(reads, 0);

      void listener() {}
      m.addListener(listener);
      expect(reads, 1); // reads straight away
      async.elapse(const Duration(seconds: 3));
      expect(reads, 3);

      m.removeListener(listener);
      async.elapse(const Duration(seconds: 10));
      expect(reads, 3);
    });
  });

  test('formats sizes and durations', () {
    expect(formatMb(812), '812 MB');
    expect(formatMb(2365), '2.31 GB');
    expect(formatMs(850), '850 ms');
    expect(formatMs(12400), '12.4 s');
    expect(formatMs(65000), '1 min 05 s');
  });
}
