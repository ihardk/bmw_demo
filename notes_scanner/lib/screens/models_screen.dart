import 'package:flutter/material.dart';

import '../models/model_option.dart';
import '../services/local_model_service.dart';

String formatGb(int bytes) => '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';

/// Every on-device model: download, delete, and pick the one scans use.
class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key, required this.model});
  final LocalModelService model;

  Future<void> _confirmDownload(BuildContext context, ModelOption m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Download ${m.name}?'),
        content: Text(
          '${formatGb(m.sizeBytes)} download. Use Wi-Fi if you can. '
          'After that it runs offline.'
          '${m.heavy != null ? '\n\n${m.heavy}' : ''}'
          '${!model.fits(m) ? '\n\nThis phone may not have enough memory for it: '
                    'it could be slow or fail to run.' : ''}',
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
    if (ok == true) model.download(m);
  }

  Future<void> _confirmDelete(BuildContext context, ModelOption m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${m.name}?'),
        content: Text(
          'Frees ${formatGb(m.sizeBytes)}. Your notes and '
          'comparisons are kept.',
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
    if (ok != true) return;
    if (model.selected.id == m.id) {
      await model.select(NoteModels.byId(NoteModels.defaultId));
    }
    await model.delete(m);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Models')),
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          if (model.state == ModelState.unsupported) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                model.unsupportedReason ??
                    'On-device models are not available on this phone.',
              ),
            );
          }
          final ram = model.deviceRamMb;
          final groups = {
            NoteModels.general: NoteModels.all.where((m) => !m.isSpecialist),
            NoteModels.ocr: NoteModels.all.where((m) => m.isSpecialist),
          };
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Download a few models, then open a note and use '
                'Compare to see how each one reads the same pages. Scans '
                'use the model marked "Used for scans".'
                '${ram != null ? ' This phone has ${(ram / 1024).toStringAsFixed(1)} GB of RAM.' : ''}',
                style: text.bodyMedium,
              ),
              for (final group in groups.entries) ...[
                const SizedBox(height: 20),
                Text(group.key, style: text.titleMedium),
                Text(
                  group.key == NoteModels.general
                      ? 'Follow instructions: they organise the note into '
                            'headings, lists and to-dos, and get ML Kit\'s text '
                            'as a hint.'
                      : 'Trained only to transcribe documents: given the '
                            'page alone, with their own fixed prompt.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final m in group.value)
                  _ModelTile(
                    option: m,
                    model: model,
                    onDownload: () => _confirmDownload(context, m),
                    onDelete: () => _confirmDelete(context, m),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'All models run on this phone; nothing is uploaded. Each '
                'file is pinned to a fixed version on Hugging Face.',
                style: text.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.option,
    required this.model,
    required this.onDownload,
    required this.onDelete,
  });

  final ModelOption option;
  final LocalModelService model;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final state = model.stateOf(option);
    final used = model.selected.id == option.id;
    final ready = state == ModelState.ready;

    return Card(
      shape: used
          ? RoundedRectangleBorder(
              side: BorderSide(color: scheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.name, style: text.titleSmall),
                      Text(
                        '${option.maker} · ${formatGb(option.sizeBytes)}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (used)
                  Chip(
                    label: const Text('Used for scans'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.primaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(option.about, style: text.bodySmall),
            if (!model.fits(option))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'May not fit this phone\'s memory.',
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            if (state == ModelState.downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: model.progressOf(option) / 100),
              const SizedBox(height: 2),
              Text(
                'Downloading ${model.progressOf(option)}%',
                style: text.bodySmall,
              ),
            ],
            if (state == ModelState.error && model.errorOf(option) != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  model.errorOf(option)!,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (ready && !used)
                  TextButton(
                    onPressed: () => model.select(option),
                    child: const Text('Use for scans'),
                  ),
                if (ready)
                  IconButton(
                    tooltip: 'Delete ${option.name}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                if (state == ModelState.downloading)
                  TextButton(
                    onPressed: () => model.cancelDownload(option),
                    child: const Text('Cancel'),
                  ),
                if (state == ModelState.notInstalled ||
                    state == ModelState.error)
                  TextButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download),
                    label: Text(
                      state == ModelState.error ? 'Try again' : 'Download',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
