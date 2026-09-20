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

import '../../core/ui/lumina_ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The downloads queue screen.
///
/// Organises [DownloadTask]s across five tabs — All / Downloading / Completed
/// / Queued / Failed — with per-task pause, resume, cancel and retry actions,
/// a "clear completed" batch action, and a persistent Wi-Fi-only indicator
/// that surfaces the current download policy to the user. Inside the active
/// tab the tasks are grouped by state under HeroUI section headers.
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
                  : _DownloadsList(tasks: visible),
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
    final h = HeroScope.of(context);
    final tasks = ref.watch(downloadsProvider);
    final active =
        tasks.where((t) => t.state == DownloadState.downloading).toList();
    final overallProgress = active.isEmpty
        ? 0.0
        : active.map((t) => t.progress).reduce((a, b) => a + b) / active.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Downloads',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HeroTokens.display.copyWith(color: h.foreground),
            ),
          ),
          const SizedBox(width: 12),
          if (active.isNotEmpty)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: HeroProgress(
                      value: overallProgress,
                      height: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(overallProgress * 100).round()}%',
                    style: HeroTokens.caption.copyWith(
                      color: h.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
    final h = HeroScope.of(context);
    final wifiOnly = ref.watch(wifiOnlyDownloadsProvider);
    final color = wifiOnly ? h.accent : h.success;
    return Material(
      color: wifiOnly ? h.accentSoft : h.successSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              wifiOnly ? Icons.wifi_rounded : Icons.signal_cellular_alt_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                wifiOnly
                    ? 'Wi-Fi only — downloads pause on metered networks.'
                    : 'Mobile data allowed — downloads will use any connection.',
                style: HeroTokens.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            HeroButton(
              label: wifiOnly ? 'Allow mobile' : 'Wi-Fi only',
              size: HeroButtonSize.sm,
              variant: HeroButtonVariant.soft,
              color: wifiOnly ? HeroColorRole.accent : HeroColorRole.success,
              onPressed: () => ref
                  .read(wifiOnlyDownloadsProvider.notifier)
                  .state = !wifiOnly,
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
                color: _tabColor(context, t),
                onTap: () => ref.read(downloadsTabProvider.notifier).state = t,
              ),
            ),
        ],
      ),
    );
  }

  Color _tabColor(BuildContext context, DownloadsTab t) {
    final h = HeroScope.of(context);
    switch (t) {
      case DownloadsTab.all:
        return h.foreground;
      case DownloadsTab.downloading:
        return h.accent;
      case DownloadsTab.queued:
        return h.foreground;
      case DownloadsTab.completed:
        return h.success;
      case DownloadsTab.failed:
        return h.danger;
    }
  }
}

/// The scrollable body: groups the visible tasks by state under HeroUI
/// section headers with a count chip per group.
class _DownloadsList extends StatelessWidget {
  const _DownloadsList({required this.tasks});
  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    final active = tasks
        .where((t) =>
            t.state == DownloadState.downloading ||
            t.state == DownloadState.paused)
        .toList();
    final queued = tasks.where((t) => t.state == DownloadState.queued).toList();
    final completed =
        tasks.where((t) => t.state == DownloadState.completed).toList();
    final failed = tasks.where((t) => t.state == DownloadState.failed).toList();
    final cancelled =
        tasks.where((t) => t.state == DownloadState.cancelled).toList();

    final groups = <(String, HeroColorRole, List<DownloadTask>)>[
      ('Downloading', HeroColorRole.accent, active),
      ('Queued', HeroColorRole.neutral, queued),
      ('Completed', HeroColorRole.success, completed),
      ('Failed', HeroColorRole.danger, failed),
      ('Cancelled', HeroColorRole.neutral, cancelled),
    ];

    return ListView(
      // Bottom nav bar / batch bar clearance.
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final (label, role, items) in groups)
          if (items.isNotEmpty) ...[
            HeroSectionHeader(
              label,
              trailing: HeroChip(
                label: '${items.length}',
                small: true,
                color: role,
              ),
            ),
            for (final task in items)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _DownloadCard(task: task),
              ),
          ],
      ],
    );
  }
}

