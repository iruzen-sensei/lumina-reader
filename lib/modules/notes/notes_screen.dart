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
/// Thoughts; a search field and a title filter picker narrow the list
/// further.
///
/// ONE create affordance exists: the watermelon.sh Expand Details band
/// under the header (the old FAB + sheet and the duplicate empty-state
/// button are gone — the user saw two "create" buttons and one appeared
/// dead). Notes can be attached to ANY library title — manga, anime,
/// novels and books — or kept general. Deleting a note uses the rare-ui
/// HeroDeleteButton morph (bin → ✓/✗ circles) right on the card.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _composerKey = GlobalKey();

  /// Bumping this regenerates the composer with initiallyOpen.
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
    final allNotes = ref.watch(notesProvider);
    final notes = ref.watch(filteredNotesProvider);
    final filtering = ref.watch(notesFilterProvider) != NotesFilter.all ||
        ref.watch(notesSearchProvider).trim().isNotEmpty ||
        ref.watch(notesBookFilterProvider) != null;

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
                      label: '${allNotes.length}',
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
            // ---- THE single create affordance: Expand Details band ----
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
            SliverToBoxAdapter(child: _TitleFilterPicker(notes: allNotes)),
            SliverPadding(
              // Bottom nav bar clearance.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: notes.isEmpty
                  ? SliverToBoxAdapter(
                      child: emptyState(
                        context: context,
                        icon: filtering
                            ? Icons.filter_alt_off_outlined
                            : Icons.sticky_note_2_outlined,
                        title: filtering
                            ? 'No notes match'
                            : 'No notes yet',
                        subtitle: filtering
                            ? 'Try a different tab, search or title filter.'
                            : 'Open the “New note” band above to jot down a thought, '
                                'or highlight text while reading.',
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
}

// ---------------------------------------------------------------------------
// Composer — watermelon.sh Expand Details. Collapsed: a compact
// "New note" band. Expanded: the full editor springs open in place,
// including an "Attach to" picker so notes can live on manga, anime,
// novels and books — not just general.
//
// NOTE: no HeroCard wrapper — the card + ExpandDetails borders stacked
// into the doubled "rectangular outline" artifact (same family as the
// search pill). The ExpandDetails surface IS the component.
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

  /// Attachment target: null = general note (not linked to a title).
  _NoteTarget? _target;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final targets = ref.watch(noteTargetsProvider);
    return WmExpandDetails(
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
            // ---- Attach to a title (manga / anime / novel / book) ----
            Text('Attach to', style: HeroTokens.caption.copyWith(color: h.muted)),
            const SizedBox(height: 8),
            WmQuickOptionPicker<_NoteTarget?>(
              hint: 'Title',
              trayAbove: false,
              value: _target,
              options: [
                WmPickerOption<_NoteTarget?>(
                  value: null,
                  label: 'General note',
                  icon: Icons.notes_rounded,
                ),
                for (final t in targets)
                  WmPickerOption<_NoteTarget?>(
                    value: t,
                    label: t.title,
                    icon: t.icon,
                  ),
              ],
              onChanged: (t) => setState(() => _target = t),
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
    );
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showSnack(ref, context, 'Write something first');
      return;
    }
    _controller.clear();
    final target = _target;
    // REAL persistence. mangaId 0 = general note; otherwise the note is
    // linked to the selected library title (manga / anime / novel / book).
    try {
      await ref.read(notesProvider.notifier).add(
            mangaId: target?.id ?? 0,
            text: text,
            type: _type,
            color: _color,
          );
      if (mounted) {
        setState(() => _target = null);
        showSnack(ref, context,
            target == null ? 'Note saved' : 'Note saved to “${target.title}”');
      }
    } catch (e) {
      if (mounted) showSnack(ref, context, 'Could not save note');
    }
  }
}

// ---------------------------------------------------------------------------
// Attachment targets — every library title across media types, so notes
// can live on anime and manga too (previously notes were books-only in
// practice: the composer always saved a general note).
// ---------------------------------------------------------------------------

class _NoteTarget {
  const _NoteTarget({
    required this.id,
    required this.title,
    required this.icon,
    required this.isAnime,
  });

