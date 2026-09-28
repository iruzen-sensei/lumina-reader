// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// ANIME BROWSE — the Netflix-style catalog explorer.
//
// ONE filter surface: the Quick Option Picker rail (Genre / Season /
// Format / Status / Sort — tap a pill, pick from the tray that pops
// above). The old tune-icon FilterSheet duplicated every one of these
// controls as a second chip wall — removed wholesale.
//
// Search lives in the Morphing Discovery Bar (watermelon.sh) in the
// header: tap the pill, it morphs full-width, predictive chips complete
// genre/term words, enter applies the search as a filter (shown as a
// dismissible chip in the rail).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/lumina_ui.dart';
import '../../core/ui/watermelon.dart';
import '../../providers/providers.dart';
import '../../services/anilist.dart';
import '../anime_home/anime_home_screen.dart'
    show openAniListEntry, kNetflixRed;

/// Filter state for the browse screen.
class AnimeBrowseFilters {
  const AnimeBrowseFilters({
    this.search,
    this.genre,
    this.year,
    this.season,
    this.format,
    this.status,
    this.sort = 'TRENDING_DESC',
  });

  final String? search;
  final String? genre;
  final int? year;
  final String? season; // WINTER/SPRING/SUMMER/FALL
  final String? format;
  final String? status;
  final String sort;

  bool get isDefault =>
      (search == null || search!.isEmpty) &&
      genre == null &&
      year == null &&
      season == null &&
      format == null &&
      status == null;

  AnimeBrowseFilters copyWith({
    String? search,
    bool clearSearch = false,
    String? genre,
    bool clearGenre = false,
    int? year,
    bool clearYear = false,
    String? season,
    bool clearSeason = false,
    String? format,
    bool clearFormat = false,
    String? status,
    bool clearStatus = false,
    String? sort,
  }) =>
      AnimeBrowseFilters(
        search: clearSearch ? null : (search ?? this.search),
        genre: clearGenre ? null : (genre ?? this.genre),
        year: clearYear ? null : (year ?? this.year),
        season: clearSeason ? null : (season ?? this.season),
        format: clearFormat ? null : (format ?? this.format),
        status: clearStatus ? null : (status ?? this.status),
        sort: sort ?? this.sort,
      );

  /// Value-equality: the family provider re-keys on this, so filter
  /// changes must produce a non-equal instance AND identical filter sets
  /// must stay equal (prevents redundant reloads).
  @override
  bool operator ==(Object other) =>
      other is AnimeBrowseFilters &&
      other.search == search &&
      other.genre == genre &&
      other.year == year &&
      other.season == season &&
      other.format == format &&
      other.status == status &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
      search, genre, year, season, format, status, sort);
}

/// Paginated browse results for the active filters.
class AnimeBrowseNotifier
    extends StateNotifier<AsyncValue<List<AniListAnime>>> {
  AnimeBrowseNotifier(this._filters, this._anilist)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final AnimeBrowseFilters _filters;
  final AniListService _anilist;

  int _page = 1;
  bool _hasMore = true;
  List<AniListAnime> _items = [];

  Future<void> _load() async {
    state = const AsyncValue.loading();
    _page = 1;
    try {
      final list = await _fetch(_page);
      _items = list;
      _hasMore = list.length >= AniListService.perPage;
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<List<AniListAnime>> _fetch(int page) => _anilist.browse(
        page: page,
        search: _filters.search,
        genre: _filters.genre,
        year: _filters.year,
        season: _filters.season,
        format: _filters.format,
        status: _filters.status,
        sort: _filters.sort,
      );

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !_hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      _page++;
      final next = await _fetch(_page);
      _hasMore = next.length >= AniListService.perPage;
      _items = [..._items, ...next];
      state = AsyncValue.data(_items);
    } catch (_) {
      _page--; // failed page — retry next time
    } finally {
      _loadingMore = false;
    }
  }

  bool _loadingMore = false;
}

final animeBrowseFiltersProvider =
    StateProvider<AnimeBrowseFilters>((ref) => const AnimeBrowseFilters());

final animeBrowseProvider = StateNotifierProvider.autoDispose
    .family<AnimeBrowseNotifier, AsyncValue<List<AniListAnime>>,
        AnimeBrowseFilters>((ref, filters) {
  return AnimeBrowseNotifier(
      filters, ref.watch(aniListServiceProvider));
});

class AnimeBrowseScreen extends ConsumerStatefulWidget {
  const AnimeBrowseScreen({
    super.key,
    this.initialSearch,
    this.initialGenre,
    this.initialRow,
    this.initialFormat,
  });

  final String? initialSearch;
  final String? initialGenre;
  final String? initialRow;
  final String? initialFormat;

