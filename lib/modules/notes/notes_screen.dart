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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/lumina_ui.dart';
import 'package:lumina_reader/core/ui/hero_motion.dart';
import '../../core/ui/watermelon.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The notes screen.
///
/// Displays user highlights and thoughts as cards with a color-coded left
/// border (7 semantic colours). Tabs switch between All / Highlights /
/// Thoughts; a search field and a per-book filter strip narrow the list
/// further.
///
/// The "create note" button is a watermelon.sh Expand Details: a compact
/// band under the header that springs open into the inline composer
/// (type, text, colour, save) — the old FAB + modal bottom sheet is gone
/// (one component, one place). Per-card actions fan out from a
/// watermelon.sh Split Actions trigger instead of a three-chip row.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _composerKey = GlobalKey();

  /// Bumping this regenerates the composer with initiallyOpen — the
  /// external "open the composer" trigger (empty-state button).
  int _composerGeneration = 0;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final notes = ref.watch(filteredNotesProvider);
    final books = ref.watch(notesProvider).map((n) => n.mangaId).toSet();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Notes',
                      style:
                          HeroTokens.display.copyWith(color: h.foreground),
                    ),
                    const SizedBox(width: 8),
                    HeroChip(
                      label: '${notes.length}',
                      small: true,
                      color: HeroColorRole.neutral,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: HeroInput(
                  controller: _searchController,
                  hint: 'Search notes…',
                  prefixIcon: Icons.search_rounded,
                  onChanged: (v) =>
                      ref.read(notesSearchProvider.notifier).state = v,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // ---- Create note: watermelon.sh Expand Details band ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: KeyedSubtree(
                  key: ValueKey('composer-$_composerGeneration'),
                  child: _NoteComposer(
                    key: _composerKey,
                    initiallyOpen: _composerGeneration > 0,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(child: _FilterTabs()),
            SliverToBoxAdapter(child: _BookFilterRow(bookIds: books.toList())),
            SliverPadding(
              // Bottom nav bar clearance.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: notes.isEmpty
                  ? SliverToBoxAdapter(
                      child: emptyState(
                        context: context,
                        icon: Icons.sticky_note_2_outlined,
                        title: 'No notes yet',
                        subtitle:
                            'Highlight text in the reader or jot down a thought to see it here.',
                        action: HeroButton(
                          label: 'New note',
                          icon: Icons.note_add_rounded,
                          variant: HeroButtonVariant.soft,
                          onPressed: _openComposer,
                        ),
                      ),
                    )
                  : SliverList.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _NoteCard(note: notes[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens (and scrolls to) the inline composer — used by the empty state.
  void _openComposer() {
    setState(() => _composerGeneration++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _composerKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Composer — watermelon.sh Expand Details. Collapsed: a compact
// "New note" band. Expanded: the full editor springs open in place.
// ---------------------------------------------------------------------------

class _NoteComposer extends ConsumerStatefulWidget {
  const _NoteComposer({super.key, this.initiallyOpen = false});

  final bool initiallyOpen;

  @override
  ConsumerState<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends ConsumerState<_NoteComposer> {
  final _controller = TextEditingController();
  NoteType _type = NoteType.thought;
  NoteColor _color = NoteColor.purple;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return HeroCard(
      padding: EdgeInsets.zero,
      child: WmExpandDetails(
        title: 'New note',
        initiallyOpen: widget.initiallyOpen,
        collapsed: Text(
          'Jot down a thought or save a highlight…',
          style: HeroTokens.bodySmall.copyWith(color: h.muted),
        ),
        expanded: Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroSegmented<NoteType>(
                segments: const [
                  (NoteType.thought, 'Thought', Icons.lightbulb_outline_rounded),
                  (NoteType.highlight, 'Highlight', Icons.highlight_rounded),
                ],
                selected: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 12),
              HeroInput(
                controller: _controller,
                hint: 'Write your note…',
                maxLines: 4,
                autofocus: widget.initiallyOpen,
              ),
              const SizedBox(height: 12),
              Text('Color', style: HeroTokens.caption.copyWith(color: h.muted)),
              const SizedBox(height: 8),
              _ColorPicker(
                color: _color,
                onPick: (c) => setState(() => _color = c),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  HeroButton(
                    label: 'Save note',
                    icon: Icons.check_rounded,
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showSnack(ref, context, 'Write something first');
      return;
    }
    _controller.clear();
    // REAL persistence — general note (mangaId 0). The notifier's Isar
    // watch refreshes the list automatically.
    try {
      await ref.read(notesProvider.notifier).add(
            mangaId: 0,
            text: text,
            type: _type,
            color: _color,
          );
      if (mounted) showSnack(ref, context, 'Note saved');
    } catch (e) {
      if (mounted) showSnack(ref, context, 'Could not save note');
    }
  }
}

class _FilterTabs extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notesFilterProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: HeroSegmented<NotesFilter>(
        expand: true,
        segments: const [
          (NotesFilter.all, 'All', Icons.list_rounded),
          (NotesFilter.highlights, 'Highlights', Icons.highlight_rounded),
          (NotesFilter.thoughts, 'Thoughts', Icons.lightbulb_outline_rounded),
        ],
        selected: filter,
        onChanged: (f) => ref.read(notesFilterProvider.notifier).state = f,
      ),
    );
  }
}

class _BookFilterRow extends ConsumerWidget {
  const _BookFilterRow({required this.bookIds});
  final List<int> bookIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookIds.isEmpty) return const SizedBox.shrink();
    final allNotes = ref.watch(notesProvider);
    final selectedBook = ref.watch(notesBookFilterProvider);
    // Apple-style soft edge fade instead of a hard cutoff; HeroChip in the
    // filter variant (unselected = neutral, selected = accent-soft).
    return HeroFadedRail(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: bookIds.length + 1,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          return HeroChip(
            label: 'All books',
            selected: selectedBook == null,
            variant: HeroChipVariant.outlineText,
            onTap: () =>
                ref.read(notesBookFilterProvider.notifier).state = null,
          );
        }
        final id = bookIds[i - 1];
        final title = allNotes.firstWhere((n) => n.mangaId == id).mangaTitle;
        return HeroChip(
          label: title,
          selected: selectedBook == id,
          variant: HeroChipVariant.outlineText,
          onTap: () => ref.read(notesBookFilterProvider.notifier).state = id,
        );
      },
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: h.dangerSoft,
          borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
        ),
        child: Icon(Icons.delete_outline_rounded, color: h.danger),
      ),
      confirmDismiss: (_) async {
        return await _confirmDelete(context);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
          onTap: () => _showEditSheet(context, ref),
          child: HeroCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 3px color bar carrying the note's semantic colour.
                    Container(width: 3, color: note.color.color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: note.color.color
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        note.type == NoteType.highlight
                                            ? Icons.highlight
                                            : Icons.lightbulb_outline,
                                        size: 13,
                                        color: _darken(note.color.color),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        note.type.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _darken(note.color.color),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                // Card actions — watermelon.sh Split
                                // Actions: one compact trigger fans out
                                // Copy / Edit / Delete (the old three-chip
                                // row dominated the card).
                                WmSplitActions(
                                  triggerIcon: Icons.more_horiz_rounded,
                                  actions: [
                                    WmSplitAction(
                                      icon: Icons.copy_outlined,
                                      label: 'Copy',
                                      onTap: () async {
                                        await Clipboard.setData(
                                            ClipboardData(
                                                text: note.content));
                                        if (context.mounted) {
                                          showSnack(
                                              ref, context, 'Note copied');
                                        }
                                      },
                                    ),
                                    WmSplitAction(
                                      icon: Icons.edit_outlined,
                                      label: 'Edit',
                                      onTap: () =>
                                          _showEditSheet(context, ref),
                                    ),
                                    WmSplitAction(
                                      icon: Icons.delete_outline,
                                      label: 'Delete',
                                      onTap: () async {
                                        if (await _confirmDelete(context) &&
                                            context.mounted) {
                                          await ref
                                              .read(notesProvider.notifier)
                                              .delete(note.id);
                                          if (context.mounted) {
                                            showSnack(
                                                ref, context, 'Note deleted');
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              note.content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: HeroTokens.body.copyWith(
                                color: h.foreground,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _metaLine(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  HeroTokens.caption.copyWith(color: h.muted),
                            ),
                            if (note.tags.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final t in note.tags)
                                    HeroChip(
                                      label: '#$t',
                                      small: true,
                                      color: HeroColorRole.neutral,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One muted caption line: manga · chapter · page · time ago.
  /// Chapter shows the human chapter/episode NAME when present — the raw
  /// chapterId is a database row id and was rendered as "Chapter 8234234".
  String _metaLine() {
    final parts = <String>[
      if (note.mangaTitle.isNotEmpty) note.mangaTitle,
      if ((note.chapterName ?? '').trim().isNotEmpty) note.chapterName!,
      if (note.page > 0) 'Page ${note.page + 1}',
      timeAgo(note.createdAt),
    ];
    return parts.join(' · ');
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showHeroDeleteConfirm(
      context: context,
      title: 'Delete note?',
      message: 'This note will be permanently removed.',
      confirmLabel: 'Delete',
    );
    return result;
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) => SingleChildScrollView(
        child: _EditNoteSheet(note: note),
      ),
    );
  }

  Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.35).clamp(0.0, 1.0)).toColor();
  }
}

class _EditNoteSheet extends ConsumerStatefulWidget {
  const _EditNoteSheet({required this.note});
  final Note note;

  @override
  ConsumerState<_EditNoteSheet> createState() => _EditNoteSheetState();
}

class _EditNoteSheetState extends ConsumerState<_EditNoteSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.note.content);
  late NoteColor _color = widget.note.color;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit note',
              style: HeroTokens.title.copyWith(color: h.foreground)),
          const SizedBox(height: 12),
          HeroInput(
            controller: _controller,
            maxLines: 6,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Text('Color', style: HeroTokens.caption.copyWith(color: h.muted)),
          const SizedBox(height: 8),
          _ColorPicker(
            color: _color,
            onPick: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HeroButton(
                label: 'Cancel',
                variant: HeroButtonVariant.light,
                color: HeroColorRole.neutral,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              HeroButton(
                label: 'Save',
                onPressed: () async {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(context);
                  // REAL update — persists text + colour through the
                  // repository; the Isar watch refreshes the card list.
                  try {
                    await ref.read(notesProvider.notifier).update(
                          widget.note.id,
                          text: text,
                          color: _color,
                        );
                    if (context.mounted) {
                      showSnack(ref, context, 'Note updated');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showSnack(ref, context, 'Could not update note');
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 7-colour picker — each swatch carries a semantic meaning shown as a
/// tooltip.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.color, required this.onPick});

  final NoteColor color;
  final ValueChanged<NoteColor> onPick;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: NoteColor.values
          .map((c) => GestureDetector(
                onTap: () => onPick(c),
                child: Tooltip(
                  message: c.meaning,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.color,
                      shape: BoxShape.circle,
                      border: color == c
                          ? Border.all(color: h.foreground, width: 3)
                          : null,
                    ),
                    child:
                        color == c ? const Icon(Icons.check, size: 18) : null,
                  ),
                ),
              ))
          .toList(),
    );
  }
}
