import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import 'background_keeper.dart';
import 'notes_repository.dart';
import 'scan_pipeline.dart';

enum JobState { waiting, running, failed }

class ScanJob {
  ScanJob(this.id, this.pages, this.mode);

  final String id;
  final List<File> pages;
  final ReadingMode mode;
  JobState state = JobState.waiting;
  String status = 'Waiting…';
  double? fraction;
  String? error;
}

/// Function that reads [pages] into a note; [ScanPipeline] in the app.
typedef ScanRunner = Future<ScanResult> Function(
  List<File> pages,
  ReadingMode mode,
  ValueChanged<ScanProgress> onProgress,
);

/// Runs scans one after another, independent of any screen, so the user can
/// keep using the app (or leave it) while notes are read.
class ScanQueue extends ChangeNotifier {
  ScanQueue({required this.notes, required this.runner, required this.keeper});

  final NotesRepository notes;
  final ScanRunner runner;
  final BackgroundKeeper keeper;

  final _jobs = <ScanJob>[];
  final _done = StreamController<ScanOutcome>.broadcast();
  bool _working = false;

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

  void retry(ScanJob job) {
    job
      ..state = JobState.waiting
      ..status = 'Waiting…'
      ..fraction = null
      ..error = null;
    notifyListeners();
    _pump();
  }

  /// Drops a failed or waiting scan and its photos.
  Future<void> remove(ScanJob job) async {
    if (job.state == JobState.running) return;
    _jobs.remove(job);
    notifyListeners();
    await NotesRepository.deleteImages(job.pages.map((f) => f.path).toList());
  }

  Future<void> _pump() async {
    if (_working) return;
    _working = true;
    Note? lastNote;
    var made = 0;
    try {
      while (true) {
        final job = _jobs.where((j) => j.state == JobState.waiting).firstOrNull;
        if (job == null) break;
        job.state = JobState.running;
        notifyListeners();
        final waiting = _jobs.where((j) => j.state == JobState.waiting).length;
        try {
          final result = await runner(job.pages, job.mode, (p) {
            job
              ..status = p.status
              ..fraction = p.fraction;
            notifyListeners();
            keeper.progress(
              waiting > 0
                  ? 'Reading your notes (${waiting + 1} scans)'
                  : 'Reading your notes',
              p.status,
            );
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
      if (lastNote != null) {
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
  ScanOutcome({this.note, this.notice, this.error});
  final Note? note;
  final String? notice;
  final String? error;
}
