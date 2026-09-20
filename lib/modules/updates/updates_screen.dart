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

import '../../core/ui/lumina_ui.dart';
import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The new chapter / episode feed.
///
/// Surfaces fresh releases grouped by the day they were published, with quick
/// actions to mark as read/seen, download or open the chapter immediately.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  /// Runs the library updater (real source fetch) on pull-to-refresh — the
  /// empty state promises it, but the screen never had a RefreshIndicator.
  Future<void> _onRefresh() async {
    try {
      final count = await ref.read(libraryUpdaterProvider).runOnce();
      if (!mounted) return;
      showSnack(
        ref,
        context,
        count > 0 ? '$count new chapter(s) found' : 'No new chapters',
      );
    } catch (e) {
      if (mounted) showSnack(ref, context, 'Update check failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final updates = ref.watch(updatesProvider);
    final filter = ref.watch(updatesFilterProvider);
    final filtered = filter == null
        ? updates
        : updates.where((u) => u.isRead == filter).toList();
    final groups = _groupByDay(filtered);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: false,
                floating: true,
                automaticallyImplyLeading: false,
                title: Text(
                  'Updates',
                  style: HeroTokens.display.copyWith(color: h.foreground),
                ),
                actions: [
                  PopupMenuButton<String>(
                    tooltip: 'Filter',
                    icon: const Icon(Icons.filter_list_rounded),
                    onSelected: (v) {
                      switch (v) {
                        case 'all':
                          ref.read(updatesFilterProvider.notifier).state = null;
                          break;
                        case 'unread':
                          ref.read(updatesFilterProvider.notifier).state =
                              false;
                          break;
                        case 'read':
                          ref.read(updatesFilterProvider.notifier).state = true;
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'all', child: Text('Show all')),
                      const PopupMenuItem(
                          value: 'unread', child: Text('Unread only')),
                      const PopupMenuItem(
                          value: 'read', child: Text('Read only')),
                    ],
                  ),
                  HeroIconButton(
                    tooltip: 'Mark all read',
                    icon: Icons.done_all_rounded,
                    onPressed: () async {
                      // REAL persistence — previously a snackbar-only stub.
                      await ref.read(updatesProvider.notifier).markAllRead();
                      if (context.mounted) {
                        showSnack(ref, context, 'Marked all as read');
                      }
                    },
                  ),
                ],
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  child: emptyState(
                    context: context,
                    icon: Icons.system_update_outlined,
                    title: 'No new updates',
                    subtitle:
                        'Pull to refresh, or wait for the next sync interval.',
                    action: HeroButton(
                      label: 'Check for updates',
                      icon: Icons.refresh_rounded,
                      variant: HeroButtonVariant.soft,
                      onPressed: () => _onRefresh(),
                    ),
                  ),
                )
              else
                ...groups.entries.map((e) => _DayGroup(
                      day: e.key,
                      items: e.value,
                    )),
              // Bottom nav bar clearance.
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  Map<DateTime, List<UpdateItem>> _groupByDay(List<UpdateItem> items) {
    final map = <DateTime, List<UpdateItem>>{};
    for (final e in items) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      map.putIfAbsent(key, () => []).add(e);
    }
    final sortedKeys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in sortedKeys) k: map[k]!};
  }
}

class _DayGroup extends ConsumerWidget {
  const _DayGroup({required this.day, required this.items});
  final DateTime day;
  final List<UpdateItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: HeroSectionHeader(
            _dayLabel(day),
            trailing: HeroChip(
              label: '${items.length}',
              small: true,
              color: HeroColorRole.neutral,
            ),
          ),
        ),
        SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const HeroSeparator(indent: 76),
          itemBuilder: (context, i) => _UpdateTile(item: items[i]),
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

class _UpdateTile extends ConsumerStatefulWidget {
  const _UpdateTile({required this.item});
  final UpdateItem item;

