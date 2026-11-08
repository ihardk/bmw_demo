/// Turns raw OCR text into a readable Markdown note using simple rules.
///
/// Used when the on-device model isn't available: it keeps the writer's
/// line layout and recognises the common notebook shapes (bullets, numbered
/// items, check boxes and "Heading:" lines).
class OcrFormatter {
  static final _bullet = RegExp(r'^[-*•·–—>→=]+\s*(.+)$');
  static final _numbered = RegExp(r'^(\d{1,2})\s*[.)]\s*(.+)$');
  static final _todo = RegExp(r'^(?:\[\s?\]|☐|□|O\s(?=[A-Z]))\s*(.+)$');
  static final _done = RegExp(r'^(?:\[[xX✓✔/]\]|☑|☒|✓|✔)\s*(.+)$');

  /// Formats [pages] (one list of text blocks per page) into Markdown whose
  /// first line is a `# Title`.
  static String format(List<List<String>> pages) {
    final bodies = <String>[];
    String? title;

    for (final blocks in pages) {
      final out = <String>[];
      for (final block in blocks) {
        final lines = block
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isEmpty) continue;

        if (title == null && lines.first.length <= 60) {
          title = lines.first.replaceAll(RegExp(r'[:\-–—]+$'), '').trim();
          lines.removeAt(0);
          if (lines.isEmpty) continue;
        }
        out.add(_formatBlock(lines));
      }
      bodies.add(out.join('\n\n'));
    }

    final body = bodies.where((b) => b.isNotEmpty).join('\n\n---\n\n');
    final heading = (title == null || title.isEmpty) ? 'Scanned note' : title;
    return body.isEmpty ? '# $heading\n' : '# $heading\n\n$body\n';
  }

  static String _formatBlock(List<String> lines) {
    final out = <String>[];
    var prevWasList = false;
    for (final line in lines) {
      String? md;
      Match? m;
      if ((m = _done.firstMatch(line)) != null) {
        md = '- [x] ${m!.group(1)}';
      } else if ((m = _todo.firstMatch(line)) != null) {
        md = '- [ ] ${m!.group(1)}';
      } else if ((m = _numbered.firstMatch(line)) != null) {
        md = '${m!.group(1)}. ${m.group(2)}';
      } else if ((m = _bullet.firstMatch(line)) != null) {
        md = '- ${m!.group(1)}';
      }

      if (md != null) {
        out.add(md);
        prevWasList = true;
      } else if (_isHeading(line)) {
        if (out.isNotEmpty) out.add('');
        out.add('## ${line.replaceAll(RegExp(r':+$'), '').trim()}');
        out.add('');
        prevWasList = false;
      } else {
        // Plain handwriting line: keep the line break the writer made.
        if (prevWasList) out.add('');
        if (out.isNotEmpty && out.last.isNotEmpty && !prevWasList) {
          out[out.length - 1] = '${out.last}  ';
        }
        out.add(line);
        prevWasList = false;
      }
    }
    return out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static bool _isHeading(String line) {
    if (line.length > 40) return false;
    if (line.endsWith(':')) return true;
    final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
    return letters.length >= 3 && letters == letters.toUpperCase();
  }
}
