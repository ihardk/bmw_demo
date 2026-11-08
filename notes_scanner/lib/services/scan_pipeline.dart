import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart' show InferenceModel;

import '../models/model_option.dart';
import 'local_model_service.dart';
import 'ocr_formatter.dart';
import 'ocr_service.dart';

enum ReadingMode { best, quick }

enum ScanStage { ocr, loadingModel, encoding, writing, formatting }

/// Where a scan is: a line for the user, how far along it is (0–1), and the
/// live numbers the activity screen shows.
class ScanProgress {
  const ScanProgress(
    this.status,
    this.fraction, {
    this.stage = ScanStage.ocr,
    this.page = 0,
    this.pages = 0,
    this.tokens = 0,
    this.words = 0,
    this.preview = '',
    this.backend,
    this.modelLoadMs,
    this.firstTokenMs,
    this.tokensPerSec,
    this.pageTimesMs = const [],
  });

  final String status;
  final double fraction;
  final ScanStage stage;

  /// 1-based page being worked on, of [pages].
  final int page;
  final int pages;

  /// Text pieces (~tokens) and words the model has written for this page.
  final int tokens;
  final int words;

  /// The end of what the model has written so far.
  final String preview;

  /// Where the model runs, e.g. "GPU · vision CPU".
  final String? backend;
  final int? modelLoadMs;

  /// Time from sending the page to the first word: image encoding + prompt.
  final int? firstTokenMs;
  final double? tokensPerSec;
  final List<int> pageTimesMs;
}

/// A scan that produced nothing, with a message fit to show the user.
class ScanFailure implements Exception {
  ScanFailure(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => '$message (cause: $cause)';
}

class ScanResult {
  ScanResult({
    required this.title,
    required this.markdown,
    required this.engine,
    this.notice,
    this.stats,
  });

  final String title;
  final String markdown;

  /// Which reader produced the note, shown on the note card.
  final String engine;

  /// Set when the app had to fall back to the quick reader.
  final String? notice;

  /// The last live numbers of the scan (speed, timings, backend).
  final ScanProgress? stats;
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
  static String engineFor(ModelOption m) => 'On-device AI (${m.name})';
  static String get modelEngine =>
      engineFor(NoteModels.byId(NoteModels.defaultId));

