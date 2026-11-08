import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('Settings shows model status and download button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = TestApp(ModelState.notInstalled);
    await app.notes.load();
    await tester.pumpWidget(app.widget());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Gemma 4 E2B'), findsOneWidget);
    expect(find.text('Not downloaded'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Best quality'), findsOneWidget);
    expect(find.text('Quick scan'), findsOneWidget);
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
    expect(find.text('Not available on this phone'), findsOneWidget);
    expect(find.text('needs about 4 GB'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
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
}
