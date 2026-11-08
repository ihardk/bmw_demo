import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:notes_scanner/services/scan_pipeline.dart';
import 'package:notes_scanner/services/scan_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late TestApp app;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app = TestApp(ModelState.ready);
    await app.notes.load();
  });

  ScanResult result(String title) => ScanResult(
    title: title,
    markdown: '# $title',
    engine: ScanPipeline.modelEngine,
  );

  test('a finished scan becomes a saved note and is announced', () async {
    final outcomes = <ScanOutcome>[];
    app.queue.outcomes.listen(outcomes.add);
    app.queue.enqueue([File('a.jpg')], ReadingMode.best);
    await pumpEventQueue();
    expect(app.queue.jobs.single.state, JobState.running);

    app.runner.onProgress!(const ScanProgress('Reading the page…', 0.3));
    expect(app.queue.jobs.single.fraction, 0.3);
    expect(app.queue.jobs.single.status, 'Reading the page…');

    app.runner.completer.complete(result('Physics'));
    await pumpEventQueue();
    expect(app.queue.jobs, isEmpty);
    expect(app.notes.notes.single.title, 'Physics');
    expect(app.notes.notes.single.imagePaths, ['a.jpg']);
    expect(outcomes.single.note?.title, 'Physics');
  });

  test('scans run one at a time, in order', () async {
    app.queue.enqueue([File('a.jpg')], ReadingMode.best);
    app.queue.enqueue([File('b.jpg')], ReadingMode.best);
    await pumpEventQueue();
    expect(app.runner.calls, 1);
    expect(app.queue.jobs.map((j) => j.state), [
      JobState.running,
      JobState.waiting,
    ]);

    app.runner.completer.complete(result('First'));
    await pumpEventQueue();
    expect(app.runner.calls, 2);
    app.runner.completer.complete(result('Second'));
    await pumpEventQueue();
    expect(app.notes.notes.map((n) => n.title), ['Second', 'First']);
  });

  test('a failed scan stays as a card and can be retried', () async {
    app.queue.enqueue([File('a.jpg')], ReadingMode.best);
    await pumpEventQueue();
    app.runner.completer.completeError(ScanFailure('Scanner broke'));
    await pumpEventQueue();
    final job = app.queue.jobs.single;
    expect(job.state, JobState.failed);
    expect(job.error, 'Scanner broke');
    expect(app.queue.busy, isFalse);

    app.queue.retry(job);
    await pumpEventQueue();
    expect(job.state, JobState.running);
    app.runner.completer.complete(result('Saved'));
    await pumpEventQueue();
    expect(app.notes.notes.single.title, 'Saved');
  });

  test('removing a failed scan deletes its photo', () async {
    final dir = Directory.systemTemp.createTempSync();
    final photo = File('${dir.path}/p.jpg')..writeAsBytesSync([1]);
    app.queue.enqueue([photo], ReadingMode.best);
    await pumpEventQueue();
    app.runner.completer.completeError(Exception('x'));
    await pumpEventQueue();
    await app.queue.remove(app.queue.jobs.single);
    expect(app.queue.jobs, isEmpty);
    expect(photo.existsSync(), isFalse);
  });
}
