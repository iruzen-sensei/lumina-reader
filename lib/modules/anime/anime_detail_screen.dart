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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/ui/heroui.dart';
import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// Anime detail screen.
///
/// Mirrors the manga detail layout but is tuned for anime:
///  - Hero cover image with gradient overlay.
///  - Title, author (studio), status, rating, tags.
///  - Expandable description.
///  - Continue-watching button.
///  - Episode list with watched / unwatched indicators + download buttons.
///  - AniSkip indicator badge.
///  - Next-airing episode info sourced from AniChart / AniList, with a live
///    countdown.
///  - Add-to-library, track and share actions.
class AnimeDetailScreen extends ConsumerStatefulWidget {
  const AnimeDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<AnimeDetailScreen> createState() =>
      _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends ConsumerState<AnimeDetailScreen> {
  bool _descExpanded = false;
  bool _downloadingAll = false;
  String? _episodeFilter;
  bool _sortDescending = true;
  bool _showDownloadedOnly = false;

  @override
  Widget build(BuildContext context) {
    final manga = ref.watch(mangaDetailProvider(widget.id));
    final nextAiring = ref.watch(nextAiringProvider(widget.id));
    if (manga == null) {
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _AnimeAppBar(manga: manga),
          SliverToBoxAdapter(
            child: _HeaderSection(
              manga: manga,
              descExpanded: _descExpanded,
              onToggleDesc: () =>
                  setState(() => _descExpanded = !_descExpanded),
              onToggleFavorite: () => _toggleFavorite(manga),
              onTrack: () => _showTrackSheet(manga),
              onShare: () => _share(manga),
            ),
          ),
          SliverToBoxAdapter(child: _TagsRow(manga: manga)),
          SliverToBoxAdapter(
            child: _NextAiringCard(animeId: manga.id, next: nextAiring),
          ),
          SliverToBoxAdapter(
            child: _AniSkipBanner(animeId: manga.id),
          ),
          SliverToBoxAdapter(
            child: _ActionRow(manga: manga, onContinue: () {
              final first = manga.chapters.firstWhere(
                (c) => !c.isRead,
                orElse: () => manga.chapters.first,
              );
              _openEpisode(manga, first);
            }),
          ),
          SliverToBoxAdapter(child: _EpisodeToolbar(
            count: manga.chapters.length,
            sortDescending: _sortDescending,
            downloadedOnly: _showDownloadedOnly,
            onToggleSort: () =>
                setState(() => _sortDescending = !_sortDescending),
            onToggleDownloaded: () =>
                setState(() => _showDownloadedOnly = !_showDownloadedOnly),
            onDownloadAll: () => _downloadAll(manga),
            downloadingAll: _downloadingAll,
            filter: _episodeFilter,
            onFilterChanged: (v) => setState(() => _episodeFilter = v),
          )),
          _EpisodeList(
            manga: manga,
            sortDescending: _sortDescending,
            downloadedOnly: _showDownloadedOnly,
            filter: _episodeFilter,
            onOpen: (c) => _openEpisode(manga, c),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  /// REAL remove-from-library (previously only flipped the favorite flag
  /// while claiming "Removed from library").
  Future<void> _toggleFavorite(Manga manga) async {
    final confirmed = await hConfirm(
      context: context,
      title: 'Remove from library?',
      message:
          '"${manga.title}" and its episodes, downloads and history will be deleted. This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await ref
        .read(data.libraryRepositoryProvider)
        .removeFromLibrary(manga.id);
    if (mounted) {
      showSnack(ref, context, 'Removed "${manga.title}" from library');
      context.pop();
    }
  }

  /// Track sheet — opens the tracker search pages in the browser (honest,
  /// working replacement for the previous snackbar-only stubs).
  void _showTrackSheet(Manga manga) {
    hSheet<void>(
      context: context,
      title: 'Track this anime',
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
                HTile(
                  icon: Icons.tv_rounded,
                  label: 'MyAnimeList',
                  subtitle: 'Open title page on MAL',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open('https://myanimelist.net/search/all?q=$encoded');
                  },
                ),
                HTile(
                  icon: Icons.auto_awesome_rounded,
                  tone: HeroVariant.secondary,
                  label: 'AniList',
                  subtitle: 'Open title page on AniList',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open('https://anilist.co/search/anime?search=$encoded');
                  },
                ),
                HTile(
                  icon: Icons.live_tv_rounded,
                  tone: HeroVariant.success,
                  label: 'Kitsu',
                  subtitle: 'Library & activity feed',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open('https://kitsu.app/anime?text=$encoded');
                  },
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
    SharePlus.instance.share(
      ShareParams(
        text: '${manga.title}\nWatch on Lumina Reader.',
        subject: manga.title,
      ),
    );
  }

  void _openEpisode(Manga manga, Chapter episode) {
    context.push('/animePlayer/${episode.id}');
  }

  /// REAL download-all: enqueues every un-downloaded episode through the
  /// download engine (previously an 800 ms snackbar-only delay).
  Future<void> _downloadAll(Manga manga) async {
    setState(() => _downloadingAll = true);
    try {
      final downloads = ref.read(downloadsProvider.notifier);
      var queued = 0;
      for (final episode in manga.chapters) {
        if (episode.isDownloaded) continue;
        await downloads.enqueueEpisode(manga: manga, chapter: episode);
        queued++;
      }
      if (mounted) {
        showSnack(ref, context,
            queued > 0 ? 'Queued $queued episodes' : 'All episodes downloaded');
      }
    } finally {
      if (mounted) setState(() => _downloadingAll = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Hero app bar with cover image + gradient overlay.
// ---------------------------------------------------------------------------
class _AnimeAppBar extends ConsumerWidget {
  const _AnimeAppBar({required this.manga});
  final Manga manga;

  Future<void> _openInBrowser(BuildContext context, WidgetRef ref) async {
    final url = manga.url;
    if (!url.startsWith('http')) {
      showSnack(ref, context, 'No web page for local items');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) showSnack(ref, context, 'Could not open browser');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      stretch: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.maybePop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined),
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              text: '${manga.title}\nWatch on Lumina Reader.',
              subject: manga.title,
            ),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'open_browser') {
              _openInBrowser(context, ref);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'open_browser', child: Text('Open in browser')),
          ],
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          return FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (manga.thumbnailUrl != null)
                  Image.network(
                    manga.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.broken_image, size: 56),
                    ),
                  )
                else
                  Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.live_tv, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('ANIME',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header section: cover thumbnail, title, studio, status, rating, library /
// track / share buttons.
// ---------------------------------------------------------------------------
class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.manga,
    required this.descExpanded,
    required this.onToggleDesc,
    required this.onToggleFavorite,
    required this.onTrack,
    required this.onShare,
  });

  final Manga manga;
  final bool descExpanded;
  final VoidCallback onToggleDesc;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTrack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'anime-cover-${manga.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 110,
                    height: 160,
                    child: manga.thumbnailUrl != null
                        ? Image.network(
                            manga.thumbnailUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.movie, size: 36),
                            ),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.movie, size: 36),
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
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    if (manga.author != null)
                      _metaLine(context, Icons.movie_creation_outlined,
                          'Studio ${manga.author}'),
                    if (manga.artist != null && manga.artist != manga.author)
                      _metaLine(context, Icons.person_outline,
                          'Director ${manga.artist}'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: 16, color: Colors.amber.shade700),
                        const SizedBox(width: 4),
                        Text(manga.rating.toStringAsFixed(1),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        StatusChip(
                          label: manga.status.label,
                          color: _statusColor(manga.status),
                          selected: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: onToggleFavorite,
                          icon: Icon(manga.favorite
                              ? Icons.favorite
                              : Icons.favorite_border),
                          label: Text(manga.favorite ? 'In library' : 'Add'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onTrack,
                          icon: const Icon(Icons.track_changes),
                          label: const Text('Track'),
                        ),
                        OutlinedButton(
                          onPressed: onShare,
                          child: const Icon(Icons.share_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (manga.description != null) ...[
            const SizedBox(height: 16),
            _Description(
              text: manga.description!,
              expanded: descExpanded,
              onToggle: onToggleDesc,
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaLine(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(ItemStatus s) {
    switch (s) {
      case ItemStatus.ongoing:
        return LuminaTheme.readingColor;
      case ItemStatus.completed:
      case ItemStatus.publishingFinished:
        return LuminaTheme.finishedColor;
      case ItemStatus.licensed:
        return LuminaTheme.unreadColor;
      default:
        return Colors.grey;
    }
  }
}

class _Description extends StatelessWidget {
  const _Description({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            secondChild: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            expanded ? 'Show less' : 'Read more',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsRow extends StatelessWidget {
  const _TagsRow({required this.manga});
  final Manga manga;

  @override
  Widget build(BuildContext context) {
    if (manga.genre.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: manga.genre
            .map((g) => Chip(
                  label: Text(g),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Next-airing card — pulls data from AniChart / AniList via
// [nextAiringProvider]. Shows a live countdown that ticks every second.
// ---------------------------------------------------------------------------
class _NextAiringCard extends StatefulWidget {
  const _NextAiringCard({required this.animeId, required this.next});
  final int animeId;
  final NextAiring? next;

  @override
  State<_NextAiringCard> createState() => _NextAiringCardState();
}

class _NextAiringCardState extends State<_NextAiringCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.next;
    if (n == null) return const SizedBox.shrink();
    final remaining = n.airingAt.difference(DateTime.now());
    final hasAired = remaining.isNegative;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasAired ? Icons.check_circle : Icons.schedule,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasAired
                          ? 'Episode ${n.episode} aired'
                          : 'Episode ${n.episode} airs in',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.8)),
                    ),
                    Text(
                      hasAired
                          ? _airDate(n.airingAt)
                          : formatDuration(remaining),
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              // NOTE: the previous "Remind" button was a snackbar-only
              // stub (no notification scheduler existed). Removed until a
              // real flutter_local_notifications pipeline is wired up.
            ],
          ),
        ),
      ),
    );
  }

  String _airDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// AniSkip banner — surfaces the configured skip ranges for this anime so the
// user knows OP/ED skips are available before they press play.
// ---------------------------------------------------------------------------
class _AniSkipBanner extends ConsumerWidget {
  const _AniSkipBanner({required this.animeId});
  final int animeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranges = ref.watch(aniSkipProvider(animeId));
    if (ranges.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in ranges)
            Chip(
              avatar: Icon(
                r.type == 'op'
                    ? Icons.skip_next_rounded
                    : r.type == 'ed'
                        ? Icons.skip_previous_rounded
                        : Icons.fast_forward,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              label: Text(
                '${r.label} · ${formatDuration(r.end - r.start)}',
                style: const TextStyle(fontSize: 12),
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.manga, required this.onContinue});
  final Manga manga;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final unread = manga.chapters.firstWhere(
      (c) => !c.isRead,
      orElse: () => manga.chapters.first,
    );
    final label = unread.isRead
        ? 'Watch again'
        : 'Continue watching Ep ${unread.number.toStringAsFixed(0)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.play_arrow),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeToolbar extends StatelessWidget {
  const _EpisodeToolbar({
    required this.count,
    required this.sortDescending,
    required this.downloadedOnly,
    required this.onToggleSort,
    required this.onToggleDownloaded,
    required this.onDownloadAll,
    required this.downloadingAll,
    required this.filter,
    required this.onFilterChanged,
  });

  final int count;
  final bool sortDescending;
  final bool downloadedOnly;
  final VoidCallback onToggleSort;
  final VoidCallback onToggleDownloaded;
  final VoidCallback onDownloadAll;
  final bool downloadingAll;
  final String? filter;
  final ValueChanged<String?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: [
          Text(
            'Episodes ($count)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Spacer(),
          IconButton(
            tooltip: downloadedOnly ? 'Show all' : 'Downloaded only',
            isSelected: downloadedOnly,
            icon: const Icon(Icons.download_done_outlined),
            onPressed: onToggleDownloaded,
          ),
          IconButton(
            tooltip: sortDescending ? 'Newest first' : 'Oldest first',
            icon: Icon(sortDescending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded),
            onPressed: onToggleSort,
          ),
          IconButton(
            tooltip: 'Download all',
            icon: downloadingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_for_offline_outlined),
            onPressed: downloadingAll ? null : onDownloadAll,
          ),
        ],
      ),
    );
  }
}

class _EpisodeList extends ConsumerWidget {
  const _EpisodeList({
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
    var episodes = List<Chapter>.from(manga.chapters);
    if (downloadedOnly) {
      episodes = episodes.where((c) => c.isDownloaded).toList();
    }
    episodes.sort((a, b) => sortDescending
        ? b.number.compareTo(a.number)
        : a.number.compareTo(b.number));

    if (episodes.isEmpty) {
      return SliverToBoxAdapter(
        child: emptyState(
          context: context,
          icon: Icons.inbox_outlined,
          title: 'No episodes match',
          subtitle: 'Adjust the filters to see more.',
        ),
      );
    }

    return SliverList.separated(
      itemCount: episodes.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, i) {
        final ep = episodes[i];
        return _EpisodeTile(
          episode: ep,
          onTap: () => onOpen(ep),
          onLongPress: () => _showEpisodeMenu(context, ref, manga, ep),
        );
      },
    );
  }

  /// Long-press episode menu: mark watched, bookmark, download, delete
  /// download — all real, all persisted (previously episodes had NO actions
  /// beyond a fake download animation).
  void _showEpisodeMenu(
    BuildContext context,
    WidgetRef ref,
    Manga manga,
    Chapter episode,
  ) {
    final repo = ref.read(data.libraryRepositoryProvider);
    hSheet<void>(
      context: context,
      title: episode.name,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                HTile(
                  icon: episode.isRead
                      ? Icons.mark_chat_unread_outlined
                      : Icons.done_all_rounded,
                  tone: HeroVariant.primary,
                  label:
                      episode.isRead ? 'Mark as unwatched' : 'Mark as watched',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    repo.markChapterRead(episode.id, read: !episode.isRead);
                  },
                ),
                HTile(
                  icon: episode.isBookmarked
                      ? Icons.bookmark_remove_outlined
                      : Icons.bookmark_add_outlined,
                  tone: HeroVariant.secondary,
                  label: episode.isBookmarked
                      ? 'Remove bookmark'
                      : 'Bookmark',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    repo.saveChapterProgress(
                      episode.id,
                      isBookmarked: !episode.isBookmarked,
                    );
                  },
                ),
                if (!episode.isDownloaded)
                  HTile(
                    icon: Icons.download_rounded,
                    tone: HeroVariant.success,
                    label: 'Download',
                    subtitle: 'Queue via the download engine',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      ref.read(downloadsProvider.notifier).enqueueEpisode(
                          manga: manga, chapter: episode);
                    },
                  )
                else
                  HTile(
                    icon: Icons.delete_outline_rounded,
                    tone: HeroVariant.danger,
                    label: 'Delete download',
                    subtitle: 'Removes the files from this device',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      ref
                          .read(downloadsProvider.notifier)
                          .deleteChapterFiles(episode.id);
                    },
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

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({
    required this.episode,
    required this.onTap,
    required this.onLongPress,
  });

  final Chapter episode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ep = widget.episode;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: ep.isRead
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        child: Icon(
          ep.isRead ? Icons.task_alt : Icons.play_arrow,
          size: 18,
          color: ep.isRead
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.primary,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              ep.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                    ep.isRead ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
          // Watch progress (time-based) — surfaces how much of the
          // episode has been watched as a small label.
          if (ep.progress > 0 && ep.progress < 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: LuminaTheme.readingColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(ep.progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LuminaTheme.readingColor,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              if (ep.scanlator != null)
                Flexible(
                  child: Text(
                    ep.scanlator!,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                const Text('Subbed'),
              const SizedBox(width: 8),
              Text(
                ep.dateUploaded != null ? timeAgo(ep.dateUploaded!) : '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (ep.progress > 0 && ep.progress < 1) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ep.progress,
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation(
                    LuminaTheme.readingColor),
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ep.isBookmarked)
            Icon(Icons.bookmark, color: theme.colorScheme.tertiary, size: 18),
          if (ep.isDownloaded)
            const Icon(Icons.check_circle,
                color: LuminaTheme.finishedColor, size: 20),
        ],
      ),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
    );
  }
}
