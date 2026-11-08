import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../models/model_option.dart';
import '../models/note.dart';
import '../services/local_model_service.dart';
import '../services/notes_repository.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_queue.dart';
import 'activity_screen.dart' show formatMs, formatMb;
import 'models_screen.dart';

enum NoteAction { deleted }

/// Shows a scanned note. Tabs: the formatted note, an editor for the
/// Markdown, other models' readings to compare, and the original photos.
class NoteScreen extends StatefulWidget {
  const NoteScreen({
    super.key,
    required this.note,
    required this.notes,
    required this.queue,
    required this.model,
    this.openCompare = false,
  });
  final Note note;
  final NotesRepository notes;
  final ScanQueue queue;
  final LocalModelService model;

  /// Start on the Compare tab.
  final bool openCompare;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _editor = TextEditingController(
    text: widget.note.markdown,
  );
  late final TabController _tabs =
      TabController(
        length: 4,
        vsync: this,
        initialIndex: widget.openCompare ? 2 : 0,
      )..addListener(() {
        // Leaving the editor tab: keep what was typed.
        if (!_tabs.indexIsChanging && _tabs.index != 1 && _dirty) _applyEdits();
      });

  bool get _dirty => _editor.text != widget.note.markdown;

  @override
  void initState() {
    super.initState();
    // Comparison results arrive while the note is open.
    widget.notes.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.notes.removeListener(_changed);
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

  Future<void> _useVersion(NoteVersion v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Use ${v.modelName}\'s text?'),
        content: const Text(
          'It becomes the note. The current text is kept in Compare, so you '
          'can switch back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use it'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_dirty) _applyEdits();
    final md = ScanPipeline.withTitle(v.markdown);
    widget.note.useVersion(
      NoteVersion(
        modelId: v.modelId,
        modelName: v.modelName,
        createdAt: v.createdAt,
        markdown: md,
      ),
      title: ScanPipeline.titleOf(md),
    );
    _editor.text = widget.note.markdown;
    await widget.notes.saveChanges();
    if (!mounted) return;
    setState(() {});
    _tabs.animateTo(0);
  }

