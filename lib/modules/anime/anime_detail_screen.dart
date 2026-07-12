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

import '../../core/theme.dart';
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
    // The seed data stores anime entries inside the manga list with
    // itemType = anime — we look them up via the shared provider.
    final manga = ref.watch(mangaDetailProvider(widget.id));
    final nextAiring = ref.watch(nextAiringProvider(widget.id));

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

  void _toggleFavorite(Manga manga) {
    setState(() => manga.favorite = !manga.favorite);
    showSnack(
      ref,
      context,
      manga.favorite ? 'Added to library' : 'Removed from library',
    );
  }

  void _showTrackSheet(Manga manga) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Track this anime',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.movie)),
                title: const Text('MyAnimeList'),
                subtitle: const Text('Sync watch status and progress'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  showSnack(ref, context, 'Opening MyAnimeList…');
                },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.auto_awesome)),
                title: const Text('AniList'),
                subtitle: const Text('Track score and rewatch'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  showSnack(ref, context, 'Opening AniList…');
                },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.live_tv)),
                title: const Text('Kitsu'),
                subtitle: const Text('Library & activity feed'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  showSnack(ref, context, 'Opening Kitsu…');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _share(Manga manga) {
    Share.share(
      '${manga.title}\nWatch on Lumina Reader.',
      subject: manga.title,
    );
  }

  void _openEpisode(Manga manga, Chapter episode) {
    context.push('/animePlayer/${episode.id}');
  }

  Future<void> _downloadAll(Manga manga) async {
    setState(() => _downloadingAll = true);
    showSnack(ref, context, 'Queued ${manga.chapters.length} episodes');
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _downloadingAll = false);
  }
}

// ---------------------------------------------------------------------------
// Hero app bar with cover image + gradient overlay.
// ---------------------------------------------------------------------------
class _AnimeAppBar extends ConsumerWidget {
  const _AnimeAppBar({required this.manga});
  final Manga manga;

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
          onPressed: () => Share.share(
            '${manga.title}\nWatch on Lumina Reader.',
            subject: manga.title,
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'open_browser') {
              showSnack(ref, context, 'Opening in browser…');
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
              if (!hasAired)
                OutlinedButton.icon(
                  onPressed: () => showMessage(
                      context, 'Reminder set for episode ${n.episode}'),
                  icon: const Icon(Icons.notifications_active_outlined,
                      size: 18),
                  label: const Text('Remind'),
                ),
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
          if (filter != null)
            IconButton(
              tooltip: 'Clear filter',
              icon: const Icon(Icons.filter_alt_off_outlined),
              onPressed: () => onFilterChanged(null),
            )
          else
            IconButton(
              tooltip: 'Filter',
              icon: const Icon(Icons.filter_alt_outlined),
              onPressed: () => onFilterChanged('Subbed'),
            ),
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
        );
      },
    );
  }
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({required this.episode, required this.onTap});

  final Chapter episode;
  final VoidCallback onTap;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _downloading = false;
  late bool _downloaded = widget.episode.isDownloaded;

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
          ep.isRead ? Icons.visibility_check : Icons.play_arrow,
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
          IconButton(
            tooltip: _downloaded ? 'Delete download' : 'Download',
            icon: _downloadIcon(),
            onPressed: _toggleDownload,
          ),
        ],
      ),
      onTap: widget.onTap,
    );
  }

  Widget _downloadIcon() {
    if (_downloading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_downloaded) {
      return const Icon(Icons.check_circle, color: LuminaTheme.finishedColor);
    }
    return const Icon(Icons.download_outlined);
  }

  Future<void> _toggleDownload() async {
    if (_downloaded) {
      setState(() => _downloaded = false);
      return;
    }
    setState(() => _downloading = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() {
        _downloading = false;
        _downloaded = true;
      });
    }
  }
}
