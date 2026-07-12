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

/// The anime library screen.
///
/// Mirrors the manga library but is tuned for anime: progress is reported in
/// episodes watched rather than pages read, the FAB imports local video files
/// (mp4 / mkv) and the empty-state copy reflects an anime context.
class AnimeLibraryScreen extends ConsumerStatefulWidget {
  const AnimeLibraryScreen({super.key});

  @override
  ConsumerState<AnimeLibraryScreen> createState() =>
      _AnimeLibraryScreenState();
}

class _AnimeLibraryScreenState extends ConsumerState<AnimeLibraryScreen> {
  bool _searchVisible = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(libraryOptionsProvider);
    final selection = ref.watch(animeLibrarySelectionProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _AnimeAppBar(
              searchVisible: _searchVisible,
              searchController: _searchController,
              onSearchToggle: () {
                setState(() {
                  _searchVisible = !_searchVisible;
                  if (!_searchVisible) {
                    _searchController.clear();
                    ref.read(libraryOptionsProvider.notifier).setQuery('');
                  }
                });
              },
              onSearchChanged: (v) =>
                  ref.read(libraryOptionsProvider.notifier).setQuery(v),
            ),
            _CategoryTabs(
              categories: categories,
              activeId: options.activeCategoryId,
              onSelect: (id) =>
                  ref.read(libraryOptionsProvider.notifier).setCategory(id),
            ),
            _FilterRow(),
            if (selection.isNotEmpty) _AnimeSelectionBar(),
            Expanded(child: _AnimeLibraryBody()),
          ],
        ),
      ),
      floatingActionButton: selection.isActive
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  showSnack(ref, context, 'Pick a .mp4 / .mkv to import'),
              icon: const Icon(Icons.video_file_outlined),
              label: const Text('Import'),
            ),
    );
  }
}

class _AnimeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AnimeAppBar({
    required this.searchVisible,
    required this.searchController,
    required this.onSearchToggle,
    required this.onSearchChanged,
  });

  final bool searchVisible;
  final TextEditingController searchController;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: searchVisible
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: searchController,
                autofocus: true,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search anime…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onSearchToggle,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
              child: Row(
                children: [
                  Text(
                    'Anime',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: onSearchToggle,
                  ),
                  Consumer(builder: (context, ref, _) {
                    final view = ref.watch(
                        libraryOptionsProvider.select((o) => o.view));
                    return IconButton(
                      tooltip:
                          view == LibraryView.grid ? 'List view' : 'Grid view',
                      icon: Icon(view == LibraryView.grid
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded),
                      onPressed: () {
                        ref.read(libraryOptionsProvider.notifier).setView(
                            view == LibraryView.grid
                                ? LibraryView.list
                                : LibraryView.grid);
                      },
                    );
                  }),
                  Consumer(builder: (context, ref, _) {
                    return PopupMenuButton<String>(
                      tooltip: 'Sort',
                      icon: const Icon(Icons.sort_rounded),
                      onSelected: (value) {
                        final notifier =
                            ref.read(libraryOptionsProvider.notifier);
                        if (value == 'desc') {
                          notifier.toggleSortDirection();
                        } else {
                          final sort = LibrarySort.values.firstWhere(
                              (s) => s.name == value,
                              orElse: () => LibrarySort.title);
                          notifier.setSort(sort);
                        }
                      },
                      itemBuilder: (context) {
                        final options = ref.read(libraryOptionsProvider);
                        return [
                          for (final s in LibrarySort.values)
                            CheckedPopupMenuItem(
                              value: s.name,
                              checked: options.sort == s,
                              child: Text(s.label),
                            ),
                          const PopupMenuDivider(),
                          CheckedPopupMenuItem(
                            value: 'desc',
                            checked: options.sortDescending,
                            child: const Text('Descending'),
                          ),
                        ];
                      },
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.categories,
    required this.activeId,
    required this.onSelect,
  });

  final List<Category> categories;
  final int activeId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          final active = c.id == activeId;
          return StatusChip(
            label: c.name,
            selected: active,
            onTap: () => onSelect(c.id),
          );
        },
      ),
    );
  }
}