  Future<ScanResult> scan(
    List<File> pages, {
    required ReadingMode mode,
    required ValueChanged<ScanProgress> onProgress,
    ModelOption? option,
    bool fallbackToQuick = true,
  }) async {
    final n = pages.length;
    String pageLabel(int i) => n == 1 ? 'the page' : 'page ${i + 1} of $n';
    final reader = option ?? model.selected;
    final useModel = mode == ReadingMode.best && model.isInstalled(reader);
    // Share of the bar for the ML Kit pass: small when the model follows.
    final ocrShare = useModel ? 0.1 : 0.9;

    // Live numbers, sent with every progress update.
    String? backend;
    int? modelLoadMs, firstTokenMs;
    double? tokensPerSec;
    var tokens = 0, words = 0, page = 0;
    var preview = '';
    final pageTimes = <int>[];
    ScanProgress? last;
    void emit(String status, double fraction, ScanStage stage) => onProgress(
      last = ScanProgress(
        status,
        fraction,
        stage: stage,
        page: page,
        pages: n,
        tokens: tokens,
        words: words,
        preview: preview,
        backend: backend,
        modelLoadMs: modelLoadMs,
        firstTokenMs: firstTokenMs,
        tokensPerSec: tokensPerSec,
        pageTimesMs: List.unmodifiable(pageTimes),
      ),
    );

    // ML Kit failing must not sink the scan: the model can still read the
    // page without its hint.
    final ocrBlocks = <List<String>>[];
    Object? ocrError;
    try {
      for (var i = 0; i < n; i++) {
        page = i + 1;
        emit(
          'Finding text on ${pageLabel(i)}…',
          ocrShare * i / n,
          ScanStage.ocr,
        );
        try {
          ocrBlocks.add(await _ocr.readBlocks(pages[i]));
        } catch (e) {
          debugPrint('ML Kit failed on page ${i + 1}: $e');
          ocrError ??= e;
          ocrBlocks.add(const []);
        }
      }
    } finally {
      try {
        await _ocr.close();
      } catch (_) {}
    }

    String? notice;
    if (useModel) {
      InferenceModel? m;
      Future<InferenceModel> open() async {
        emit(
          'Loading ${reader.name}…',
          last?.fraction ?? ocrShare,
          ScanStage.loadingModel,
        );
        final load = Stopwatch()..start();
        final opened = await model.openModel(reader);
        modelLoadMs = (modelLoadMs ?? 0) + load.elapsedMilliseconds;
        backend = LocalModelService.backendLabel(opened);
        return opened;
      }

      try {
        final parts = <String>[];
        for (var i = 0; i < n; i++) {
          // Hybrid models carry state across conversations on one engine:
          // those get a fresh engine for every page.
          if (m != null && reader.enginePerPage) {
            await model.closeModel(m);
            m = null;
          }
          m ??= await open();
          page = i + 1;
          tokens = 0;
          words = 0;
          preview = '';
          firstTokenMs = null;
          tokensPerSec = null;
          final base = ocrShare + (1 - ocrShare) * i / n;
          final share = (1 - ocrShare) / n;
          emit(
            'Looking at ${pageLabel(i)} (encoding the image)…',
            base,
            ScanStage.encoding,
          );
          final clock = Stopwatch()..start();
          parts.add(
            await model.readPage(
              m,
              option: reader,
              image: await pages[i].readAsBytes(),
              pageNumber: i + 1,
              pageCount: n,
              ocrHint: ocrBlocks[i].join('\n\n'),
              onText: (text) {
                tokens++;
                final now = clock.elapsedMilliseconds;
                firstTokenMs ??= now;
                final decodingMs = now - firstTokenMs!;
                if (tokens > 1 && decodingMs > 0) {
                  tokensPerSec = (tokens - 1) * 1000 / decodingMs;
                }
                words = RegExp(r'\S+').allMatches(text).length;
                preview = text.length > 600
                    ? text.substring(text.length - 600)
                    : text;
                // No way to know a page's length up front: assume ~250
                // words and never quite reach the end of the page's share.
                emit(
                  'Writing ${pageLabel(i)} · $words words',
                  base + share * (words / 250).clamp(0.0, 0.95),
                  ScanStage.writing,
                );
              },
            ),
          );
          pageTimes.add(clock.elapsedMilliseconds);
        }
        final markdown = withTitle(
          parts.where((p) => p.isNotEmpty).join('\n\n'),
        );
        if (markdown.trim().isNotEmpty) {
          return ScanResult(
            title: titleOf(markdown),
            markdown: markdown,
            engine: engineFor(reader),
            stats: last,
          );
        }
        if (!fallbackToQuick) {
          throw ScanFailure('${reader.name} returned no text for these pages.');
        }
        notice = '${reader.name} returned nothing, so a quick scan was used.';
      } catch (e) {
        if (!fallbackToQuick) rethrow;
        debugPrint('On-device model failed: $e');
        notice =
            '${reader.name} could not run (often low memory), '
            'so a quick scan was used. Closing other apps can help.';
      } finally {
        if (m != null) await model.closeModel(m);
      }
    } else if (!fallbackToQuick) {
      throw ScanFailure('${reader.name} is not downloaded.');
    } else if (mode == ReadingMode.best &&
        model.stateOf(reader) == ModelState.notInstalled) {
      notice =
          'Quick scan used. Download an on-device model in Settings '
          'for much better results on messy handwriting.';
    }

    if (ocrError != null && ocrBlocks.every((b) => b.isEmpty)) {
      throw ScanFailure(
        'The text scanner failed on this phone, so the pages could not be read. '
        'Please try again${model.isReady ? '' : ', or download the on-device model in Settings'}.',
        ocrError,
      );
    }

    emit('Formatting your note…', 0.95, ScanStage.formatting);
    final markdown = OcrFormatter.format(ocrBlocks);
    return ScanResult(
      title: titleOf(markdown),
      markdown: markdown,
      engine: quickEngine,
      notice: notice,
      stats: last,
    );
  }

  /// Makes sure the note starts with a `# Title` line. OCR models write no
  /// title, so a short first line (or heading) is promoted to one.
  static String withTitle(String md) {
    final t = md.trimLeft();
    if (t.startsWith('# ')) return t;
    final lines = t.split('\n');
    final first = lines.first.replaceAll(RegExp(r'^#+\s*'), '').trim();
    if (first.isNotEmpty && first.length <= 60 && !first.startsWith('|')) {
      return '# $first\n${lines.skip(1).join('\n')}'.trimRight();
    }
    return '# Scanned note\n\n$t';
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
