// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// ANIME HOME — the app's front page, structured like a streaming service:
//
//   * Morphing Discovery Bar (watermelon.sh) — the search button that
//     morphs open + quick category pills
//   * Auto-advancing hero carousel (top trending, swipeable, indicators)
//   * Continue Watching rail (real watch progress, resume one tap away)
//   * My List rail (the user's anime library)
//   * Trending Now / New This Season / Top 10 (numbered) / All-Time
//     Popular / Coming Soon rails (AniList GraphQL)
//
//   NOTE: genre browsing lives in ONE place — the browse screen's
//   Quick Option Picker filter bar (reached via the Discovery Bar and
//   every row's See-all). The old duplicated genre chip-wall at the
//   bottom of this page was removed.
//
// Accent note: this screen deliberately uses Netflix crimson (#E50914)
// for its primary actions — everywhere else the app stays Lumina Noir.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/lumina_ui.dart';
import '../../core/ui/watermelon.dart';
import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/anilist.dart';
import '../shared/widgets.dart' show showSnack, BookCover;

const Color kNetflixRed = Color(0xFFE50914);

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _anilistProvider = Provider<AniListService>((ref) {
  final svc = ref.watch(aniListServiceProvider);
  return svc;
});

final animeTrendingProvider = FutureProvider.autoDispose<List<AniListAnime>>(
    (ref) => ref.watch(_anilistProvider).trending());

final animeSeasonalProvider = FutureProvider.autoDispose<List<AniListAnime>>(
    (ref) => ref.watch(_anilistProvider).seasonal());

final animeTopProvider = FutureProvider.autoDispose<List<AniListAnime>>(
    (ref) => ref.watch(_anilistProvider).topRated());

final animePopularProvider = FutureProvider.autoDispose<List<AniListAnime>>(
    (ref) => ref.watch(_anilistProvider).popular());

final animeUpcomingProvider = FutureProvider.autoDispose<List<AniListAnime>>(
    (ref) => ref.watch(_anilistProvider).upcoming());

/// One Continue-Watching card: library entry + latest watch progress.
class ContinueWatchingItem {
  const ContinueWatchingItem({
    required this.manga,
    required this.episodeName,
    required this.progress,
    required this.lastWatchedAt,
  });

  final Manga manga;
  final String episodeName;
  final double progress;
  final DateTime lastWatchedAt;
}

