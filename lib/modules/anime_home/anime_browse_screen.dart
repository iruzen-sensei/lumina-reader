// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// ANIME BROWSE — the Netflix-style catalog explorer: a filter bar (genre,
// year, season, format, status, sort), AniList search, and an infinite
// paginated grid. Reached from the Anime home (rows' See all / genre
// chips / search / filter icon).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/lumina_ui.dart';
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
  });

  final String? initialSearch;
  final String? initialGenre;
  final String? initialRow;

  @override
  ConsumerState<AnimeBrowseScreen> createState() => _AnimeBrowseScreenState();
}

class _AnimeBrowseScreenState extends ConsumerState<AnimeBrowseScreen> {
  late final AnimeBrowseFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = AnimeBrowseFilters(
      search: widget.initialSearch,
      genre: widget.initialGenre,
      sort: switch (widget.initialRow) {
        'Top 10 Anime' => 'SCORE_DESC',
        'All-Time Popular' => 'POPULARITY_DESC',
        'New This Season' => 'POPULARITY_DESC',
        'Coming Soon' => 'POPULARITY_DESC',
        _ => 'TRENDING_DESC',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final results = ref.watch(animeBrowseProvider(_filters));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title(),
          style: HeroTokens.title.copyWith(color: h.foreground),
        ),
        actions: [
          HeroIconButton(
            tooltip: 'Filters',
            icon: Icons.tune_rounded,
            onPressed: () => _openFilterSheet(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(filters: _filters, onChanged: _setFilters),
          Expanded(
            child: results.when(
              data: (items) => items.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing matches these filters.',
                        style:
                            HeroTokens.bodySmall.copyWith(color: h.muted),
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
    );
  }

  String _title() {
    if (_filters.search?.isNotEmpty == true) return '“${_filters.search}”';
    if (_filters.genre != null) return _filters.genre!;
    if (widget.initialRow != null) return widget.initialRow!;
    return 'Browse Anime';
  }

  void _setFilters(AnimeBrowseFilters f) => setState(() => _filters = f);

  void _openFilterSheet(BuildContext context) {
    showHeroSheet<void>(
      context: context,
      isScrollControlled: true,
      title: 'Filters',
      builder: (sheetContext) => _FilterSheet(
        filters: _filters,
        onChanged: (f) {
          _setFilters(f);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick filter chips bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filters, required this.onChanged});

  final AnimeBrowseFilters filters;
  final ValueChanged<AnimeBrowseFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    const seasons = [
      ('WINTER', 'Winter'),
      ('SPRING', 'Spring'),
      ('SUMMER', 'Summer'),
      ('FALL', 'Fall'),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(context, 'All', filters.genre == null,
              () => onChanged(filters.copyWith(clearGenre: true))),
          for (final g in AniListService.genres.take(10))
            _chip(context, g, filters.genre == g,
                () => onChanged(filters.copyWith(genre: g))),
          const SizedBox(width: 8),
          for (final (code, label) in seasons)
            _chip(
                context,
                '$label ${DateTime.now().year}',
                filters.season == code &&
                    filters.year == DateTime.now().year,
                () => onChanged(filters.copyWith(
                    season: code, year: DateTime.now().year))),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected,
      VoidCallback onTap) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        backgroundColor: selected ? kNetflixRed : h.surface,
        labelStyle: TextStyle(
          fontFamily: HeroTokens.fontSans,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? Colors.white : h.muted,
        ),
        side: BorderSide(
            color: selected ? kNetflixRed : h.border,
            width: selected ? 1.4 : 1),
        onPressed: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full filter sheet
// ---------------------------------------------------------------------------

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.filters, required this.onChanged});

  final AnimeBrowseFilters filters;
  final ValueChanged<AnimeBrowseFilters> onChanged;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late AnimeBrowseFilters _f;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _f = widget.filters;
    _searchController =
        TextEditingController(text: widget.filters.search ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroInput(
            controller: _searchController,
            hint: 'Search titles…',
            prefixIcon: Icons.search_rounded,
          ),
          const SizedBox(height: 16),
          _group('Sort', [
            for (final e in AniListService.sortOptions.entries)
              _option(e.key, _f.sort == e.value,
                  () => setState(() => _f = _f.copyWith(sort: e.value))),
          ]),
          _group('Genre', [
            _option('Any', _f.genre == null,
                () => setState(() => _f = _f.copyWith(clearGenre: true))),
            for (final g in AniListService.genres)
              _option(g, _f.genre == g,
                  () => setState(() => _f = _f.copyWith(genre: g))),
          ]),
          _group('Format', [
            _option('Any', _f.format == null,
                () => setState(() => _f = _f.copyWith(clearFormat: true))),
            for (final e in AniListService.formatOptions.entries)
              _option(e.key, _f.format == e.value,
                  () => setState(() => _f = _f.copyWith(format: e.value))),
          ]),
          _group('Status', [
            _option('Any', _f.status == null,
                () => setState(() => _f = _f.copyWith(clearStatus: true))),
            for (final e in AniListService.statusOptions.entries)
              _option(e.key, _f.status == e.value,
                  () => setState(() => _f = _f.copyWith(status: e.value))),
          ]),
          _group('Season', [
            _option('Any', _f.season == null && _f.year == null,
                () => setState(() => _f = _f.copyWith(clearSeason: true, clearYear: true))),
            for (final (code, label) in const [
              ('WINTER', 'Winter'),
              ('SPRING', 'Spring'),
              ('SUMMER', 'Summer'),
              ('FALL', 'Fall'),
            ])
              for (final year in [
                DateTime.now().year,
                DateTime.now().year - 1,
              ])
                _option(
                    '$label $year',
                    _f.season == code && _f.year == year,
                    () => setState(
                        () => _f = _f.copyWith(season: code, year: year))),
          ]),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HeroButton(
                label: 'Reset',
                variant: HeroButtonVariant.light,
                color: HeroColorRole.neutral,
                onPressed: () => setState(() {
                  _searchController.clear();
                  _f = const AnimeBrowseFilters();
                }),
              ),
              const SizedBox(width: 12),
              HeroButton(
                label: 'Apply',
                icon: Icons.check_rounded,
                onPressed: () => widget.onChanged(_f.copyWith(
                    search: _searchController.text.trim().isEmpty
                        ? null
                        : _searchController.text.trim())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> chips) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: HeroTokens.fontSans,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: h.muted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _option(String label, bool selected, VoidCallback onTap) {
    final h = HeroScope.of(context);
    return ActionChip(
      label: Text(label),
      backgroundColor: selected ? kNetflixRed : h.surface,
      labelStyle: TextStyle(
        fontFamily: HeroTokens.fontSans,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: selected ? Colors.white : h.muted,
      ),
      side:
          BorderSide(color: selected ? kNetflixRed : h.border, width: selected ? 1.4 : 1),
      onPressed: onTap,
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