class _DownloadCard extends ConsumerWidget {
  const _DownloadCard({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final (tileBg, tileFg, barColor) = _stateColors(h, task.state);

    return HeroCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  task.isAnime ? Icons.movie_rounded : Icons.menu_book_rounded,
                  size: 20,
                  color: tileFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.chapterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.body.copyWith(
                        color: h.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.caption.copyWith(color: h.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (task.state == DownloadState.downloading ||
              task.state == DownloadState.paused) ...[
            const SizedBox(height: 12),
            HeroProgress(
              value: task.progress,
              height: 6,
              color: barColor,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _meta(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HeroTokens.caption.copyWith(color: h.muted),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: HeroTokens.caption.copyWith(color: h.danger),
            ),
          ],
        ],
      ),
    );
  }

  /// Soft-tinted leading tile colours per download state: accent while
  /// downloading, warning while paused, neutral while queued, success once
  /// completed, danger when failed/cancelled.
  (Color, Color, Color) _stateColors(HeroThemeData h, DownloadState s) {
    switch (s) {
      case DownloadState.downloading:
        return (h.accentSoft, h.accentSoftFg, h.accent);
      case DownloadState.paused:
        return (h.warningSoft, h.warningSoftFg, h.warning);
      case DownloadState.queued:
        return (h.dflt, h.foreground, h.accent);
      case DownloadState.completed:
        return (h.successSoft, h.successSoftFg, h.success);
      case DownloadState.failed:
        return (h.dangerSoft, h.dangerSoftFg, h.danger);
      case DownloadState.cancelled:
        return (h.dflt, h.muted, h.muted);
    }
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
          HeroIconButton(
            tooltip: 'Pause',
            icon: Icons.pause_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.warning,
            onPressed: () => notifier.pause(task.id),
          ),
          HeroIconButton(
            tooltip: 'Cancel',
            icon: Icons.cancel_outlined,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.danger,
            onPressed: () => notifier.cancel(task.id),
          ),
        ];
      case DownloadState.paused:
        return [
          HeroIconButton(
            tooltip: 'Resume',
            icon: Icons.play_arrow_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.success,
            onPressed: () => notifier.resume(task.id),
          ),
          HeroIconButton(
            tooltip: 'Cancel',
            icon: Icons.cancel_outlined,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.danger,
            onPressed: () => notifier.cancel(task.id),
          ),
        ];
      case DownloadState.queued:
        return [
          HeroIconButton(
            tooltip: 'Pause',
            icon: Icons.pause_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.warning,
            onPressed: () => notifier.pause(task.id),
          ),
          HeroIconButton(
            tooltip: 'Remove',
            icon: Icons.delete_outline_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.danger,
            onPressed: () => notifier.removeWithFiles(task.id),
          ),
        ];
      case DownloadState.failed:
        return [
          HeroIconButton(
            tooltip: 'Retry',
            icon: Icons.refresh_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.accent,
            onPressed: () => notifier.retry(task.id),
          ),
          HeroIconButton(
            tooltip: 'Remove',
            icon: Icons.delete_outline_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.danger,
            onPressed: () => notifier.removeWithFiles(task.id),
          ),
        ];
      case DownloadState.completed:
        return [
          HeroIconButton(
            tooltip: 'Remove',
            icon: Icons.delete_outline_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.danger,
            onPressed: () => notifier.removeWithFiles(task.id),
          ),
        ];
      case DownloadState.cancelled:
        return [
          HeroIconButton(
            tooltip: 'Retry',
            icon: Icons.refresh_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.accent,
            onPressed: () => notifier.retry(task.id),
          ),
          HeroIconButton(
            tooltip: 'Remove',
            icon: Icons.delete_outline_rounded,
            size: 34,
            iconSize: 19,
            variant: HeroColorRole.danger,
            onPressed: () => notifier.removeWithFiles(task.id),
          ),
        ];
    }
  }
}

class _BatchBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: h.surface,
          border: Border(top: BorderSide(color: h.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: HeroButton(
                label: 'Pause all',
                icon: Icons.pause_rounded,
                variant: HeroButtonVariant.light,
                color: HeroColorRole.neutral,
                fullWidth: true,
                onPressed: () {
                  ref.read(downloadsProvider.notifier).pauseAll();
                  showSnack(ref, context, 'Paused all');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HeroButton(
                label: 'Resume all',
                icon: Icons.play_arrow_rounded,
                variant: HeroButtonVariant.solid,
                color: HeroColorRole.accent,
                fullWidth: true,
                onPressed: () {
                  ref.read(downloadsProvider.notifier).resumeAll();
                  showSnack(ref, context, 'Resumed all');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