  final int id;
  final String title;
  final IconData icon;
  final bool isAnime;
}

final noteTargetsProvider = Provider<List<_NoteTarget>>((ref) {
  final manga = ref.watch(mangaLibraryProvider);
  final anime = ref.watch(animeLibraryProvider);
  final novels = ref.watch(novelLibraryProvider);
  final books = ref.watch(bookLibraryProvider);
  return [
    for (final m in anime)
      _NoteTarget(
          id: m.id, title: m.title, icon: Icons.smart_display_rounded, isAnime: true),
    for (final m in manga)
      _NoteTarget(
          id: m.id, title: m.title, icon: Icons.menu_book_rounded, isAnime: false),
    for (final m in novels)
      _NoteTarget(
          id: m.id, title: m.title, icon: Icons.auto_stories_rounded, isAnime: false),
    for (final m in books)
      _NoteTarget(
          id: m.id, title: m.title, icon: Icons.book_rounded, isAnime: false),
  ];
});

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

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

/// The title filter — a Quick Option Picker pill that OPENS a tray with
/// All / General / every titled note's series (the old chip rail showed a
/// dead "All books" chip plus an empty chip for general notes, and tapping
/// it visibly did nothing).
class _TitleFilterPicker extends ConsumerWidget {
  const _TitleFilterPicker({required this.notes});
  final List<Note> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(notesBookFilterProvider);

    // Distinct titles that actually have notes (keeps the tray short).
    final titles = <String>{};
    for (final n in notes) {
      if (n.mangaId != 0 && n.mangaTitle.trim().isNotEmpty) {
        titles.add(n.mangaTitle);
      }
    }
    // Nothing to filter by — hide the picker entirely.
    if (titles.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: WmQuickOptionPicker<int>(
          hint: 'Filter',
          trayAbove: false,
          value: selected ?? -1,
          options: [
            WmPickerOption<int>(
                value: -1, label: 'All notes', icon: Icons.notes_rounded),
            WmPickerOption<int>(
                value: 0, label: 'General', icon: Icons.notes_rounded),
            for (final title in titles)
              WmPickerOption<int>(
                value: notes.firstWhere((n) => n.mangaTitle == title).mangaId,
                label: title,
                icon: Icons.library_books_rounded,
              ),
          ],
          onChanged: (v) =>
              ref.read(notesBookFilterProvider.notifier).state = v < 0 ? null : v,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note card — color bar, type badge, content, meta. Actions:
//   * 3-dot Split Actions: Copy / Edit (clamped overlay — never clips the
//     card padding or screen corner).
//   * rare-ui HeroDeleteButton morph: the DEFAULT delete affordance,
//     confirm (✓) / cancel (✗) circles appear inside the component.
// ---------------------------------------------------------------------------

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return Material(
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
                              // Copy / Edit — watermelon.sh Split Actions
                              // (delete moved to the HeroDeleteButton
                              // morph below the content).
                              WmSplitActions(
                                triggerIcon: Icons.more_horiz_rounded,
                                actions: [
                                  WmSplitAction(
                                    icon: Icons.copy_outlined,
                                    label: 'Copy',
                                    onTap: () async {
                                      await Clipboard.setData(
                                          ClipboardData(text: note.content));
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
                          const SizedBox(height: 12),
                          // rare-ui Delete Button — the app-wide delete
                          // component (bin morphs open; ✓ confirms, ✗
                          // keeps). Aligned LEFT so the expanded panel
                          // never runs off the card or the screen edge.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: HeroDeleteButton(
                              size: 36,
                              onConfirm: () async {
                                await ref
                                    .read(notesProvider.notifier)
                                    .delete(note.id);
                              },
                            ),
                          ),
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
    );
  }

  /// One muted caption line: manga · chapter · page · time ago.
  String _metaLine() {
    final parts = <String>[
      if (note.mangaTitle.isNotEmpty) note.mangaTitle,
      if ((note.chapterName ?? '').trim().isNotEmpty) note.chapterName!,
      if (note.page > 0) 'Page ${note.page + 1}',
      timeAgo(note.createdAt),
    ];
    return parts.join(' · ');
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
