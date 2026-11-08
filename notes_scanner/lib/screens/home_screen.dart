import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../services/local_model_service.dart';
import '../services/memory_monitor.dart';
import '../services/note_store.dart';
import '../services/notes_repository.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_queue.dart';
import 'activity_screen.dart';
import 'note_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.model,
    required this.notes,
    required this.queue,
    required this.store,
    required this.memory,
  });

  final LocalModelService model;
  final NotesRepository notes;
  final ScanQueue queue;
  final NoteStore store;
  final MemoryMonitor memory;

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
    if (o.compared != null && o.note != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Comparison ready: ${o.compared} model${o.compared == 1 ? '' : 's'} '
            'on “${o.note!.title}”',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openNote(o.note!, compare: true),
          ),
        ),
      );
    } else if (o.note != null) {
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

  void _openActivity() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityScreen(
          queue: widget.queue,
          model: widget.model,
          memory: widget.memory,
        ),
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
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan pages'),
              subtitle: const Text(
                'Snap as many pages as you like, one after another',
              ),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Pick one or more photos'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final List<String> paths;
    if (source == 'scan') {
      paths = await _scanPages();
    } else {
      try {
        paths = (await _picker.pickMultiImage(
          maxWidth: _maxSide,
          maxHeight: _maxSide,
          imageQuality: _quality,
          limit: 20,
        )).map((x) => x.path).toList();
      } catch (e) {
        _showMessage('Could not open the gallery.');
        return;
      }
    }
    if (paths.isEmpty) return;

    final saved = await _keepImages(paths);
    final mode = await widget.store.loadMode();
    if (!_askedNotifications) {
      // So the progress notification can show if the user leaves the app.
      _askedNotifications = true;
      await widget.queue.keeper.ensurePermission();
    }
    widget.queue.enqueue(saved, mode);
  }

  // Downscale big photos: plenty for handwriting, much faster to read.
  static const _maxSide = 2000.0;
  static const _quality = 85;

  /// Several pages in one go. Uses Google's document scanner (auto-capture,
  /// edge detection, crop, page by page) where Google Play services offers
  /// it, else a camera loop.
  Future<List<String>> _scanPages() async {
    if (Platform.isAndroid) {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: const {DocumentFormat.jpeg},
          mode: ScannerMode.filter,
          pageLimit: 20,
          isGalleryImport: true,
        ),
      );
      try {
        final result = await scanner.scanDocument();
        return result.images ?? const [];
      } on PlatformException catch (e) {
        if ((e.message ?? '').toLowerCase().contains('cancel')) return const [];
        debugPrint('Document scanner unavailable: $e');
      } catch (e) {
        debugPrint('Document scanner unavailable: $e');
      } finally {
        scanner.close();
      }
    }
    return _cameraLoop();
  }

  /// Fallback: take a photo, then "Next page" or "Done", until done.
  Future<List<String>> _cameraLoop() async {
    final paths = <String>[];
    while (mounted) {
      XFile? shot;
      try {
        shot = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: _maxSide,
          maxHeight: _maxSide,
          imageQuality: _quality,
        );
      } catch (e) {
        _showMessage('Could not open the camera.');
        break;
      }
      if (shot != null) paths.add(shot.path);
      if (paths.isEmpty || !mounted) break;
      final more = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            '${paths.length} page${paths.length == 1 ? '' : 's'} taken',
          ),
          content: const Text('Take another page, or scan what you have?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Scan ${paths.length} page${paths.length == 1 ? '' : 's'}',
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Next page'),
            ),
          ],
        ),
      );
      if (more != true) break;
    }
    return paths;
  }

  /// Copies the photos into app storage so they survive cache clean-up.
  Future<List<File>> _keepImages(List<String> paths) async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/scans',
    );
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final out = <File>[];
    for (var i = 0; i < paths.length; i++) {
      final ext = paths[i].contains('.') ? paths[i].split('.').last : 'jpg';
      out.add(await File(paths[i]).copy('${dir.path}/${stamp}_$i.$ext'));
    }
    return out;
  }

  Future<void> _openNote(Note note, {bool compare = false}) async {
    final action = await Navigator.push<NoteAction>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteScreen(
          note: note,
          notes: widget.notes,
          queue: widget.queue,
          model: widget.model,
          openCompare: compare,
        ),
      ),
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
          ListenableBuilder(
            listenable: widget.queue,
            builder: (context, _) => IconButton(
              tooltip: 'Activity',
              isSelected: widget.queue.busy,
              icon: const Icon(Icons.monitor_heart_outlined),
              selectedIcon: const Icon(Icons.monitor_heart),
              onPressed: _openActivity,
            ),
          ),
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
                    memory: widget.memory,
                    onOpen: _openActivity,
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
    required this.memory,
    required this.onOpen,
    required this.onRetry,
    required this.onRemove,
  });

  final ScanJob job;
  final MemoryMonitor memory;
  final VoidCallback onOpen;
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
        onTap: failed ? onRetry : onOpen,
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
                      job.isCompare
                          ? (failed
                                ? 'Comparison failed'
                                : job.state == JobState.waiting
                                ? 'Waiting to compare ${job.models.length} models'
                                : 'Comparing ${job.models.length} models on '
                                      '“${job.compareNote!.title}”')
                          : failed
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
                      if (job.state == JobState.running) ...[
                        const SizedBox(height: 6),
                        _LiveLine(job: job, memory: memory),
                      ],
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

/// "App RAM 1.9 GB · 8.4 tok/s · 0:42" under a running scan.
class _LiveLine extends StatelessWidget {
  const _LiveLine({required this.job, required this.memory});
  final ScanJob job;
  final MemoryMonitor memory;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: memory,
      builder: (context, _) {
        final ram = memory.latest?.appMb;
        final speed = job.progress?.tokensPerSec;
        final elapsed = job.startedAt == null
            ? null
            : DateTime.now().difference(job.startedAt!).inMilliseconds;
        return Text(
          [
            if (ram != null) 'App RAM ${formatMb(ram)}',
            if (speed != null) '${speed.toStringAsFixed(1)} tok/s',
            if (elapsed != null) formatMs(elapsed),
            'tap for details',
          ].join(' · '),
          style: Theme.of(context).textTheme.labelSmall,
        );
      },
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
