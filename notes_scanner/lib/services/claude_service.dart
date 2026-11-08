import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Result of transcribing notebook pages.
class ScanResult {
  ScanResult(this.title, this.markdown);
  final String title;
  final String markdown;
}

class ScanException implements Exception {
  ScanException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sends photos of handwritten pages to the Claude Messages API and gets
/// back clean, structured Markdown notes.
///
/// There is no official Anthropic SDK for Dart, so this calls the REST API
/// directly.
class ClaudeService {
  ClaudeService(this.apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-5-5';

  static const _systemPrompt = '''
You turn photos of rough, handwritten notebook pages into clean digital notes.

How to work:
- Read every page carefully, in order. Handwriting may be messy, slanted, crossed out, or squeezed into margins; use the surrounding context to work out unclear words.
- Keep the writer's meaning and wording. Fix obvious spelling slips, but do not add facts, opinions or content that is not on the page.
- Rebuild the structure the writer intended: headings, bullet and numbered lists, checklists ("- [ ]" / "- [x]" for to-dos and ticked boxes), tables, and arrows or links between ideas.
- Write math in plain text or LaTeX-style inline notation, and code in fenced code blocks.
- Describe drawings or diagrams briefly in italics, e.g. *[Diagram: flow from A to B]*.
- Ignore crossed-out text. If a word truly cannot be read, write [illegible] rather than guessing.
- If there are several pages, merge them into one continuous note.

Output format: GitHub-flavored Markdown only, with nothing before or after it. The very first line must be a short, descriptive title as a level-1 heading ("# Title"). If the pages contain no handwriting at all, reply with "# Empty scan" followed by one line saying no handwritten text was found.
''';

  Future<ScanResult> transcribe(List<File> pages) async {
    if (pages.isEmpty) throw ScanException('No pages to scan.');

    final content = <Map<String, dynamic>>[];
    for (var i = 0; i < pages.length; i++) {
      final bytes = await pages[i].readAsBytes();
      if (pages.length > 1) {
        content.add({'type': 'text', 'text': 'Page ${i + 1}:'});
      }
      content.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': _mediaType(pages[i].path),
          'data': base64Encode(bytes),
        },
      });
    }
    content.add({
      'type': 'text',
      'text': pages.length == 1
          ? 'Transcribe this notebook page into a clean note.'
          : 'Transcribe these ${pages.length} notebook pages into one clean note.',
    });

    final body = {
      'model': _model,
      'max_tokens': 16000,
      'system': _systemPrompt,
      'output_config': {'effort': 'medium'},
      // If a request is declined by a safety classifier, let the API retry
      // it on Anthropic's recommended fallback model automatically.
      'fallbacks': 'default',
      'messages': [
        {'role': 'user', 'content': content},
      ],
    };

    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2026-10-21',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 5));
    } on SocketException {
      throw ScanException(
        'No internet connection. Check your network and try again.',
      );
    } on HttpException catch (e) {
      throw ScanException('Network error: ${e.message}');
    }

    final decoded = _tryDecode(res.body);
    if (res.statusCode != 200) {
      throw ScanException(_errorMessage(res.statusCode, decoded));
    }
    if (decoded == null) {
      throw ScanException('Unexpected response from the server.');
    }

    final stopReason = decoded['stop_reason'];
    if (stopReason == 'refusal') {
      throw ScanException(
        'These pages could not be processed. Try different photos.',
      );
    }

    final blocks = (decoded['content'] as List?) ?? const [];
    final text = blocks
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join()
        .trim();
    if (text.isEmpty) {
      throw ScanException('No text came back. Try a clearer photo.');
    }

    var markdown = text;
    if (stopReason == 'max_tokens') {
      markdown += '\n\n*[Note was cut off because it was very long. Try scanning fewer pages at a time.]*';
    }
    return ScanResult(_extractTitle(markdown), markdown);
  }

  static String _extractTitle(String markdown) {
    for (final line in markdown.split('\n')) {
      final t = line.trim();
      if (t.startsWith('# ')) return t.substring(2).trim();
      if (t.isNotEmpty) return t.replaceAll(RegExp(r'^#+\s*'), '');
    }
    return 'Untitled note';
  }

  static String _mediaType(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static String _errorMessage(int status, Map<String, dynamic>? body) {
    final apiMsg = (body?['error'] as Map?)?['message'] as String?;
    switch (status) {
      case 401:
        return 'Your API key was rejected. Check it in Settings.';
      case 403:
        return 'This API key does not have permission to use the model.';
      case 413:
        return 'The photos are too large. Try fewer pages at once.';
      case 429:
        return 'Too many requests right now. Wait a moment and try again.';
      case 529:
      case 503:
        return 'The service is busy. Please try again shortly.';
      default:
        if (status >= 500) return 'Server error ($status). Please try again.';
        return apiMsg ?? 'Request failed ($status).';
    }
  }
}
