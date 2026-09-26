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
/// Combines three surfaces: a source strip (installed extensions), a
/// Popular / Latest / Search segmented control that switches the grid of
/// covers for the active source, a global search that queries every source
/// at once, an "Add repository" button (for third-party extension repos)
/// and an "Extensions" management link.
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
                  expandedHeight: 84,
                  automaticallyImplyLeading: false,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                    title: Text(
                      'Browse',
                      style: HeroTokens.display.copyWith(
                        color: h.foreground,
                        fontSize: 30,
                      ),
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
                    HeroIconButton(
                      tooltip: 'Global search',
                      icon: Icons.travel_explore_outlined,
                      onPressed: () => _showGlobalSearch(context),
                    ),
                    const SizedBox(width: 8),
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
                  // HeroSegmented instead of a Material TabBar: the control
                  // now aligns exactly with the source strip's 16px inset
                  // (the old TabBar indented "Popular" and broke the visual
                  // rhythm) while still driving the SAME TabController as
                  // the TabBarView below.
                  delegate:
                      _SegmentedHeaderDelegate(controller: _tabController),
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
                    source: activeSource),
                _SourceGrid(
                    sourceId: activeSource.id,
                    label: 'Latest',
                    latest: true,
                    source: activeSource),
                _SourceSearch(source: activeSource),
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
    showAddRepoSheet(context, ref);
  }

  void _showGlobalSearch(BuildContext context) {
    showHeroDialog<void>(
      context: context,
      builder: (dialogContext) {
        final h = HeroScope.of(dialogContext);
        return Padding(
          // Keep the dialog above the on-screen keyboard.
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
          ),
          child: HeroDialogFrame(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Global search',
                  style: HeroTokens.title.copyWith(color: h.foreground),
                ),
                const SizedBox(height: 16),
                HeroInput(
                  controller: _searchController,
                  autofocus: true,
                  hint: 'Search across all sources…',
                  prefixIcon: Icons.search_rounded,
                  onSubmitted: (v) {
                    Navigator.pop(dialogContext);
                    _openGlobalSearchResults(v);
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    HeroButton(
                      label: 'Cancel',
                      variant: HeroButtonVariant.light,
                      color: HeroColorRole.neutral,
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                    const SizedBox(width: 12),
                    HeroButton(
                      label: 'Search',
                      icon: Icons.search_rounded,
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _openGlobalSearchResults(_searchController.text);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
// Top-level add-repo sheet — callable from both the app bar and the
// extensions catalog sheet (previously the catalog sheet's "Add repo"
// button only dismissed the sheet).
//
// REAL repository registration — fetches the index (with Mangayomi URL
// normalization), persists the repo and upserts its extension catalog.
// Surfaces validation errors inline via snack bars.
// ----------------------------------------------------------------------------
void showAddRepoSheet(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  showHeroSheet<void>(
    context: context,
    isScrollControlled: true,
    title: 'Add extension repository',
    builder: (sheetContext) {
      final h = HeroScope.of(sheetContext);
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste the URL of a Lumina / Tachiyomi / Aniyomi compatible '
              'extension repository to make its extensions available.',
              style: HeroTokens.bodySmall.copyWith(color: h.muted),
            ),
            const SizedBox(height: 16),
            HeroInput(
              controller: controller,
              autofocus: true,
              hint: 'https://raw.githubusercontent.com/…/…',
              prefixIcon: Icons.link_rounded,
            ),
            const SizedBox(height: 8),
            _ExistingReposList(),
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
                  label: 'Add',
                  icon: Icons.add_rounded,
                  onPressed: () =>
                      _submitRepoUrl(sheetContext, ref, controller.text.trim()),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _submitRepoUrl(
    BuildContext sheetContext, WidgetRef ref, String url) async {
  if (url.isEmpty) return;
  Navigator.pop(sheetContext);
  final context = sheetContext;
  showSnack(ref, context, 'Fetching repository…');
  {
    try {
      final service = ref.read(data.extensionRepoServiceProvider);
      final count = await service.addRepo(url);
      if (!context.mounted) return;
      showSnack(
        ref,
        context,
        count > 0
            ? 'Added repository with $count extensions'
            : 'Repository added — no compatible extensions found',
      );
    } catch (e) {
      if (context.mounted) {
        showSnack(ref, context, 'Could not add repository: $e');
      }
    }
  }
}

class _ExistingReposList extends ConsumerWidget {
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
  void dispose() {
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
                  Navigator.pop(context);
                  showAddRepoSheet(context, ref);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: HeroInput(
            controller: _searchController,
            hint: 'Search extensions…',
            prefixIcon: Icons.search_rounded,
            onChanged: (v) => setState(() => _query = v),
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
    } catch (_) {}
    if (mounted) setState(() => _syncing = false);
  }
}

class _CatalogTile extends ConsumerWidget {
  const _CatalogTile({required this.entry});

  final Source entry;

  bool get _supported =>
      const {'madara', 'mangareader', 'mangadex', 'mangabox', 'mmrcms'}
          .contains((entry.typeSource ?? '').toLowerCase()) ||
      // MangaDex language variants: `single` template on mangadex.org runs
      // through the native MangaDex implementation.
      ((entry.typeSource ?? '').toLowerCase() == 'single' &&
          entry.baseUrl.contains('mangadex.org'));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return HeroListTile(
      leading: _iconTile(h),
      title: entry.name,
      subtitle:
          '${entry.lang} • v${entry.version} • ${(entry.typeSource ?? '').isEmpty ? 'unknown' : entry.typeSource}',
      trailing: _trailing(ref),
    );
  }

  /// Rounded-11 icon tile: the extension artwork when available, an
  /// accent-soft glyph tile otherwise.
  Widget _iconTile(HeroThemeData h) {
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
    final idString = entry.idString;
    if (idString == null) return const SizedBox.shrink();
    if (entry.isInstalled) {
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
    return HeroButton(
      label: 'Install',
      size: HeroButtonSize.sm,
      onPressed: () async {
        await ref.read(data.extensionRepoServiceProvider).install(idString);
      },
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
    final h = HeroScope.of(context);
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = sources[i];
          final active = s.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(s.id),
            child: AnimatedContainer(
              duration: HeroTokens.motionColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                // Active pill: accent-soft fill + 1.5px accent border +
                // accent avatar — a high-contrast selection state.
                // Inactive: neutral surface2 pill with muted content.
                color: active ? h.accentSoft : h.surface2,
                borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
                border: Border.all(
                  color: active ? h.accent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: active ? h.accent : h.dflt,
                    child: Text(
                      s.name.isEmpty ? '?' : s.name.substring(0, 1),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: active ? h.accentFg : h.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The previous vertical layout (avatar above label) needed
                  // ~47px inside a 34px content box — it overflowed on every
                  // device. Horizontal chip layout fits and reads better.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? h.accentSoftFg : h.muted,
                      ),
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

/// Pins the Popular / Latest / Search [HeroSegmented] directly under the
/// source strip. Driven by the SAME [TabController] as the [TabBarView]:
/// segment taps call [TabController.animateTo] and page swipes update the
/// selection through the controller listener.
class _SegmentedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SegmentedHeaderDelegate({required this.controller});

  final TabController controller;

  /// Pinned-bar height. The child is forced to this exact height via
  /// SizedBox (a slimmer segmented control must never make the pinned
  /// header's paintExtent fall below its declared layoutExtent — that
  /// trips SliverGeometry's assertion).
  static const double headerHeight = 46;

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => HeroSegmented<int>(
              expand: true,
              selected: controller.index,
              segments: const [
                (0, 'Popular', Icons.local_fire_department_rounded),
                (1, 'Latest', Icons.new_releases_rounded),
                (2, 'Search', Icons.search_rounded),
              ],
              onChanged: controller.animateTo,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SegmentedHeaderDelegate oldDelegate) =>
      controller != oldDelegate.controller;
}

/// 3-column skeleton grid (9 cover-shaped tiles) shown while a catalog
/// search is in flight — HeroUI shimmer instead of a bare spinner.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 180,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      children: List.generate(
        9,
        (_) => const HeroSkeleton(width: double.infinity, height: 180),
      ),
    );
  }
}

class _SourceGrid extends ConsumerWidget {
  const _SourceGrid({
    required this.sourceId,
    required this.label,
    required this.latest,
    required this.source,
  });

  final int sourceId;
  final String label;
  final bool latest;
  final Source source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keyed by (sourceId, latest) — the Latest tab previously watched the
    // SAME provider instance as Popular, so it rendered a duplicate of the
    // popular grid while `load(latest: true)` sat unreachable.
    final feed = ref.watch(browseFeedProvider((sourceId, latest)));

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
              ref.invalidate(browseFeedProvider((sourceId, latest))),
        ),
      );
    }

    if (feed.items.isEmpty) {
      return emptyState(
        context: context,
        icon: Icons.inbox_outlined,
        title: 'Nothing here yet',
        subtitle: 'No $label items came back from ${source.name}.',
        action: HeroButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: () =>
              ref.invalidate(browseFeedProvider((sourceId, latest))),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Infinite scroll: fetch the next page near the end of the grid.
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          ref.read(browseFeedProvider((sourceId, latest)).notifier).loadMore();
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
    // Per-source search (previously watched the merged globalSearch
    // provider, so searching ONE source returned every source's results).
    final results = _query.isEmpty
        ? const AsyncValue<List<Manga>>.data([])
        : ref.watch(sourceSearchProvider((widget.source.id, _query)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: HeroInput(
            controller: _controller,
            hint: 'Search ${widget.source.name}…',
            prefixIcon: Icons.search_rounded,
            suffix: _query.isNotEmpty
                ? HeroIconButton(
                    icon: Icons.close_rounded,
                    size: 30,
                    iconSize: 18,
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
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
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
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
            loading: () => const _GridSkeleton(),
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
            return SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
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
              ),
            );
          },
          // Cover-shaped shimmer tiles instead of a bare spinner.
          loading: () => SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => const HeroSkeleton(
                width: 110,
                height: 160,
              ),
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
