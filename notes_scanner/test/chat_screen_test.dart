import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<TestApp> openChat(
  WidgetTester tester, {
  ModelState state = ModelState.ready,
  Set<String> installed = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final app = TestApp(state, installed: installed);
  await app.notes.load();
  await tester.pumpWidget(app.widget());
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Chat'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('chats with the selected model and shows its numbers', (
    tester,
  ) async {
    final app = await openChat(tester);
    expect(app.chat.opened.single.option.id, 'gemma-4-e2b');
    expect(find.textContaining('GPU · loaded in 1.2 s'), findsOneWidget);
    expect(find.textContaining('App RAM 1.50 GB'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello there');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(app.chat.opened.single.sent, ['hello there']);
    expect(find.text('hello there'), findsOneWidget); // my bubble
    expect(find.text('You said: hello there'), findsOneWidget);
    expect(find.textContaining('3 tokens'), findsOneWidget);
  });

  testWidgets('offers only downloaded models that can chat', (tester) async {
    await openChat(tester, installed: {'xiaomi-ocr-0', 'qwen2-vl-2b'});
    await tester.tap(find.text('Gemma 4 E2B').last);
    await tester.pumpAndSettle();
    expect(find.text('Qwen2-VL 2B'), findsWidgets);
    expect(find.text('Xiaomi-OCR-0'), findsNothing);
  });

  testWidgets('switching model loads it and closes the old one', (
    tester,
  ) async {
    final app = await openChat(tester, installed: {'qwen2-vl-2b'});
    await tester.tap(find.text('Gemma 4 E2B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Qwen2-VL 2B').last);
    await tester.pumpAndSettle();
    expect(app.chat.opened.map((s) => s.option.id), [
      'gemma-4-e2b',
      'qwen2-vl-2b',
    ]);
    expect(app.chat.opened.first.closed, isTrue);
  });

  testWidgets('explains when no downloaded model can chat', (tester) async {
    await openChat(
      tester,
      state: ModelState.notInstalled,
      installed: {'xiaomi-ocr-0'},
    );
    expect(
      find.textContaining('only read pages and can\'t chat'),
      findsOneWidget,
    );
    expect(find.text('Get models'), findsOneWidget);
  });

  testWidgets('Stop ends an answer early', (tester) async {
    final app = await openChat(tester);
    final session = app.chat.opened.single..hold = Completer<void>();
    await tester.enterText(find.byType(TextField), 'long story');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(find.byTooltip('Stop'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(session.hold, isNull);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.text('You said: long story'), findsNothing);
    expect(find.text('Stopped before it answered.'), findsOneWidget);
  });

  testWidgets('New chat clears; hybrid models get a fresh engine', (
    tester,
  ) async {
    final app = await openChat(tester, installed: {'lfm2.5-vl-1.6b'});
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(app.chat.opened.single.resets, 1);
    expect(find.text('You said: hi'), findsNothing);

    // LFM2.5-VL carries state across conversations: reload instead.
    await tester.tap(find.text('Gemma 4 E2B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('LFM2.5-VL 1.6B').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(app.chat.opened.length, 3);
    expect(app.chat.opened[1].closed, isTrue);
    expect(app.chat.opened.last.option.id, 'lfm2.5-vl-1.6b');
  });

  testWidgets('leaving the screen frees the model', (tester) async {
    final app = await openChat(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(app.chat.opened.single.closed, isTrue);
  });
}
