import 'package:flutter/material.dart';

import '../services/local_model_service.dart';
import '../services/note_store.dart';
import '../services/scan_pipeline.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, required this.model});
  final NoteStore store;
  final LocalModelService model;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ReadingMode _mode = ReadingMode.best;

  @override
  void initState() {
    super.initState();
    widget.store.loadMode().then((m) {
      if (mounted) setState(() => _mode = m);
    });
  }

  Future<void> _setMode(ReadingMode? m) async {
    if (m == null) return;
    setState(() => _mode = m);
    await widget.store.saveMode(m);
  }

  Future<void> _confirmDownload() async {
    final model = widget.model;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download on-device model?'),
        content: Text(
          '${LocalModelService.displayName} is about '
          '${_gb(LocalModelService.sizeBytes)}. Use Wi-Fi if you can. '
          'You only download it once, and after that everything works offline.'
          '${model.lowRam ? '\n\nThis phone has limited memory, so reading may be slow or fail. The quick scan will be used if it does.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (ok == true) model.download();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete on-device model?'),
        content: Text(
          'Frees ${_gb(LocalModelService.sizeBytes)}. Scans will use the quick '
          'reader until you download it again. Your notes are kept.',
        ),
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
    if (ok == true) await widget.model.delete();
  }

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final model = widget.model;
          final canUseModel = model.state != ModelState.unsupported;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('On-device AI model', style: text.titleMedium),
              const SizedBox(height: 8),
              _ModelCard(
                model: model,
                onDownload: _confirmDownload,
                onDelete: _confirmDelete,
              ),
              const SizedBox(height: 24),
              Text('Reading mode', style: text.titleMedium),
              RadioGroup<ReadingMode>(
                groupValue: _mode,
                onChanged: _setMode,
                child: Column(
                  children: [
                    RadioListTile<ReadingMode>(
                      value: ReadingMode.best,
                      enabled: canUseModel,
                      title: const Text('Best quality'),
                      subtitle: const Text(
                        'Uses the on-device AI model when it is downloaded. '
                        'Best for messy handwriting. About 10–60 s per page.',
                      ),
                    ),
                    const RadioListTile<ReadingMode>(
                      value: ReadingMode.quick,
                      title: Text('Quick scan'),
                      subtitle: Text(
                        'ML Kit text recognition only. Instant and works on '
                        'every phone, but struggles with rough handwriting.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Everything runs on this phone. Your photos and notes '
                      'never leave the device. The only network use is the '
                      'one-time model download.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.onDownload,
    required this.onDelete,
  });

  final LocalModelService model;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ram = model.deviceRamMb;

    final (IconData icon, String status, Color color) = switch (model.state) {
      ModelState.checking => (
        Icons.hourglass_empty,
        'Checking…',
        scheme.outline,
      ),
      ModelState.unsupported => (
        Icons.block,
        'Not available on this phone',
        scheme.error,
      ),
      ModelState.notInstalled => (
        Icons.cloud_download_outlined,
        'Not downloaded',
        scheme.outline,
      ),
      ModelState.downloading => (
        Icons.downloading,
        'Downloading ${model.progress}%',
        scheme.primary,
      ),
      ModelState.ready => (
        Icons.check_circle,
        'Ready, works offline',
        Colors.green,
      ),
      ModelState.error => (
        Icons.error_outline,
        'Download failed',
        scheme.error,
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocalModelService.displayName,
                        style: text.titleSmall,
                      ),
                      Text(
                        status,
                        style: text.bodyMedium?.copyWith(color: color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (model.state == ModelState.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: model.progress / 100),
            ],
            const SizedBox(height: 12),
            Text(
              model.state == ModelState.unsupported
                  ? model.unsupportedReason ?? ''
                  : 'Reads messy handwriting and organises it into headings, '
                        'lists and to-dos. '
                        '${(LocalModelService.sizeBytes / (1 << 30)).toStringAsFixed(1)} GB download.',
              style: text.bodySmall,
            ),
            if (ram != null && model.state != ModelState.unsupported) ...[
              const SizedBox(height: 4),
              Text(
                'This phone: ${(ram / 1024).toStringAsFixed(1)} GB RAM'
                '${model.lowRam ? ' (may be slow)' : ' (good fit)'}',
                style: text.bodySmall,
              ),
            ],
            if (model.error != null && model.state == ModelState.error) ...[
              const SizedBox(height: 4),
              Text(
                model.error!,
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: switch (model.state) {
                ModelState.notInstalled ||
                ModelState.error => FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download),
                  label: Text(
                    model.state == ModelState.error ? 'Try again' : 'Download',
                  ),
                ),
                ModelState.downloading => OutlinedButton(
                  onPressed: model.cancelDownload,
                  child: const Text('Cancel'),
                ),
                ModelState.ready => TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete model'),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
