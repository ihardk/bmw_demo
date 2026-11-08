import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notes_scanner/main.dart';
import 'package:notes_scanner/models/model_option.dart';
import 'package:notes_scanner/services/background_keeper.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:notes_scanner/services/memory_monitor.dart';
import 'package:notes_scanner/services/note_store.dart';
import 'package:notes_scanner/services/notes_repository.dart';
import 'package:notes_scanner/services/scan_pipeline.dart';
import 'package:notes_scanner/services/scan_queue.dart';

/// A scan runner the test drives by hand.
class ControlledRunner {
  Completer<ScanResult> completer = Completer();
  ValueChanged<ScanProgress>? onProgress;
  int calls = 0;

  Future<ScanResult> call(
    List<File> pages,
    ReadingMode mode,
    ValueChanged<ScanProgress> progress,
  ) {
    calls++;
    onProgress = progress;
    completer = Completer();
    return completer.future;
  }
}

/// Compare runner: each model answers `NAME read this`, or fails if its
/// id is in [failing].
class FakeCompareRunner {
  FakeCompareRunner({this.failing = const {}});
  final Set<String> failing;
  final ran = <String>[];

  Future<ScanResult> call(
    List<File> pages,
    ModelOption model,
    ValueChanged<ScanProgress> progress,
  ) async {
    ran.add(model.id);
    progress(const ScanProgress('Writing the page · 3 words', 0.5));
    if (failing.contains(model.id)) {
      throw ScanFailure('${model.name} ran out of memory.');
    }
    return ScanResult(
      title: 'T',
      markdown: '# T\n\n${model.name} read this',
      engine: ScanPipeline.engineFor(model),
      stats: const ScanProgress(
        'done',
        1,
        tokensPerSec: 12.5,
        modelLoadMs: 2000,
        firstTokenMs: 1500,
        backend: 'CPU',
      ),
    );
  }
}

class TestApp {
  TestApp(
    ModelState state, {
    ControlledRunner? runner,
    Set<String> installed = const {},
    FakeCompareRunner? compare,
  }) : model = LocalModelService.fake(state, installed: installed),
       runner = runner ?? ControlledRunner(),
       compare = compare ?? FakeCompareRunner() {
    notes = NotesRepository(store);
    queue = ScanQueue(
      notes: notes,
      runner: this.runner.call,
      compareRunner: this.compare.call,
      keeper: BackgroundKeeper(enabled: false),
    );
  }

  final FakeCompareRunner compare;

  final LocalModelService model;
  final ControlledRunner runner;
  final store = NoteStore();
  late final NotesRepository notes;
  late final ScanQueue queue;

  /// Fixed memory figures: 1.5 GB app, 8 GB phone with 3 GB free.
  final memory = MemoryMonitor(
    reader: () => const MemorySnapshot(
      appMb: 1536,
      appPeakMb: 2048,
      deviceTotalMb: 8192,
      deviceAvailableMb: 3072,
    ),
  );

  Widget widget() => NotesScannerApp(
    model: model,
    notes: notes,
    queue: queue,
    store: store,
    memory: memory,
  );
}
