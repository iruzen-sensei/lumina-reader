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

import '../../core/ui/lumina_ui.dart';
import '../../core/ui/watermelon.dart';
import '../../data/providers.dart' as data;
import '../../eval/lib.dart' as eval_lib;

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
      // Route by media type — anime entries previously landed on the
      // MANGA detail screen ("Start reading" copy on an anime).
      await router.push(existing.isAnime
          ? '/animeDetail/${existing.id}'
          : '/mangaDetail/${existing.id}');
    } else {
      await router.push('/sourceMangaDetail', extra: manga);
    }
  } catch (_) {
    // Library lookup failures must not block browsing — fall through to the
    // preview screen, which surfaces its own errors.
    unawaited(router.push('/sourceMangaDetail', extra: manga));
  }
}

/// The browse screen (Explore).
///
/// Layout (the user-specified structure):
///   * Morphing Discovery Bar on top — THE search surface (collapsed
///     pill morphs into a live field; submits run the GLOBAL search
///     across every installed source).
///   * Below it ONE pinned picker row with THREE watermelon.sh Quick
///     Option Pickers: the extension Source, the Popular / Latest mode,
///     and a Genre filter. The old source-switcher chips on the discovery
///     bar (a fourth, redundant way to change the source) are gone.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key, this.initialGenre});

  /// Pre-selects a genre (deep links from detail-screen tag chips:
  /// '/browse?genre=Action').
  final String? initialGenre;

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);
  int _selectedSourceId = 1;

  /// Active genre filter (null = Any). Changing it re-keys the feed —
  /// the grid browses the source's catalogue filtered by the genre
  /// through its search pipeline.
  String? _genre;

  @override
  void initState() {
    super.initState();
    final g = widget.initialGenre;
    if (g != null && g.trim().isNotEmpty) _genre = g.trim();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    // Only INSTALLED sources appear in the browse strip — the full catalog
    // (installed + available) lives in the extensions sheet.
    //
    // NOTE: the empty-state check MUST run before resolving [activeSource]:
    // `sources.first` inside `orElse` crashes with "Bad state: No element"
    // while the provider is still loading its first frame (and whenever the
    // user has no installed sources) — this took down the whole tab on
    // every cold start before.
    final allSources = ref.watch(sourcesProvider);
    final sources = allSources.where((s) => s.isInstalled).toList();

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
                  style: HeroTokens.display.copyWith(color: h.foreground),
                ),
                actions: [
                  HeroIconButton(
                    tooltip: 'Extensions',
                    icon: Icons.extension_outlined,
                    onPressed: () => _showExtensionsSheet(context),
                  ),
                  HeroIconButton(
                    tooltip: 'Add repository',
                    icon: Icons.add_link,
                    onPressed: () => _showAddRepoSheet(context),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverFillRemaining(
                child: emptyState(
                  context: context,
                  icon: Icons.extension_outlined,
                  title: 'No sources installed',
                  subtitle: 'Add an extension repository and install a '
                      'source to start browsing.',
                  action: HeroButton(
                    label: 'Browse extensions',
                    icon: Icons.extension_rounded,
                    variant: HeroButtonVariant.bordered,
                    onPressed: () => _showExtensionsSheet(context),
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
        child: Builder(builder: (context) {
          // Safe now: sources is guaranteed non-empty past this point.
          final activeSource = sources.firstWhere(
            (s) => s.id == _selectedSourceId,
            orElse: () => sources.first,
          );
          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  pinned: true,
                  floating: true,
                  automaticallyImplyLeading: false,
                  title: Text(
                    'Explore',
                    style: HeroTokens.display.copyWith(
                      color: h.foreground,
                      fontSize: 28,
                    ),
                  ),
                  actions: [
                    HeroIconButton(
                      tooltip: 'Extensions',
                      icon: Icons.extension_outlined,
                      onPressed: () => _showExtensionsSheet(context),
                    ),
                    HeroIconButton(
                      tooltip: 'Add repository',
                      icon: Icons.add_link,
                      onPressed: () => _showAddRepoSheet(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                // Morphing Discovery Bar (watermelon.sh) — THE search
                // button. Pure search: the source-switcher chips that used
                // to live here duplicated the Source picker below (two
                // components, one function — the redundancy report).
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: WmDiscoveryBar(
                      searchHint: 'Search all sources…',
                      onSearch: _openGlobalSearchResults,
                      categories: const [],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  // The pinned picker row: Source + Popular/Latest + Genre
                  // — three watermelon.sh Quick Option Pickers, one job
                  // each, no duplicated surfaces.
                  delegate: _PickerHeaderDelegate(
                    controller: _tabController,
                    sources: sources,
                    selectedSourceId: activeSource.id,
                    onSelectSource: (id) =>
                        setState(() => _selectedSourceId = id),
                    genre: _genre,
                    onSelectGenre: (g) => setState(() => _genre = g),
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
                    latest: false,
                    genre: _genre,
                    source: activeSource),
                _SourceGrid(
                    sourceId: activeSource.id,
                    label: 'Latest',
                    latest: true,
                    genre: _genre,
                    source: activeSource),
              ],
            ),
          );
        }),
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
    showHeroSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.85,
        child: const SafeArea(
          top: false,
          child: _ExtensionCatalogSheet(),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Add repository sheet — see the top-level showAddRepoSheet() below.
  // --------------------------------------------------------------------------
  void _showAddRepoSheet(BuildContext context) {
    showAddRepoSheet(context);
  }

  void _openGlobalSearchResults(String query) {
    if (query.isEmpty) return;
    showHeroSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.88,
        child: SafeArea(
          top: false,
          child: _GlobalSearchResults(query: query),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Top-level add-repo sheet — callable from anywhere (app bar, extensions
// screen, extensions catalog sheet).
//
// SELF-CONTAINED BY DESIGN: the sheet owns its own [WidgetRef] (it is a
// ConsumerStatefulWidget, so `ref` lives exactly as long as the sheet
// route) and the submit path captures the ROOT scaffold messenger before
// its first await. The previous version accepted the CALLER's `ref` and
// held it across the network await — when the caller was the extensions
// catalog sheet (which pops itself right before opening this sheet), that
// ref was already disposed and every add attempt died with
// "Bad state: cannot use ref after widget was disposed", masking the real
// (often just "unsupported format") repository error.
// ----------------------------------------------------------------------------
void showAddRepoSheet(BuildContext context) {
  showHeroSheet<void>(
    context: context,
    isScrollControlled: true,
    title: 'Add extension repository',
    builder: (sheetContext) => const _AddRepoSheet(),
  );
}

class _AddRepoSheet extends ConsumerStatefulWidget {
  const _AddRepoSheet();

  @override
  ConsumerState<_AddRepoSheet> createState() => _AddRepoSheetState();
}

class _AddRepoSheetState extends ConsumerState<_AddRepoSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _submitting) return;

    // Capture everything that must OUTLIVE this sheet BEFORE the await:
    // the service (sync read on a still-mounted ref) and the ROOT scaffold
    // messenger (owned by MaterialApp, survives any route pops). After the
    // await we touch NOTHING but locals — no `ref`, no `context`.
    final service = ref.read(data.extensionRepoServiceProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);

    setState(() => _submitting = true);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(const SnackBar(
      content: Text('Fetching repository…'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 8),
    ));

    try {
      final count = await service.addRepo(url);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        content: Text(count > 0
            ? 'Added repository with $count extensions'
            : 'Repository added — no compatible extensions found'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        content: Text('Could not add repository: $e'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    }
    if (mounted) {
      setState(() => _submitting = false);
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste the URL of a Lumina / Tachiyomi / Aniyomi / Mihon '
            'compatible extension repository (index.json, index.min.json '
            'or index.pb) to make its extensions available.',
            style: HeroTokens.bodySmall.copyWith(color: h.muted),
          ),
          const SizedBox(height: 16),
          HeroInput(
            controller: _controller,
            autofocus: true,
            hint: 'https://raw.githubusercontent.com/…/…',
            prefixIcon: Icons.link_rounded,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          const _ExistingReposList(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HeroButton(
                label: 'Cancel',
                variant: HeroButtonVariant.light,
                color: HeroColorRole.neutral,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              HeroButton(
                label: _submitting ? 'Adding…' : 'Add',
                icon: _submitting ? null : Icons.add_rounded,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExistingReposList extends ConsumerWidget {
  const _ExistingReposList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final repos = ref.watch(extensionReposProvider);
    if (repos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Added repositories',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
              color: h.muted,
            ),
          ),
        ),
        // HeroListTile anatomy (icon tile + title/subtitle + trailing
        // action), inlined with zero horizontal padding so the rows stay
        // aligned with the sheet's own 20px inset.
        ...repos.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: h.accentSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: h.accentSoftFg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HeroTokens.body.copyWith(color: h.foreground),
                        ),
                        Text(
                          '${r.extensionCount} extensions'
                          '${r.lastError != null ? ' • sync failed' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HeroTokens.caption.copyWith(color: h.muted),
                        ),
                      ],
                    ),
                  ),
                  HeroIconButton(
                    tooltip: 'Remove repository',
                    icon: Icons.delete_outline_rounded,
                    variant: HeroColorRole.danger,
                    size: 32,
                    iconSize: 18,
                    onPressed: () async {
                      // REAL removal — persists + uninstalls its extensions.
                      await ref
                          .read(data.extensionRepoServiceProvider)
                          .removeRepo(r.url);
                    },
                  ),
                ],
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

class _ExtensionCatalogSheetState
    extends ConsumerState<_ExtensionCatalogSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // Live filtering: the predictive input's completion chips build on
    // the controller, and every keystroke still narrows the list below.
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    final v = _searchController.text;
    if (v != _query) setState(() => _query = v);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
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
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Extensions',
                  style: HeroTokens.title.copyWith(color: h.foreground),
                ),
              ),
              _syncing
                  ? const SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : HeroIconButton(
                      tooltip: 'Sync repositories',
                      icon: Icons.sync_rounded,
                      size: 34,
                      iconSize: 19,
                      onPressed: _syncAll,
                    ),
              const SizedBox(width: 8),
              HeroButton(
                label: 'Add repo',
                icon: Icons.add_link,
                size: HeroButtonSize.sm,
                variant: HeroButtonVariant.soft,
                // Closes the extensions sheet and opens the real add-repo
                // form (previously this button only dismissed the sheet).
                onPressed: () {
                  showAddRepoSheet(context);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          // watermelon.sh Predictive Text — completion chips built from the
          // extension catalog itself; filtering stays live per keystroke.
          child: WmPredictiveInput(
            controller: _searchController,
            hint: 'Search extensions…',
            dictionary: [
              for (final e in catalog.take(60))
                e.name,
              'english',
              'manga',
              'anime',
            ],
            onSubmitted: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'No extensions found.\nAdd a repository to fill the catalog.',
                    textAlign: TextAlign.center,
                    style: HeroTokens.bodySmall.copyWith(color: h.muted),
                  ),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const HeroSeparator(
                    indent: 72,
                  ),
                  itemBuilder: (context, i) => _CatalogTile(entry: entries[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _syncAll() async {
    setState(() => _syncing = true);
    try {
      await ref.read(data.extensionRepoServiceProvider).syncAll();
    } catch (e) {
      // Swallowing this made a failed sync look identical to a successful
      // one — the "I added a repo but nothing appears" trap.
      if (mounted) {
        showSnack(ref, context, 'Repository sync failed — check your '
            'connection and try again.');
      }
    }
    if (mounted) setState(() => _syncing = false);
  }
}

class _CatalogTile extends ConsumerStatefulWidget {
  const _CatalogTile({required this.entry});

  final Source entry;

  @override
  ConsumerState<_CatalogTile> createState() => _CatalogTileState();
}

class _CatalogTileState extends ConsumerState<_CatalogTile> {
  bool _busy = false;
  String _progress = '';

  bool get _supported =>
      const {'madara', 'mangareader', 'mangadex', 'mangabox', 'mmrcms'}
          .contains((widget.entry.typeSource ?? '').toLowerCase()) ||
      // Central truth: templates, MangaDex variants, JS extensions and
      // Aniyomi/Mihon APK extensions.
      eval_lib.isRepoDtoSupported(
        typeSource: widget.entry.typeSource,
        baseUrl: widget.entry.baseUrl,
        sourceCodeLanguage: widget.entry.sourceCodeLanguage,
      );

  Future<void> _install(String idString) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = '';
    });
    try {
      await ref.read(data.extensionRepoServiceProvider).install(
        idString,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = total != null && total > 0
              ? '${(received / 1024 / 1024).toStringAsFixed(1)} / '
                  '${(total / 1024 / 1024).toStringAsFixed(1)} MB'
              : '${(received / 1024 / 1024).toStringAsFixed(1)} MB');
        },
      );
    } catch (e) {
      if (mounted) {
        showSnack(ref, context, 'Install failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final entry = widget.entry;
    return HeroListTile(
      leading: _iconTile(h),
      title: entry.name,
      subtitle: _progress.isNotEmpty
          ? _progress
          : '${entry.lang} • v${entry.version} • '
              '${(entry.typeSource ?? '').isEmpty ? 'unknown' : entry.typeSource}',
      trailing: _trailing(ref),
    );
  }

  /// Rounded-11 icon tile: the extension artwork when available, an
  /// accent-soft glyph tile otherwise.
  Widget _iconTile(HeroThemeData h) {
    final entry = widget.entry;
    if (entry.iconUrl != null) {
      return Container(
        width: 42,
        height: 42,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
        ),
        child: Image.network(
          entry.iconUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(h),
        ),
      );
    }
    return _fallbackIcon(h);
  }

  Widget _fallbackIcon(HeroThemeData h) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: h.accentSoft,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(Icons.extension_rounded, size: 20, color: h.accentSoftFg),
      );

  Widget _trailing(WidgetRef ref) {
    if (!_supported) {
      return const Tooltip(
        message: 'This extension needs the code interpreter, which is not '
            'available in this build',
        child: HeroChip(
          label: 'Not supported',
          variant: HeroChipVariant.bordered,
          color: HeroColorRole.neutral,
          small: true,
        ),
      );
    }
    final idString = widget.entry.idString;
    if (idString == null) return const SizedBox.shrink();
    if (widget.entry.isInstalled) {
      // Install state as a soft accent chip; uninstall stays one tap away.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HeroChip(
            label: 'Installed',
            variant: HeroChipVariant.soft,
            small: true,
          ),
          const SizedBox(width: 4),
          HeroIconButton(
            tooltip: 'Uninstall',
            icon: Icons.delete_outline_rounded,
            variant: HeroColorRole.danger,
            size: 32,
            iconSize: 18,
            onPressed: () async {
              await ref
                  .read(data.extensionRepoServiceProvider)
                  .uninstall(idString);
            },
          ),
        ],
      );
    }
    // Stateful install: live download progress + busy state (the old
    // bare button threw failures into the void and allowed double-taps).
    return HeroButton(
      label: _busy ? 'Installing…' : 'Install',
      size: HeroButtonSize.sm,
      onPressed: _busy ? null : () => _install(idString),
    );
  }
}

/// Pins the picker row under the discovery bar: active Source +
/// Popular/Latest mode + Genre filter (watermelon.sh Quick Option
/// Pickers driving the SAME [TabController] as the [TabBarView]).
class _PickerHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PickerHeaderDelegate({
    required this.controller,
    required this.sources,
    required this.selectedSourceId,
    required this.onSelectSource,
    required this.genre,
    required this.onSelectGenre,
  });

  final TabController controller;
  final List<Source> sources;
  final int selectedSourceId;
  final ValueChanged<int> onSelectSource;
  final String? genre;
  final ValueChanged<String?> onSelectGenre;

  /// The shared genre vocabulary. Sources disagree on genre names; a
  /// common list keeps the picker identical across every source (each
  /// source resolves the genre through its own search pipeline).
  static const List<String> genres = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Horror',
    'Mahou Shoujo',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
  ];

  /// Pinned-bar height. The child is forced to this exact height via
  /// SizedBox (a slimmer picker row must never make the pinned header's
  /// paintExtent fall below its declared layoutExtent — that trips
  /// SliverGeometry's assertion).
  static const double headerHeight = 52;

  @override
  double get minExtent => headerHeight;

  @override
  double get maxExtent => headerHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final h = HeroScope.of(context);
    // Noir frosted sub-nav: the near-black canvas at ~78% over a clipped
    // blur so covers scrolling beneath the pinned header melt through as
    // a dimmed smear (ChatGPT/Codex nav behaviour).
    return HeroGlass(
      blurSigma: 18,
      color: h.glass,
      border: Border(
        bottom: BorderSide(
          color: h.isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: SizedBox(
        height: headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Flexible(
                child: WmQuickOptionPicker<int>(
                  hint: 'Source',
                  trayAbove: false,
                  value: selectedSourceId,
                  options: [
                    for (final s in sources)
                      WmPickerOption(
                        value: s.id,
                        label: s.name,
                        icon: Icons.language_rounded,
                      ),
                  ],
                  onChanged: onSelectSource,
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => WmQuickOptionPicker<int>(
                  hint: 'Browse',
                  trayAbove: false,
                  value: controller.index,
                  options: const [
                    WmPickerOption(
                        value: 0,
                        label: 'Popular',
                        icon: Icons.local_fire_department_rounded),
                    WmPickerOption(
                        value: 1,
                        label: 'Latest',
                        icon: Icons.new_releases_rounded),
                  ],
                  onChanged: controller.animateTo,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: WmQuickOptionPicker<String>(
                  hint: 'Genre',
                  trayAbove: false,
                  value: genre ?? '',
                  options: [
                    const WmPickerOption<String>(
                      value: '',
                      label: 'Any genre',
                      icon: Icons.all_inclusive_rounded,
                    ),
                    for (final g in genres)
                      WmPickerOption<String>(
                        value: g,
                        label: g,
                        icon: Icons.category_rounded,
                      ),
                  ],
                  onChanged: (g) => onSelectGenre(g.isEmpty ? null : g),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PickerHeaderDelegate oldDelegate) =>
      controller != oldDelegate.controller ||
      selectedSourceId != oldDelegate.selectedSourceId ||
      sources != oldDelegate.sources ||
      genre != oldDelegate.genre;
}

class _SourceGrid extends ConsumerWidget {
  const _SourceGrid({
    required this.sourceId,
    required this.label,
    required this.latest,
    required this.source,
    this.genre,
  });

  final int sourceId;
  final String label;
  final bool latest;
  final Source source;

  /// Optional genre filter — re-keys the feed (see BrowseGridNotifier).
  final String? genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keyed by (sourceId, latest, genre) — the Latest tab previously
    // watched the SAME provider instance as Popular, so it rendered a
    // duplicate of the popular grid while `load(latest: true)` sat
    // unreachable.
    final feed = ref.watch(browseFeedProvider((sourceId, latest, genre)));

    // A genre filter hides the Popular/Latest distinction (both tabs run
    // the same genre search) — one shared label keeps the header honest.
    final effectiveLabel =
        (genre == null || genre!.isEmpty) ? label : genre!;

    // LOADING: skeleton grid while the first page is in flight. Previously
    // the empty-state flashed here, making every slow source look dead.
    if (feed.loading && feed.items.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          childAspectRatio: 0.66,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
        ),
        itemCount: 15,
        itemBuilder: (context, i) => const HeroSkeleton(
          height: double.infinity,
          radius: 8,
        ),
      );
    }

    // ERROR: an explicit failure card with the reason + retry. Previously
    // failures were indistinguishable from empty results. Copy is friendly
    // (no raw source names / exception strings in the headline) and the
    // retry is a FILLED capsule so it reads as the primary action.
    if (feed.hasError && feed.items.isEmpty) {
      return emptyState(
        context: context,
        icon: Icons.wifi_off_rounded,
        title: 'This source is unreachable',
        subtitle: '${source.name} did not respond — the site may be down, '
            'blocked or slow. Check your connection and try again.',
        // Invalidating the family member rebuilds its BrowseGridNotifier,
        // whose constructor kicks off a fresh load for this source.
        action: HeroButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: () =>
              ref.invalidate(browseFeedProvider((sourceId, latest, genre))),
        ),
      );
    }

    if (feed.items.isEmpty) {
      return emptyState(
        context: context,
        icon: Icons.inbox_outlined,
        title: 'Nothing here yet',
        subtitle: 'No $effectiveLabel items came back from ${source.name}.',
        action: HeroButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: () =>
              ref.invalidate(browseFeedProvider((sourceId, latest, genre))),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Infinite scroll: fetch the next page near the end of the grid.
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          ref.read(browseFeedProvider((sourceId, latest, genre)).notifier).loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          if (feed.hasError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  feed.error!,
                  style: HeroTokens.caption
                      .copyWith(color: HeroScope.of(context).muted),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
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
                  final manga = feed.items[i];
                  return BookCover(
                    manga: manga,
                    width: double.infinity,
                    height: double.infinity,
                    onTap: () => openSourceManga(context, ref, manga),
                  );
                },
                childCount: feed.items.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalSearchResults extends ConsumerWidget {
  const _GlobalSearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    // INSTALLED sources only — previously the sheet listed every catalog
    // row (including ~360 uninstalled ones, firing real network searches
    // at each) and every row displayed the identical merged result list.
    final sources =
        ref.watch(sourcesProvider).where((s) => s.isInstalled).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '“$query” across ${sources.length} sources',
                  style: HeroTokens.title.copyWith(color: h.foreground),
                ),
              ),
              HeroIconButton(
                icon: Icons.close_rounded,
                size: 32,
                iconSize: 19,
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
    final h = HeroScope.of(context);
    // Each row searches its OWN source (previously every row watched the
    // same merged provider — identical lists and counts everywhere).
    final results = ref.watch(sourceSearchProvider((source.id, query)));
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: h.accentSoft, shape: BoxShape.circle),
        child: Text(
          source.name.isEmpty ? '?' : source.name.substring(0, 1),
          style: TextStyle(
            fontSize: 13,
            height: 1,
            fontWeight: FontWeight.w600,
            color: h.accentSoftFg,
          ),
        ),
      ),
      title: Text(
        source.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HeroTokens.body.copyWith(
          color: h.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${source.lang} • ${source.baseUrl}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: HeroTokens.caption.copyWith(color: h.muted),
      ),
      trailing: results.maybeWhen(
        data: (d) => HeroChip(
          label: '${d.length}',
          variant: HeroChipVariant.bordered,
          color: HeroColorRole.neutral,
          small: true,
        ),
        orElse: () => const SizedBox.shrink(),
      ),
      children: [
        results.when(
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No results',
                  style: HeroTokens.bodySmall.copyWith(color: h.muted),
                ),
              );
            }
            // Apple-style soft edge fade instead of a hard cutoff at
            // the screen edges.
            return HeroFadedRail(
              height: 170,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => BookCover(
                manga: items[i],
                onTap: () {
                  Navigator.pop(context);
                  openSourceManga(context, ref, items[i]);
                },
              ),
            );
          },
          // Cover-shaped shimmer tiles instead of a bare spinner.
          loading: () => HeroFadedRail(
            height: 170,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => const HeroSkeleton(
              width: 110,
              height: 160,
            ),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Source error',
              style: HeroTokens.bodySmall.copyWith(color: h.muted),
            ),
          ),
        ),
      ],
    );
  }
}
