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
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// Preview detail for a catalog entry that is NOT yet in the library.
///
/// This screen is the missing half of the Browse flow: browse/search items
/// are in-memory DTOs with `id: 0` (nothing is persisted until the user
/// commits), so the previous "push /mangaDetail/${manga.id}" routing always
/// landed on /mangaDetail/0 → library lookup → "Not found". Tapping a cover
/// showed nothing but the error state — the "only covers, no content" bug.
///
/// The screen serves ALL THREE media types through one pipeline and adapts
/// its copy to the entry: anime entries say "Start watching" / "Episodes",
/// manga say "Start reading" / "Chapters" (the old build said "Start
/// reading" + a book icon on anime entries straight from the Netflix-style
/// home hero — the exact report that started this rewrite).
///
/// Flow implemented here (mirrors Tachiyomi / Mangayomi):
///   1. Seed the header instantly from the browse DTO (title + cover).
///   2. Fetch the authoritative detail + chapter list through
///      [sourceMangaDetailProvider] → ExtensionCoordinator.detail().
///   3. "Add to library" persists manga + chapters and continues into the
///      full detail screen (downloads, tracking, history all work from
///      the persisted id).
///   4. Tapping an episode auto-adds to library (with episodes) and opens
///      the player/reader with the PERSISTED chapter id — deep links and
///      progress tracking only work on persisted rows.
class SourceMangaDetailScreen extends ConsumerStatefulWidget {
  const SourceMangaDetailScreen({super.key, required this.manga});

  /// The in-memory browse/search item. Null when the route was opened
  /// without `extra` (deep link / state restoration) — the screen then
  /// renders an honest error state instead of crashing.
  final Manga? manga;

  @override
  ConsumerState<SourceMangaDetailScreen> createState() =>
      _SourceMangaDetailScreenState();
}

