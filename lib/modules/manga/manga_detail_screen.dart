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

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/lumina_ui.dart';
import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// Manga / novel / book detail screen (HeroUI v3).
///
/// Layout:
///  * Full-bleed hero header — the cover art blurred 40px behind a gradient
///    scrim that melts into the page background, floating back / open-in-
///    browser / share buttons, and an info row (cover thumbnail, title,
///    author, status chip, rating) overlapping the backdrop's bottom edge.
///  * Action block — full-width "Continue reading" CTA plus the library and
///    track pills.
///  * Synopsis card with read-more toggle, genre chips and a compact
///    metadata chip row.
///  * Chapter list with per-row download actions, read/unread dimming,
///    scanlator filter, downloaded-only filter, sort direction toggle and
///    the download-all + long-press chapter actions.
class MangaDetailScreen extends ConsumerStatefulWidget {
  const MangaDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends ConsumerState<MangaDetailScreen> {
  bool _descExpanded = false;
  bool _downloadingAll = false;
  String? _chapterFilter;
  bool _sortDescending = true; // newest first (Aniyomi default)
  bool _showDownloadedOnly = false;

  @override
  Widget build(BuildContext context) {
    final manga = ref.watch(mangaDetailProvider(widget.id));
    if (manga == null) {
      // Loading or missing — a deep link to a removed item must never
      // render a blank/broken page.
      return Scaffold(
        appBar: AppBar(title: const Text('Details')),
        body: emptyState(
          context: context,
          icon: Icons.search_off,
          title: 'Not found',
          subtitle: 'This item is no longer in your library.',
        ),
      );
    }

    final scanlators = manga.chapters
        .map((c) => c.scanlator)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _HeroHeader(
              manga: manga,
              onBack: () => Navigator.maybePop(context),
              onOpenInBrowser: () => _openInBrowser(manga),
              onShare: () => _share(manga),
            ),
          ),
          SliverToBoxAdapter(
            child: _ActionBlock(
              continueLabel: _continueLabel(manga),
              isAnime: manga.isAnime,
              inLibrary: manga.favorite,
              onContinue: () {
                // Imported books (epub / pdf) open their dedicated readers;
                // manga/anime continue into the first unread chapter. The old
                // code crashed with StateError on empty chapter lists.
                final route = _bookReaderRoute(manga);
                if (route != null) {
                  context.push(route);
                  return;
                }
                if (manga.chapters.isEmpty) {
                  showSnack(ref, context, 'No chapters available yet');
                  return;
                }
                final first = manga.chapters.firstWhere(
                  (c) => !c.isRead,
                  orElse: () => manga.chapters.first,
                );
                _openChapter(manga, first);
              },
              onToggleLibrary: () => _toggleFavorite(manga),
              onTrack: () => _showTrackSheet(manga),
            ),
          ),
          SliverToBoxAdapter(
            child: _SynopsisCard(
              text: manga.description,
              expanded: _descExpanded,
              onToggle: () => setState(() => _descExpanded = !_descExpanded),
            ),
          ),
          SliverToBoxAdapter(child: _GenreChips(genres: manga.genre)),
          SliverToBoxAdapter(child: _MetaChips(manga: manga)),
          SliverToBoxAdapter(
            child: _ListSectionHeader(
              title: manga.isAnime ? 'Episodes' : 'Chapters',
              count: manga.chapters.length,
              showFilter: scanlators.isNotEmpty || _chapterFilter != null,
              filterActive: _chapterFilter != null,
              downloadedOnly: _showDownloadedOnly,
              downloadingAll: _downloadingAll,
              sortDescending: _sortDescending,
              onFilter: () => _onFilterTapped(scanlators),
              onToggleDownloaded: () =>
                  setState(() => _showDownloadedOnly = !_showDownloadedOnly),
              onDownloadAll: () => _downloadAll(manga),
              onToggleSort: () =>
                  setState(() => _sortDescending = !_sortDescending),
            ),
          ),
          _ChapterList(
            manga: manga,
            sortDescending: _sortDescending,
            downloadedOnly: _showDownloadedOnly,
            filter: _chapterFilter,
            onOpen: (c) => _openChapter(manga, c),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions (business logic — unchanged from the previous implementation)
  // ---------------------------------------------------------------------------

  /// Label for the primary CTA. Guards against empty chapter lists (the
  /// previous version crashed with a StateError while building the label).
  String _continueLabel(Manga manga) {
    if (manga.chapters.isEmpty) {
      return manga.isAnime ? 'Start watching' : 'Start reading';
    }
    final next = manga.chapters.firstWhere(
      (c) => !c.isRead,
      orElse: () => manga.chapters.first,
    );
    if (next.isRead) {
      return manga.isAnime ? 'Watch again' : 'Read again';
    }
    final n = next.number.toStringAsFixed(0);
    return manga.isAnime ? 'Continue watching Ep $n' : 'Continue reading Ch $n';
  }

  /// Returns the dedicated reader route for imported book files
  /// (epub / pdf / cbz), or null for regular manga/anime entries.
  String? _bookReaderRoute(Manga manga) {
    if (manga.itemType == ItemType.book) {
      final url = manga.url.toLowerCase();
      if (url.endsWith('.epub')) return '/epubReader/${manga.id}';
      if (url.endsWith('.pdf')) return '/pdfReader/${manga.id}';
      if (url.endsWith('.cbz') || url.endsWith('.zip')) {
        return '/cbzReader/${manga.id}';
      }
      return null;
    }
    // Imported .txt novels open the novel reader.
    if (manga.itemType == ItemType.novel &&
        manga.url.toLowerCase().endsWith('.txt')) {
      return null; // routed per-chapter by _openChapter
    }
    return null;
  }

  /// REAL remove-from-library with confirmation. The button truly deletes
  /// the entry (chapters, downloads, history, notes) and pops back.
  Future<void> _toggleFavorite(Manga manga) async {
    final confirmed = await showHeroConfirm(
      context: context,
      title: 'Remove from library?',
      message:
          '"${manga.title}" and its chapters, downloads, history and notes will be deleted. This cannot be undone.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!confirmed) return;
    await ref.read(data.libraryRepositoryProvider).removeFromLibrary(manga.id);
    if (mounted) {
      showSnack(ref, context, 'Removed "${manga.title}" from library');
      context.pop();
    }
  }

  /// Opens the entry's web page in the external browser (top-right header
  /// button).
  Future<void> _openInBrowser(Manga manga) async {
    final url = manga.url;
    if (!url.startsWith('http')) {
      showSnack(ref, context, 'No web page for local items');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(ref, context, 'Could not open browser');
    }
  }

  /// Track sheet — opens the entry's search page on the tracking sites in
  /// the browser. In-app tracker sync requires OAuth credentials this build
  /// does not bundle; deep-linking to the tracker search is the honest,
  /// actually-working replacement for the previous snackbar-only stubs.
  void _showTrackSheet(Manga manga) {
    showHeroSheet<void>(
      context: context,
      title: 'Track this ${manga.isAnime ? 'anime' : 'manga'}',
      builder: (sheetContext) {
        Future<void> open(String url) async {
          final uri = Uri.tryParse(url);
          if (uri == null ||
              !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            if (sheetContext.mounted) {
              showSnack(ref, sheetContext, 'Could not open link');
            }
          }
        }

        final encoded = Uri.encodeComponent(manga.title);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                HeroListTile(
                  leadingIcon: Icons.tv_rounded,
                  title: 'MyAnimeList',
                  subtitle: 'Open title page on MAL',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open('https://myanimelist.net/search/all?q=$encoded');
                  },
                  showChevron: true,
                ),
                HeroListTile(
                  leadingIcon: Icons.auto_awesome_rounded,
                  title: 'AniList',
                  subtitle: 'Open title page on AniList',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open('https://anilist.co/search/manga?search=$encoded');
                  },
                  showChevron: true,
                ),
                HeroListTile(
                  leadingIcon: Icons.bookmark_rounded,
                  leadingColor: HeroTokens.success,
                  title: 'MangaUpdates',
                  subtitle: 'Follow release updates',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open(
                        'https://www.mangaupdates.com/series.html?search=$encoded');
                  },
                  showChevron: true,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _share(Manga manga) {
    final text = '${manga.title}\n'
        'Status: ${manga.status.label}\n'
        'Rating: ${manga.rating.toStringAsFixed(1)}\n'
        '${manga.isAnime ? "Watch" : "Read"} on Lumina Reader.';
    SharePlus.instance.share(ShareParams(text: text, subject: manga.title));
  }

  void _openChapter(Manga manga, Chapter chapter) {
    if (manga.isAnime) {
      context.push('/animePlayer/${chapter.id}');
    } else if (manga.itemType == ItemType.novel) {
      context.push('/novelReader/${chapter.id}');
    } else {
      context.push('/reader/${chapter.id}');
    }
  }

  Future<void> _downloadAll(Manga manga) async {
    setState(() => _downloadingAll = true);
    try {
      final downloads = ref.read(downloadsProvider.notifier);
      var queued = 0;
      for (final chapter in manga.chapters) {
        if (chapter.isDownloaded) continue;
        await downloads.enqueueChapter(manga: manga, chapter: chapter);
        queued++;
      }
      if (mounted) {
        showSnack(ref, context,
            queued > 0 ? 'Queued $queued chapters' : 'All chapters downloaded');
      }
    } finally {
      if (mounted) setState(() => _downloadingAll = false);
    }
  }

  void _onFilterTapped(List<String> scanlators) {
    if (_chapterFilter != null) {
      setState(() => _chapterFilter = null);
      return;
    }
    if (scanlators.isEmpty) return;
    _showScanlatorSheet(scanlators);
  }

  /// REAL scanlator filter: lists the scanlator groups present in the
  /// chapter list.
  void _showScanlatorSheet(List<String> scanlators) {
    showHeroSheet<void>(
      context: context,
      title: 'Filter by group',
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...scanlators.map((s) => HeroListTile(
                      leadingIcon: Icons.groups_rounded,
                      title: s,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _chapterFilter = s);
                      },
                      showChevron: true,
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

// ---------------------------------------------------------------------------
// Hero header — blurred cover backdrop + floating nav buttons + overlapping
// info row (cover thumbnail, title, author, status chip, rating).
// ---------------------------------------------------------------------------

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.manga,
    required this.onBack,
    required this.onOpenInBrowser,
    required this.onShare,
  });

  /// Backdrop height excluding the status bar (~200-230 total on device).
  static const double _backdropHeight = 182;

  /// How far the info row climbs into the backdrop.
  static const double _overlap = 70;

  final Manga manga;
  final VoidCallback onBack;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final statusTop = MediaQuery.paddingOf(context).top;
    final backdropHeight = statusTop + _backdropHeight;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Blurred cover backdrop with a scrim melting into the page
        // background.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: backdropHeight,
          child: _HeroBackdrop(url: manga.thumbnailUrl),
        ),
        // Floating navigation over the backdrop.
        Positioned(
          top: statusTop + 6,
          left: 10,
          right: 10,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HeroIconButton(
                icon: Icons.arrow_back_rounded,
                iconSize: 22,
                color: Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                tooltip: 'Back',
                onPressed: onBack,
              ),
              Row(
                children: [
                  HeroIconButton(
                    icon: Icons.open_in_new_rounded,
                    iconSize: 20,
                    color: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    tooltip: 'Open in browser',
                    onPressed: onOpenInBrowser,
                  ),
                  const SizedBox(width: 4),
                  HeroIconButton(
                    icon: Icons.ios_share_outlined,
                    iconSize: 20,
                    color: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    tooltip: 'Share',
                    onPressed: onShare,
                  ),
                ],
              ),
            ],
          ),
        ),
        // Info row overlapping the backdrop's bottom edge.
        Padding(
          padding: EdgeInsets.only(
            top: backdropHeight - _overlap,
            left: 20,
            right: 20,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverThumb(url: manga.thumbnailUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    Text(
                      manga.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          HeroTokens.display.copyWith(color: h.foreground, fontSize: 28),
                    ),
                    if (manga.author != null && manga.author!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'by ${manga.author}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HeroTokens.bodySmall.copyWith(color: h.muted),
                      ),
                    ],
                    if (manga.artist != null &&
                        manga.artist!.isNotEmpty &&
                        manga.artist != manga.author) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Art by ${manga.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HeroTokens.bodySmall.copyWith(color: h.muted),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _StatusRatingRow(
                      status: manga.status,
                      rating: manga.rating,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-bleed backdrop: the cover blurred 40px behind a gradient scrim that
/// fades into the page background. Falls back to a subtle accent-tinted
/// gradient when there is no cover or it fails to load.
class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Accent-tinted fallback — also the placeholder while loading.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                h.accent.withValues(alpha: 0.32),
                h.background,
              ],
            ),
          ),
        ),
        if (url != null)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Transform.scale(
                scale: 1.25,
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        // Scrim: transparent at the top, page background at the bottom, so
        // the backdrop transitions into the rest of the screen.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.3, 1],
              colors: [
                h.background.withValues(alpha: 0),
                h.background,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Cover thumbnail (100x145, radius 14, drop shadow) used by the info row.
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Container(
      width: 100,
      height: 145,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: h.isDark ? 0.45 : 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: url != null
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(h),
              )
            : _placeholder(h),
      ),
    );
  }

