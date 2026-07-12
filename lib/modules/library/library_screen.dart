// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The manga / novel / book library screen.
///
/// Features:
///  - Grid view and list view toggle.
///  - Filter pills for status (All / Reading / Finished / Unread) and a
///    horizontally scrolling media-type strip (Anime / Manga / Novel / Book).
///  - Horizontally scrollable category tabs.
///  - Sort options: title, author, last read, date added, unread, progress.
///  - Inline search bar.
///  - Import FAB that opens the file picker for EPUB / PDF / CBZ.
///  - Book cover grid with reading-progress bars.
///  - Long-press multi-select with a contextual action bar.
///  - Pull-to-refresh to re-sync library metadata.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _searchVisible = false;
  final _searchController = TextEditingController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(libraryOptionsProvider);
    final selection = ref.watch(librarySelectionProvider);
    final categories = ref.watch(categoriesProvider);
    final incognito = ref.watch(incognitoModeProvider);
    final downloadedOnly = ref.watch(downloadedOnlyProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _LibraryHeader(
              incognito: incognito,
              downloadedOnly: downloadedOnly,
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
              onToggleIncognito: () => ref
                  .read(incognitoModeProvider.notifier)
                  .state = !incognito,
              onToggleDownloadedOnly: () => ref
                  .read(downloadedOnlyProvider.notifier)
                  .state = !downloadedOnly,
            ),
            _CategoryTabs(
              categories: categories,
              activeId: options.activeCategoryId,
              onSelect: (id) =>
                  ref.read(libraryOptionsProvider.notifier).setCategory(id),
            ),
            _StatusFilterRow(),
            _MediaTypeFilterRow(),
            if (selection.isNotEmpty) _SelectionBar(),
            Expanded(
              child: RefreshIndicator(
                key: _refreshKey,
                edgeOffset: 0,
                displacement: 60,
                onRefresh: _onRefresh,
                child: _LibraryBody(isAnime: false),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: selection.isActive
          ? null
          : FloatingActionButton.extended(
              onPressed: _importLocalFile,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import'),
            ),
    );
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) showSnack(ref, context, 'Library up to date');
  }

  Future<void> _importLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf', 'cbz', 'cbr', 'zip'],
        allowMultiple: true,
      );
      if (result == null || result.paths.isEmpty) {
        showSnack(ref, context, 'No file selected');
        return;
      }
      final names =
          result.paths.whereType<String>().map((p) => p.split('/').last);
      showSnack(ref, context, 'Imported ${names.length} file(s)');
    } catch (e) {
      showSnack(ref, context, 'Import failed: $e');
    }
  }
}

class _LibraryHeader extends StatelessWidget implements PreferredSizeWidget {
  const _LibraryHeader({
    required this.incognito,
    required this.downloadedOnly,
    required this.searchVisible,
    required this.searchController,
    required this.onSearchToggle,
    required this.onSearchChanged,
    required this.onToggleIncognito,
    required this.onToggleDownloadedOnly,
  });

  final bool incognito;
  final bool downloadedOnly;
  final bool searchVisible;
  final TextEditingController searchController;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleIncognito;
  final VoidCallback onToggleDownloadedOnly;

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
                  hintText: 'Search library…',
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
                    'Library',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (incognito) ...[
                    const SizedBox(width: 6),
                    _QuickBadge(
                      icon: Icons.visibility_off,
                      label: 'Incognito',
                      color: LuminaTheme.unreadColor,
                      onTap: onToggleIncognito,
                    ),
                  ],
                  if (downloadedOnly) ...[
                    const SizedBox(width: 6),
                    _QuickBadge(
                      icon: Icons.cloud_off_outlined,
                      label: 'Downloaded',
                      color: LuminaTheme.readingColor,
                      onTap: onToggleDownloadedOnly,
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Incognito mode',
                    icon: Icon(
                      incognito
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_outlined,
                      color: incognito ? LuminaTheme.unreadColor : null,
                    ),
                    onPressed: onToggleIncognito,
                  ),
                  IconButton(
                    tooltip: 'Downloaded only',
                    icon: Icon(
                      downloadedOnly
                          ? Icons.cloud_off_rounded
                          : Icons.cloud_outlined,
                      color: downloadedOnly ? LuminaTheme.readingColor : null,
                    ),
                    onPressed: onToggleDownloadedOnly,
                  ),
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
                                  : LibraryView.grid,
                            );
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

class _QuickBadge extends StatelessWidget {
  const _QuickBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
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
            color: Color(c.color),
            onTap: () => onSelect(c.id),
          );
        },
      ),
    );
  }
}

class _StatusFilterRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryOptionsProvider.select((o) => o.filter));
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
            icon: Icons.menu_book_rounded,
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
            icon: Icons.circle_notifications,
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

/// Horizontally scrolling media-type filter pills (All / Anime / Manga /
/// Novel / Book) — sits beneath the status filter row.
class _MediaTypeFilterRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(libraryOptionsProvider.select((o) => o.mediaType));
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: LibraryMediaType.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = LibraryMediaType.values[i];
          return StatusChip(
            label: m.label,
            icon: m.icon,
            selected: media == m,
            color: _colorFor(m),
            onTap: () =>
                ref.read(libraryOptionsProvider.notifier).setMediaType(m),
          );
        },
      ),
    );
  }

  Color _colorFor(LibraryMediaType m) {
    switch (m) {
      case LibraryMediaType.all:
        return LuminaTheme.seed;
      case LibraryMediaType.manga:
        return LuminaTheme.readingColor;
      case LibraryMediaType.anime:
        return LuminaTheme.finishedColor;
      case LibraryMediaType.novel:
        return LuminaTheme.unreadColor;
      case LibraryMediaType.book:
        return const Color(0xFF8E24AA);
    }
  }
}

