import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/main.dart';
import 'package:notes_scanner/models/note.dart';
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
      ),
    ];
    final back = Note.decodeList(Note.encodeList(notes));
    expect(back.single.title, 'Physics lecture');
    expect(back.single.markdown, contains('F = ma'));
    expect(back.single.imagePaths, ['/tmp/a.jpg']);
    expect(back.single.createdAt, DateTime(2026, 11, 8, 9, 30));
  });

  testWidgets('Home shows empty state and scan button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NotesScannerApp());
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Scan notes'), findsOneWidget);
  });

  testWidgets('Scanning without an API key opens Settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NotesScannerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan notes'));
    await tester.pumpAndSettle();
    expect(find.text('Anthropic API key'), findsOneWidget);
  });
}
