import 'package:flutter_test/flutter_test.dart';
import 'package:notes_scanner/services/local_model_service.dart';
import 'package:notes_scanner/services/ocr_formatter.dart';
import 'package:notes_scanner/services/scan_pipeline.dart';

void main() {
  group('OcrFormatter', () {
    test('first short line becomes the title', () {
      final md = OcrFormatter.format([
        ['Biology Ch 3', 'Cells are the basic unit of life'],
      ]);
      expect(md, startsWith('# Biology Ch 3\n'));
      expect(md, contains('Cells are the basic unit of life'));
    });

    test('bullets, numbers and check boxes', () {
      final md = OcrFormatter.format([
        [
          'Groceries',
          '- milk\n• eggs\n1. call mum\n2) pay rent\n[ ] buy stamps\n[x] post letter',
        ],
      ]);
      expect(md, contains('- milk'));
      expect(md, contains('- eggs'));
      expect(md, contains('1. call mum'));
      expect(md, contains('2. pay rent'));
      expect(md, contains('- [ ] buy stamps'));
      expect(md, contains('- [x] post letter'));
    });

    test('"Heading:" and ALL CAPS lines become sub-headings', () {
      final md = OcrFormatter.format([
        [
          'Meeting',
          'Action items:\n- ship app',
          'NEXT STEPS\nreview on friday',
        ],
      ]);
      expect(md, contains('## Action items'));
      expect(md, contains('## NEXT STEPS'));
    });

    test('plain lines keep their line breaks', () {
      final md = OcrFormatter.format([
        ['Diary', 'went to the park\nit rained'],
      ]);
      expect(md, contains('went to the park  \nit rained'));
    });

    test('pages are separated', () {
      final md = OcrFormatter.format([
        ['Title', 'page one text'],
        ['page two text'],
      ]);
      expect(md, contains('page one text\n\n---\n\npage two text'));
    });

    test('nothing found still gives a titled note', () {
      expect(OcrFormatter.format([[]]), '# Scanned note\n');
    });
  });

  test('cleanReply strips a markdown code fence', () {
    expect(
      LocalModelService.cleanReply('```markdown\n# Title\n\n- a\n```'),
      '# Title\n\n- a',
    );
    expect(LocalModelService.cleanReply('  # Plain\n'), '# Plain');
  });

  test('titleOf reads the first heading', () {
    expect(ScanPipeline.titleOf('# Lecture 4\n\ntext'), 'Lecture 4');
    expect(ScanPipeline.titleOf('\n## Notes\ntext'), 'Notes');
    expect(ScanPipeline.titleOf(''), 'Untitled note');
  });
}
