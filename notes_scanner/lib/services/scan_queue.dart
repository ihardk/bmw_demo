import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/model_option.dart';
import '../models/note.dart';
import 'background_keeper.dart';
import 'notes_repository.dart';
import 'scan_pipeline.dart';

enum JobState { waiting, running, failed }

class ScanJob {
  ScanJob(
    this.id,
    this.pages,
    this.mode, {
    this.compareNote,
    this.models = const [],
  });

  final String id;
  final List<File> pages;
  final ReadingMode mode;

  /// Set for a comparison: run each of [models] on this note's pages.
  final Note? compareNote;
  final List<ModelOption> models;
  bool get isCompare => compareNote != null;
  JobState state = JobState.waiting;
  String status = 'Waiting…';
  double? fraction;
  String? error;

  /// Latest live numbers from the pipeline.
  ScanProgress? progress;
  DateTime? startedAt;
}

/// What the last finished scan took, for the activity screen.
class ScanSummary {
  ScanSummary({
    required this.title,
    required this.pages,
    required this.totalMs,
    required this.engine,
    this.last,
  });
  final String title;
  final int pages;
  final int totalMs;
  final String engine;
  final ScanProgress? last;
}

/// Function that reads [pages] into a note; [ScanPipeline] in the app.
typedef ScanRunner = Future<ScanResult> Function(
  List<File> pages,
  ReadingMode mode,
  ValueChanged<ScanProgress> onProgress,
);

/// Function that reads [pages] with one given model and fails rather than
/// falling back; [ScanPipeline] in the app.
typedef CompareRunner = Future<ScanResult> Function(
  List<File> pages,
  ModelOption model,
  ValueChanged<ScanProgress> onProgress,
);

/// Runs scans and model comparisons one after another, independent of any
/// screen, so the user can keep using the app (or leave it) meanwhile.
class ScanQueue extends ChangeNotifier {
  ScanQueue({
    required this.notes,
    required this.runner,
    required this.keeper,
    this.compareRunner,
  });

  final NotesRepository notes;
  final ScanRunner runner;
  final CompareRunner? compareRunner;
  final BackgroundKeeper keeper;

  final _jobs = <ScanJob>[];
  final _done = StreamController<ScanOutcome>.broadcast();
  bool _working = false;
  DateTime _lastKeeperUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  ScanSummary? _lastSummary;

  /// The last scan that finished, if any.
  ScanSummary? get lastSummary => _lastSummary;

  List<ScanJob> get jobs => List.unmodifiable(_jobs);
  bool get busy => _jobs.any((j) => j.state != JobState.failed);

  /// Finished scans, for the in-app "Note ready" message.
  Stream<ScanOutcome> get outcomes => _done.stream;

  void enqueue(List<File> pages, ReadingMode mode) {
    _jobs.add(
      ScanJob(DateTime.now().microsecondsSinceEpoch.toString(), pages, mode),
    );
    notifyListeners();
    _pump();
  }

  /// Runs each of [models] on [note]'s pages; each result is saved on the
  /// note as a version as soon as that model finishes.
  void compare(Note note, List<ModelOption> models) {
    _jobs.add(
      ScanJob(
        'cmp-${DateTime.now().microsecondsSinceEpoch}',
        note.imagePaths.map(File.new).toList(),
        ReadingMode.best,
        compareNote: note,
        models: models,
      ),
    );
    notifyListeners();
    _pump();
  }

  void retry(ScanJob job) {
    job
      ..state = JobState.waiting
      ..status = 'Waiting…'
      ..fraction = null
      ..error = null;
    notifyListeners();
    _pump();
  }

  /// Drops a failed or waiting scan and its photos. (A comparison's photos
  /// belong to its note and stay.)
  Future<void> remove(ScanJob job) async {
    if (job.state == JobState.running) return;
    _jobs.remove(job);
    notifyListeners();
    if (job.isCompare) return;
    await NotesRepository.deleteImages(job.pages.map((f) => f.path).toList());
  }

  void _report(ScanJob job, ScanProgress p, String title, int waiting) {
    notifyListeners();
    // Android rate-limits notification updates: about once a second.
    final now = DateTime.now();
    if (now.difference(_lastKeeperUpdate).inMilliseconds >= 1000 ||
        p.stage != ScanStage.writing) {
      _lastKeeperUpdate = now;
      keeper.progress(
        waiting > 0 ? '$title (${waiting + 1} jobs)' : title,
        job.status,
      );
    }
  }

