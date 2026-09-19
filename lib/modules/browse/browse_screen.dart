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

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// Opens a catalog item discovered in Browse / search.
///
/// Browse DTOs are in-memory (`id: 0` — nothing is persisted until the user
/// commits), so routing to /mangaDetail/<id> always landed on a dead
/// "Not found" page. This helper first checks whether the entry is already
/// in the library (matched by source URL, the stable identity): if yes it
/// opens the full library-backed detail screen, otherwise it opens the
/// [SourceMangaDetailScreen] preview which can load details, add to library
/// and start reading.
///
/// The router and repository are captured SYNCHRONOUSLY: callers may pop
/// their own surface (e.g. the global-search bottom sheet) immediately after
/// invoking this helper, which disposes the calling context — any use of
/// `context` / `ref` after an await would then throw.
Future<void> openSourceManga(
  BuildContext context,
  WidgetRef ref,
  Manga manga,
) async {
  if (!context.mounted || manga.url.isEmpty) return;
  final router = GoRouter.of(context);
  final repo = ref.read(data.libraryRepositoryProvider);
  try {
    final existing = await repo.getMangaBySourceUrl(manga.url);
    if (existing != null) {
      await router.push('/mangaDetail/${existing.id}');
    } else {
      await router.push('/sourceMangaDetail', extra: manga);
    }
  } catch (_) {
    // Library lookup failures must not block browsing — fall through to the
    // preview screen, which surfaces its own errors.
    unawaited(router.push('/sourceMangaDetail', extra: manga));
  }
}

/// The browse screen.
///
/// Combines three surfaces: a source list (installed extensions), a
/// Popular / Latest / Search tab bar that switches the grid of covers for the
/// active source, a global search that queries every source at once, an "Add
/// repository" button (for third-party extension repos) and an "Extensions"
/// management link.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);
  final _searchController = TextEditingController();
  int _selectedSourceId = 1;

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only INSTALLED sources appear in the browse strip — the full catalog
    // (installed + available) lives in the extensions sheet.
    final allSources = ref.watch(sourcesProvider);
    final sources = allSources.where((s) => s.isInstalled).toList();
    final activeSource = sources.firstWhere(
      (s) => s.id == _selectedSourceId,
      orElse: () => sources.first,
    );

    if (sources.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: false,
                floating: true,
                automaticallyImplyLeading: false,
                title: Text(
                  'Browse',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Extensions',
                    icon: const Icon(Icons.extension_outlined),
                    onPressed: () => _showExtensionsSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Add repository',
                    icon: const Icon(Icons.add_link),
                    onPressed: () => _showAddRepoSheet(context),
                  ),
                ],
              ),
              SliverFillRemaining(
                child: emptyState(
                  context: context,
                  icon: Icons.extension_outlined,
                  title: 'No sources installed',
                  subtitle: 'Add an extension repository and install a '
                      'source to start browsing.',
                  action: FilledButton.icon(
                    onPressed: () => _showExtensionsSheet(context),
                    icon: const Icon(Icons.extension),
                    label: const Text('Browse extensions'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                pinned: true,
                floating: true,
                expandedHeight: 84,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
                  title: Text(
                    'Browse',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Extensions',
                    icon: const Icon(Icons.extension_outlined),
                    onPressed: () => _showExtensionsSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Add repository',
                    icon: const Icon(Icons.add_link),
                    onPressed: () => _showAddRepoSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Global search',
                    icon: const Icon(Icons.travel_explore_outlined),
                    onPressed: () => _showGlobalSearch(context),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: _SourceStrip(
                  sources: sources,
                  selectedId: _selectedSourceId,
                  onSelect: (id) => setState(() => _selectedSourceId = id),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(
                          icon: Icon(Icons.local_fire_department_outlined),
                          text: 'Popular'),
                      Tab(
                          icon: Icon(Icons.new_releases_outlined),
                          text: 'Latest'),
                      Tab(icon: Icon(Icons.search), text: 'Search'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _SourceGrid(
                  sourceId: activeSource.id,
                  label: 'Popular',
                  source: activeSource),
              _SourceGrid(
                  sourceId: activeSource.id,
                  label: 'Latest',
                  source: activeSource),
              _SourceSearch(source: activeSource),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'browse-extensions',
            tooltip: 'Manage extensions',
            onPressed: () => _showExtensionsSheet(context),
            child: const Icon(Icons.extension),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'browse-global-search',
            onPressed: () => _showGlobalSearch(context),
            icon: const Icon(Icons.travel_explore_outlined),
            label: const Text('Global search'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Extensions sheet — REAL catalog: every extension from every registered
  // repository (installed + available), with working install / uninstall.
  // Multisrc templates (madara / mangareader / mangadex) install natively;
  // interpreter-only extensions are listed with an honest "not supported".
  // --------------------------------------------------------------------------
  void _showExtensionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, controller) {
            return const _ExtensionCatalogSheet();
          },
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // Add repository sheet — lets the user paste the URL of a third-party
  // extension repository (the same workflow as Tachiyomi / Aniyomi).
  // --------------------------------------------------------------------------
  void _showAddRepoSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add extension repository',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Paste the URL of a Lumina / Tachiyomi / Aniyomi compatible '
                'extension repository to make its extensions available.',
                style: Theme.of(sheetContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://raw.githubusercontent.com/…/…',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _ExistingReposList(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _submitRepoUrl(
                        sheetContext, controller.text.trim()),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// REAL repository registration — fetches the index (with Mangayomi URL
  /// normalization), persists the repo and upserts its extension catalog.
  /// Shows a spinner while fetching and surfaces validation errors inline.
  Future<void> _submitRepoUrl(BuildContext sheetContext, String url) async {
    if (url.isEmpty) return;
    Navigator.pop(sheetContext);
    if (!mounted) return;
    showSnack(ref, context, 'Fetching repository…');
    try {
      final service = ref.read(data.extensionRepoServiceProvider);
      final count = await service.addRepo(url);
      if (!mounted) return;
      showSnack(ref, context,
          count > 0 ? 'Repository added — $count extensions' : 'Repository added');
    } catch (e) {
      if (!mounted) return;
      showSnack(
          ref, context, 'Could not add repository: ${e.toString()}');
    }
  }

  void _showGlobalSearch(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Global search'),
          content: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search across all sources…',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (v) {
              Navigator.pop(context);
              _openGlobalSearchResults(v);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _openGlobalSearchResults(_searchController.text);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  void _openGlobalSearchResults(String query) {
    if (query.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 1,
          expand: false,
          builder: (context, _) {
            return _GlobalSearchResults(query: query);
          },
        );
      },
    );
  }
}

class _ExistingReposList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repos = ref.watch(extensionReposProvider);
    if (repos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text('Added repositories',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        ...repos.map((r) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined, size: 22),
              title: Text(r.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                  '${r.extensionCount} extensions${r.lastError != null ? ' • sync failed' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  // REAL removal — persists + uninstalls its extensions.
                  await ref
                      .read(data.extensionRepoServiceProvider)
                      .removeRepo(r.url);
                },
              ),
            )),
      ],
    );
  }
}

