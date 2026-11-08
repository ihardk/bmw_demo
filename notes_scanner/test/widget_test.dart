import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/main.dart';
import 'package:notes_scanner/models/note.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    await tester.pumpWidget(
      NotesScannerApp(model: LocalModelService.fake(ModelState.notInstalled)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Scan notes'), findsOneWidget);
    expect(find.text('Better results for messy handwriting'), findsOneWidget);
  });

  testWidgets('No banner once the model is ready', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      NotesScannerApp(model: LocalModelService.fake(ModelState.ready)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Better results for messy handwriting'), findsNothing);
  });

  testWidgets('Settings shows model status and download button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      NotesScannerApp(model: LocalModelService.fake(ModelState.notInstalled)),
    );
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
    final model = LocalModelService.fake(
      ModelState.unsupported,
      deviceRamMb: 3000,
    )..unsupportedReason = 'needs about 4 GB';
    await tester.pumpWidget(NotesScannerApp(model: model));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Not available on this phone'), findsOneWidget);
    expect(find.text('needs about 4 GB'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });
}