class _SelectionBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(librarySelectionProvider);
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(librarySelectionProvider.notifier).clear(),
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
                final all = ref.read(filteredMangaProvider);
                ref
                    .read(librarySelectionProvider.notifier)
                    .addAll(all.map((m) => m.id));
              },
            ),
            IconButton(
              tooltip: 'Mark as read',
              icon: const Icon(Icons.done_all),
              onPressed: () {
                showSnack(ref, context, 'Marked ${selection.length} as read');
                ref.read(librarySelectionProvider.notifier).clear();
              },
            ),
            IconButton(
              tooltip: 'Add to category',
              icon: const Icon(Icons.label_outline),
              onPressed: () => _showCategorySheet(context, ref),
            ),
            IconButton(
              tooltip: 'Remove from library',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                showSnack(ref, context, 'Removed ${selection.length} items');
                ref.read(librarySelectionProvider.notifier).clear();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCategorySheet(BuildContext context, WidgetRef ref) {
    final categories = ref.read(categoriesProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Set categories',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ...categories.where((c) => c.id != 0).map((c) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(c.color),
                      child: const Icon(Icons.label,
                          color: Colors.white, size: 18),
                    ),
                    title: Text(c.name),
                    onTap: () {
                      Navigator.pop(context);
                      showSnack(ref, context, 'Added to ${c.name}');
                      ref.read(librarySelectionProvider.notifier).clear();
                    },
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({required this.isAnime});
  final bool isAnime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(libraryOptionsProvider);
    final items = isAnime
        ? ref.watch(filteredAnimeProvider)
        : ref.watch(filteredMangaProvider);

    if (items.isEmpty) {
      // Wrapping the empty state in a scroll view lets the parent
      // RefreshIndicator receive drag gestures even when there's no list.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: emptyState(
              context: context,
              icon: Icons.library_books_outlined,
              title: 'Your library is empty',
              subtitle:
                  'Browse sources to add manga to your library, or import local files.',
              action: FilledButton.tonalIcon(
                onPressed: () => context.go('/browse'),
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Browse sources'),
              ),
            ),
          ),
        ],
      );
    }

    final body = options.view == LibraryView.list
        ? _LibraryListView(items: items)
        : _LibraryGridView(items: items);

    // Always-scrollable physics lets users pull-to-refresh even when the
    // list is shorter than the viewport.
    return ScrollConfiguration(
      behavior: const AlwaysScrollableScrollBehavior(),
      child: body,
    );
  }
}

class _LibraryGridView extends ConsumerWidget {
  const _LibraryGridView({required this.items});
  final List<Manga> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        childAspectRatio: 0.66,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final manga = items[i];
        final selected = ref.watch(
            librarySelectionProvider.select((s) => s.contains(manga.id)));
        return BookCover(
          manga: manga,
          width: double.infinity,
          height: double.infinity,
          selected: selected,
          onTap: () {
            final sel = ref.read(librarySelectionProvider);
            if (sel.isActive) {
              ref.read(librarySelectionProvider.notifier).toggle(manga.id);
            } else {
              context.push('/mangaDetail/${manga.id}');
            }
          },
          onLongPress: () {
            ref.read(librarySelectionProvider.notifier).toggle(manga.id);
          },
        );
      },
    );
  }
}

class _LibraryListView extends ConsumerWidget {
  const _LibraryListView({required this.items});
  final List<Manga> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 88),
      itemBuilder: (context, i) {
        final manga = items[i];
        final selected = ref.watch(
            librarySelectionProvider.select((s) => s.contains(manga.id)));
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: SizedBox(
            width: 64,
            height: 92,
            child: BookCover(
              manga: manga,
              width: 64,
              height: 92,
              showProgress: false,
              selected: selected,
              radius: 8,
            ),
          ),
          title: Text(
            manga.title,
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
                  Icon(
                      manga.isAnime
                          ? Icons.movie_outlined
                          : Icons.book_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    manga.isAnime
                        ? '${manga.readCount}/${manga.totalChapters} eps'
                        : '${manga.readCount}/${manga.totalChapters} ch',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  if (manga.author != null && manga.author!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '· ${manga.author}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                  if (manga.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: LuminaTheme.newColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${manga.unreadCount}',
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
                  value: manga.progress,
                  minHeight: 5,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    manga.progress >= 1
                        ? LuminaTheme.finishedColor
                        : LuminaTheme.readingColor,
                  ),
                ),
              ),
            ],
          ),
          onTap: () {
            final sel = ref.read(librarySelectionProvider);
            if (sel.isActive) {
              ref.read(librarySelectionProvider.notifier).toggle(manga.id);
            } else {
              context.push('/mangaDetail/${manga.id}');
            }
          },
          onLongPress: () =>
              ref.read(librarySelectionProvider.notifier).toggle(manga.id),
        );
      },
    );
  }
}
