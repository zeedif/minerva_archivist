import 'package:flutter/material.dart';
import 'package:minerva_core/minerva_core.dart';

import 'run_controller.dart';

void main(List<String> args) {
  final controller = RunController(args.firstOrNull ?? '.minerva-cache')
    ..load();
  runApp(MinervaApp(controller: controller));
}

class MinervaApp extends StatelessWidget {
  const MinervaApp({super.key, required this.controller});

  final RunController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MiNERVA Archivist',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            SizedBox(width: 280, child: _ProfileList(controller)),
            const VerticalDivider(width: 1),
            Expanded(child: _RunView(controller)),
          ],
        ),
      ),
    ),
  );
}

class _ProfileList extends StatelessWidget {
  const _ProfileList(this.controller);

  final RunController controller;

  @override
  Widget build(BuildContext context) {
    final names = controller.profiles?.names.toList() ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextFormField(
            initialValue: controller.cacheDir,
            decoration: InputDecoration(
              labelText: 'Cache folder',
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Reload profiles',
                icon: const Icon(Icons.refresh),
                onPressed: controller.running ? null : controller.load,
              ),
            ),
            onChanged: (value) => controller.cacheDir = value,
            onFieldSubmitted: (_) => controller.load(),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: names.length,
            itemBuilder: (context, index) => ListTile(
              dense: true,
              title: Text(names[index]),
              selected: names[index] == controller.selected,
              onTap: controller.running
                  ? null
                  : () => controller.select(names[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView(this.controller);

  final RunController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.options;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.loadError case final error?)
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          if (options != null) ...[
            Text(controller.selected!, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(options.root ?? 'No ROM root: selection only'),
            Text(
              [
                options.dats.join(' + '),
                'lang ${options.languages.join(',')}',
                'priority ${options.priority.map((a) => a.name).join(',')}'
                    '${options.langCount == null ? "" : " (${options.langCount!.name})"}',
                options.layout.cli,
                if (options.wishlist != null) 'wishlist',
                if (options.skip.isNotEmpty)
                  'skips ${options.skip.map((s) => s.name).join(',')}',
              ].join('  ·  '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                  onPressed: controller.running
                      ? null
                      : () => controller.start(apply: false),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Apply'),
                  onPressed: controller.running
                      ? null
                      : () => controller.start(apply: true),
                ),
                if (controller.running) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    onPressed: controller.stop,
                  ),
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                if (controller.syncSummary case final summary?) Text(summary),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final platform in controller.platforms)
                    _PlatformCard(platform, applied: controller.applied),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard(this.platform, {required this.applied});

  final PlatformProgress platform;
  final bool applied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dry = applied ? '' : ' (preview)';
    final lines = [
      if (platform.selection case final selection?) ...[
        'Selected ${selection.stats.selected} of ${selection.stats.total}'
            '${selection.stats.reasons.isEmpty ? "" : "  (${selection.stats.reasons.join(', ')})"}',
        for (final entry in selection.unmatchedWishlist)
          'Wishlist entry matches nothing: $entry',
      ],
      if (platform.audit case final audit?)
        '${audit.present.length}/${audit.results.length} on disk, '
            '${audit.missing.length} missing, '
            '${audit.unknownFiles.length} unknown',
      if (platform.download case final download?) ...[
        '${download.plan.selected.length} to download, '
            '${_size(download.plan.totalBytes)}'
            '${download.seeders == null ? "" : ", ${download.seeders} seeders"}$dry',
        for (final name in download.plan.unmatched) 'Not distributed: $name',
        for (final name in download.held) 'Held by a curated folder: $name',
      ],
      if (platform.fetched case final fetched?) '$fetched file(s) downloaded',
      if (platform.organized case final actions?)
        'Organize: ${actions.summary}$dry',
      if (platform.playlists case final count?) '$count playlist(s)$dry',
      if (platform.pruned case final pruned?)
        '${pruned.moved.length} moved to $trashFolderName$dry',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(platform.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final line in lines) Text(line),
            for (final failure in platform.failures)
              Text(failure, style: TextStyle(color: theme.colorScheme.error)),
            if (platform.transfer case final transfer?
                when platform.fetched == null)
              _TransferTable(transfer),
          ],
        ),
      ),
    );
  }
}

/// Every requested file with its own progress, largest remaining first.
class _TransferTable extends StatelessWidget {
  const _TransferTable(this.snapshot);

  final TransferSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final files = [...snapshot.files]
      ..sort((a, b) => _rank(a).compareTo(_rank(b)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          '${snapshot.files.where((f) => f.isComplete).length}/'
          '${snapshot.files.length} files  ·  '
          '${_size(snapshot.done)} of ${_size(snapshot.total)}  ·  '
          '${_size(snapshot.bytesPerSecond)}/s  ·  '
          '${snapshot.seeds} seeds, ${snapshot.peers} peers',
          style: style,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: files.length,
            itemExtent: 28,
            itemBuilder: (context, index) {
              final file = files[index];
              return Row(
                spacing: 12,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      file.name,
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      _size(file.total),
                      style: style,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: LinearProgressIndicator(value: file.fraction),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(file.fraction * 100).toStringAsFixed(1)}%',
                      style: style,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Active transfers first, then waiting, then finished.
  static int _rank(FileTransfer file) => switch (file) {
    FileTransfer(isComplete: true) => 2,
    FileTransfer(done: 0) => 1,
    _ => 0,
  };
}

String _size(int bytes) => switch (bytes) {
  >= 1 << 30 => '${(bytes / (1 << 30)).toStringAsFixed(2)} GB',
  >= 1 << 20 => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB',
  _ => '${(bytes / 1024).toStringAsFixed(0)} KB',
};
