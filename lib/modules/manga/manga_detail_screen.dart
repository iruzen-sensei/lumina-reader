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
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// Manga / novel / book detail screen.
///
/// Renders a hero cover with a gradient scrim, metadata (title, author,
/// status, rating, tags), an expandable description, a chapter list with
/// read/unread indicators and per-chapter download buttons, plus the
/// add-to-library, track (MAL / AniList) and share actions.
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
  bool _sortDescending = true;
  bool _showDownloadedOnly = false;

  @override
  Widget build(BuildContext context) {
    final manga = ref.watch(mangaDetailProvider(widget.id));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _DetailAppBar(manga: manga),
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
          SliverToBoxAdapter(child: _ActionRow(manga: manga, onContinue: () {
            final first = manga.chapters.firstWhere(
              (c) => !c.isRead,
              orElse: () => manga.chapters.first,
            );
            _openChapter(manga, first);
          })),
          SliverToBoxAdapter(child: _ChapterToolbar(
            count: manga.chapters.length,
            isAnime: manga.isAnime,
            sortDescending: _sortDescending,
            downloadedOnly: _showDownloadedOnly,
            onToggleSort: () =>
                setState(() => _sortDescending = !_sortDescending),
            onToggleDownloaded: () =>
                setState(() => _showDownloadedOnly = !_showDownloadedOnly),
            onDownloadAll: () => _downloadAll(manga),
            downloadingAll: _downloadingAll,
            filter: _chapterFilter,
            onFilterChanged: (v) => setState(() => _chapterFilter = v),
          )),
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
                child: Text('Track this ${manga.isAnime ? 'anime' : 'manga'}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.movie)),
                title: const Text('MyAnimeList'),
                subtitle: const Text('Sync status and progress'),
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
                leading: const CircleAvatar(child: Icon(Icons.bookmark)),
                title: const Text('MangaUpdates'),
                subtitle: const Text('Follow release updates'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  showSnack(ref, context, 'Opening MangaUpdates…');
                },
              ),
            ],
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
    Share.share(text, subject: manga.title);
  }

  void _openChapter(Manga manga, Chapter chapter) {
    if (manga.isAnime) {
      context.push('/animePlayer/${chapter.id}');
    } else {
      context.push('/reader/${chapter.id}');
    }
  }

  Future<void> _downloadAll(Manga manga) async {
    setState(() => _downloadingAll = true);
    showSnack(ref, context, 'Queued ${manga.chapters.length} chapters');
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _downloadingAll = false);
  }
}

// ---------------------------------------------------------------------------
// Hero app bar with cover image + gradient overlay.
// ---------------------------------------------------------------------------
class _DetailAppBar extends ConsumerWidget {
  const _DetailAppBar({required this.manga});
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
            '${manga.title}\n${manga.isAnime ? "Watch" : "Read"} on Lumina Reader.',
            subject: manga.title,
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'open_browser') {
              showSnack(ref, context, 'Opening in browser…');
            } else if (v == 'share') {
              Share.share('${manga.title}\n${manga.url}',
                  subject: manga.title);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'open_browser', child: Text('Open in browser')),
            PopupMenuItem(value: 'share', child: Text('Share link')),
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
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.85),
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
// Header: cover thumbnail, title, author/artist, status, rating, library /
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
                tag: 'cover-${manga.id}',
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
                              child: const Icon(Icons.menu_book, size: 36),
                            ),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.menu_book, size: 36),
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
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    if (manga.author != null)
                      _metaLine(
                          context, Icons.person_outline, 'by ${manga.author}'),
                    if (manga.artist != null && manga.artist != manga.author)
                      _metaLine(context, Icons.brush_outlined,
                          'Art by ${manga.artist}'),
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
        ? (manga.isAnime ? 'Watch again' : 'Read again')
        : (manga.isAnime
            ? 'Continue watching Ep ${unread.number.toStringAsFixed(0)}'
            : 'Continue reading Ch ${unread.number.toStringAsFixed(0)}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: Icon(manga.isAnime ? Icons.play_arrow : Icons.menu_book),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterToolbar extends StatelessWidget {
  const _ChapterToolbar({
    required this.count,
    required this.isAnime,
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
  final bool isAnime;
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
            isAnime ? 'Episodes ($count)' : 'Chapters ($count)',
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
              tooltip: 'Filter by scanlator',
              icon: const Icon(Icons.filter_alt_outlined),
              onPressed: () => _showFilterSheet(context),
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

  void _showFilterSheet(BuildContext context) {
    onFilterChanged('Lumina Scans');
  }
}

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
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, i) {
        final c = chapters[i];
        final selected =
            ref.watch(librarySelectionProvider).contains(c.id);
        return _ChapterTile(
          chapter: c,
          isAnime: manga.isAnime,
          selected: selected,
          onTap: () => onOpen(c),
          onLongPress: () =>
              ref.read(librarySelectionProvider.notifier).toggle(c.id),
        );
      },
    );
  }
}

class _ChapterTile extends StatefulWidget {
  const _ChapterTile({
    required this.chapter,
    required this.isAnime,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Chapter chapter;
  final bool isAnime;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends State<_ChapterTile> {
  bool _downloading = false;
  bool _downloaded = false;

  @override
  void initState() {
    super.initState();
    _downloaded = widget.chapter.isDownloaded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.chapter;
    return ListTile(
      leading: _leading(),
      title: Text(
        c.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: c.isRead ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (c.scanlator != null)
            Flexible(
              child: Text(
                c.scanlator!,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            const Text('Unknown group'),
          const SizedBox(width: 8),
          Text(
            c.dateUploaded != null ? timeAgo(c.dateUploaded!) : '',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.isBookmarked)
            Icon(Icons.bookmark, color: theme.colorScheme.tertiary, size: 18),
          IconButton(
            tooltip: _downloaded ? 'Delete download' : 'Download',
            icon: _downloadIcon(),
            onPressed: _toggleDownload,
          ),
        ],
      ),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      selected: widget.selected,
    );
  }

  Widget _leading() {
    if (widget.isAnime) {
      return CircleAvatar(
        backgroundColor: widget.chapter.isRead
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          widget.chapter.isRead ? Icons.visibility_check : Icons.play_arrow,
          size: 18,
          color: widget.chapter.isRead
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: widget.chapter.isRead
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.primaryContainer,
      child: widget.chapter.isRead
          ? Icon(Icons.done_all,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant)
          : Icon(Icons.menu_book_outlined,
              size: 16, color: Theme.of(context).colorScheme.primary),
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