  Future<void> _deleteVersion(NoteVersion v) async {
    widget.note.versions.remove(v);
    await widget.notes.saveChanges();
    if (mounted) setState(() {});
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
            tabs: [
              const Tab(text: 'Note'),
              const Tab(text: 'Edit'),
              Tab(
                text: note.versions.isEmpty
                    ? 'Compare'
                    : 'Compare (${note.versions.length})',
              ),
              const Tab(text: 'Pages'),
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
            ListenableBuilder(
              listenable: Listenable.merge([widget.notes, widget.queue]),
              builder: (context, _) => _CompareView(
                note: note,
                queue: widget.queue,
                model: widget.model,
                onUse: _useVersion,
                onDelete: _deleteVersion,
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

class _CompareView extends StatelessWidget {
  const _CompareView({
    required this.note,
    required this.queue,
    required this.model,
    required this.onUse,
    required this.onDelete,
  });

  final Note note;
  final ScanQueue queue;
  final LocalModelService model;
  final ValueChanged<NoteVersion> onUse;
  final ValueChanged<NoteVersion> onDelete;

  ScanJob? get _job => queue.jobs
      .where((j) => j.isCompare && j.compareNote?.id == note.id)
      .firstOrNull;

  Future<void> _start(BuildContext context) async {
    final installed = model.installed;
    if (installed.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ModelsScreen(model: model)),
      );
      return;
    }
    final picked = await showDialog<List<ModelOption>>(
      context: context,
      builder: (_) => _PickModelsDialog(installed: installed, model: model),
    );
    if (picked == null || picked.isEmpty) return;
    queue.compare(note, picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final job = _job;
    final noPages = note.imagePaths.isEmpty;
    final results = note.versions.where((v) => v.modelId != 'earlier').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Run several on-device models on this note\'s pages and compare '
          'what each one reads, how long it takes and how much memory it '
          'uses. Runs in the background, one model at a time.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (job != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.state == JobState.waiting
                        ? 'Waiting to start…'
                        : 'Comparing ${job.models.length} models…',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: job.fraction),
                  const SizedBox(height: 4),
                  Text(job.status, style: text.bodySmall),
                ],
              ),
            ),
          )
        else
          Row(
            children: [
              FilledButton.icon(
                onPressed: noPages ? null : () => _start(context),
                icon: const Icon(Icons.compare_outlined),
                label: Text(
                  model.installed.isEmpty ? 'Get models' : 'Compare models…',
                ),
              ),
              const SizedBox(width: 8),
              if (noPages)
                Expanded(
                  child: Text(
                    'This note has no page photos.',
                    style: text.bodySmall,
                  ),
                ),
            ],
          ),
        if (results.length > 1) ...[
          const SizedBox(height: 16),
          Text('At a glance', style: text.titleMedium),
          const SizedBox(height: 6),
          _SummaryTable(versions: results),
        ],
        const SizedBox(height: 8),
        for (final v in note.versions)
          _VersionCard(
            version: v,
            onUse: v.failed ? null : () => onUse(v),
            onDelete: () => onDelete(v),
          ),
        if (note.versions.isEmpty && job == null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              'No comparisons yet.',
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// One row per model: total time, speed, peak RAM, words. Fastest first.
class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.versions});
  final List<NoteVersion> versions;

  @override
  Widget build(BuildContext context) {
    final rows = [...versions]
      ..sort((a, b) {
        if (a.failed != b.failed) return a.failed ? 1 : -1;
        return (a.totalMs ?? 1 << 30).compareTo(b.totalMs ?? 1 << 30);
      });
    final style = Theme.of(context).textTheme.bodySmall;
    final head = style?.copyWith(fontWeight: FontWeight.bold);
    Widget cell(String s, {TextStyle? st}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Text(s, style: st ?? style),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(2.2)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                cell('Model', st: head),
                cell('Time', st: head),
                cell('tok/s', st: head),
                cell('RAM', st: head),
                cell('Words', st: head),
              ],
            ),
            for (final v in rows)
              TableRow(
                children: [
                  cell(v.modelName),
                  cell(
                    v.failed
                        ? 'failed'
                        : v.totalMs == null
                        ? '–'
                        : formatMs(v.totalMs!),
                  ),
                  cell(v.tokensPerSec?.toStringAsFixed(1) ?? '–'),
                  cell(v.peakRamMb == null ? '–' : formatMb(v.peakRamMb!)),
                  cell(v.words?.toString() ?? '–'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _VersionCard extends StatefulWidget {
  const _VersionCard({
    required this.version,
    this.onUse,
    required this.onDelete,
  });
  final NoteVersion version;
  final VoidCallback? onUse;
  final VoidCallback onDelete;

  @override
  State<_VersionCard> createState() => _VersionCardState();
}

class _VersionCardState extends State<_VersionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.version;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final d = v.createdAt;
    final when =
        '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final stats = [
      if (v.totalMs != null) 'Total ${formatMs(v.totalMs!)}',
      if (v.modelLoadMs != null) 'load ${formatMs(v.modelLoadMs!)}',
      if (v.firstTokenMs != null) 'first word ${formatMs(v.firstTokenMs!)}',
      if (v.tokensPerSec != null) '${v.tokensPerSec!.toStringAsFixed(1)} tok/s',
      if (v.peakRamMb != null) 'RAM ${formatMb(v.peakRamMb!)}',
      if (v.backend != null) v.backend!,
      if (v.words != null) '${v.words} words',
      if (v.pageTimesMs.length > 1)
        'pages ${v.pageTimesMs.map(formatMs).join(' · ')}',
    ];

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(v.modelName, style: text.titleSmall)),
                Text(when, style: text.labelSmall),
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(stats.join(' · '), style: text.bodySmall),
            ],
            const SizedBox(height: 8),
            if (v.failed)
              Text(
                v.error!,
                style: text.bodyMedium?.copyWith(color: scheme.error),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _expanded ? double.infinity : 220,
                ),
                child: ClipRect(
                  child: MarkdownBody(data: v.markdown, selectable: true),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!v.failed)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? 'Show less' : 'Show all'),
                  ),
                if (widget.onUse != null)
                  TextButton(
                    onPressed: widget.onUse,
                    child: const Text('Use as note'),
                  ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PickModelsDialog extends StatefulWidget {
  const _PickModelsDialog({required this.installed, required this.model});
  final List<ModelOption> installed;
  final LocalModelService model;

  @override
  State<_PickModelsDialog> createState() => _PickModelsDialogState();
}

class _PickModelsDialogState extends State<_PickModelsDialog> {
  late final Set<String> _chosen = widget.installed.map((m) => m.id).toSet();

  @override
  Widget build(BuildContext context) {
    final missing = NoteModels.all.length - widget.installed.length;
    return AlertDialog(
      title: const Text('Compare models'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in widget.installed)
              CheckboxListTile(
                value: _chosen.contains(m.id),
                onChanged: (on) => setState(
                  () => on == true ? _chosen.add(m.id) : _chosen.remove(m.id),
                ),
                title: Text(m.name),
                subtitle: Text(m.kind),
                dense: true,
              ),
            if (missing > 0)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ModelsScreen(model: widget.model),
                    ),
                  );
                },
                icon: const Icon(Icons.download),
                label: Text('Get more models ($missing more available)'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.installed
                      .where((m) => _chosen.contains(m.id))
                      .toList(),
                ),
          child: Text('Run ${_chosen.length}'),
        ),
      ],
    );
  }
}