  Widget _placeholder(HeroThemeData h) {
    return Container(
      color: h.surface2,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book_rounded, size: 34, color: h.muted),
    );
  }
}

/// Status chip (soft, colored by publication status) + star rating in
/// accent. "Unknown" status renders no chip at all.
class _StatusRatingRow extends StatelessWidget {
  const _StatusRatingRow({required this.status, required this.rating});

  final ItemStatus status;
  final double rating;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final role = _statusRole(status);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (role != null)
          HeroChip(
            label: status.label,
            variant: HeroChipVariant.soft,
            color: role,
            small: true,
          ),
        if (rating > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, size: 15, color: h.accent),
              const SizedBox(width: 3),
              Text(
                rating.toStringAsFixed(1),
                style: HeroTokens.bodySmall
                    .copyWith(color: h.accent, fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Action block — primary continue CTA + library / track pills.
// ---------------------------------------------------------------------------

class _ActionBlock extends StatelessWidget {
  const _ActionBlock({
    required this.continueLabel,
    required this.isAnime,
    required this.inLibrary,
    required this.onContinue,
    required this.onToggleLibrary,
    required this.onTrack,
  });

  final String continueLabel;
  final bool isAnime;
  final bool inLibrary;
  final VoidCallback onContinue;
  final VoidCallback onToggleLibrary;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroButton(
            label: continueLabel,
            icon: isAnime ? Icons.play_arrow_rounded : Icons.menu_book_rounded,
            variant: HeroButtonVariant.solid,
            size: HeroButtonSize.md,
            onPressed: onContinue,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: HeroButton(
                    label: inLibrary ? 'In Library' : 'Add to Library',
                    icon: inLibrary
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    variant: HeroButtonVariant.soft,
                    size: HeroButtonSize.md,
                    onPressed: onToggleLibrary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: HeroButton(
                    label: 'Track',
                    icon: Icons.insights_outlined,
                    variant: HeroButtonVariant.light,
                    size: HeroButtonSize.md,
                    onPressed: onTrack,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Synopsis card — collapsed to 4 lines with an accent read-more toggle.
// ---------------------------------------------------------------------------

class _SynopsisCard extends StatelessWidget {
  const _SynopsisCard({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  /// Descriptions longer than this offer the "Read more" toggle.
  static const int _longTextThreshold = 240;

  final String? text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final clean = text?.trim() ?? '';
    if (clean.isEmpty) return const SizedBox.shrink();

    final isLong = clean.length > _longTextThreshold;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: HeroCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              clean,
              maxLines: expanded ? null : 4,
              overflow: TextOverflow.ellipsis,
              style: HeroTokens.body.copyWith(color: h.muted, height: 1.55),
            ),
            if (isLong) ...[
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Text(
                  expanded ? 'Less' : 'Read more',
                  style: HeroTokens.bodySmall.copyWith(
                    color: h.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Genre chips — soft accent, only when the source provides genres.
// ---------------------------------------------------------------------------

class _GenreChips extends StatelessWidget {
  const _GenreChips({required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final visible =
        genres.where((g) => g.trim().isNotEmpty).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final genre in visible)
            HeroChip(
              label: genre,
              variant: HeroChipVariant.soft,
              color: HeroColorRole.accent,
              small: true,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact metadata chips — media type, chapter count, unread count.
// ---------------------------------------------------------------------------

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.manga});

  final Manga manga;

  String get _typeLabel {
    switch (manga.itemType) {
      case ItemType.manga:
        return 'Manga';
      case ItemType.anime:
        return 'Anime';
      case ItemType.novel:
        return 'Novel';
      case ItemType.book:
        return 'Book';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          HeroChip(
            label: _typeLabel,
            variant: HeroChipVariant.soft,
            color: HeroColorRole.neutral,
            small: true,
          ),
          if (manga.chapters.isNotEmpty)
            HeroChip(
              label: manga.isAnime
                  ? '${manga.chapters.length} episodes'
                  : '${manga.chapters.length} chapters',
              variant: HeroChipVariant.soft,
              color: HeroColorRole.neutral,
              small: true,
            ),
          if (manga.unreadCount > 0)
            HeroChip(
              label: '${manga.unreadCount} unread',
              variant: HeroChipVariant.soft,
              color: HeroColorRole.neutral,
              small: true,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter section header — title + count chip + filter / downloaded-only /
// download-all / sort icon buttons.
// ---------------------------------------------------------------------------

class _ListSectionHeader extends StatelessWidget {
  const _ListSectionHeader({
    required this.title,
    required this.count,
    required this.showFilter,
    required this.filterActive,
    required this.downloadedOnly,
    required this.downloadingAll,
    required this.sortDescending,
    required this.onFilter,
    required this.onToggleDownloaded,
    required this.onDownloadAll,
    required this.onToggleSort,
  });

  final String title;
  final int count;
  final bool showFilter;
  final bool filterActive;
  final bool downloadedOnly;
  final bool downloadingAll;
  final bool sortDescending;
  final VoidCallback onFilter;
  final VoidCallback onToggleDownloaded;
  final VoidCallback onDownloadAll;
  final VoidCallback onToggleSort;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 10, 4),
      child: Row(
        children: [
          Text(title, style: HeroTokens.title.copyWith(color: h.foreground)),
          const SizedBox(width: 8),
          HeroChip(
            label: '$count',
            variant: HeroChipVariant.soft,
            color: HeroColorRole.neutral,
            small: true,
          ),
          const Spacer(),
          if (showFilter)
            HeroIconButton(
              icon: filterActive
                  ? Icons.filter_alt_off_outlined
                  : Icons.filter_alt_outlined,
              size: 36,
              iconSize: 19,
              tooltip: filterActive ? 'Clear group filter' : 'Filter by group',
              color: filterActive ? h.accent : null,
              onPressed: onFilter,
            ),
          HeroIconButton(
            icon: Icons.download_done_outlined,
            size: 36,
            iconSize: 19,
            tooltip: downloadedOnly ? 'Show all' : 'Downloaded only',
            color: downloadedOnly ? h.accent : null,
            backgroundColor: downloadedOnly ? h.accentSoft : null,
            onPressed: onToggleDownloaded,
          ),
          if (downloadingAll)
            const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            HeroIconButton(
              icon: Icons.download_for_offline_outlined,
              size: 36,
              iconSize: 19,
              tooltip: 'Download all',
              onPressed: onDownloadAll,
            ),
          HeroIconButton(
            icon: sortDescending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 36,
            iconSize: 19,
            tooltip: sortDescending ? 'Newest first' : 'Oldest first',
            onPressed: onToggleSort,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter list — filtering + sorting, HeroSeparator-divided rows.
// ---------------------------------------------------------------------------

class _ChapterList extends ConsumerWidget {
  const _ChapterList({
    required this.manga,
    required this.sortDescending,
    required this.downloadedOnly,
    required this.filter,
    required this.onOpen,
  });

  final Manga manga;
  final bool sortDescending;
  final bool downloadedOnly;
  final String? filter;
  final void Function(Chapter) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadsProvider);
    var chapters = List<Chapter>.from(manga.chapters);
    if (downloadedOnly) {
      chapters = chapters.where((c) => c.isDownloaded).toList();
    }
    if (filter != null) {
      chapters = chapters.where((c) => c.scanlator == filter).toList();
    }
    chapters.sort((a, b) => sortDescending
        ? b.number.compareTo(a.number)
        : a.number.compareTo(b.number));

    if (chapters.isEmpty) {
      return SliverToBoxAdapter(
        child: emptyState(
          context: context,
          icon: Icons.inbox_outlined,
          title: 'No chapters match',
          subtitle: 'Adjust the filters to see more.',
        ),
      );
    }

    return SliverList.separated(
      itemCount: chapters.length,
      separatorBuilder: (_, __) => const HeroSeparator(indent: 56),
      itemBuilder: (context, i) {
        final c = chapters[i];
        return _ChapterTile(
          chapter: c,
          isAnime: manga.isAnime,
          queuedOrDownloading: _isQueuedOrDownloading(tasks, manga, c),
          onTap: () => onOpen(c),
          onLongPress: () => _showChapterMenu(context, ref, manga, c),
          onDownload: () {
            if (manga.isAnime) {
              ref.read(downloadsProvider.notifier).enqueueEpisode(
                    manga: manga,
                    chapter: c,
                  );
            } else {
              ref.read(downloadsProvider.notifier).enqueueChapter(
                    manga: manga,
                    chapter: c,
                  );
            }
          },
        );
      },
    );
  }

  /// Long-press context menu — Mihon-style chapter actions: mark read,
  /// bookmark, download and delete download.
  void _showChapterMenu(
    BuildContext context,
    WidgetRef ref,
    Manga manga,
    Chapter chapter,
  ) {
    final repo = ref.read(data.libraryRepositoryProvider);
    showHeroSheet<void>(
      context: context,
      title: chapter.name,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                HeroListTile(
                  leadingIcon: chapter.isRead
                      ? Icons.mark_chat_unread_outlined
                      : Icons.done_all_rounded,
                  title: chapter.isRead ? 'Mark as unread' : 'Mark as read',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    repo.markChapterRead(chapter.id, read: !chapter.isRead);
                  },
                  showChevron: true,
                ),
                HeroListTile(
                  leadingIcon: chapter.isBookmarked
                      ? Icons.bookmark_remove_outlined
                      : Icons.bookmark_add_outlined,
                  title: chapter.isBookmarked ? 'Remove bookmark' : 'Bookmark',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref
                        .read(data.libraryRepositoryProvider)
                        .saveChapterProgress(
                          chapter.id,
                          isBookmarked: !chapter.isBookmarked,
                        );
                  },
                  showChevron: true,
                ),
                if (!chapter.isDownloaded)
                  HeroListTile(
                    leadingIcon: Icons.download_rounded,
                    leadingColor: HeroTokens.success,
                    title: 'Download',
                    subtitle: 'Queue via the download engine',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      if (manga.isAnime) {
                        ref.read(downloadsProvider.notifier).enqueueEpisode(
                              manga: manga,
                              chapter: chapter,
                            );
                      } else {
                        ref.read(downloadsProvider.notifier).enqueueChapter(
                              manga: manga,
                              chapter: chapter,
                            );
                      }
                    },
                    showChevron: true,
                  )
                else
                  HeroListTile(
                    leadingIcon: Icons.delete_outline_rounded,
                    danger: true,
                    title: 'Delete download',
                    subtitle: 'Removes the files from this device',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      ref
                          .read(downloadsProvider.notifier)
                          .deleteChapterFiles(chapter.id);
                    },
                    showChevron: true,
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter tile — leading number tile, name + date, download state trailing.
// Read chapters are dimmed to muted.
// ---------------------------------------------------------------------------

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.isAnime,
    required this.queuedOrDownloading,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
  });

  final Chapter chapter;
  final bool isAnime;
  final bool queuedOrDownloading;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final c = chapter;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.isRead ? h.dflt : h.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatNumber(c.number),
                  style: HeroTokens.caption.copyWith(
                    color: c.isRead ? h.muted : h.accentSoftFg,
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
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: c.isRead ? h.muted : h.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HeroTokens.caption.copyWith(color: h.muted),
                  ),
                ],
              ),
            ),
            if (c.isBookmarked) ...[
              const SizedBox(width: 6),
              Icon(Icons.bookmark_rounded, size: 15, color: h.warning),
            ],
            const SizedBox(width: 6),
            _buildDownloadTrailing(h),
          ],
        ),
      ),
    );
  }

  String _subtitle(Chapter c) {
    final parts = <String>[
      if (c.scanlator != null && c.scanlator!.trim().isNotEmpty) c.scanlator!,
      if (c.dateUploaded != null) timeAgo(c.dateUploaded!),
    ];
    return parts.join(' · ');
  }

  Widget _buildDownloadTrailing(HeroThemeData h) {
    if (chapter.isDownloaded) {
      return Icon(Icons.check_circle_rounded, size: 20, color: h.success);
    }
    if (queuedOrDownloading) {
      return Icon(Icons.downloading_rounded, size: 20, color: h.accent);
    }
    return HeroIconButton(
      icon: Icons.download_outlined,
      size: 32,
      iconSize: 19,
      tooltip: 'Download',
      variant: HeroColorRole.accent,
      onPressed: onDownload,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Maps a publication status onto a HeroUI chip role. `null` for unknown —
/// an unknown status renders no chip at all (no "Unknown" placeholders).
HeroColorRole? _statusRole(ItemStatus status) {
  switch (status) {
    case ItemStatus.ongoing:
    case ItemStatus.completed:
    case ItemStatus.publishingFinished:
      return HeroColorRole.success;
    case ItemStatus.onHiatus:
    case ItemStatus.licensed:
      return HeroColorRole.warning;
    case ItemStatus.cancelled:
      return HeroColorRole.danger;
    case ItemStatus.unknown:
      return null;
  }
}

/// Formats a chapter number: whole numbers without trailing `.0`.
String _formatNumber(double n) =>
    n == n.truncateToDouble() ? n.toStringAsFixed(0) : n.toString();

/// Whether a chapter currently sits in the download queue (queued,
/// downloading or paused) for this manga.
bool _isQueuedOrDownloading(
  List<DownloadTask> tasks,
  Manga manga,
  Chapter chapter,
) {
  for (final t in tasks) {
    if (t.mangaId == manga.id &&
        t.chapterName == chapter.name &&
        (t.state == DownloadState.queued ||
            t.state == DownloadState.downloading ||
            t.state == DownloadState.paused)) {
      return true;
    }
  }
  return false;
}
