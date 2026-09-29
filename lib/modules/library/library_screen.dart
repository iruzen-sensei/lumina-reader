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
import '../../core/ui/lumina_ui.dart';
import '../../core/ui/watermelon.dart';
import 'package:lumina_reader/core/ui/hero_motion.dart';
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
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

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
              mediaType: options.mediaType,
              searchDictionary: [
                for (final m in ref.watch(filteredMangaProvider).take(200))
                  m.title,
              ],
              onSearchChanged: (v) =>
                  ref.read(libraryOptionsProvider.notifier).setQuery(v),
              onMediaType: (m) =>
                  ref.read(libraryOptionsProvider.notifier).setMediaType(m),
              onToggleIncognito: () =>
                  ref.read(incognitoModeProvider.notifier).state = !incognito,
              onToggleDownloadedOnly: () => ref
                  .read(downloadedOnlyProvider.notifier)
                  .state = !downloadedOnly,
              onImport: _importLocalFile,
            ),
            // The category pill only exists when the user has REAL
            // categories — with the lone default "All" it was a dead
            // control saying the same thing as the default state.
            if (categories.length > 1)
              _CategoryTabs(
                categories: categories,
                activeId: options.activeCategoryId,
                onSelect: (id) => ref
                    .read(libraryOptionsProvider.notifier)
                    .setCategory(id),
              ),
            _LibraryFilterBar(),
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
              itemType: isTxt ? ItemType.novel : ItemType.book,
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

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.incognito,
    required this.downloadedOnly,
    required this.mediaType,
    required this.searchDictionary,
    required this.onSearchChanged,
    required this.onMediaType,
    required this.onToggleIncognito,
    required this.onToggleDownloadedOnly,
    required this.onImport,
  });

  final bool incognito;
  final bool downloadedOnly;
  final LibraryMediaType mediaType;
  final List<String> searchDictionary;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<LibraryMediaType> onMediaType;
  final VoidCallback onToggleIncognito;
  final VoidCallback onToggleDownloadedOnly;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 2),
          child: Stack(
            children: [
              // Monochrome light bloom behind the title (whisper-quiet).
              const Positioned.fill(
                child: HeroOrbs(opacity: 0.4, seed: 3),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Library',
                      style: HeroTokens.display.copyWith(
                        color: h.foreground,
                      ),
                    ),
                  ),
                  HeroIconButton(
                    tooltip: 'Import files',
                    icon: Icons.file_upload_outlined,
                    onPressed: onImport,
                  ),
                  // Updates bell — the feed moved off the bottom nav; the
                  // Library is where new chapters land, so the bell lives
                  // here, with a live unread badge.
                  Consumer(builder: (context, ref, _) {
                    final updates = ref.watch(updatesProvider);
                    final unread = updates.where((u) => !u.isRead).length;
                    return HeroIconButton(
                      tooltip: 'Updates',
                      icon: Icons.notifications_outlined,
                      color: unread > 0 ? LuminaTheme.unreadColor : null,
                      badgeCount: unread,
                      onPressed: () => context.push('/updates'),
                    );
                  }),
                  // Incognito — a small icon that turns RED while active
                  // (no banner, no layout shift; the old inline orange
                  // "Incognito" badge wrapped to a second line and pushed
                  // the whole library down).
                  HeroIconButton(
                    tooltip: incognito
                        ? 'Incognito on — tap to turn off'
                        : 'Incognito mode',
                    icon: incognito
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_outlined,
                    color: incognito ? h.danger : null,
                    variant: incognito
                        ? HeroColorRole.danger
                        : HeroColorRole.neutral,
                    onPressed: onToggleIncognito,
                  ),
                  HeroIconButton(
                    tooltip: 'Downloaded only',
                    icon: downloadedOnly
                        ? Icons.cloud_off_rounded
                        : Icons.cloud_outlined,
                    color: downloadedOnly ? LuminaTheme.readingColor : null,
                    variant: downloadedOnly
                        ? HeroColorRole.accent
                        : HeroColorRole.neutral,
                    onPressed: onToggleDownloadedOnly,
                  ),
                  Consumer(builder: (context, ref, _) {
                    final view =
                        ref.watch(libraryOptionsProvider.select((o) => o.view));
                    return HeroIconButton(
                      tooltip:
                          view == LibraryView.grid ? 'List view' : 'Grid view',
                      icon: view == LibraryView.grid
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                      onPressed: () {
                        ref.read(libraryOptionsProvider.notifier).setView(
                              view == LibraryView.grid
                                  ? LibraryView.list
                                  : LibraryView.grid,
                            );
                      },
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
        // The SAME melon-ui Morphing Discovery Bar as the anime page —
        // search morphs live (filtering per keystroke) and the category
        // chips switch the media type. The old search icon toggle + hidden
        // predictive input swap stacked two search patterns; this is one.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: WmDiscoveryBar(
            searchHint: 'Search library…',
            suggestionDictionary: searchDictionary,
            onChanged: onSearchChanged,
            onSearch: onSearchChanged,
            categories: [
              for (final m in LibraryMediaType.values)
                WmDiscoveryCategory(
                  icon: m.icon,
                  label: m.label,
                  selected: m == mediaType,
                  onTap: () => onMediaType(m),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryTabs extends ConsumerWidget {
  const _CategoryTabs({
    required this.categories,
    required this.activeId,
    required this.onSelect,
  });

  final List<Category> categories;
  final int activeId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = categories.where((c) => c.id == activeId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        // watermelon.sh Quick Option Picker — category selection. The
        // Edit-Badge rename lives on a long-press of the pill (renames the
        // ACTIVE category).
        child: GestureDetector(
          onLongPress: (active == null || active.id == 0)
              ? null
              : () => _renameCategory(context, ref, active),
          child: WmQuickOptionPicker<int>(
            trayAbove: false,
            value: activeId,
            options: [
              for (final c in categories)
                WmPickerOption(
                  value: c.id,
                  label: c.name,
                  icon: Icons.label_outline_rounded,
                ),
            ],
            onChanged: onSelect,
          ),
        ),
      ),
    );
  }

  Future<void> _renameCategory(
      BuildContext context, WidgetRef ref, Category category) async {
    final controller = TextEditingController(text: category.name);
    final h = HeroScope.of(context);
    await showHeroSheet<void>(
      context: context,
      title: 'Rename category',
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            HeroInput(
              controller: controller,
              autofocus: true,
              hint: 'Category name',
              prefixIcon: Icons.label_outline_rounded,
              onSubmitted: (v) {
                Navigator.pop(sheetContext);
                ref.read(categoriesProvider.notifier).rename(category.id, v);
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                HeroButton(
                  label: 'Cancel',
                  variant: HeroButtonVariant.light,
                  color: HeroColorRole.neutral,
                  onPressed: () => Navigator.pop(sheetContext),
                ),
                const SizedBox(width: 12),
                HeroButton(
                  label: 'Rename',
                  icon: Icons.edit_rounded,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    ref
                        .read(categoriesProvider.notifier)
                        .rename(category.id, controller.text);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Long-press the category pill to rename it.',
              style: HeroTokens.caption.copyWith(color: h.muted),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }
}

/// ONE compact row of watermelon.sh pickers: status + sort (direction
/// embedded in the sort options). Media-type switching lives on the
/// discovery bar's category chips; the separate Media and Order pills are
/// gone — the old row showed THREE pills defaulting to "All"/"All"/more
/// of the same, which read as pure redundancy.
class _LibraryFilterBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(libraryOptionsProvider);
    final notifier = ref.read(libraryOptionsProvider.notifier);

    // Sort options with the direction folded in: one picker, one job.
    // (sort, descending) pairs keep the provider API unchanged.
    final sortChoices = <(String, LibrarySort, bool)>[
      ('Title A–Z', LibrarySort.title, false),
      ('Title Z–A', LibrarySort.title, true),
      ('Recently read', LibrarySort.lastRead, true),
      ('Least recently read', LibrarySort.lastRead, false),
      ('Recently added', LibrarySort.dateAdded, true),
      ('Unread first', LibrarySort.unread, true),
      ('Best progress', LibrarySort.progress, true),
      ('Author A–Z', LibrarySort.author, false),
    ];
    final activeSort = sortChoices.firstWhere(
      (c) => c.$2 == options.sort && c.$3 == options.sortDescending,
      orElse: () => sortChoices.first,
    );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          WmStatusPicker(
            value: LibraryFilter.values.indexOf(options.filter),
            onChanged: (i) => notifier.setFilter(LibraryFilter.values[i]),
            items: [
              WmStatusItem(
                id: 0,
                icon: Icons.apps_rounded,
                name: LibraryFilter.all.label,
              ),
              WmStatusItem(
                id: 1,
                icon: Icons.menu_book_rounded,
                name: LibraryFilter.reading.label,
                color: HeroScope.of(context).accent,
              ),
              WmStatusItem(
                id: 2,
                icon: Icons.check_circle_outline_rounded,
                name: LibraryFilter.finished.label,
                color: HeroScope.of(context).success,
              ),
              WmStatusItem(
                id: 3,
                icon: Icons.markunread_rounded,
                name: LibraryFilter.unread.label,
                color: HeroScope.of(context).warning,
              ),
            ],
          ),
          const SizedBox(width: 8),
          WmQuickOptionPicker<int>(
            hint: 'Sort',
            trayAbove: false,
            value: sortChoices.indexOf(activeSort),
            options: [
              for (var i = 0; i < sortChoices.length; i++)
                WmPickerOption(
                  value: i,
                  label: sortChoices[i].$1,
                  icon: switch (sortChoices[i].$2) {
                    LibrarySort.title => Icons.sort_by_alpha_rounded,
                    LibrarySort.author => Icons.person_outline_rounded,
                    LibrarySort.lastRead => Icons.schedule_rounded,
                    LibrarySort.dateAdded => Icons.event_outlined,
                    LibrarySort.unread => Icons.markunread_rounded,
                    LibrarySort.progress => Icons.percent_rounded,
                  },
                ),
            ],
            onChanged: (i) {
              final c = sortChoices[i];
              notifier.setSort(c.$2);
              notifier.setSortDirection(c.$3);
            },
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(librarySelectionProvider);
    final h = HeroScope.of(context);
    return Material(
      color: h.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              HeroIconButton(
                icon: Icons.close_rounded,
                onPressed: () =>
                    ref.read(librarySelectionProvider.notifier).clear(),
              ),
              Text(
                '${selection.length} selected',
                style: HeroTokens.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: h.foreground,
                ),
              ),
              const Spacer(),
              HeroIconButton(
                tooltip: 'Select all',
                icon: Icons.select_all_outlined,
                onPressed: () {
                  final all = ref.read(filteredMangaProvider);
                  ref
                      .read(librarySelectionProvider.notifier)
                      .addAll(all.map((m) => m.id));
                },
              ),
              HeroIconButton(
                tooltip: 'Mark as read',
                icon: Icons.done_all_rounded,
                variant: HeroColorRole.success,
                onPressed: () => _markAllRead(context, ref, selection),
              ),
              HeroIconButton(
                tooltip: 'Add to category',
                icon: Icons.label_outline_rounded,
                onPressed: () => _showCategorySheet(context, ref, selection),
              ),
              HeroIconButton(
                tooltip: 'Remove from library',
                icon: Icons.delete_outline_rounded,
                variant: HeroColorRole.danger,
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
    final confirmed = await showHeroDeleteConfirm(
      context: context,
      title:
          'Remove ${selection.length} ${selection.length == 1 ? 'entry' : 'entries'}?',
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
      showSnack(ref, context,
          'Removed $removed ${removed == 1 ? 'entry' : 'entries'} from library');
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

  void _showCategorySheet(
      BuildContext context, WidgetRef ref, Set<int> selection) {
    final categories = ref.read(categoriesProvider);
    showHeroSheet<void>(
      context: context,
      title: 'Set category',
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...categories.where((c) => c.id != 0).map((c) => HeroListTile(
                      leadingIcon: Icons.label_rounded,
                      title: c.name,
                      subtitle:
                          'Move ${selection.length} selected ${selection.length == 1 ? 'entry' : 'entries'} here',
                      showChevron: true,
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
        maxCrossAxisExtent: 128,
        // Cover (2:3) + 46px title/metadata block under it.
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final manga = items[i];
        final selected = ref.watch(
            librarySelectionProvider.select((s) => s.contains(manga.id)));
        return HeroEntrance(
          index: i.clamp(0, 12),
          child: BookCover(
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
          ),
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
              showTitle: false,
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
                          horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(
                        color: LuminaTheme.newColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${manga.unreadCount}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: manga.progress,
                  minHeight: 5,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
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
