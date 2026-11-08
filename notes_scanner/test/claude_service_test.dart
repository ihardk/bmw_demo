import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_scanner/services/claude_service.dart';

void main() {
  late File page;

  setUp(() async {
    page = File('${Directory.systemTemp.createTempSync().path}/page.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
  });

  test('sends the image and parses title + markdown', () async {
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      headers = req.headers;
      return http.Response(
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'thinking', 'thinking': ''},
            {
              'type': 'text',
              'text': '# Grocery list\n\n- [ ] milk\n- [x] eggs',
            },
          ],
        }),
        200,
      );
    });

    final r = await ClaudeService('key', client: client).transcribe([page]);
    expect(r.title, 'Grocery list');
    expect(r.markdown, contains('- [x] eggs'));

    expect(headers['x-api-key'], 'key');
    expect(sent['model'], 'claude-opus-5-5');
    final content = (sent['messages'] as List).single['content'] as List;
    final image = content.firstWhere((b) => b['type'] == 'image');
    expect(image['source']['media_type'], 'image/jpeg');
    expect(base64Decode(image['source']['data'] as String), [
      0xFF,
      0xD8,
      0xFF,
      0xD9,
    ]);
  });

  test('bad API key gives a friendly error', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'type': 'error',
          'error': {
            'type': 'authentication_error',
            'message': 'invalid x-api-key',
          },
        }),
        401,
      ),
    );
    expect(
      () => ClaudeService('bad', client: client).transcribe([page]),
      throwsA(
        isA<ScanException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
  });

  test('refusal is reported, not shown as a note', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'stop_reason': 'refusal', 'content': []}),
        200,
      ),
    );
    expect(
      () => ClaudeService('k', client: client).transcribe([page]),
      throwsA(isA<ScanException>()),
    );
  });
}
