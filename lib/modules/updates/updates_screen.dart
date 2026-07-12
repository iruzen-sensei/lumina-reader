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
  @override
  Widget build(BuildContext context) {
    final updates = ref.watch(updatesProvider);
    final filter = ref.watch(updatesFilterProvider);
    final filtered =
        filter == null ? updates : updates.where((u) => u.isRead == filter).toList();
    final groups = _groupByDay(filtered);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              automaticallyImplyLeading: false,
              title: Text(
                'Updates',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                        ref.read(updatesFilterProvider.notifier).state = false;
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
                IconButton(
                  tooltip: 'Mark all read',
                  icon: const Icon(Icons.done_all),
                  onPressed: () =>
                      showSnack(ref, context, 'Marked all as read'),
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
                ),
              )
            else
              ...groups.entries.map((e) => _DayGroup(
                    day: e.key,
                    items: e.value,
                  )),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
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
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      leading: SizedBox(
        width: 50,
        height: 72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.thumbnailUrl != null)
                Image.network(
                  item.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(item.isAnime ? Icons.movie : Icons.menu_book),
                  ),
                )
              else
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(item.isAnime ? Icons.movie : Icons.menu_book),
                ),
            ],
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.mangaTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                    _isRead ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
          if (!_isRead)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 6),
              decoration: const BoxDecoration(
                color: LuminaTheme.newColor,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            item.chapterName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (item.scanlator != null) ...[
                Icon(Icons.group_outlined,
                    size: 12, color: theme.colorScheme.outline),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    item.scanlator!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.schedule,
                  size: 12, color: theme.colorScheme.outline),
              const SizedBox(width: 3),
              Text(
                timeAgo(item.date),
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _isRead
                ? (item.isAnime ? 'Mark as unseen' : 'Mark as unread')
                : (item.isAnime ? 'Mark as seen' : 'Mark as read'),
            icon: Icon(
              _isRead
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
              color: _isRead
                  ? theme.colorScheme.outline
                  : LuminaTheme.readingColor,
            ),
            onPressed: () {
              setState(() => _isRead = !_isRead);
            },
          ),
          IconButton(
            tooltip: _isDownloaded ? 'Delete download' : 'Download',
            icon: _downloadIcon(),
            onPressed: _toggleDownload,
          ),
        ],
      ),
      onTap: () {
        // Open the reader / player for the new chapter / episode.
        if (item.isAnime) {
          context.push('/animeDetail/${item.mangaId}');
        } else {
          context.push('/mangaDetail/${item.mangaId}');
        }
      },
    );
  }

  Widget _downloadIcon() {
    if (_downloading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_isDownloaded) {
      return const Icon(Icons.check_circle, color: LuminaTheme.finishedColor);
    }
    return const Icon(Icons.download_outlined);
  }

  Future<void> _toggleDownload() async {
    if (_isDownloaded) {
      setState(() => _isDownloaded = false);
      return;
    }
    setState(() => _downloading = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        _downloading = false;
        _isDownloaded = true;
      });
    }
  }
}
