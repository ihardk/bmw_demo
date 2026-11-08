import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../services/local_model_service.dart';
import '../services/note_store.dart';
import '../services/scan_pipeline.dart';
import 'note_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.model});
  final LocalModelService model;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = NoteStore();
  final _picker = ImagePicker();
  List<Note> _notes = [];
  bool _loading = true;
  bool _scanning = false;
  bool _bannerDismissed = true;
  final _status = ValueNotifier<String>('');
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _status.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final notes = await _store.loadNotes();
    final dismissed = await _store.bannerDismissed();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _bannerDismissed = dismissed;
      _loading = false;
    });
  }

  Future<void> _persist() => _store.saveNotes(_notes);

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
        builder: (_) => SettingsScreen(store: _store, model: widget.model),
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

    // Downscale big phone photos: plenty for handwriting, much faster upload.
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
        'Could not open ${source == 'camera' ? 'camera' : 'gallery'}: $e',
      );
      return;
    }
    if (picked.isEmpty) return;

    _status.value = 'Preparing photos…';
    setState(() => _scanning = true);
    try {
      final saved = await _keepImages(picked);
      final mode = await _store.loadMode();
      final result = await ScanPipeline(model: widget.model)
          .scan(saved, mode: mode, onStatus: (s) => _status.value = s);
      final note = Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: result.title,
        markdown: result.markdown,
        createdAt: DateTime.now(),
        imagePaths: saved.map((f) => f.path).toList(),
        engine: result.engine,
      );
      setState(() => _notes.insert(0, note));
      await _persist();
      if (result.notice != null) _showMessage(result.notice!);
      if (mounted) await _openNote(note);
    } on ScanFailure catch (e) {
      debugPrint('Scan failed: $e');
      _showMessage(e.message);
    } catch (e, st) {
      debugPrint('Scan failed: $e\n$st');
      final detail = e.toString().split('\n').first;
      _showMessage(
        'Could not read the pages. Please try again.\n'
        '(${detail.length > 120 ? '${detail.substring(0, 120)}…' : detail})',
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
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
      await _delete(note);
    } else {
      setState(() {});
      await _persist();
    }
  }

  Future<void> _delete(Note note) async {
    setState(() => _notes.removeWhere((n) => n.id == note.id));
    await _persist();
    for (final p in note.imagePaths) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final visible = q.isEmpty
        ? _notes
        : _notes
              .where(
                (n) =>
                    n.title.toLowerCase().contains(q) ||
                    n.markdown.toLowerCase().contains(q),
              )
              .toList();

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
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                ListenableBuilder(
                  listenable: widget.model,
                  builder: (context, _) => _ModelBanner(
                    model: widget.model,
                    dismissed: _bannerDismissed,
                    onOpen: _openSettings,
                    onDismiss: () {
                      setState(() => _bannerDismissed = true);
                      _store.dismissBanner();
                    },
                  ),
                ),
                if (_notes.isEmpty)
                  const Expanded(child: _EmptyState())
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SearchBar(
                      hintText: 'Search notes',
                      leading: const Icon(Icons.search),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _NoteCard(
                        note: visible[i],
                        onTap: () => _openNote(visible[i]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          if (_scanning) _ScanningOverlay(status: _status),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _startScan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan notes'),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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

class _ScanningOverlay extends StatelessWidget {
  const _ScanningOverlay({required this.status});
  final ValueListenable<String> status;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  ValueListenableBuilder(
                    valueListenable: status,
                    builder: (context, s, _) => Text(
                      s,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Everything stays on your phone.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