  @override
  ConsumerState<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<_UpdateTile> {
  late bool _isRead = widget.item.isRead;
  late bool _isDownloaded = widget.item.isDownloaded;
  bool _downloading = false;

  @override
  void didUpdateWidget(covariant _UpdateTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the local flags aligned with persisted state changes (the
    // Isar watch rebuilds the list after setRead / download updates).
    if (widget.item.isRead != oldWidget.item.isRead) {
      _isRead = widget.item.isRead;
    }
    if (widget.item.isDownloaded != oldWidget.item.isDownloaded) {
      _isDownloaded = widget.item.isDownloaded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final item = widget.item;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Open the reader / player for the new chapter / episode.
        if (item.isAnime) {
          context.push('/animeDetail/${item.mangaId}');
        } else {
          context.push('/mangaDetail/${item.mangaId}');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            BookCover(
              manga: Manga(
                id: item.mangaId,
                title: item.mangaTitle,
                sourceId: 0,
                url: '',
                itemType: item.isAnime ? ItemType.anime : ItemType.manga,
                thumbnailUrl: item.thumbnailUrl,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.mangaTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HeroTokens.body.copyWith(
                            color: _isRead ? h.muted : h.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Unread indicator: small accent dot.
                      if (!_isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: h.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.chapterName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HeroTokens.caption.copyWith(color: h.muted),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.scanlator != null) ...[
                        Icon(Icons.group_outlined, size: 12, color: h.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.scanlator!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HeroTokens.caption.copyWith(color: h.muted),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(Icons.schedule_rounded, size: 12, color: h.muted),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo(item.date),
                        style: HeroTokens.caption.copyWith(color: h.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            HeroIconButton(
              tooltip: _isRead
                  ? (item.isAnime ? 'Mark as unseen' : 'Mark as unread')
                  : (item.isAnime ? 'Mark as seen' : 'Mark as read'),
              icon: _isRead
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_rounded,
              size: 36,
              iconSize: 20,
              color: _isRead ? null : h.accent,
              onPressed: () {
                // Persist through the notifier — previously this only
                // flipped a local copy that reset on the next rebuild.
                final next = !_isRead;
                setState(() => _isRead = next);
                ref
                    .read(updatesProvider.notifier)
                    .setRead(widget.item.id, read: next);
              },
            ),
            _downloadButton(h),
          ],
        ),
      ),
    );
  }

  Widget _downloadButton(HeroThemeData h) {
    if (_downloading) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return HeroIconButton(
      tooltip: _isDownloaded ? 'Delete download' : 'Download',
      icon:
          _isDownloaded ? Icons.check_circle_rounded : Icons.download_outlined,
      size: 36,
      iconSize: 20,
      variant: _isDownloaded ? HeroColorRole.success : HeroColorRole.neutral,
      onPressed: _toggleDownload,
    );
  }

  Future<void> _toggleDownload() async {
    final item = widget.item;
    if (_isDownloaded) {
      // REAL delete — removes the downloaded files + queue rows and
      // resets the chapter flag (previously "flip visual state only").
      if (item.chapterId == null) return;
      final confirmed = await showHeroConfirm(
        context: context,
        title: 'Delete download?',
        message:
            'The downloaded files for "${item.chapterName}" will be removed from this device.',
        confirmLabel: 'Delete',
      );
      if (!confirmed) return;
      await ref
          .read(downloadsProvider.notifier)
          .deleteChapterFiles(item.chapterId!);
      if (mounted) {
        setState(() => _isDownloaded = false);
        showSnack(ref, context, 'Download deleted');
      }
      return;
    }
    if (item.chapterId == null) {
      showSnack(ref, context, 'Chapter unavailable for download');
      return;
    }
    setState(() => _downloading = true);
    try {
      // REAL enqueue — resolve the manga + chapter from Isar and queue the
      // download (previously a fake 700 ms "downloaded" animation).
      final repo = ref.read(data.libraryRepositoryProvider);
      final manga = await repo.getManga(item.mangaId);
      final chapter =
          manga?.chapters.where((c) => c.id == item.chapterId).firstOrNull;
      if (manga == null || chapter == null) {
        if (mounted) {
          showSnack(ref, context, 'Chapter unavailable for download');
        }
        return;
      }
      if (item.isAnime) {
        await ref.read(downloadsProvider.notifier).enqueueEpisode(
              manga: manga,
              chapter: chapter,
            );
      } else {
        await ref.read(downloadsProvider.notifier).enqueueChapter(
              manga: manga,
              chapter: chapter,
            );
      }
      if (mounted) {
        setState(() => _isDownloaded = true);
        showSnack(ref, context, 'Download queued');
      }
    } catch (e) {
      if (mounted) showSnack(ref, context, 'Download failed to queue');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}
