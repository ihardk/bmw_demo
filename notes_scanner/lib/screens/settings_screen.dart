import 'package:flutter/material.dart';

import '../models/model_option.dart';
import '../services/local_model_service.dart';
import '../services/note_store.dart';
import '../services/scan_pipeline.dart';
import 'models_screen.dart';

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

  void _openModels() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ModelsScreen(model: widget.model)),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final model = widget.model;
          final unsupported = model.state == ModelState.unsupported;
          final installed = model.installed.length;
          final downloading = NoteModels.all
              .where((m) => model.stateOf(m) == ModelState.downloading)
              .length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('On-device models', style: text.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Models'),
                  subtitle: Text(
                    unsupported
                        ? model.unsupportedReason ??
                              'Not available on this phone'
                        : 'Scans use ${model.selected.name}'
                              '${model.isReady ? '' : ' (not downloaded)'} · '
                              '$installed of ${NoteModels.all.length} downloaded'
                              '${downloading > 0 ? ' · $downloading downloading' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: unsupported ? null : _openModels,
                ),
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
                      enabled: !unsupported,
                      title: const Text('Best quality'),
                      subtitle: Text(
                        'Uses ${model.selected.name} when it is downloaded. '
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
                      'never leave the device. The only network use is '
                      'downloading models.',
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
