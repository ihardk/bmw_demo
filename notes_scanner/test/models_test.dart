import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notes_scanner/models/model_option.dart';
import 'package:notes_scanner/models/note.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:notes_scanner/services/page_prep.dart';
import 'package:notes_scanner/services/scan_pipeline.dart';

void main() {
  group('model list', () {
    test('ids and stored file names are unique', () {
      final ids = NoteModels.all.map((m) => m.id).toList();
      final files = NoteModels.all.map((m) => m.installFilename).toList();
      expect(ids.toSet().length, ids.length);
      expect(files.toSet().length, files.length);
    });

    test('every download is pinned to a commit and has a size', () {
      for (final m in NoteModels.all) {
        expect(m.sizeBytes, greaterThan(100 << 20), reason: m.id);
        if (m.url != null) {
          expect(
            m.url,
            matches(RegExp(r'/resolve/[0-9a-f]{40}/')),
            reason: m.id,
          );
        }
      }
    });

    test('OCR specialists get their own prompt, not our instructions', () {
      for (final m in NoteModels.all.where((m) => m.isSpecialist)) {
        expect(m.promptStyle, isNot(PromptStyle.notes), reason: m.id);
        if (m.promptStyle == PromptStyle.task) {
          expect(m.taskPrompt, isNotEmpty, reason: m.id);
        }
        expect(m.greedy, isTrue, reason: m.id);
      }
    });
  });

  group('page prep', () {
    Uint8List jpg(int w, int h, {int orientation = 1}) {
      final i = img.Image(width: w, height: h)
        ..clear(img.ColorRgb8(10, 10, 10));
      i.exif.imageIfd.orientation = orientation;
      return img.encodeJpg(i);
    }

    test('pads a page to the model shape, centred, aspect kept', () {
      final out = img.decodeImage(
        PagePrep.prepareSync(jpg(400, 400), 768, 1344, 255),
      )!;
      expect([out.width, out.height], [768, 1344]);
      // Square page fills the width; white bands above and below.
      expect(out.getPixel(384, 5).r, 255);
      expect(out.getPixel(384, 672).r, lessThan(40));
    });

    test('turns a sideways phone photo upright first', () {
      // Stored 800×400 with "rotate 90°" in EXIF: really a 400×800 portrait.
      final out = img.decodeImage(
        PagePrep.prepareSync(jpg(800, 400, orientation: 6), null, null, 255),
      )!;
      expect([out.width, out.height], [400, 800]);
    });

    test('caps the long side for models without a fixed shape', () {
      final out = img.decodeImage(
        PagePrep.prepareSync(jpg(3000, 1500), null, null, 255),
      )!;
      expect(out.width, PagePrep.maxSide);
      expect(out.height, PagePrep.maxSide ~/ 2);
    });

    test('uses the padding colour of the model', () {
      final out = img.decodeImage(
        PagePrep.prepareSync(jpg(200, 400), 1024, 1024, 127),
      )!;
      expect(out.getPixel(5, 512).r, 127);
    });
  });

  test('Unlimited-OCR-2 tags become Markdown', () {
    const raw =
        '<PAGE><BLOCK>title[10, 10, 500, 40]<FORK>Shopping list'
        '<BLOCK>text[10, 60, 500, 90]<FORK>milk, eggs, bread';
    expect(
      NoteModels.cleanUnlimitedOcr(raw),
      '## Shopping list\n\nmilk, eggs, bread',
    );
  });

  test('a short first line of OCR output becomes the title', () {
    expect(
      ScanPipeline.withTitle('Physics notes\nF = ma'),
      '# Physics notes\nF = ma',
    );
    expect(ScanPipeline.withTitle('## Week 3\n- a'), '# Week 3\n- a');
    expect(ScanPipeline.withTitle('# Kept\ntext'), '# Kept\ntext');
    expect(
      ScanPipeline.withTitle('${'x' * 80}\nmore'),
      startsWith('# Scanned note'),
    );
  });

  test('cleanReply drops an empty thinking block', () {
    expect(LocalModelService.cleanReply('<think>\n\n</think>\nHello'), 'Hello');
  });

  test('note versions survive saving and "use as note" keeps the old text', () {
    final note = Note(
      id: '1',
      title: 'Old',
      markdown: '# Old\nfirst',
      createdAt: DateTime(2026),
      engine: 'Quick scan (ML Kit)',
    );
    note.versions.add(
      NoteVersion(
        modelId: 'xiaomi-ocr-0',
        modelName: 'Xiaomi-OCR-0',
        createdAt: DateTime(2026, 2),
        markdown: '# New\nsecond',
        totalMs: 12000,
        tokensPerSec: 9.5,
        peakRamMb: 1800,
        pageTimesMs: [12000],
      ),
    );
    final back = Note.decodeList(Note.encodeList([note])).single;
    final v = back.versions.single;
    expect(v.tokensPerSec, 9.5);
    expect(v.peakRamMb, 1800);
    expect(v.pageTimesMs, [12000]);

    back.useVersion(v, title: 'New');
    expect(back.markdown, '# New\nsecond');
    expect(back.title, 'New');
    expect(back.engine, 'On-device AI (Xiaomi-OCR-0)');
    expect(back.versions.first.markdown, '# Old\nfirst');
  });
}
