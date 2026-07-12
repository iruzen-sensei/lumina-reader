// Copyright 2024 Lumina Reader Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The downloads queue screen.
///
/// Organises [DownloadTask]s across five tabs — All / Downloading / Completed
/// / Queued / Failed — with per-task pause, resume, cancel and retry actions,
/// a "clear completed" batch action, and a persistent Wi-Fi-only indicator
/// that surfaces the current download policy to the user.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(downloadsTabProvider);
    final tasks = ref.watch(downloadsProvider);

    final all = tasks;
    final downloading = tasks
        .where((t) =>
            t.state == DownloadState.downloading ||
            t.state == DownloadState.paused)
        .toList();
    final queued = tasks.where((t) => t.state == DownloadState.queued).toList();
    final completed =
        tasks.where((t) => t.state == DownloadState.completed).toList();
    final failed = tasks.where((t) => t.state == DownloadState.failed).toList();

    final counts = {
      DownloadsTab.all: all.length,
      DownloadsTab.downloading: downloading.length,
      DownloadsTab.completed: completed.length,
      DownloadsTab.queued: queued.length,
      DownloadsTab.failed: failed.length,
    };

    final visible = switch (tab) {
      DownloadsTab.all => all,
      DownloadsTab.downloading => downloading,
      DownloadsTab.completed => completed,
      DownloadsTab.queued => queued,
      DownloadsTab.failed => failed,
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _DownloadsHeader(counts: counts),
            _WifiOnlyIndicator(),
            _DownloadsTabs(counts: counts),
            Expanded(
              child: visible.isEmpty
                  ? emptyState(
                      context: context,
                      icon: Icons.download_done_outlined,
                      title: _emptyTitle(tab),
                      subtitle: _emptySubtitle(tab),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _DownloadCard(task: visible[i]),
                    ),
            ),
            if (downloading.any((t) => t.state == DownloadState.downloading) ||
                queued.isNotEmpty)
              _BatchBar(),
          ],
        ),
      ),
    );
  }

  String _emptyTitle(DownloadsTab tab) {
    switch (tab) {
      case DownloadsTab.all:
        return 'No downloads yet';
      case DownloadsTab.downloading:
        return 'No active downloads';
      case DownloadsTab.completed:
        return 'Nothing downloaded yet';
      case DownloadsTab.queued:
        return 'Queue is empty';
      case DownloadsTab.failed:
        return 'No failed downloads';
    }
  }

  String _emptySubtitle(DownloadsTab tab) {
    switch (tab) {
      case DownloadsTab.all:
        return 'Queue chapters or episodes for offline reading from any detail screen.';
      case DownloadsTab.downloading:
        return 'New downloads will appear here with live progress.';
      case DownloadsTab.completed:
        return 'Finished downloads are listed here for offline reading.';
      case DownloadsTab.queued:
        return 'Queued chapters start downloading as slots free up.';
      case DownloadsTab.failed:
        return 'Failed tasks will show up here so you can retry them.';
    }
  }
}

