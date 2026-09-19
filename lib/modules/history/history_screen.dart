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

import '../../core/ui/heroui_v3.dart';
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
  bool _searchVisible = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final allHistory = ref.watch(historyProvider);
    // Client-side search filter (title / chapter name).
    final query = _searchController.text.trim().toLowerCase();
    final history = query.isEmpty
        ? allHistory
        : allHistory
            .where((e) =>
                e.mangaTitle.toLowerCase().contains(query) ||
                (e.chapterName.toLowerCase().contains(query)))
            .toList();
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
                style: HeroTokens.titleLarge.copyWith(color: h.foreground),
              ),
              actions: [
                HeroIconButton(
                  tooltip: 'Search history',
                  icon: _searchVisible
                      ? Icons.close_rounded
                      : Icons.search_rounded,
                  onPressed: () => setState(() {
                    _searchVisible = !_searchVisible;
                    if (!_searchVisible) _searchController.clear();
                  }),
                ),
                HeroIconButton(
                  tooltip: 'Clear history',
                  icon: Icons.delete_sweep_outlined,
                  variant: HeroColorRole.danger,
                  onPressed: () => _confirmClear(),
                ),
              ],
            ),
            if (_searchVisible)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: HeroInput(
                    controller: _searchController,
                    hint: 'Search history…',
                    prefixIcon: Icons.search_rounded,
                    autofocus: true,
                    onChanged: (v) => setState(() {}),
                  ),
                ),
              ),
            if (history.isEmpty)
              SliverFillRemaining(
                child: emptyState(
                  context: context,
                  icon: Icons.history_toggle_off,
                  title: 'No history yet',
                  subtitle:
                      'Chapters you read and episodes you watch will show up here.',
                  action: HeroButton(
                    label: 'Browse library',
                    icon: Icons.local_library_outlined,
                    variant: HeroButtonVariant.soft,
                    onPressed: () => context.go('/library'),
                  ),
                ),
              )
            else
              ...groups.entries.map((e) => _DayGroup(
                    day: e.key,
                    entries: e.value,
                  )),
            // Bottom nav bar clearance.
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
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

  Future<void> _confirmClear() async {
    final confirmed = await showHeroConfirm(
      context: context,
      title: 'Clear history?',
      message: 'This permanently removes your reading and watching history. '
          'This action cannot be undone.',
      confirmLabel: 'Clear',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    // REAL clear — previously a snackbar-only stub.
    try {
      await ref.read(historyProvider.notifier).clearAll();
      if (!mounted) return;
      showSnack(ref, context, 'History cleared');
    } catch (e) {
      if (!mounted) return;
      showSnack(ref, context, 'Could not clear history');
    }
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
          child: HeroSectionHeader(
            _dayLabel(day),
            trailing: HeroChip(
              label: '${entries.length}',
              small: true,
              color: HeroColorRole.neutral,
            ),
          ),
        ),
        SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) => const HeroSeparator(indent: 76),
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1].toUpperCase()} ${d.day}, ${d.year}';
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: h.dangerSoft,
        child: Icon(Icons.delete_outline_rounded, color: h.danger),
      ),
      onDismissed: (_) async {
        // REAL removal — the Isar watch drops the row (previously the
        // snackbar fired but the entry resurrected on the next DB event).
        try {
          await ref.read(historyProvider.notifier).remove(entry.id);
        } catch (_) {}
        if (context.mounted) {
          showSnack(ref, context, 'Removed from history');
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _resume(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              BookCover(
                manga: Manga(
                  id: entry.mangaId,
                  title: entry.mangaTitle,
                  sourceId: 0,
                  url: '',
                  itemType: entry.isAnime ? ItemType.anime : ItemType.manga,
                  thumbnailUrl: entry.thumbnailUrl,
                ),
                width: 48,
                height: 68,
                radius: 8,
                showTitle: false,
                showProgress: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.mangaTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.body.copyWith(
                        color: h.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.chapterName} · ${timeAgo(entry.readAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.caption.copyWith(color: h.muted),
                    ),
                    if (entry.progress > 0) ...[
                      const SizedBox(height: 7),
                      HeroProgress(
                        value: entry.progress,
                        height: 4,
                        color: entry.progress >= 1 ? h.success : h.accent,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              HeroIconButton(
                tooltip:
                    entry.isAnime ? 'Continue watching' : 'Continue reading',
                icon: Icons.play_arrow_rounded,
                iconSize: 24,
                size: 40,
                variant: HeroColorRole.accent,
                backgroundColor: h.accentSoft,
                onPressed: () => _resume(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resume(BuildContext context) {
    if (entry.isAnime) {
      context.push('/animePlayer/${entry.chapterId ?? entry.id}');
    } else {
      context.push('/reader/${entry.chapterId ?? entry.id}');
    }
  }
}