/// The full extension catalog: every entry from every registered repo with
/// install / uninstall actions (previously a list of installed sources with
/// a dead `onPressed: () {}` Install button).
class _ExtensionCatalogSheet extends ConsumerStatefulWidget {
  const _ExtensionCatalogSheet();

  @override
  ConsumerState<_ExtensionCatalogSheet> createState() =>
      _ExtensionCatalogSheetState();
}

class _ExtensionCatalogSheetState extends ConsumerState<_ExtensionCatalogSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _syncing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(extensionCatalogProvider);
    final query = _query.toLowerCase();
    final entries = query.isEmpty
        ? catalog
        : catalog
            .where((s) =>
                s.name.toLowerCase().contains(query) ||
                s.lang.toLowerCase().contains(query))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Extensions',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                tooltip: 'Sync repositories',
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                onPressed: _syncing ? null : _syncAll,
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.add_link, size: 18),
                label: const Text('Add repo'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search extensions…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'No extensions found.\nAdd a repository to fill the catalog.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _CatalogTile(entry: entries[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _syncAll() async {
    setState(() => _syncing = true);
    try {
      await ref.read(data.extensionRepoServiceProvider).syncAll();
    } catch (_) {}
    if (mounted) setState(() => _syncing = false);
  }
}

class _CatalogTile extends ConsumerWidget {
  const _CatalogTile({required this.entry});

  final Source entry;

