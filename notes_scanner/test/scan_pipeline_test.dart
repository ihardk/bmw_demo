import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:notes_scanner/services/ocr_service.dart';
import 'package:notes_scanner/services/scan_pipeline.dart';

/// OCR that fails on chosen pages like ML Kit did on a phone in the R8 build.
class FakeOcr extends OcrService {
  FakeOcr(this.pages);
  final Map<String, List<String>?> pages; // null = throw

  @override
  Future<List<String>> readBlocks(File page) async {
    final r = pages[page.path];
    if (r == null) {
      throw PlatformException(
        code: 'error',
        message: 'Object.getClass() on null',
      );
    }
    return r;
  }

  @override
  Future<void> close() async {}
}

void main() {
  final p1 = File('p1.jpg'), p2 = File('p2.jpg');

  test('ML Kit failing on every page gives a friendly ScanFailure', () async {
    final pipeline = ScanPipeline(
      model: LocalModelService.fake(ModelState.notInstalled),
      ocr: FakeOcr({}),
    );
    await expectLater(
      pipeline.scan([p1], mode: ReadingMode.quick, onStatus: (_) {}),
      throwsA(
        isA<ScanFailure>().having(
          (e) => e.message,
          'message',
          contains('download the on-device model'),
        ),
      ),
    );
  });

  test(
    'ML Kit failing on one page still makes a note from the others',
    () async {
      final pipeline = ScanPipeline(
        model: LocalModelService.fake(ModelState.notInstalled),
        ocr: FakeOcr({
          p1.path: ['Shopping', '- milk'],
          p2.path: null,
        }),
      );
      final r = await pipeline.scan(
        [p1, p2],
        mode: ReadingMode.quick,
        onStatus: (_) {},
      );
      expect(r.title, 'Shopping');
      expect(r.markdown, contains('- milk'));
      expect(r.engine, ScanPipeline.quickEngine);
    },
  );

  test('Best mode without the model says how to get better results', () async {
    final pipeline = ScanPipeline(
      model: LocalModelService.fake(ModelState.notInstalled),
      ocr: FakeOcr({
        p1.path: ['Title', 'text'],
      }),
    );
    final r = await pipeline.scan(
      [p1],
      mode: ReadingMode.best,
      onStatus: (_) {},
    );
    expect(r.notice, contains('Download the on-device model'));
  });
}