  Future<void> _runCompare(ScanJob job, int waiting) async {
    final note = job.compareNote!;
    final count = job.models.length;
    for (var i = 0; i < count; i++) {
      final option = job.models[i];
      final clock = Stopwatch()..start();
      var peak = ProcessInfo.currentRss;
      var lastSample = DateTime.now();
      ScanProgress? last;
      NoteVersion version;
      try {
        final result = await compareRunner!(job.pages, option, (p) {
          last = p;
          final now = DateTime.now();
          if (now.difference(lastSample).inMilliseconds >= 300) {
            lastSample = now;
            final rss = ProcessInfo.currentRss;
            if (rss > peak) peak = rss;
          }
          job
            ..status = '${option.name} (${i + 1} of $count) · ${p.status}'
            ..fraction = (i + p.fraction) / count
            ..progress = p;
          _report(job, p, 'Comparing models', waiting);
        });
        final rss = ProcessInfo.currentRss;
        if (rss > peak) peak = rss;
        final stats = result.stats ?? last;
        version = NoteVersion(
          modelId: option.id,
          modelName: option.name,
          createdAt: DateTime.now(),
          markdown: result.markdown,
          totalMs: clock.elapsedMilliseconds,
          modelLoadMs: stats?.modelLoadMs,
          firstTokenMs: stats?.firstTokenMs,
          tokensPerSec: stats?.tokensPerSec,
          words: RegExp(r'\S+').allMatches(result.markdown).length,
          backend: stats?.backend,
          peakRamMb: peak ~/ (1024 * 1024),
          pageTimesMs: stats?.pageTimesMs ?? const [],
        );
      } catch (e) {
        debugPrint('Compare: ${option.name} failed: $e');
        version = NoteVersion(
          modelId: option.id,
          modelName: option.name,
          createdAt: DateTime.now(),
          error: e is ScanFailure ? e.message : _shortError(e),
          totalMs: clock.elapsedMilliseconds,
          backend: last?.backend,
          peakRamMb: peak ~/ (1024 * 1024),
        );
      }
      note.versions.insert(0, version);
      await notes.saveChanges();
    }
  }

  static String _shortError(Object e) {
    final line = e.toString().split('\n').first;
    return line.length > 160 ? '${line.substring(0, 160)}…' : line;
  }

  Future<void> _pump() async {
    if (_working) return;
    _working = true;
    Note? lastNote;
    var made = 0;
    Note? compared;
    try {
      while (true) {
        final job = _jobs.where((j) => j.state == JobState.waiting).firstOrNull;
        if (job == null) break;
        job
          ..state = JobState.running
          ..startedAt = DateTime.now();
        notifyListeners();
        final waiting = _jobs.where((j) => j.state == JobState.waiting).length;
        if (job.isCompare) {
          await _runCompare(job, waiting);
          _jobs.remove(job);
          compared = job.compareNote;
          _done.add(
            ScanOutcome(note: job.compareNote, compared: job.models.length),
          );
          notifyListeners();
          continue;
        }
        try {
          final result = await runner(job.pages, job.mode, (p) {
            job
              ..status = p.status
              ..fraction = p.fraction
              ..progress = p;
            _report(job, p, 'Reading your notes', waiting);
          });
          final note = Note(
            id: job.id,
            title: result.title,
            markdown: result.markdown,
            createdAt: DateTime.now(),
            imagePaths: job.pages.map((f) => f.path).toList(),
            engine: result.engine,
          );
          await notes.add(note);
          _lastSummary = ScanSummary(
            title: note.title,
            pages: job.pages.length,
            totalMs: DateTime.now().difference(job.startedAt!).inMilliseconds,
            engine: result.engine,
            last: job.progress,
          );
          _jobs.remove(job);
          lastNote = note;
          made++;
          _done.add(ScanOutcome(note: note, notice: result.notice));
        } catch (e) {
          debugPrint('Scan failed: $e');
          job
            ..state = JobState.failed
            ..error = e is ScanFailure
                ? e.message
                : 'Could not read the pages. Tap to try again.';
          _done.add(ScanOutcome(error: job.error));
        }
        notifyListeners();
      }
    } finally {
      _working = false;
      if (lastNote == null && compared != null) {
        await keeper.finished('Comparison ready', compared.title);
      } else if (lastNote != null) {
        await keeper.finished(
          made == 1 ? 'Note ready' : '$made notes ready',
          made == 1 ? lastNote.title : 'Latest: ${lastNote.title}',
        );
      } else {
        await keeper.stop();
      }
    }
  }

  @override
  void dispose() {
    _done.close();
    super.dispose();
  }
}

class ScanOutcome {
  ScanOutcome({this.note, this.notice, this.error, this.compared});
  final Note? note;
  final String? notice;
  final String? error;

  /// For a finished comparison: how many models ran.
  final int? compared;
}
