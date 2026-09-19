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

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/ui/heroui.dart';
import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../providers/storage_provider.dart';
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
                child: const _LibraryBody(isAnime: false),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: selection.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _importLocalFile,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import'),
            ),
    );
  }

  Future<void> _onRefresh() async {
    try {
      final newChapters = await ref.read(libraryUpdaterProvider).runOnce();
      if (!mounted) return;
      showSnack(
        ref,
        context,
        newChapters > 0
            ? '$newChapters new chapter(s) found'
            : 'Library up to date',
      );
    } catch (e) {
      if (mounted) showSnack(ref, context, 'Update check failed');
    }
  }

  Future<void> _importLocalFile() async {
    try {
      // file_picker 11.0.3 (EXACT PIN — 12.x+ federates to android_file_picker,
      // whose 2.0.0 Gradle script breaks `flutter build apk` on our AGP 8.7
      // toolchain): pickFiles is still a static, but multi-select is opt-in
      // and cancelling yields a null result rather than an empty list.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf', 'cbz', 'cbr', 'zip', 'txt'],
        allowMultiple: true,
      );
      if (!mounted) return;
      final files = result?.files ?? const <PlatformFile>[];
      if (files.isEmpty) {
        showSnack(ref, context, 'No file selected');
        return;
      }

      // Copy each picked file into the app's documents directory so it
      // survives even if the source location (Downloads, SD card, cache)
      // is cleaned, then create a library entry for it. The previous
      // implementation showed a snackbar and dropped the paths.
      final repo = ref.read(data.libraryRepositoryProvider);
      final docsDir = await StorageProvider().getDownloadsDir();
      final importsDir = '$docsDir/imports';
      await Directory(importsDir).create(recursive: true);

      var imported = 0;
      final failures = <String>[];
      for (final path in files.map((f) => f.path).whereType<String>()) {
        final fileName = path.split('/').last;
        final dest = '$importsDir/$fileName';
        try {
          await File(path).copy(dest);
          final isTxt = dest.toLowerCase().endsWith('.txt');
          await repo.addToLibrary(
            Manga(
              id: 0,
              title: fileName.replaceFirst(
                  RegExp(r'\.(epub|pdf|cbz|cbr|zip|txt)$',
                      caseSensitive: false),
                  ''),
              sourceId: 0,
              url: dest,
              // .txt imports are novels (opened in the novel reader);
              // everything else is a book (epub / pdf / cbz readers).
              itemType:
                  isTxt ? ItemType.novel : ItemType.book,
              genre: const ['Local file'],
              status: ItemStatus.unknown,
              dateAdded: DateTime.now(),
            ),
            chapters: isTxt
                ? [
                    Chapter(
                      id: 0,
                      url: dest,
                      name: 'Chapter 1',
                      number: 1,
                      dateUploaded: DateTime.now(),
                    ),
                  ]
                : null,
          );
          imported++;
        } catch (e) {
          failures.add('$fileName: $e');
        }
      }

      if (!mounted) return;
      // Imported books land on the Library tab under the "Book" media filter
      // — tell the user where to look, otherwise successful imports look
      // like silent failures.
      if (imported > 0) {
        showSnack(
          ref,
          context,
          'Imported $imported file(s) — visible under '
          'All / Book filters${failures.isNotEmpty ? ' (${failures.length} failed)' : ''}',
        );
      } else if (failures.isNotEmpty) {
        showSnack(ref, context, 'Import failed: ${failures.first}');
      } else {
        showSnack(ref, context, 'No file selected');
      }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? HeroColors.darkContent1 : Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              HIconButton(
                icon: Icons.close_rounded,
                onPressed: () =>
                    ref.read(librarySelectionProvider.notifier).clear(),
              ),
              Text(
                '${selection.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : HeroColors.default900,
                ),
              ),
              const Spacer(),
              HIconButton(
                tooltip: 'Select all',
                icon: Icons.select_all_outlined,
                onPressed: () {
                  final all = ref.read(filteredMangaProvider);
                  ref
                      .read(librarySelectionProvider.notifier)
                      .addAll(all.map((m) => m.id));
                },
              ),
              HIconButton(
                tooltip: 'Mark as read',
                icon: Icons.done_all_rounded,
                color: HeroVariant.success,
                onPressed: () => _markAllRead(context, ref, selection),
              ),
              HIconButton(
                tooltip: 'Add to category',
                icon: Icons.label_outline_rounded,
                onPressed: () => _showCategorySheet(context, ref, selection),
              ),
              HIconButton(
                tooltip: 'Remove from library',
                icon: Icons.delete_outline_rounded,
                color: HeroVariant.danger,
                onPressed: () => _removeSelected(context, ref, selection),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// REAL delete: confirm → repository removeFromLibraryMany (removes
  /// chapters, download queue rows, downloaded files, imported files,
  /// history and notes) → clear selection. Previously this showed a
  /// snackbar and deleted nothing.
  Future<void> _removeSelected(
    BuildContext context,
    WidgetRef ref,
    Set<int> selection,
  ) async {
    final confirmed = await hConfirm(
      context: context,
      title: 'Remove ${selection.length} ${selection.length == 1 ? 'entry' : 'entries'}?',
      message:
          'This also deletes their downloaded chapters, imported files, history and notes. This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    final ids = selection.toList();
    ref.read(librarySelectionProvider.notifier).clear();
    final removed = await ref
        .read(data.libraryRepositoryProvider)
        .removeFromLibraryMany(ids);
    if (context.mounted) {
      showSnack(ref, context, 'Removed $removed ${removed == 1 ? 'entry' : 'entries'} from library');
    }
  }

  /// REAL mark-as-read: marks every chapter of every selected entry read.
  Future<void> _markAllRead(
    BuildContext context,
    WidgetRef ref,
    Set<int> selection,
  ) async {
    final repo = ref.read(data.libraryRepositoryProvider);
    for (final id in selection) {
      await repo.markAllChaptersRead(id, read: true);
    }
    ref.read(librarySelectionProvider.notifier).clear();
    if (context.mounted) {
      showSnack(ref, context, 'Marked ${selection.length} as read');
    }
  }

  void _showCategorySheet(BuildContext context, WidgetRef ref, Set<int> selection) {
    final categories = ref.read(categoriesProvider);
    hSheet<void>(
      context: context,
      title: 'Set category',
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...categories.where((c) => c.id != 0).map((c) => HTile(
                      icon: Icons.label_rounded,
                      tone: HeroVariant.secondary,
                      label: c.name,
                      subtitle: 'Move ${selection.length} selected ${selection.length == 1 ? 'entry' : 'entries'} here',
                      onTap: () async {
                        final repo = ref.read(data.libraryRepositoryProvider);
                        for (final id in selection) {
                          await repo.setMangaCategory(id, c.id);
                        }
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                        ref.read(librarySelectionProvider.notifier).clear();
                        if (context.mounted) {
                          showSnack(ref, context, 'Moved to ${c.name}');
                        }
                      },
                    )),
                const SizedBox(height: 12),
              ],
            ),
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
      // `AlwaysScrollableScrollBehavior` does not exist in Flutter — the
      // supported way is a ScrollBehavior whose physics is always scrollable
      // (this is what enables pull-to-refresh on short lists).
      behavior: const MaterialScrollBehavior()
          .copyWith(physics: const AlwaysScrollableScrollPhysics()),
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
            if (sel.isNotEmpty) {
              ref.read(librarySelectionProvider.notifier).toggle(manga.id);
            } else {
              context.push(_routeFor(manga));
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
            if (sel.isNotEmpty) {
              ref.read(librarySelectionProvider.notifier).toggle(manga.id);
            } else {
              context.push(_routeFor(manga));
            }
          },
          onLongPress: () =>
              ref.read(librarySelectionProvider.notifier).toggle(manga.id),
        );
      },
    );
  }
}

/// Opens imported book files (epub / pdf / cbz) in their dedicated readers;
/// everything else goes to the detail screen. Previously EVERY tap went to
/// the detail screen, leaving the finished epub/pdf readers unreachable.
String _routeFor(Manga manga) {
  if (manga.itemType == ItemType.book) {
    final url = manga.url.toLowerCase();
    if (url.endsWith('.epub')) return '/epubReader/${manga.id}';
    if (url.endsWith('.pdf')) return '/pdfReader/${manga.id}';
    if (url.endsWith('.cbz') || url.endsWith('.zip')) {
      return '/cbzReader/${manga.id}';
    }
  }
  return '/mangaDetail/${manga.id}';
}
