import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_model_service.dart';
import 'ocr_formatter.dart';
import 'ocr_service.dart';

enum ReadingMode { best, quick }

class ScanResult {
  ScanResult({
    required this.title,
    required this.markdown,
    required this.engine,
    this.notice,
  });

  final String title;
  final String markdown;

  /// Which reader produced the note, shown on the note card.
  final String engine;

  /// Set when the app had to fall back to the quick reader.
  final String? notice;
}

/// Reads notebook pages entirely on the phone.
///
/// ML Kit always runs first (fast; its text also helps the model). In
/// [ReadingMode.best] with the model downloaded, Gemma then reads each page
/// image and writes the structured note. Otherwise, or if the model fails,
/// ML Kit's text is formatted with [OcrFormatter].
class ScanPipeline {
  ScanPipeline({required this.model, OcrService? ocr})
    : _ocr = ocr ?? OcrService();

  final LocalModelService model;
  final OcrService _ocr;

  static const quickEngine = 'Quick scan (ML Kit)';
  static const modelEngine = 'On-device AI (${LocalModelService.displayName})';

  Future<ScanResult> scan(
    List<File> pages, {
    required ReadingMode mode,
    required ValueChanged<String> onStatus,
  }) async {
    final n = pages.length;
    String pageLabel(int i) => n == 1 ? 'the page' : 'page ${i + 1} of $n';

    final ocrBlocks = <List<String>>[];
    try {
      for (var i = 0; i < n; i++) {
        onStatus('Finding text on ${pageLabel(i)}…');
        ocrBlocks.add(await _ocr.readBlocks(pages[i]));
      }
    } finally {
      await _ocr.close();
    }

    String? notice;
    if (mode == ReadingMode.best && model.isReady) {
      try {
        onStatus('Loading the on-device model…');
        final m = await model.openModel();
        try {
          final parts = <String>[];
          for (var i = 0; i < n; i++) {
            onStatus('Reading handwriting on ${pageLabel(i)}…');
            parts.add(
              await model.readPage(
                m,
                image: await pages[i].readAsBytes(),
                pageNumber: i + 1,
                pageCount: n,
                ocrHint: ocrBlocks[i].join('\n\n'),
              ),
            );
          }
          final markdown = _withTitle(
            parts.where((p) => p.isNotEmpty).join('\n\n'),
          );
          if (markdown.trim().isNotEmpty) {
            return ScanResult(
              title: titleOf(markdown),
              markdown: markdown,
              engine: modelEngine,
            );
          }
          notice =
              'The on-device model returned nothing, so a quick scan was used.';
        } finally {
          await model.closeModel(m);
        }
      } catch (e) {
        debugPrint('On-device model failed: $e');
        notice =
            'The on-device model could not run (often low memory), '
            'so a quick scan was used. Closing other apps can help.';
      }
    } else if (mode == ReadingMode.best &&
        model.state == ModelState.notInstalled) {
      notice =
          'Quick scan used. Download the on-device model in Settings '
          'for much better results on messy handwriting.';
    }

    onStatus('Formatting your note…');
    final markdown = OcrFormatter.format(ocrBlocks);
    return ScanResult(
      title: titleOf(markdown),
      markdown: markdown,
      engine: quickEngine,
      notice: notice,
    );
  }

  /// Makes sure the note starts with a `# Title` line.
  static String _withTitle(String md) {
    final t = md.trimLeft();
    return t.startsWith('# ') ? t : '# Scanned note\n\n$t';
  }

  static String titleOf(String markdown) {
    for (final line in markdown.split('\n')) {
      final t = line.trim();
      if (t.startsWith('# ')) return t.substring(2).trim();
      if (t.isNotEmpty) return t.replaceAll(RegExp(r'^#+\s*'), '');
    }
    return 'Untitled note';
  }
}