/// Continue Watching = the newest history row per anime, resolved against
/// the library for covers/titles. Watches history so the rail updates the
/// moment a watch session lands.
final continueWatchingProvider =
    StreamProvider.autoDispose<List<ContinueWatchingItem>>((ref) async* {
  final repo = ref.watch(data.historyRepositoryProvider);
  final library = ref.watch(data.libraryRepositoryProvider);

  Future<List<ContinueWatchingItem>> load() async {
    final history = await repo.getHistory();
    final latestByManga = <int, HistoryEntry>{};
    for (final hh in history) {
      if (!hh.isAnime) continue;
      final id = hh.mangaId;
      final existing = latestByManga[id];
      if (existing == null || hh.readAt.isAfter(existing.readAt)) {
        latestByManga[id] = hh;
      }
    }
    final out = <ContinueWatchingItem>[];
    for (final entry in latestByManga.values) {
      final manga = await library.getManga(entry.mangaId);
      if (manga == null) continue;
      out.add(ContinueWatchingItem(
        manga: manga,
        episodeName: entry.chapterName,
        progress: entry.progress,
        lastWatchedAt: entry.readAt,
      ));
    }
    out.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return out.take(12).toList();
  }

  yield await load();
  await for (final _ in repo.watchHistory()) {
    yield await load();
  }
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AnimeHomeScreen extends ConsumerStatefulWidget {
  const AnimeHomeScreen({super.key});

  @override
  ConsumerState<AnimeHomeScreen> createState() => _AnimeHomeScreenState();
}

class _AnimeHomeScreenState extends ConsumerState<AnimeHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final trending = ref.watch(animeTrendingProvider);

    // Full-feed outage: the hero error card carries the message, rows
    // collapse instead of stacking five redundant error captions.
    final feedDown = trending.hasError;

    return Scaffold(
      backgroundColor: h.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              automaticallyImplyLeading: false,
              title: Text(
                'Anime',
                style: HeroTokens.display.copyWith(color: h.foreground),
              ),
            ),
            // Morphing Discovery Bar — the search button (watermelon.sh):
            // collapsed = search pill + quick category pills; expanded =
            // morphs into a live search field with predictive completions
            // + a close circle.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: WmDiscoveryBar(
                  accent: kNetflixRed,
                  searchHint: 'Search anime…',
                  suggestionDictionary: [
                    ...AniListService.genres.map((g) => g.toLowerCase()),
                    ...const [
                      'adventure', 'action', 'comedy', 'romance', 'isekai',
                      'school', 'shounen', 'shoujo', 'seinen', 'slice',
                      'supernatural', 'sports', 'mecha', 'music', 'mystery',
                    ],
                  ],
                  onSearch: (q) => context.push(
                      '/animeBrowse?search=${Uri.encodeComponent(q)}'),
                  categories: [
                    WmDiscoveryCategory(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Trending',
                      onTap: () => context.push('/animeBrowse?row=Trending'),
                    ),
                    WmDiscoveryCategory(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Top 10',
                      onTap: () => context.push('/animeBrowse?row=Top 10'),
                    ),
                    WmDiscoveryCategory(
                      icon: Icons.movie_rounded,
                      label: 'Movies',
                      onTap: () => context
                          .push('/animeBrowse?row=Movies&format=MOVIE'),
                    ),
                    WmDiscoveryCategory(
                      icon: Icons.schedule_rounded,
                      label: 'New Season',
                      onTap: () =>
                          context.push('/animeBrowse?row=New This Season'),
                    ),
                    // The ONE genre entry point — genre-name button walls
                    // were removed (redundant with the browse filter
                    // picker); this opens Browse where Genre lives in the
                    // Quick Option Picker rail.
                    WmDiscoveryCategory(
                      icon: Icons.grid_view_rounded,
                      label: 'Genres',
                      onTap: () => context.push('/animeBrowse'),
                    ),
                  ],
                ),
              ),
            ),
            // Hero carousel — top trending, auto-advancing + swipeable.
            trending.when(
              data: (items) => items.isEmpty
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : SliverToBoxAdapter(child: _HeroCarousel(anime: items)),
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: HeroSkeleton(height: 220),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: _HeroError(message: e.toString()),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            // Continue Watching
            const _ContinueWatchingSection(),
            // My List
            const _MyListSection(),
            // Discovery rows
            _AniListRow(
              title: 'Trending Now',
              provider: animeTrendingProvider,
            ),
            _AniListRow(
              title: 'New This Season',
              provider: animeSeasonalProvider,
              hideOnError: feedDown,
            ),
            _AniListRow(
              title: 'Top 10 Anime',
              provider: animeTopProvider,
              numbered: true,
              hideOnError: feedDown,
            ),
            _AniListRow(
              title: 'All-Time Popular',
              provider: animePopularProvider,
              hideOnError: feedDown,
            ),
            // Coming Soon rail — genres live in the browse filter picker
            // now; the redundant genre-name chip wall is gone.
            _AniListRow(
              title: 'Coming Soon',
              provider: animeUpcomingProvider,
              hideOnError: feedDown,
            ),
            const SliverToBoxAdapter(
                child: SizedBox(height: kBottomNavigationBarHeight + 32)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero carousel (watermelon.sh carousel-slider pattern: auto-advance,
// swipe, animated indicators; parallax on the backdrop)
// ---------------------------------------------------------------------------

class _HeroCarousel extends ConsumerStatefulWidget {
  const _HeroCarousel({required this.anime});

  final List<AniListAnime> anime;

  @override
  ConsumerState<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends ConsumerState<_HeroCarousel> {
  final _page = PageController(viewportFraction: 0.92);
  Timer? _auto;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startAuto();
  }

  void _startAuto() {
    _auto?.cancel();
    if (!heroAnimationsEnabled) return;
    _auto = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || widget.anime.length < 2) return;
      final next = (_index + 1) % widget.anime.length;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final shows = widget.anime.take(5).toList();

    return Column(
      children: [
        SizedBox(
          height: 236,
          child: PageView.builder(
            controller: _page,
            itemCount: shows.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final anime = shows[i];
              final active = i == _index;
              return AnimatedScale(
                scale: heroAnimationsEnabled ? (active ? 1.0 : 0.94) : 1.0,
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                child: _HeroCard(anime: anime, rank: i + 1),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Animated indicator dots (current = stretched + Netflix red).
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < shows.length; i++)
              AnimatedContainer(
                duration: heroAnimationsEnabled
                    ? const Duration(milliseconds: 260)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _index ? kNetflixRed : h.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.anime, required this.rank});

  final AniListAnime anime;
  final int rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: HeroScaleTap(
        onTap: () => openAniListEntry(context, ref, anime),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (anime.bannerUrl != null || anime.coverUrl != null)
                Image.network(
                  anime.bannerUrl ?? anime.coverUrl!,
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, wasSync) => wasSync
                      ? child
                      : AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 280),
                          child: child,
                        ),
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1C1C1E)),
                )
              else
                const ColoredBox(color: Color(0xFF1C1C1E)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.45, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text(
                      rank == 1
                          ? '#1 IN TRENDING TODAY'
                          : 'TRENDING #$rank TODAY',
                      style: const TextStyle(
                        fontFamily: HeroTokens.fontSans,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: kNetflixRed,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      anime.bestTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.display.copyWith(
                        color: Colors.white,
                        fontSize: 24,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _metaLine(),
                      style: TextStyle(
                        fontFamily: HeroTokens.fontSans,
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _HeroAction(
                          onTap: () => openAniListEntry(context, ref, anime),
                          icon: Icons.play_arrow_rounded,
                          label: 'Play',
                          filled: true,
                        ),
                        const SizedBox(width: 8),
                        _HeroAction(
                          onTap: () => openAniListEntry(context, ref, anime),
                          icon: Icons.info_outline_rounded,
                          label: 'Info',
                          filled: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaLine() {
    final parts = <String>[
      if (anime.averageScore != null) '★ ${anime.averageScore}%',
      if (anime.format != null) anime.format!,
      if (anime.seasonYear != null) '${anime.seasonYear}',
      if (anime.episodes != null) '${anime.episodes} eps',
    ];
    return parts.join('  •  ');
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction(
      {required this.onTap,
      required this.icon,
      required this.label,
      required this.filled});

  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return HeroScaleTap(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: filled ? kNetflixRed : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(HeroTokens.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: HeroTokens.fontSans,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroError extends ConsumerWidget {
  const _HeroError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: h.surface,
          borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 30, color: h.muted),
              const SizedBox(height: 10),
              Text(
                'AniList is unreachable',
                style: HeroTokens.body.copyWith(
                    color: h.foreground, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Check your connection and try again.',
                style: HeroTokens.caption.copyWith(color: h.muted),
              ),
              const SizedBox(height: 12),
              HeroButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                size: HeroButtonSize.sm,
                onPressed: () => ref.refresh(animeTrendingProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

class _RowHeader extends StatelessWidget {
  const _RowHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: HeroTokens.title.copyWith(
                color: h.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onSeeAll != null)
            HeroIconButton(
              tooltip: 'See all',
              icon: Icons.chevron_right_rounded,
              size: 34,
              iconSize: 22,
              onPressed: onSeeAll,
            ),
        ],
      ),
    );
  }
}

class _ContinueWatchingSection extends ConsumerWidget {
  const _ContinueWatchingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider).value ?? const [];
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(
            child: _RowHeader(title: 'Continue Watching')),
        SliverToBoxAdapter(
          child: HeroFadedRail(
            height: 168,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _ContinueCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item});

  final ContinueWatchingItem item;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final m = item.manga;
    return HeroScaleTap(
      onTap: () => context.push('/animeDetail/${m.id}'),
      child: SizedBox(
        width: 232,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 232,
              height: 118,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
                color: h.surface2,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if ((m.thumbnailUrl ?? '').isNotEmpty)
                    Image.network(m.thumbnailUrl!,
                        fit: BoxFit.cover,
                        frameBuilder: (context, child, frame, wasSync) => wasSync
                            ? child
                            : AnimatedOpacity(
                                opacity: frame == null ? 0 : 1,
                                duration: const Duration(milliseconds: 260),
                                child: child,
                              ),
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink()),
                  Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      child: LinearProgressIndicator(
                        value: item.progress.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        valueColor:
                            const AlwaysStoppedAnimation(kNetflixRed),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              m.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HeroTokens.body.copyWith(
                  color: h.foreground, fontWeight: FontWeight.w600),
            ),
            Text(
              item.episodeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HeroTokens.caption.copyWith(color: h.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyListSection extends ConsumerWidget {
  const _MyListSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(animeLibraryProvider);
    if (list.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _RowHeader(
            title: 'My List',
            onSeeAll: () => context.push('/animeLibrary'),
          ),
        ),
        SliverToBoxAdapter(
          child: HeroFadedRail(
            height: 208,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => BookCover(
              manga: list[i],
              width: 120,
              onTap: () => context.push('/animeDetail/${list[i].id}'),
            ),
          ),
        ),
      ],
    );
  }
}

class _AniListRow extends ConsumerWidget {
  const _AniListRow({
    required this.title,
    required this.provider,
    this.numbered = false,
    this.hideOnError = false,
  });

  final String title;
  final AutoDisposeFutureProvider<List<AniListAnime>> provider;
  final bool numbered;

  /// When the whole AniList feed is down (hero errored), rows collapse
  /// silently instead of stacking redundant error captions — the hero
  /// error card carries the message + retry.
  final bool hideOnError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final items = ref.watch(provider);
    if (hideOnError && items.hasError) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _RowHeader(
            title: title,
            onSeeAll: () => context.push(
                '/animeBrowse?row=${Uri.encodeComponent(title)}'),
          ),
        ),
        items.when(
          data: (list) => SliverToBoxAdapter(
            child: HeroFadedRail(
              height: 214,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final anime = list[i];
                return numbered
                    ? _NumberedCard(rank: i + 1, anime: anime)
                    : _PosterCard(anime: anime);
              },
            ),
          ),
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  HeroSkeleton(width: 118, height: 170),
                  SizedBox(width: 10),
                  HeroSkeleton(width: 118, height: 170),
                  SizedBox(width: 10),
                  HeroSkeleton(width: 118, height: 170),
                ],
              ),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Could not load — check your connection.',
                style: HeroTokens.caption.copyWith(color: h.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standard portrait poster card: cover with fade-in, score badge, two-line
/// title + muted meta line (format · year).
class _PosterCard extends ConsumerWidget {
  const _PosterCard({required this.anime});

  final AniListAnime anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return HeroScaleTap(
      onTap: () => openAniListEntry(context, ref, anime),
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 118,
              height: 160,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
                color: h.surface2,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  (anime.coverUrl ?? '').isNotEmpty
                      ? Image.network(anime.coverUrl!,
                          fit: BoxFit.cover,
                          frameBuilder: (context, child, frame, wasSync) => wasSync
                              ? child
                              : AnimatedOpacity(
                                  opacity: frame == null ? 0 : 1,
                                  duration: const Duration(milliseconds: 260),
                                  child: child,
                                ),
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink())
                      : const SizedBox.shrink(),
                  // Score badge (bottom-left, over the gradient).
                  if (anime.averageScore != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.0),
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 12, color: Colors.amber),
                              const SizedBox(width: 3),
                              Text(
                                '${anime.averageScore}%',
                                style: const TextStyle(
                                  fontFamily: HeroTokens.fontSans,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
            if (anime.seasonYear != null)
              Text(
                [
                  if (anime.format != null) anime.format!,
                  '${anime.seasonYear}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HeroTokens.caption.copyWith(
                  color: h.muted,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Netflix-style Top-10 card: the SAME poster card as every other rail
/// (consistent sizing), with a compact rank badge fused to the poster's
/// top-left — the Netflix "TOP 10" badge grammar. The previous design
/// (a 96px outlined numeral behind an offset poster) overflowed its rail,
/// misaligned titles and read as noise.
class _NumberedCard extends ConsumerWidget {
  const _NumberedCard({required this.rank, required this.anime});

  final int rank;
  final AniListAnime anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return HeroScaleTap(
      onTap: () => openAniListEntry(context, ref, anime),
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  width: 118,
                  height: 160,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
                    color: h.surface2,
                  ),
                  child: (anime.coverUrl ?? '').isNotEmpty
                      ? Image.network(anime.coverUrl!,
                          fit: BoxFit.cover,
                          frameBuilder:
                              (context, child, frame, wasSync) => wasSync
                                  ? child
                                  : AnimatedOpacity(
                                      opacity: frame == null ? 0 : 1,
                                      duration:
                                          const Duration(milliseconds: 260),
                                      child: child,
                                    ),
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink())
                      : const SizedBox.shrink(),
                ),
                // Rank badge — a small crimson tab fused to the top-left
                // corner (rank number + TOP 10 eyebrow).
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      color: kNetflixRed,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '$rank',
                          style: const TextStyle(
                            fontFamily: HeroTokens.fontSans,
                            fontSize: 15,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'TOP 10',
                          style: TextStyle(
                            fontFamily: HeroTokens.fontSans,
                            fontSize: 8,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
            if (anime.seasonYear != null)
              Text(
                [
                  if (anime.format != null) anime.format!,
                  '${anime.seasonYear}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HeroTokens.caption.copyWith(
                  color: h.muted,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared routing helper
// ---------------------------------------------------------------------------

/// Opens an AniList catalog entry through the streaming pipeline: routes to
/// the source-anime preview with the seeded AniList provider, carrying the
/// `anilist:<id>` identity tag so AniSkip + calendar cross-links resolve.
void openAniListEntry(
    BuildContext context, WidgetRef ref, AniListAnime anime) {
  final sources = ref.read(sourcesProvider);
  int? sourceId;
  for (final s in sources) {
    if (!s.isInstalled) continue;
    final hay = '${s.baseUrl} ${s.idString ?? ''} ${s.typeSource ?? ''}'
        .toLowerCase();
    if (hay.contains('anilist') || hay.contains('anizone')) {
      sourceId = s.id;
      break;
    }
  }
  if (sourceId == null) {
    showSnack(ref, context,
        'No anime source installed — install one from Explore.');
    return;
  }
  final dto = Manga(
    id: 0,
    title: anime.bestTitle,
    sourceId: sourceId,
    url: 'anilist:${anime.id}',
    itemType: ItemType.anime,
    thumbnailUrl: anime.coverUrl,
    description: anime.description,
    genre: [
      ...anime.genres,
      'anilist:${anime.id}',
      if (anime.idMal != null) 'mal:${anime.idMal}',
    ],
  );
  GoRouter.of(context).push('/sourceMangaDetail', extra: dto);
}
