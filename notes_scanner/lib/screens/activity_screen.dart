import 'package:flutter/material.dart';

import '../services/local_model_service.dart';
import '../services/memory_monitor.dart';
import '../services/scan_pipeline.dart';
import '../services/scan_queue.dart';

String formatMb(int mb) =>
    mb >= 1024 ? '${(mb / 1024).toStringAsFixed(2)} GB' : '$mb MB';

String formatMs(int ms) {
  if (ms < 1000) return '$ms ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} s';
  final s = ms ~/ 1000;
  return '${s ~/ 60} min ${(s % 60).toString().padLeft(2, '0')} s';
}

String stageLabel(ScanStage s) => switch (s) {
  ScanStage.ocr => 'Finding text (ML Kit)',
  ScanStage.loadingModel => 'Loading model',
  ScanStage.encoding => 'Encoding image + prompt',
  ScanStage.writing => 'Writing note',
  ScanStage.formatting => 'Formatting',
};

/// Live view of what the app is doing: memory, the running scan and the
/// on-device model.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({
    super.key,
    required this.queue,
    required this.model,
    required this.memory,
  });

  final ScanQueue queue;
  final LocalModelService model;
  final MemoryMonitor memory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: ListenableBuilder(
        // The memory monitor ticks every 1.5 s, which also keeps the
        // elapsed times current.
        listenable: Listenable.merge([queue, model, memory]),
        builder: (context, _) {
          final running = queue.jobs
              .where((j) => j.state == JobState.running)
              .firstOrNull;
          final waiting = queue.jobs
              .where((j) => j.state == JobState.waiting)
              .length;
          final failed = queue.jobs
              .where((j) => j.state == JobState.failed)
              .length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _MemoryCard(snapshot: memory.latest),
              const SizedBox(height: 12),
              if (running != null)
                _RunningCard(job: running)
              else
                _IdleCard(summary: queue.lastSummary),
              if (waiting > 0 || failed > 0) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.queue_outlined),
                    title: Text(
                      '$waiting waiting'
                      '${failed > 0 ? ' · $failed failed' : ''}',
                    ),
                    subtitle: const Text('Scans run one at a time.'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _ModelCard(model: model),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.snapshot});
  final MemorySnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final scheme = Theme.of(context).colorScheme;
    if (s == null) {
      return const _Section(
        icon: Icons.memory,
        title: 'Memory',
        children: [LinearProgressIndicator()],
      );
    }
    final total = s.deviceTotalMb, avail = s.deviceAvailableMb;
    final low = avail != null && avail < 600;
    return _Section(
      icon: Icons.memory,
      title: 'Memory',
      children: [
        _Stat(
          'This app',
          '${formatMb(s.appMb)}  (peak ${formatMb(s.appPeakMb)})',
        ),
        if (total != null && avail != null) ...[
          _Stat(
            'Phone',
            '${formatMb(s.deviceUsedMb!)} used of ${formatMb(total)}',
          ),
          _Stat('Free for apps', formatMb(avail)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                // Whole bar: phone RAM in use; darker part: this app's share.
                LinearProgressIndicator(
                  value: s.deviceUsedMb! / total,
                  minHeight: 10,
                  color: low ? scheme.error : scheme.secondary,
                ),
                LinearProgressIndicator(
                  value: (s.appMb / total).clamp(0.0, 1.0),
                  minHeight: 10,
                  color: scheme.primary,
                  backgroundColor: Colors.transparent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Dark part: this app · light part: everything else',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (low) ...[
          const SizedBox(height: 8),
          Text(
            'Memory is low. Android may stop the model; closing other '
            'apps helps.',
            style: TextStyle(color: scheme.error),
          ),
        ],
      ],
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.job});
  final ScanJob job;

  @override
  Widget build(BuildContext context) {
    final p = job.progress;
    final elapsed = job.startedAt == null
        ? null
        : DateTime.now().difference(job.startedAt!).inMilliseconds;
    final pages = job.pages.length;
    return _Section(
      icon: Icons.document_scanner_outlined,
      title: 'Scanning $pages page${pages == 1 ? '' : 's'}',
      children: [
        LinearProgressIndicator(value: job.fraction, minHeight: 6),
        const SizedBox(height: 4),
        Text(job.status, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (p != null) ...[
          _Stat('Stage', stageLabel(p.stage)),
          if (p.pages > 0) _Stat('Page', '${p.page} of ${p.pages}'),
        ],
        if (elapsed != null) _Stat('Elapsed', formatMs(elapsed)),
        if (p?.backend != null) _Stat('Runs on', p!.backend!),
        if (p?.modelLoadMs != null)
          _Stat('Model load', formatMs(p!.modelLoadMs!)),
        if (p?.firstTokenMs != null)
          _Stat('Image + prompt', formatMs(p!.firstTokenMs!)),
        if (p?.tokensPerSec != null)
          _Stat('Speed', '${p!.tokensPerSec!.toStringAsFixed(1)} tokens/s'),
        if (p != null && p.tokens > 0)
          _Stat('Written', '${p.words} words · ~${p.tokens} tokens'),
        if (p != null && p.pageTimesMs.isNotEmpty)
          _Stat(
            'Pages done',
            [
              for (var i = 0; i < p.pageTimesMs.length; i++)
                'p${i + 1} ${formatMs(p.pageTimesMs[i])}',
            ].join(' · '),
          ),
        _Stat('Where', 'Native worker threads; the screen stays responsive'),
        if (p != null && p.preview.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Live output', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              reverse: true, // keep the newest words in view
              child: Text(
                p.preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.summary});
  final ScanSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) {
      return const _Section(
        icon: Icons.document_scanner_outlined,
        title: 'No scan running',
        children: [Text('Start a scan and its progress shows here.')],
      );
    }
    final p = s.last;
    return _Section(
      icon: Icons.check_circle_outline,
      title: 'No scan running',
      children: [
        Text('Last scan', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        _Stat('Note', s.title),
        _Stat('Pages', '${s.pages}'),
        _Stat('Total time', formatMs(s.totalMs)),
        _Stat('Read by', s.engine),
        if (p?.backend != null) _Stat('Ran on', p!.backend!),
        if (p?.modelLoadMs != null)
          _Stat('Model load', formatMs(p!.modelLoadMs!)),
        if (p?.tokensPerSec != null)
          _Stat(
            'Speed (last page)',
            '${p!.tokensPerSec!.toStringAsFixed(1)} tokens/s',
          ),
        if (p != null && p.pageTimesMs.isNotEmpty)
          _Stat('Per page', p.pageTimesMs.map(formatMs).join(' · ')),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.model});
  final LocalModelService model;

  @override
  Widget build(BuildContext context) {
    final status = switch (model.state) {
      ModelState.checking => 'Checking…',
      ModelState.unsupported =>
        'Not available: ${model.unsupportedReason ?? ''}',
      ModelState.notInstalled => 'Not downloaded (quick scan only)',
      ModelState.downloading => 'Downloading ${model.progress}%',
      ModelState.ready => 'Ready',
      ModelState.error => 'Download failed',
    };
    return _Section(
      icon: Icons.auto_awesome_outlined,
      title: 'On-device model',
      children: [
        _Stat('Model', LocalModelService.displayName),
        _Stat('Status', status),
        _Stat(
          'File size',
          formatMb(LocalModelService.sizeBytes ~/ (1024 * 1024)),
        ),
        _Stat('Context', '4096 tokens · 1 image per page'),
        if (model.deviceRamMb != null)
          _Stat('Phone RAM', formatMb(model.deviceRamMb!)),
      ],
    );
  }
}
