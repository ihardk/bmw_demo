import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Fast on-device text recognition with Google ML Kit (Latin script).
class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// The text blocks found on [page], in ML Kit's reading order.
  Future<List<String>> readBlocks(File page) async {
    final result = await _recognizer.processImage(InputImage.fromFile(page));
    return result.blocks
        .map((b) => b.lines.map((l) => l.text).join('\n'))
        .where((t) => t.trim().isNotEmpty)
        .toList();
  }

  Future<void> close() => _recognizer.close();
}
