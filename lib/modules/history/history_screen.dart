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
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The reading / watching history timeline.
///
/// Groups recent [HistoryEntry]s by day — Today / Yesterday / earlier this
/// week / older — and lets the user resume, remove or clear history entirely.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final groups = _groupByDay(history);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              automaticallyImplyLeading: false,
              title: Text(
                'History',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Search history',
                  icon: const Icon(Icons.search),
                  onPressed: () => showMessage(context, 'Search history'),
                ),
                IconButton(
                  tooltip: 'Clear history',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => _confirmClear(),
                ),
              ],
            ),
            if (history.isEmpty)
              SliverFillRemaining(
                child: emptyState(
                  context: context,
                  icon: Icons.history_toggle_off,
                  title: 'No history yet',
                  subtitle:
                      'Chapters you read and episodes you watch will show up here.',
                ),
              )
            else
              ...groups.entries.map((e) => _DayGroup(
                    day: e.key,
                    entries: e.value,
                  )),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Map<DateTime, List<HistoryEntry>> _groupByDay(List<HistoryEntry> items) {
    final map = <DateTime, List<HistoryEntry>>{};
    for (final e in items) {
      final key = DateTime(e.readAt.year, e.readAt.month, e.readAt.day);
      map.putIfAbsent(key, () => []).add(e);
    }
    final sortedKeys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in sortedKeys) k: map[k]!};
  }

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Clear history?'),
        content: const Text(
            'This permanently removes your reading and watching history. '
            'This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              showSnack(ref, context, 'History cleared');
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _DayGroup extends ConsumerWidget {
  const _DayGroup({required this.day, required this.entries});
  final DateTime day;
  final List<HistoryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              _dayLabel(day),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
          itemBuilder: (context, i) => _HistoryTile(entry: entries[i]),
        ),
      ],
    );
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    if (d == today) return 'TODAY';
    if (d == yesterday) return 'YESTERDAY';
    if (d.isAfter(weekAgo) && d.isBefore(today)) return 'THIS WEEK';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1].toUpperCase()} ${d.day}, ${d.year}';
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      ),
      onDismissed: (_) => showSnack(ref, context, 'Removed from history'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        leading: SizedBox(
          width: 56,
          height: 80,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (entry.thumbnailUrl != null)
                  Image.network(
                    entry.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child:
                          Icon(entry.isAnime ? Icons.movie : Icons.menu_book),
                    ),
                  )
                else
                  Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child:
                        Icon(entry.isAnime ? Icons.movie : Icons.menu_book),
                  ),
                if (entry.isAnime)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('EP',
                          style:
                              TextStyle(color: Colors.white, fontSize: 9)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        title: Text(
          entry.mangaTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              entry.chapterName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  entry.isAnime ? Icons.live_tv : Icons.menu_book,
                  size: 13,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  '${(entry.progress * 100).round()}% • ${timeAgo(entry.readAt)}',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: entry.progress,
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(entry.progress >= 1
                    ? LuminaTheme.finishedColor
                    : LuminaTheme.readingColor),
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip:
              entry.isAnime ? 'Continue watching' : 'Continue reading',
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.play_arrow,
                color: theme.colorScheme.primary, size: 20),
          ),
          onPressed: () => _resume(context),
        ),
        onTap: () => _resume(context),
      ),
    );
  }

  void _resume(BuildContext context) {
    if (entry.isAnime) {
      context.push('/animePlayer/${entry.id}');
    } else {
      context.push('/reader/${entry.id}');
    }
  }
}