class _DownloadsHeader extends ConsumerWidget {
  const _DownloadsHeader({required this.counts});
  final Map<DownloadsTab, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadsProvider);
    final active =
        tasks.where((t) => t.state == DownloadState.downloading).toList();
    final overallProgress = active.isEmpty
        ? 0.0
        : active.map((t) => t.progress).reduce((a, b) => a + b) /
            active.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Text(
            'Downloads',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 12),
          if (active.isNotEmpty)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: overallProgress,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(overallProgress * 100).round()}%'),
                ],
              ),
            )
          else
            const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              final notifier = ref.read(downloadsProvider.notifier);
              switch (value) {
                case 'pause_all':
                  notifier.pauseAll();
                  showSnack(ref, context, 'Paused all downloads');
                  break;
                case 'resume_all':
                  notifier.resumeAll();
                  showSnack(ref, context, 'Resumed all downloads');
                  break;
                case 'clear_completed':
                  notifier.clearCompleted();
                  showSnack(ref, context, 'Cleared completed downloads');
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pause_all',
                child: ListTile(
                  leading: Icon(Icons.pause_circle_outline),
                  title: Text('Pause all'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'resume_all',
                child: ListTile(
                  leading: Icon(Icons.play_circle_outline),
                  title: Text('Resume all'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'clear_completed',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: Text('Clear completed'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Persistent banner that reflects the Wi-Fi-only setting and lets the user
/// flip it directly from the downloads screen.
class _WifiOnlyIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wifiOnly = ref.watch(wifiOnlyDownloadsProvider);
    return Material(
      color: (wifiOnly ? LuminaTheme.readingColor : LuminaTheme.finishedColor)
          .withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              wifiOnly ? Icons.wifi : Icons.signal_cellular_alt,
              size: 18,
              color: wifiOnly
                  ? LuminaTheme.readingColor
                  : LuminaTheme.finishedColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                wifiOnly
                    ? 'Wi-Fi only — downloads pause on metered networks.'
                    : 'Mobile data allowed — downloads will use any connection.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: wifiOnly
                      ? LuminaTheme.readingColor
                      : LuminaTheme.finishedColor,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref
                  .read(wifiOnlyDownloadsProvider.notifier)
                  .state = !wifiOnly,
              child: Text(wifiOnly ? 'Allow mobile' : 'Wi-Fi only'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadsTabs extends ConsumerWidget {
  const _DownloadsTabs({required this.counts});
  final Map<DownloadsTab, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(downloadsTabProvider);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final t in DownloadsTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: StatusChip(
                label: '${t.label} (${counts[t] ?? 0})',
                selected: tab == t,
                color: _tabColor(t),
                onTap: () =>
                    ref.read(downloadsTabProvider.notifier).state = t,
              ),
            ),
        ],
      ),
    );
  }

  Color _tabColor(DownloadsTab t) {
    switch (t) {
      case DownloadsTab.all:
        return LuminaTheme.seed;
      case DownloadsTab.downloading:
        return LuminaTheme.readingColor;
      case DownloadsTab.queued:
        return LuminaTheme.unreadColor;
      case DownloadsTab.completed:
        return LuminaTheme.finishedColor;
      case DownloadsTab.failed:
        return LuminaTheme.newColor;
    }
  }
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    task.isAnime ? Icons.movie : Icons.menu_book,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _StateBadge(state: task.state),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value:
                    task.state == DownloadState.completed ? 1 : task.progress,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor:
                    AlwaysStoppedAnimation(_progressColor(task.state)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _meta(task),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                ..._actions(context, ref),
              ],
            ),
            if (task.state == DownloadState.failed &&
                task.errorMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                task.errorMessage!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _meta(DownloadTask t) {
    switch (t.state) {
      case DownloadState.downloading:
        return '${(t.progress * 100).round()}% • ${formatSpeed(t.speedBytesPerSec)} • '
            '${formatBytes(t.downloadedBytes)} / ${formatBytes(t.totalBytes)}';
      case DownloadState.completed:
        return 'Downloaded ${formatBytes(t.totalBytes)}';
      case DownloadState.failed:
        return 'Failed at ${(t.progress * 100).round()}%';
      case DownloadState.paused:
        return 'Paused at ${(t.progress * 100).round()}%';
      case DownloadState.queued:
        return 'Waiting for a free slot…';
      case DownloadState.cancelled:
        return 'Cancelled';
    }
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(downloadsProvider.notifier);
    switch (task.state) {
      case DownloadState.downloading:
        return [
          IconButton(
            tooltip: 'Pause',
            icon: const Icon(Icons.pause),
            onPressed: () => notifier.pause(task.id),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.cancel_outlined),
            onPressed: () => notifier.cancel(task.id),
          ),
        ];
      case DownloadState.paused:
        return [
          IconButton(
            tooltip: 'Resume',
            icon: const Icon(Icons.play_arrow),
            onPressed: () => notifier.resume(task.id),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.cancel_outlined),
            onPressed: () => notifier.cancel(task.id),
          ),
        ];
      case DownloadState.queued:
        return [
          IconButton(
            tooltip: 'Pause',
            icon: const Icon(Icons.pause),
            onPressed: () => notifier.pause(task.id),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => notifier.remove(task.id),
          ),
        ];
      case DownloadState.failed:
        return [
          IconButton(
            tooltip: 'Retry',
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.retry(task.id),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => notifier.remove(task.id),
          ),
        ];
      case DownloadState.completed:
        return [
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => notifier.remove(task.id),
          ),
        ];
      case DownloadState.cancelled:
        return [
          IconButton(
            tooltip: 'Retry',
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.retry(task.id),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => notifier.remove(task.id),
          ),
        ];
    }
  }

  Color _progressColor(DownloadState s) {
    switch (s) {
      case DownloadState.downloading:
        return LuminaTheme.readingColor;
      case DownloadState.completed:
        return LuminaTheme.finishedColor;
      case DownloadState.failed:
        return LuminaTheme.newColor;
      case DownloadState.paused:
        return LuminaTheme.unreadColor;
      default:
        return LuminaTheme.seed;
    }
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});
  final DownloadState state;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (state) {
      DownloadState.downloading =>
        (LuminaTheme.readingColor, Icons.downloading),
      DownloadState.paused => (LuminaTheme.unreadColor, Icons.pause_circle),
      DownloadState.queued =>
        (LuminaTheme.unreadColor, Icons.hourglass_top),
      DownloadState.completed =>
        (LuminaTheme.finishedColor, Icons.check_circle),
      DownloadState.failed => (LuminaTheme.newColor, Icons.error),
      DownloadState.cancelled => (Colors.grey, Icons.cancel),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            state.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(downloadsProvider.notifier).pauseAll();
                  showSnack(ref, context, 'Paused all');
                },
                icon: const Icon(Icons.pause),
                label: const Text('Pause all'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () {
                  ref.read(downloadsProvider.notifier).resumeAll();
                  showSnack(ref, context, 'Resumed all');
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume all'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
