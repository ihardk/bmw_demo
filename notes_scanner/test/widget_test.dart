import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/models/model_option.dart';
import 'package:notes_scanner/models/note.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:notes_scanner/services/scan_pipeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  test('Note list round-trips through JSON', () {
    final notes = [
      Note(
        id: '1',
        title: 'Physics lecture',
        markdown: '# Physics lecture\n\n- F = ma',
        createdAt: DateTime(2026, 11, 8, 9, 30),
        imagePaths: ['/tmp/a.jpg'],
        engine: 'Quick scan (ML Kit)',
      ),
    ];
    final back = Note.decodeList(Note.encodeList(notes)).single;
    expect(back.title, 'Physics lecture');
    expect(back.markdown, contains('F = ma'));
    expect(back.imagePaths, ['/tmp/a.jpg']);
    expect(back.engine, 'Quick scan (ML Kit)');
    expect(back.createdAt, DateTime(2026, 11, 8, 9, 30));
  });

  test('Notes saved by the earlier version still load', () {
    final old = Note.decodeList(
      '[{"id":"1","title":"T","markdown":"# T","createdAt":"2026-11-08T09:30:00.000"}]',
    ).single;
    expect(old.engine, isNull);
    expect(old.imagePaths, isEmpty);
  });

  testWidgets('Home shows the model banner when the model is not downloaded', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.notInstalled);
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Scan notes'), findsOneWidget);
    expect(find.text('Better results for messy handwriting'), findsOneWidget);
  });

  testWidgets('No banner once the model is ready', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.ready);
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();
    expect(find.text('Better results for messy handwriting'), findsNothing);
  });

  testWidgets('Settings links to the Models screen with every model', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.notInstalled);
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Scans use Gemma 4 E2B (not downloaded)'),
      findsOneWidget,
    );
    expect(find.text('Best quality'), findsOneWidget);
    expect(find.text('Quick scan'), findsOneWidget);

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    for (final m in NoteModels.all) {
      await tester.scrollUntilVisible(
        find.text(m.name),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(m.name), findsOneWidget);
    }
  });

  testWidgets('A downloaded model can be chosen for scans', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.ready, installed: {'xiaomi-ocr-0'});
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    expect(find.text('Used for scans'), findsOneWidget); // on Gemma 4 E2B
    final use = find.text('Use for scans');
    await tester.scrollUntilVisible(
      use,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(app.model.selected.id, 'xiaomi-ocr-0');
  });

  testWidgets('Unsupported phone explains why', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.unsupported);
    app.model.unsupportedReason = 'needs about 4 GB';
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('needs about 4 GB'), findsOneWidget);
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing); // tile is disabled
  });

  testWidgets('Compare tab: runs models, shows results, swaps the note text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(
      ModelState.ready,
      installed: {'xiaomi-ocr-0', 'paddleocr-vl-1.6'},
      compare: FakeCompareRunner(failing: {'paddleocr-vl-1.6'}),
    );
    await app.notes.load();
    await app.notes.add(
      Note(
        id: 'n1',
        title: 'Lecture',
        markdown: '# Lecture\n\nquick scan text',
        createdAt: DateTime(2026, 11, 8),
        imagePaths: ['p1.jpg'],
        engine: 'Quick scan (ML Kit)',
      ),
    );
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compare models…'));
    await tester.pumpAndSettle();
    // All three downloaded models are ticked.
    expect(find.text('Run 3'), findsOneWidget);
    await tester.tap(find.text('Run 3'));
    await tester.pumpAndSettle();

    expect(app.compare.ran, [
      'gemma-4-e2b',
      'xiaomi-ocr-0',
      'paddleocr-vl-1.6',
    ]);
    expect(find.text('Compare (3)'), findsOneWidget);
    expect(find.text('At a glance'), findsOneWidget);
    expect(find.text('failed'), findsOneWidget); // PaddleOCR row
    expect(find.text('PaddleOCR-VL 1.6 ran out of memory.'), findsOneWidget);
    expect(find.text('12.5'), findsNWidgets(2)); // speed column, both models

    final use = find.text('Use as note').first;
    await tester.ensureVisible(use);
    await tester.pumpAndSettle();
    await tester.tap(use);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use it'));
    await tester.pumpAndSettle();

    final note = app.notes.notes.single;
    expect(note.markdown, contains('read this'));
    expect(note.versions.first.modelName, startsWith('Earlier note text'));
    expect(note.versions.first.markdown, contains('quick scan text'));
  });

  testWidgets('A running scan shows as a card and the app stays usable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.ready);
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();

    app.queue.enqueue([File('page.jpg')], ReadingMode.best);
    await tester.pump();
    app.runner.onProgress!(
      const ScanProgress('Writing the page · 42 words', 0.5),
    );
    await tester.pump();

    expect(find.text('Scanning 1 page…'), findsOneWidget);
    expect(find.text('Writing the page · 42 words'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
    // No blocking overlay: settings and the scan button still work.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Reading mode'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    app.runner.completer.complete(
      ScanResult(
        title: 'Groceries',
        markdown: '# Groceries\n\n- milk',
        engine: ScanPipeline.modelEngine,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scanning 1 page…'), findsNothing);
    expect(find.text('Groceries'), findsOneWidget); // the note card
    expect(find.text('Note ready: Groceries'), findsOneWidget); // snackbar
  });

  testWidgets('Activity screen shows memory, speed, backend and live output', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.ready);
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();

    app.queue.enqueue([File('a.jpg'), File('b.jpg')], ReadingMode.best);
    await tester.pump();
    app.runner.onProgress!(
      const ScanProgress(
        'Writing page 2 of 2 · 12 words',
        0.7,
        stage: ScanStage.writing,
        page: 2,
        pages: 2,
        tokens: 20,
        words: 12,
        preview: '# Groceries\n\n- milk\n- eggs',
        backend: 'GPU · vision CPU',
        modelLoadMs: 4200,
        firstTokenMs: 3100,
        tokensPerSec: 9.5,
        pageTimesMs: [21000],
      ),
    );
    await tester.pump();

    // The scan card shows the live line, then opens the activity screen.
    expect(find.textContaining('App RAM 1.50 GB'), findsOneWidget);
    expect(find.textContaining('9.5 tok/s'), findsOneWidget);
    await tester.tap(find.text('Scanning 2 pages…'));
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('1.50 GB  (peak 2.00 GB)'), findsOneWidget);
    expect(find.text('5.00 GB used of 8.00 GB'), findsOneWidget);
    expect(find.text('3.00 GB'), findsOneWidget); // free
    expect(find.text('Writing note'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('GPU · vision CPU'), findsOneWidget);
    expect(find.text('4.2 s'), findsOneWidget); // model load
    expect(find.text('3.1 s'), findsOneWidget); // image + prompt
    expect(find.text('9.5 tokens/s'), findsOneWidget);
    expect(find.text('12 words · ~20 tokens'), findsOneWidget);
    expect(find.text('p1 21.0 s'), findsOneWidget);
    expect(find.textContaining('- eggs'), findsOneWidget);

    // Finishing shows the last scan's summary.
    app.runner.completer.complete(
      ScanResult(
        title: 'Groceries',
        markdown: '# Groceries',
        engine: ScanPipeline.modelEngine,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No scan running'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