  @override
  ConsumerState<AnimeBrowseScreen> createState() => _AnimeBrowseScreenState();
}

class _AnimeBrowseScreenState extends ConsumerState<AnimeBrowseScreen> {
  // NOTE: NOT `late final` — the filter state is reassigned on every chip
  // tap. The previous `late final` threw LateInitializationError on the
  // FIRST filter change, which surfaced as "the filter buttons are just
  // for show" (the zone handler swallowed it and the UI never updated).
  late AnimeBrowseFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = AnimeBrowseFilters(
      search: widget.initialSearch,
      genre: widget.initialGenre,
      format: widget.initialFormat,
      sort: switch (widget.initialRow) {
        'Top 10 Anime' => 'SCORE_DESC',
        'All-Time Popular' => 'POPULARITY_DESC',
        'New This Season' => 'POPULARITY_DESC',
        'Coming Soon' => 'POPULARITY_DESC',
        'Movies' => 'POPULARITY_DESC',
        _ => 'TRENDING_DESC',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final results = ref.watch(animeBrowseProvider(_filters));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Header: back + the Morphing Discovery Bar (search) ----
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
              child: Row(
                children: [
                  HeroIconButton(
                    tooltip: 'Back',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: WmDiscoveryBar(
                      accent: kNetflixRed,
                      searchHint: 'Search anime…',
                      categories: const [],
                      suggestionDictionary: [
                        ...AniListService.genres.map((g) => g.toLowerCase()),
                        ...const [
                          'adventure', 'action', 'comedy', 'romance',
                          'isekai', 'school', 'shounen', 'shoujo', 'seinen',
                          'slice', 'supernatural', 'sports', 'mecha', 'music',
                          'mystery',
                        ],
                      ],
                      onSearch: (q) => _setFilters(
                          _filters.copyWith(search: q, clearSearch: false)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text(
                _title(),
                style: HeroTokens.title.copyWith(
                  color: h.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ---- THE filter surface: Quick Option Picker rail ----
            _FilterRail(filters: _filters, onChanged: _setFilters),
            const SizedBox(height: 4),
            Expanded(
              child: results.when(
                data: (items) => items.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing matches these filters.',
                          style: HeroTokens.bodySmall
                              .copyWith(color: h.muted),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >
                              n.metrics.maxScrollExtent - 600) {
                            ref
                                .read(animeBrowseProvider(_filters).notifier)
                                .loadMore();
                          }
                          return false;
                        },
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              16, 12, 16, kBottomNavigationBarHeight + 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 130,
                            childAspectRatio: 0.58,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _BrowseCard(
                              anime: items[i],
                              showScore: _filters.sort == 'SCORE_DESC'),
                        ),
                      ),
                loading: () => GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: 12,
                  itemBuilder: (_, __) =>
                      const HeroSkeleton(height: 220),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('AniList is unreachable.',
                          style: HeroTokens.body
                              .copyWith(color: h.foreground)),
                      const SizedBox(height: 8),
                      HeroButton(
                        label: 'Retry',
                        icon: Icons.refresh_rounded,
                        onPressed: () =>
                            setState(() => _filters = _filters.copyWith()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title() {
    if (_filters.search?.isNotEmpty == true) return '“${_filters.search}”';
    if (_filters.genre != null) return _filters.genre!;
    if (widget.initialRow != null) return widget.initialRow!;
    return 'Browse Anime';
  }

  void _setFilters(AnimeBrowseFilters f) => setState(() => _filters = f);
}

// ---------------------------------------------------------------------------
// Filter rail — watermelon.sh Quick Option Pickers: compact pills
// (Genre / Season / Format / Status / Sort) that pop a tray of options
// above with a 3D bottom-origin tilt. ONE filter surface — the old
// tune-icon FilterSheet duplicated all of this and is gone.
//
// An active search shows as a dismissible chip at the head of the rail.
// ---------------------------------------------------------------------------

class _FilterRail extends StatelessWidget {
  const _FilterRail({required this.filters, required this.onChanged});

  final AnimeBrowseFilters filters;
  final ValueChanged<AnimeBrowseFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final now = DateTime.now();
    final seasonOptions = <WmPickerOption<(String, int)>>[
      WmPickerOption(
          value: ('WINTER', now.year), label: 'Winter ${now.year}'),
      WmPickerOption(
          value: ('SPRING', now.year), label: 'Spring ${now.year}'),
      WmPickerOption(value: ('SUMMER', now.year), label: 'Summer ${now.year}'),
      WmPickerOption(value: ('FALL', now.year), label: 'Fall ${now.year}'),
      WmPickerOption(
          value: ('WINTER', now.year - 1), label: 'Winter ${now.year - 1}'),
      WmPickerOption(
          value: ('SPRING', now.year - 1), label: 'Spring ${now.year - 1}'),
      WmPickerOption(
          value: ('SUMMER', now.year - 1), label: 'Summer ${now.year - 1}'),
      WmPickerOption(value: ('FALL', now.year - 1), label: 'Fall ${now.year - 1}'),
    ];
    final currentSeason = (filters.season == null || filters.year == null)
        ? null
        : (filters.season!, filters.year!);

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          // Active search — dismissible chip (the only search UI here).
          if (filters.search?.isNotEmpty == true) ...[
            _ActiveFilterChip(
              label: filters.search!,
              icon: Icons.search_rounded,
              onClear: () =>
                  onChanged(filters.copyWith(clearSearch: true)),
            ),
            const SizedBox(width: 8),
          ],
          WmQuickOptionPicker<String>(
            hint: 'Genre',
            trayAbove: false,
            value: filters.genre ?? '',
            options: [
              const WmPickerOption(value: '', label: 'All genres', icon: Icons.apps_rounded),
              for (final g in AniListService.genres)
                WmPickerOption(value: g, label: g),
            ],
            onChanged: (v) => onChanged(
                v.isEmpty ? filters.copyWith(clearGenre: true) : filters.copyWith(genre: v)),
          ),
          const SizedBox(width: 8),
          WmQuickOptionPicker<(String, int)>(
            hint: 'Season',
            trayAbove: false,
            value: currentSeason ?? ('', 0),
            options: [
              const WmPickerOption(value: ('', 0), label: 'Any season', icon: Icons.calendar_today_rounded),
              ...seasonOptions,
            ],
            onChanged: (v) => onChanged(v.$1.isEmpty
                ? filters.copyWith(clearSeason: true, clearYear: true)
                : filters.copyWith(season: v.$1, year: v.$2)),
          ),
          const SizedBox(width: 8),
          WmQuickOptionPicker<String>(
            hint: 'Format',
            trayAbove: false,
            value: filters.format ?? '',
            options: [
              const WmPickerOption(value: '', label: 'Any format', icon: Icons.category_rounded),
              for (final e in AniListService.formatOptions.entries)
                WmPickerOption(value: e.value, label: e.key),
            ],
            onChanged: (v) => onChanged(
                v.isEmpty ? filters.copyWith(clearFormat: true) : filters.copyWith(format: v)),
          ),
          const SizedBox(width: 8),
          WmQuickOptionPicker<String>(
            hint: 'Status',
            trayAbove: false,
            value: filters.status ?? '',
            options: [
              const WmPickerOption(value: '', label: 'Any status', icon: Icons.flag_rounded),
              for (final e in AniListService.statusOptions.entries)
                WmPickerOption(value: e.value, label: e.key),
            ],
            onChanged: (v) => onChanged(
                v.isEmpty ? filters.copyWith(clearStatus: true) : filters.copyWith(status: v)),
          ),
          const SizedBox(width: 8),
          WmQuickOptionPicker<String>(
            hint: 'Sort',
            trayAbove: false,
            value: filters.sort,
            options: [
              for (final e in AniListService.sortOptions.entries)
                WmPickerOption(
                    value: e.value,
                    label: e.key,
                    icon: e.value == 'SCORE_DESC'
                        ? Icons.star_rounded
                        : e.value == 'TRENDING_DESC'
                            ? Icons.local_fire_department_rounded
                            : Icons.sort_rounded),
            ],
            onChanged: (v) => onChanged(filters.copyWith(sort: v)),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// A filter value currently applied — tap the ✕ to clear it.
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    required this.label,
    required this.icon,
    required this.onClear,
  });

  final String label;
  final IconData icon;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return GestureDetector(
      onTap: onClear,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kNetflixRed.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
          border: Border.all(color: kNetflixRed.withValues(alpha: 0.6), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kNetflixRed),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HeroTokens.caption.copyWith(
                  color: h.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.close_rounded, size: 13, color: h.muted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid card
// ---------------------------------------------------------------------------

class _BrowseCard extends ConsumerWidget {
  const _BrowseCard({required this.anime, this.showScore = false});

  final AniListAnime anime;
  final bool showScore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return HeroScaleTap(
      onTap: () => openAniListEntry(context, ref, anime),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
                color: h.surface,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  (anime.coverUrl ?? '').isNotEmpty
                      ? Image.network(anime.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink())
                      : const SizedBox.shrink(),
                  if (showScore && anime.averageScore != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${anime.averageScore}%',
                          style: const TextStyle(
                            fontFamily: HeroTokens.fontSans,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            anime.bestTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: HeroTokens.caption.copyWith(
              color: h.foreground,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