class _SourceMangaDetailScreenState
    extends ConsumerState<SourceMangaDetailScreen> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final seed = widget.manga;
    if (seed == null || seed.url.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Details')),
        body: emptyState(
          context: context,
          icon: Icons.link_off,
          title: 'Cannot open this entry',
          subtitle: 'The catalog entry is no longer available. '
              'Go back and tap it again from Browse.',
        ),
      );
    }

    final detail = ref.watch(
        sourceMangaDetailProvider((seed.sourceId, seed.url)));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _PreviewAppBar(seed: seed, detail: detail),
          SliverToBoxAdapter(
            child: _PreviewHeader(
              seed: seed,
              detail: detail,
            ),
          ),
          detail.when(
            data: (manga) => _EpisodeSection(
              manga: manga,
              onOpen: (chapter) => _openChapter(manga, chapter),
              onRetry: () => ref.invalidate(
                  sourceMangaDetailProvider((seed.sourceId, seed.url))),
            ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: emptyState(
                context: context,
                icon: Icons.cloud_off,
                title: 'Could not load details',
                subtitle: 'The source did not respond or the site format '
                    'changed.\n${e.toString()}',
                action: FilledButton.tonalIcon(
                  onPressed: () => ref.invalidate(
                      sourceMangaDetailProvider((seed.sourceId, seed.url))),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
      bottomNavigationBar: detail.maybeWhen(
        data: (manga) => _BottomActions(
          manga: manga,
          isAnime: seed.isAnime,
          adding: _adding,
          onAddToLibrary: () => _addToLibrary(manga),
          onStart: () => _startFirst(manga),
        ),
        orElse: () => null,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  /// Persists the entry (+ chapters) and continues into the full,
  /// library-backed detail screen. pushReplacement keeps the browse screen
  /// underneath on the back stack.
  Future<void> _addToLibrary(Manga detail) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final repo = ref.read(data.libraryRepositoryProvider);
      final id = await repo.addToLibrary(
          _mergedWithSeed(detail),
          chapters: detail.chapters);
      if (!mounted) return;
      showSnack(ref, context, 'Added to library');
      // go_router's context.pushReplacement returns void (unlike
      // router.pushReplacement) — fire-and-forget navigation.
      context.pushReplacement(
          detail.isAnime ? '/animeDetail/$id' : '/mangaDetail/$id');
    } catch (e) {
      if (mounted) showSnack(ref, context, 'Could not add: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Opens an episode/chapter — the entry is auto-added to the library
  /// first so the reader receives a real chapter id (progress, history and
  /// deep links only work on persisted rows). The preview is replaced by
  /// the full detail screen under the player/reader, so back-navigation
  /// lands on the real library entry (favorite / downloads / tracking all
  /// live there).
  Future<void> _openChapter(Manga detail, Chapter chapter) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final persisted = await _ensureInLibrary(detail);
      if (persisted == null) {
        if (mounted) {
          showSnack(ref, context, 'Could not open ${_unitWord(detail)}');
        }
        return;
      }
      final persistedChapter = persisted.chapters.firstWhere(
        (c) => c.url == chapter.url,
        orElse: () => persisted.chapters.isNotEmpty
            ? persisted.chapters.first
            : chapter,
      );
      if (!mounted) return;
      // Anime catalog entries open the video player via the anime detail
      // screen; novels the text reader via the novel reader; manga the
      // image reader via the manga detail screen.
      final isNovel = persisted.itemType == ItemType.novel;
      context.pushReplacement(persisted.isAnime
          ? '/animeDetail/${persisted.id}'
          : '/mangaDetail/${persisted.id}');
      unawaited(context.push(persisted.isAnime
          ? '/animePlayer/${persistedChapter.id}'
          : isNovel
              ? '/novelReader/${persistedChapter.id}'
              : '/reader/${persistedChapter.id}'));
    } catch (e) {
      if (mounted) {
        showSnack(ref, context, 'Could not open ${_unitWord(detail)}: $e');
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// "Start watching" / "Start reading" — the FIRST unit chronologically
  /// (chapters sort newest-first in the coordinator).
  Future<void> _startFirst(Manga detail) async {
    if (detail.chapters.isEmpty) {
      showSnack(
          ref, context, 'No ${_unitWord(detail)}s available from this source');
      return;
    }
    final first = [...detail.chapters]
      ..sort((a, b) => a.number.compareTo(b.number));
    await _openChapter(detail, first.first);
  }

  String _unitWord(Manga m) => m.isAnime ? 'episode' : 'chapter';

  /// Upserts the detail into the library and returns the refreshed row
  /// (with persisted chapter ids), or null on failure.
  Future<Manga?> _ensureInLibrary(Manga detail) async {
    try {
      final repo = ref.read(data.libraryRepositoryProvider);
      final id = await repo.addToLibrary(
          _mergedWithSeed(detail),
          chapters: detail.chapters);
      return await repo.getManga(id);
    } catch (e) {
      debugPrint('SourceMangaDetail: ensureInLibrary failed: $e');
      return null;
    }
  }

  /// Defence-in-depth for the nameless-library-row bug: if the source's
  /// detail payload failed to yield a title or cover (theme variance,
  /// HTML drift), fall back to the browse-seed values so a persisted row
  /// is never blank.
  Manga _mergedWithSeed(Manga detail) {
    final seed = widget.manga;
    if (seed == null) return detail;
    final blankTitle = detail.title.trim().isEmpty && seed.title.isNotEmpty;
    final blankCover = (detail.thumbnailUrl ?? '').isEmpty &&
        (seed.thumbnailUrl ?? '').isNotEmpty;
    if (!blankTitle && !blankCover) return detail;
    return detail.copyWith(
      title: blankTitle ? seed.title : null,
      thumbnailUrl: blankCover ? seed.thumbnailUrl : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Hero app bar — cover from the browse seed (available instantly), swapped
// for the detail's cover once loaded.
// ---------------------------------------------------------------------------

class _PreviewAppBar extends StatelessWidget {
  const _PreviewAppBar({required this.seed, required this.detail});

  final Manga seed;
  final AsyncValue<Manga> detail;

  @override
  Widget build(BuildContext context) {
    final cover = detail.maybeWhen(
      data: (m) => m.thumbnailUrl,
      orElse: () => seed.thumbnailUrl,
    );
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.maybePop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image, size: 56),
                ),
              )
            else
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — cover thumb, title, author, status, source chip, synopsis
// (watermelon.sh Expand Details — same component as the full detail
// screens, so preview and library detail feel like one app).
// ---------------------------------------------------------------------------

class _PreviewHeader extends ConsumerWidget {
  const _PreviewHeader({
    required this.seed,
    required this.detail,
  });

  final Manga seed;
  final AsyncValue<Manga> detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final manga = detail.maybeWhen(
      data: (m) => m,
      orElse: () => seed,
    );
    final loading = detail.isLoading;
    final isAnime = seed.isAnime;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover thumb — 2:3 poster for anime, book crop for manga.
              ClipRRect(
                borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
                child: SizedBox(
                  width: 110,
                  height: 160,
                  child: manga.thumbnailUrl != null
                      ? Image.network(
                          manga.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: h.surface2,
                            child: Icon(
                              isAnime
                                  ? Icons.movie_outlined
                                  : Icons.menu_book,
                              size: 36,
                              color: h.muted,
                            ),
                          ),
                        )
                      : Container(
                          color: h.surface2,
                          child: Icon(
                            isAnime ? Icons.movie_outlined : Icons.menu_book,
                            size: 36,
                            color: h.muted,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      style: HeroTokens.title.copyWith(
                        color: h.foreground,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (manga.author != null && manga.author!.isNotEmpty)
                      _metaLine(
                          context, Icons.person_outline, 'by ${manga.author}'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: 18, color: h.accent),
                        const SizedBox(width: 4),
                        Text(
                          manga.status.label,
                          style: HeroTokens.bodySmall
                              .copyWith(color: h.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Source chip — makes it obvious which extension serves
                    // this entry (multi-source global search results).
                    Builder(
                      builder: (chipContext) {
                        final sources = ref.watch(sourcesProvider);
                        String name = 'Source';
                        for (final s in sources) {
                          if (s.id == seed.sourceId) {
                            name = s.name;
                            break;
                          }
                        }
                        return HeroChip(
                          label: name,
                          small: true,
                          color: HeroColorRole.neutral,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (manga.genre.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in manga.genre
                    .where((g) => !RegExp(r'^(anilist|mal):\d+$')
                        .hasMatch(g.trim()))
                    .take(8))
                  HeroChip(
                    label: tag,
                    small: true,
                    color: HeroColorRole.accent,
                  ),
              ],
            ),
          ],
          if (loading) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                inlineLoader(context, size: 16),
                const SizedBox(width: 12),
                Text(
                  'Loading details and ${isAnime ? 'episodes' : 'chapters'}…',
                  style: HeroTokens.bodySmall.copyWith(color: h.muted),
                ),
              ],
            ),
          ],
          if (manga.description != null &&
              manga.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            WmExpandDetails(
              title: 'Synopsis',
              collapsed: Text(
                _collapse(manga.description!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HeroTokens.bodySmall.copyWith(color: h.muted),
              ),
              expanded: Text(
                manga.description!.trim(),
                style:
                    HeroTokens.body.copyWith(color: h.muted, height: 1.55),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _collapse(String text) {
    final t = text.trim();
    return '${t.substring(0, t.length > 90 ? 90 : t.length)}…';
  }

  Widget _metaLine(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: HeroScope.of(context).muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HeroTokens.bodySmall
                  .copyWith(color: HeroScope.of(context).muted),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode / chapter list (preview — no per-unit download buttons until the
// entry is persisted; downloads live in the full detail screen).
// Number-tile rows, identical grammar to the full anime detail screen.
// ---------------------------------------------------------------------------

class _EpisodeSection extends StatelessWidget {
  const _EpisodeSection({
    required this.manga,
    required this.onOpen,
    this.onRetry,
  });

  final Manga manga;
  final void Function(Chapter chapter) onOpen;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isAnime = manga.isAnime;
    final unit = isAnime ? 'episode' : 'chapter';
    if (manga.chapters.isEmpty) {
      // Distinguish "provider failed" (metadata loaded but the episode
      // scrape died — show the retry affordance) from a genuinely empty
      // list. Previously a dead provider produced an identical "no
      // chapters" brick with no way forward.
      if (manga.sourceError != null) {
        return SliverToBoxAdapter(
          child: emptyState(
            context: context,
            icon: Icons.cloud_off,
            title: 'Episode provider unreachable',
            subtitle: manga.sourceError!,
            action: onRetry != null
                ? FilledButton.tonalIcon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  )
                : null,
          ),
        );
      }
      return SliverToBoxAdapter(
        child: emptyState(
          context: context,
          icon: Icons.inbox_outlined,
          title: 'No ${unit}s found',
          subtitle: 'This source returned an empty $unit list for '
              '"${manga.title}".',
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '${manga.chapters.length} ${unit}s',
              style: HeroTokens.title.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final chapter in manga.chapters)
            _UnitRow(
              chapter: chapter,
              isAnime: isAnime,
              onOpen: () => onOpen(chapter),
            ),
        ],
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.chapter,
    required this.isAnime,
    required this.onOpen,
  });

  final Chapter chapter;
  final bool isAnime;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Number tile — play glyph for anime, page glyph for manga.
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: h.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatNumber(chapter.number),
                  style: HeroTokens.caption.copyWith(
                    color: h.accentSoftFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HeroTokens.body.copyWith(
                      color: h.foreground,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (chapter.scanlator != null ||
                      chapter.dateUploaded != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (chapter.scanlator != null &&
                            chapter.scanlator!.trim().isNotEmpty)
                          chapter.scanlator!,
                        if (chapter.dateUploaded != null)
                          _shortDate(chapter.dateUploaded!),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.caption.copyWith(color: h.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isAnime ? Icons.play_arrow_rounded : Icons.chevron_right_rounded,
              size: 22,
              color: h.muted,
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(double n) =>
      n == n.truncateToDouble() ? n.toStringAsFixed(0) : n.toString();

  String _shortDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${d.year}';
  }
}

// ---------------------------------------------------------------------------
// Bottom action bar — Add to library (watermelon.sh Feedback Action) +
// Start watching / Start reading (media-aware copy + icon).
// ---------------------------------------------------------------------------

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.manga,
    required this.isAnime,
    required this.adding,
    required this.onAddToLibrary,
    required this.onStart,
  });

  final Manga manga;
  final bool isAnime;
  final bool adding;
  final VoidCallback onAddToLibrary;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final empty = manga.chapters.isEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            // watermelon.sh Feedback Action: the circle-to-pill morph with
            // per-character staggered status text and a slide-in retry
            // button on failure (the old button had only a bare spinner
            // and snackbar errors).
            WmFeedbackAction(
              idleLabel: 'Add to library',
              idleIcon: Icons.favorite_border,
              loadingLabel: 'Adding…',
              successLabel: 'Added',
              errorLabel: 'Failed',
              onAction: () async {
                onAddToLibrary();
                // The screen navigates away on success (pushReplacement);
                // true keeps the pill in the success state meanwhile.
                return true;
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: HeroButton(
                label: empty
                    ? (isAnime ? 'No episodes' : 'No chapters')
                    : (isAnime ? 'Start watching' : 'Start reading'),
                icon: isAnime
                    ? Icons.play_arrow_rounded
                    : Icons.menu_book_outlined,
                variant: empty ? HeroButtonVariant.soft : HeroButtonVariant.solid,
                color: empty ? HeroColorRole.neutral : HeroColorRole.accent,
                onPressed: adding || empty ? null : onStart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
