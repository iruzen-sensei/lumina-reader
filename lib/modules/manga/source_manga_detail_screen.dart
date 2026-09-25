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
/// Flow implemented here (mirrors Tachiyomi / Mangayomi):
///   1. Seed the header instantly from the browse DTO (title + cover).
///   2. Fetch the authoritative detail + chapter list through
///      [sourceMangaDetailProvider] → ExtensionCoordinator.detail().
///   3. "Add to library" persists manga + chapters and continues into the
///      full [MangaDetailScreen] (downloads, tracking, history all work
///      from the persisted id).
///   4. Tapping a chapter auto-adds to library (with chapters) and opens
///      the reader with the PERSISTED chapter id — deep links and progress
///      tracking only work on persisted rows.
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
  bool _descExpanded = false;
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
              descExpanded: _descExpanded,
              onToggleDesc: () =>
                  setState(() => _descExpanded = !_descExpanded),
            ),
          ),
          detail.when(
            data: (manga) => _ChaptersSection(
              manga: manga,
              onOpen: (chapter) => _openChapter(manga, chapter),
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
          adding: _adding,
          onAddToLibrary: () => _addToLibrary(manga),
          onStartReading: () => _startReading(manga),
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
      context.pushReplacement('/mangaDetail/$id');
    } catch (e) {
      if (mounted) showSnack(ref, context, 'Could not add: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Opens a chapter — the entry is auto-added to the library first so the
  /// reader receives a real chapter id (progress, history and deep links
  /// only work on persisted rows). The preview is replaced by the full
  /// detail screen under the reader, so back-navigation lands on the real
  /// library entry (favorite / downloads / tracking all live there).
  Future<void> _openChapter(Manga detail, Chapter chapter) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final persisted = await _ensureInLibrary(detail);
      if (persisted == null) {
        if (mounted) showSnack(ref, context, 'Could not open chapter');
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
      if (mounted) showSnack(ref, context, 'Could not open chapter: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _startReading(Manga detail) async {
    if (detail.chapters.isEmpty) {
      showSnack(ref, context, 'No chapters available from this source');
      return;
    }
    // Chapters sort newest-first in the coordinator; "start reading" means
    // the FIRST chapter chronologically (lowest number).
    final first = [...detail.chapters]..sort((a, b) => a.number.compareTo(b.number));
    await _openChapter(detail, first.first);
  }

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
// Header — cover thumb, title, author, status, source chip, description.
// ---------------------------------------------------------------------------

class _PreviewHeader extends ConsumerWidget {
  const _PreviewHeader({
    required this.seed,
    required this.detail,
    required this.descExpanded,
    required this.onToggleDesc,
  });

  final Manga seed;
  final AsyncValue<Manga> detail;
  final bool descExpanded;
  final VoidCallback onToggleDesc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manga = detail.maybeWhen(
      data: (m) => m,
      orElse: () => seed,
    );
    final loading = detail.isLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
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
                    const SizedBox(height: 8),
                    if (manga.author != null && manga.author!.isNotEmpty)
                      _metaLine(
                          context, Icons.person_outline, 'by ${manga.author}'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          manga.status.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
                        return Chip(
                          label:
                              Text(name, style: theme.textTheme.labelSmall),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in manga.genre.take(8))
                  Chip(
                    label: Text(tag, style: theme.textTheme.labelSmall),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                Text('Loading details and chapters…',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
          if (manga.description != null &&
              manga.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon,
              size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Synopsis',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          text.trim(),
          maxLines: expanded ? null : 4,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(height: 1.5),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onToggle,
            child: Text(expanded ? 'Show less' : 'Show more'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chapter list (preview — no per-chapter download buttons until the entry
// is persisted; downloads live in the full detail screen).
// ---------------------------------------------------------------------------

class _ChaptersSection extends StatelessWidget {
  const _ChaptersSection({required this.manga, required this.onOpen});

  final Manga manga;
  final void Function(Chapter chapter) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (manga.chapters.isEmpty) {
      return SliverToBoxAdapter(
        child: emptyState(
          context: context,
          icon: Icons.inbox_outlined,
          title: 'No chapters found',
          subtitle: 'This source returned an empty chapter list for '
              '"${manga.title}".',
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 20, 8),
            child: Text(
              '${manga.chapters.length} chapters',
              style: theme.textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          for (final chapter in manga.chapters)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: chapter.scanlator != null
                  ? Text(
                      chapter.scanlator!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    )
                  : null,
              trailing: chapter.dateUploaded != null
                  ? Text(
                      _shortDate(chapter.dateUploaded!),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  : null,
              onTap: () => onOpen(chapter),
            ),
        ],
      ),
    );
  }

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
// Bottom action bar — Add to library / Start reading.
// ---------------------------------------------------------------------------

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.manga,
    required this.adding,
    required this.onAddToLibrary,
    required this.onStartReading,
  });

  final Manga manga;
  final bool adding;
  final VoidCallback onAddToLibrary;
  final VoidCallback onStartReading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: adding ? null : onAddToLibrary,
                icon: adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite_border),
                label: const Text('Add to library'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: adding ? null : onStartReading,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(
                  manga.chapters.isEmpty ? 'No chapters' : 'Start reading',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
