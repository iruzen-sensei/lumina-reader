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
  String _globalQuery = '';

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    final activeSource = sources.firstWhere(
      (s) => s.id == _selectedSourceId,
      orElse: () => sources.first,
    );

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
  // Extensions sheet — also reachable from the "Extensions" link in the more
  // screen. Lists every installed source with its version + install state.
  // --------------------------------------------------------------------------
  void _showExtensionsSheet(BuildContext context) {
    final sources = ref.read(sourcesProvider);
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
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text('Installed extensions',
                          style: Theme.of(context).textTheme.titleLarge),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: () => _showAddRepoSheet(context),
                        icon: const Icon(Icons.add_link, size: 18),
                        label: const Text('Add repo'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: sources.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = sources[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Text(s.name.substring(0, 1)),
                        ),
                        title: Text(s.name),
                        subtitle: Text('${s.lang} • v${s.version}'),
                        trailing: s.isInstalled
                            ? Chip(
                                label: const Text('Installed'),
                                visualDensity: VisualDensity.compact,
                              )
                            : FilledButton.tonal(
                                onPressed: () {},
                                child: const Text('Install'),
                              ),
                        onTap: () {
                          setState(() => _selectedSourceId = s.id);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
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
                    onPressed: () {
                      final url = controller.text.trim();
                      if (url.isEmpty) return;
                      final repos = ref.read(extensionReposProvider.notifier);
                      repos.state = [
                        ...repos.state,
                        ExtensionRepo(
                          url: url,
                          name: url.split('/').last,
                          installedCount: 0,
                          lastUpdated: DateTime.now(),
                        ),
                      ];
                      Navigator.pop(sheetContext);
                      showSnack(ref, context, 'Repository added');
                    },
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
              setState(() => _globalQuery = v);
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
                setState(() => _globalQuery = _searchController.text);
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
              subtitle: Text(r.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  final notifier = ref.read(extensionReposProvider.notifier);
                  notifier.state =
                      notifier.state.where((e) => e.url != r.url).toList();
                },
              ),
            )),
      ],
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
                  onTap: () => context.push('/mangaDetail/${manga.id}'),
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
                  onTap: () => context.push('/mangaDetail/${items[i].id}'),
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
                    context.push('/mangaDetail/${items[i].id}');
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
                  onTap: () => context.push('/mangaDetail/${items[i].id}'),
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
