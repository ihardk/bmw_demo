import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notes_scanner/main.dart';
import 'package:notes_scanner/services/background_keeper.dart';
import 'package:notes_scanner/services/local_model_service.dart';
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

class TestApp {
  TestApp(ModelState state, {ControlledRunner? runner})
    : model = LocalModelService.fake(state),
      runner = runner ?? ControlledRunner() {
    notes = NotesRepository(store);
    queue = ScanQueue(
      notes: notes,
      runner: this.runner.call,
      keeper: BackgroundKeeper(enabled: false),
    );
  }

  final LocalModelService model;
  final ControlledRunner runner;
  final store = NoteStore();
  late final NotesRepository notes;
  late final ScanQueue queue;

  Widget widget() =>
      NotesScannerApp(model: model, notes: notes, queue: queue, store: store);
}