  bool get _supported =>
      const {'madara', 'mangareader', 'mangadex'}
          .contains((entry.typeSource ?? '').toLowerCase());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: entry.iconUrl != null
              ? Image.network(
                  entry.iconUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallbackIcon(context),
                )
              : _fallbackIcon(context),
        ),
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.lang} • v${entry.version} • ${(entry.typeSource ?? '').isEmpty ? 'unknown' : entry.typeSource}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _trailing(context, ref),
    );
  }

  Widget _fallbackIcon(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.extension,
            color: Theme.of(context).colorScheme.outline),
      );

  Widget _trailing(BuildContext context, WidgetRef ref) {
    if (!_supported) {
      return const Tooltip(
        message: 'This extension needs the code interpreter, which is not '
            'available in this build',
        child: Chip(
          label: Text('Not supported'),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    final idString = entry.idString;
    if (idString == null) return const SizedBox.shrink();
    if (entry.isInstalled) {
      return TextButton(
        onPressed: () async {
          await ref
              .read(data.extensionRepoServiceProvider)
              .uninstall(idString);
        },
        child: const Text('Uninstall'),
      );
    }
    return FilledButton.tonal(
      onPressed: () async {
        await ref
            .read(data.extensionRepoServiceProvider)
            .install(idString);
      },
      child: const Text('Install'),
    );
  }
}

class _SourceStrip extends StatelessWidget {
  const _SourceStrip({
    required this.sources,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Source> sources;
  final int selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final s = sources[i];
          final active = s.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(s.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    child: Text(
                      s.name.substring(0, 1),
                      style: TextStyle(
                        color: active
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}

class _SourceGrid extends ConsumerWidget {
  const _SourceGrid({
    required this.sourceId,
    required this.label,
    required this.source,
  });

  final int sourceId;
  final String label;
  final Source source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(browseGridProvider(sourceId));
    if (items.isEmpty) {
      return emptyState(
        context: context,
        icon: Icons.inbox_outlined,
        title: 'Nothing here yet',
        subtitle: '$label returned no items from ${source.name}.',
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              childAspectRatio: 0.66,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final manga = items[i];
                return BookCover(
                  manga: manga,
                  width: double.infinity,
                  height: double.infinity,
                  onTap: () => openSourceManga(context, ref, manga),
                );
              },
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceSearch extends ConsumerStatefulWidget {
  const _SourceSearch({required this.source});
  final Source source;

  @override
  ConsumerState<_SourceSearch> createState() => _SourceSearchState();
}

class _SourceSearchState extends ConsumerState<_SourceSearch> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.isEmpty
        ? const AsyncValue<List<Manga>>.data([])
        : ref.watch(globalSearchProvider(_query));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Search ${widget.source.name}…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
            onSubmitted: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: results.when(
            data: (items) {
              if (items.isEmpty && _query.isEmpty) {
                return emptyState(
                  context: context,
                  icon: Icons.search,
                  title: 'Search ${widget.source.name}',
                  subtitle: 'Type a title above and hit enter to begin.',
                );
              }
              if (items.isEmpty) {
                return emptyState(
                  context: context,
                  icon: Icons.sentiment_dissatisfied_outlined,
                  title: 'No results',
                  subtitle: '“$_query” did not match anything.',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  childAspectRatio: 0.66,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 14,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => BookCover(
                  manga: items[i],
                  width: double.infinity,
                  height: double.infinity,
                  onTap: () => openSourceManga(context, ref, items[i]),
                ),
              );
            },
            loading: () => Center(child: inlineLoader(context, size: 32)),
            error: (e, _) => emptyState(
              context: context,
              icon: Icons.error_outline,
              title: 'Search failed',
              subtitle: e.toString(),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlobalSearchResults extends ConsumerWidget {
  const _GlobalSearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '“$query” across ${sources.length} sources',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: sources.length,
            itemBuilder: (context, i) {
              final source = sources[i];
              return _SourceSearchRow(source: source, query: query);
            },
          ),
        ),
      ],
    );
  }
}

class _SourceSearchRow extends ConsumerWidget {
  const _SourceSearchRow({required this.source, required this.query});
  final Source source;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(globalSearchProvider(query));
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(source.name.substring(0, 1)),
      ),
      title: Text(source.name),
      subtitle: Text('${source.lang} • ${source.baseUrl}'),
      trailing: results.maybeWhen(
        data: (d) => Text('${d.length}'),
        orElse: () => const SizedBox.shrink(),
      ),
      children: [
        results.when(
          data: (items) {
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No results'),
              );
            }
            return SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => BookCover(
                  manga: items[i],
                  onTap: () {
                    Navigator.pop(context);
                    openSourceManga(context, ref, items[i]);
                  },
                ),
              ),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: inlineLoader(context, size: 24),
          ),
          error: (_, __) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Source error'),
          ),
        ),
      ],
    );
  }
}

/// Source detail route — opened when the user taps the source card header.
/// Kept here as a public widget so it can be wired into the router.
class SourceDetailView extends ConsumerWidget {
  const SourceDetailView({super.key, required this.sourceId});
  final int sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final source = sources.firstWhere((s) => s.id == sourceId);
    final items = ref.watch(browseGridProvider(sourceId));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(source.name),
              background: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: LuminaTheme.headerGradient,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(source.baseUrl,
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 4),
                        Chip(
                          label: Text(source.lang),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                childAspectRatio: 0.66,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => BookCover(
                  manga: items[i],
                  onTap: () => openSourceManga(context, ref, items[i]),
                ),
                childCount: items.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
