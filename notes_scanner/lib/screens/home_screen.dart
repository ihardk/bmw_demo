import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../services/local_model_service.dart';
import '../services/note_store.dart';
import '../services/notes_repository.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_queue.dart';
import 'note_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.model,
    required this.notes,
    required this.queue,
    required this.store,
  });

  final LocalModelService model;
  final NotesRepository notes;
  final ScanQueue queue;
  final NoteStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  bool _bannerDismissed = true;
  bool _askedNotifications = false;
  String _query = '';
  StreamSubscription<ScanOutcome>? _outcomes;

  @override
  void initState() {
    super.initState();
    widget.store.bannerDismissed().then((d) {
      if (mounted) setState(() => _bannerDismissed = d);
    });
    _outcomes = widget.queue.outcomes.listen(_onOutcome);
  }

  @override
  void dispose() {
    _outcomes?.cancel();
    super.dispose();
  }

  void _onOutcome(ScanOutcome o) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (o.note != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            o.notice == null
                ? 'Note ready: ${o.note!.title}'
                : '${o.note!.title}: ${o.notice}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: o.notice == null ? 5 : 8),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openNote(o.note!),
          ),
        ),
      );
    } else if (o.error != null) {
      _showMessage(o.error!);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(store: widget.store, model: widget.model),
      ),
    );
  }

  Future<void> _startScan() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              subtitle: const Text('Snap one notebook page'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Pick one or more pages'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    // Downscale big phone photos: plenty for handwriting, much faster to read.
    const maxSide = 2000.0;
    const quality = 85;
    List<XFile> picked;
    try {
      if (source == 'camera') {
        final shot = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: maxSide,
          maxHeight: maxSide,
          imageQuality: quality,
        );
        picked = shot == null ? [] : [shot];
      } else {
        picked = await _picker.pickMultiImage(
          maxWidth: maxSide,
          maxHeight: maxSide,
          imageQuality: quality,
          limit: 10,
        );
      }
    } catch (e) {
      _showMessage(
        'Could not open ${source == 'camera' ? 'camera' : 'gallery'}.',
      );
      return;
    }
    if (picked.isEmpty) return;

    final saved = await _keepImages(picked);
    final mode = await widget.store.loadMode();
    if (!_askedNotifications) {
      // So the progress notification can show if the user leaves the app.
      _askedNotifications = true;
      await widget.queue.keeper.ensurePermission();
    }
    widget.queue.enqueue(saved, mode);
  }

  /// Copies picked photos into app storage so they survive cache clean-up.
  Future<List<File>> _keepImages(List<XFile> picked) async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/scans',
    );
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final out = <File>[];
    for (var i = 0; i < picked.length; i++) {
      final ext = picked[i].path.split('.').last;
      final dest = '${dir.path}/${stamp}_$i.$ext';
      await picked[i].saveTo(dest);
      out.add(File(dest));
    }
    return out;
  }

  Future<void> _openNote(Note note) async {
    final action = await Navigator.push<NoteAction>(
      context,
      MaterialPageRoute(builder: (_) => NoteScreen(note: note)),
    );
    if (action == NoteAction.deleted) {
      await widget.notes.delete(note);
    } else {
      await widget.notes.saveChanges();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes Scanner'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.notes,
          widget.queue,
          widget.model,
        ]),
        builder: (context, _) {
          if (!widget.notes.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final jobs = widget.queue.jobs;
          final all = widget.notes.notes;
          final q = _query.toLowerCase();
          final visible = q.isEmpty
              ? all
              : all
                    .where(
                      (n) =>
                          n.title.toLowerCase().contains(q) ||
                          n.markdown.toLowerCase().contains(q),
                    )
                    .toList();
          final banner = _ModelBanner(
            model: widget.model,
            dismissed: _bannerDismissed,
            onOpen: _openSettings,
            onDismiss: () {
              setState(() => _bannerDismissed = true);
              widget.store.dismissBanner();
            },
          );

          if (all.isEmpty && jobs.isEmpty) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: banner,
                ),
                const Expanded(child: _EmptyState()),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              banner,
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SearchBar(
                    hintText: 'Search notes',
                    leading: const Icon(Icons.search),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              for (final job in jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _JobCard(
                    job: job,
                    onRetry: () => widget.queue.retry(job),
                    onRemove: () => widget.queue.remove(job),
                  ),
                ),
              for (final note in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NoteCard(note: note, onTap: () => _openNote(note)),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startScan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan notes'),
      ),
    );
  }
}

/// A scan in progress, waiting, or failed, shown above the notes.
class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.onRetry,
    required this.onRemove,
  });

  final ScanJob job;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final failed = job.state == JobState.failed;
    final pages = job.pages.length;
    final thumb = job.pages.first;

    return Card(
      color: failed ? scheme.errorContainer : scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: failed ? onRetry : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 72,
                  child: thumb.existsSync()
                      ? Image.file(thumb, fit: BoxFit.cover, cacheWidth: 160)
                      : const Icon(Icons.image_outlined),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failed
                          ? 'Scan failed'
                          : job.state == JobState.waiting
                          ? 'Waiting to scan'
                          : 'Scanning $pages page${pages == 1 ? '' : 's'}…',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failed ? job.error ?? '' : job.status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                    if (!failed) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: job.state == JobState.running
                            ? job.fraction
                            : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ],
                ),
              ),
              if (job.state != JobState.running)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});
  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = note.markdown
        .split('\n')
        .skip(1)
        .map((l) => l.replaceAll(RegExp(r'^[#>*\-\s\[\]x]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .take(2)
        .join(' · ');
    final thumb = note.imagePaths.isNotEmpty
        ? File(note.imagePaths.first)
        : null;
    final d = note.createdAt;
    final date =
        '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final quick = note.engine == ScanPipeline.quickEngine;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 72,
                  child: thumb != null && thumb.existsSync()
                      ? Image.file(thumb, fit: BoxFit.cover, cacheWidth: 160)
                      : Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.notes),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$date · ${note.imagePaths.length} page${note.imagePaths.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        if (note.engine != null)
                          Tooltip(
                            message: note.engine!,
                            child: Icon(
                              quick ? Icons.bolt : Icons.auto_awesome,
                              size: 14,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelBanner extends StatelessWidget {
  const _ModelBanner({
    required this.model,
    required this.dismissed,
    required this.onOpen,
    required this.onDismiss,
  });

  final LocalModelService model;
  final bool dismissed;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final downloading = model.state == ModelState.downloading;
    if (!downloading && (dismissed || model.state != ModelState.notInstalled)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: scheme.secondaryContainer,
        child: ListTile(
          leading: Icon(downloading ? Icons.downloading : Icons.auto_awesome),
          title: Text(
            downloading
                ? 'Downloading on-device model… ${model.progress}%'
                : 'Better results for messy handwriting',
          ),
          subtitle: downloading
              ? LinearProgressIndicator(value: model.progress / 100)
              : const Text(
                  'Download the on-device AI model (2.6 GB, one time).',
                ),
          onTap: onOpen,
          trailing: downloading
              ? null
              : IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No notes yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Snap a photo of your handwritten notebook pages and they\'ll be '
              'turned into clean, organised notes.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