class _FilterRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter =
        ref.watch(libraryOptionsProvider.select((o) => o.filter));
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          StatusChip(
            label: LibraryFilter.all.label,
            selected: filter == LibraryFilter.all,
            color: LuminaTheme.seed,
            onTap: () => ref
                .read(libraryOptionsProvider.notifier)
                .setFilter(LibraryFilter.all),
          ),
          const SizedBox(width: 8),
          StatusChip(
            label: LibraryFilter.reading.label,
            icon: Icons.live_tv_rounded,
            selected: filter == LibraryFilter.reading,
            color: LuminaTheme.readingColor,
            onTap: () => ref
                .read(libraryOptionsProvider.notifier)
                .setFilter(LibraryFilter.reading),
          ),
          const SizedBox(width: 8),
          StatusChip(
            label: LibraryFilter.finished.label,
            icon: Icons.check_circle_outline,
            selected: filter == LibraryFilter.finished,
            color: LuminaTheme.finishedColor,
            onTap: () => ref
                .read(libraryOptionsProvider.notifier)
                .setFilter(LibraryFilter.finished),
          ),
          const SizedBox(width: 8),
          StatusChip(
            label: LibraryFilter.unread.label,
            icon: Icons.notification_important_outlined,
            selected: filter == LibraryFilter.unread,
            color: LuminaTheme.unreadColor,
            onTap: () => ref
                .read(libraryOptionsProvider.notifier)
                .setFilter(LibraryFilter.unread),
          ),
        ],
      ),
    );
  }
}

class _AnimeSelectionBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(animeLibrarySelectionProvider);
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(animeLibrarySelectionProvider.notifier).clear(),
            ),
            Text(
              '${selection.length} selected',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all_outlined),
              onPressed: () {
                final all = ref.read(filteredAnimeProvider);
                ref
                    .read(animeLibrarySelectionProvider.notifier)
                    .addAll(all.map((m) => m.id));
              },
            ),
            IconButton(
              tooltip: 'Mark as seen',
              icon: const Icon(Icons.done_all),
              onPressed: () {
                showSnack(ref, context, 'Marked ${selection.length} as seen');
                ref.read(animeLibrarySelectionProvider.notifier).clear();
              },
            ),
            IconButton(
              tooltip: 'Remove from library',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                showSnack(ref, context, 'Removed ${selection.length} items');
                ref.read(animeLibrarySelectionProvider.notifier).clear();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimeLibraryBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(libraryOptionsProvider);
    final items = ref.watch(filteredAnimeProvider);

    if (items.isEmpty) {
      return emptyState(
        context: context,
        icon: Icons.live_tv_outlined,
        title: 'No anime in your library',
        subtitle:
            'Browse anime sources and add shows to your watch list, or import local video files.',
        action: FilledButton.tonalIcon(
          onPressed: () => context.go('/browse'),
          icon: const Icon(Icons.explore_outlined),
          label: const Text('Browse sources'),
        ),
      );
    }

    if (options.view == LibraryView.list) {
      return _AnimeListView(items: items);
    }
    return _AnimeGridView(items: items);
  }
}

class _AnimeGridView extends ConsumerWidget {
  const _AnimeGridView({required this.items});
  final List<Manga> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        childAspectRatio: 0.66,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final anime = items[i];
        final selected = ref.watch(animeLibrarySelectionProvider
            .select((s) => s.contains(anime.id)));
        return BookCover(
          manga: anime,
          width: double.infinity,
          height: double.infinity,
          selected: selected,
          onTap: () {
            final sel = ref.read(animeLibrarySelectionProvider);
            if (sel.isActive) {
              ref
                  .read(animeLibrarySelectionProvider.notifier)
                  .toggle(anime.id);
            } else {
              context.push('/manga/${anime.id}');
            }
          },
          onLongPress: () =>
              ref.read(animeLibrarySelectionProvider.notifier).toggle(anime.id),
        );
      },
    );
  }
}

class _AnimeListView extends ConsumerWidget {
  const _AnimeListView({required this.items});
  final List<Manga> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 88),
      itemBuilder: (context, i) {
        final anime = items[i];
        final selected = ref.watch(animeLibrarySelectionProvider
            .select((s) => s.contains(anime.id)));
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: SizedBox(
            width: 64,
            height: 92,
            child: BookCover(
              manga: anime,
              width: 64,
              height: 92,
              showProgress: false,
              selected: selected,
              radius: 8,
            ),
          ),
          title: Text(
            anime.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.play_circle_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    '${anime.readCount}/${anime.totalChapters} eps',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  if (anime.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: LuminaTheme.newColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${anime.unreadCount}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: anime.progress,
                  minHeight: 5,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    anime.progress >= 1
                        ? LuminaTheme.finishedColor
                        : LuminaTheme.readingColor,
                  ),
                ),
              ),
            ],
          ),
          onTap: () {
            final sel = ref.read(animeLibrarySelectionProvider);
            if (sel.isActive) {
              ref
                  .read(animeLibrarySelectionProvider.notifier)
                  .toggle(anime.id);
            } else {
              context.push('/manga/${anime.id}');
            }
          },
          onLongPress: () => ref
              .read(animeLibrarySelectionProvider.notifier)
              .toggle(anime.id),
        );
      },
    );
  }
}
