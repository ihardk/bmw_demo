import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';

enum NoteAction { deleted }

/// Shows a scanned note. Tabs: the formatted note, an editor for the
/// Markdown, and the original page photos.
class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.note});
  final Note note;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _editor = TextEditingController(
    text: widget.note.markdown,
  );
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() {
      // Leaving the editor tab: keep what was typed.
      if (!_tabs.indexIsChanging && _tabs.index != 1 && _dirty) _applyEdits();
    });

  bool get _dirty => _editor.text != widget.note.markdown;

  @override
  void dispose() {
    _tabs.dispose();
    _editor.dispose();
    super.dispose();
  }

  void _applyEdits() {
    final md = _editor.text;
    widget.note.markdown = md;
    final firstHeading = md
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('# '), orElse: () => '');
    if (firstHeading.isNotEmpty) {
      widget.note.title = firstHeading.substring(2).trim();
    }
    setState(() {});
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.note.markdown));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  Future<void> _share() => SharePlus.instance.share(
    ShareParams(text: widget.note.markdown, subject: widget.note.title),
  );

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('The note and its page photos will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, NoteAction.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (_dirty) _applyEdits();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(note.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: _copy,
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share),
              onPressed: _share,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Note'),
              Tab(text: 'Edit'),
              Tab(text: 'Pages'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            Markdown(
              data: note.markdown,
              selectable: true,
              padding: const EdgeInsets.all(16),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _editor,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Markdown',
                ),
              ),
            ),
            _PagesView(paths: note.imagePaths),
          ],
        ),
      ),
    );
  }
}

class _PagesView extends StatelessWidget {
  const _PagesView({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final files = paths.map(File.new).where((f) => f.existsSync()).toList();
    if (files.isEmpty) {
      return const Center(child: Text('Original photos are not available.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InteractiveViewer(child: Image.file(files[i])),
      ),
    );
  }
}
