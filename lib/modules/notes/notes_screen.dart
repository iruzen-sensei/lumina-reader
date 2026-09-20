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
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The notes screen.
///
/// Displays user highlights and thoughts as cards with a color-coded left
/// border (7 semantic colours: yellow / green / blue / pink / purple /
/// orange / red). Tabs switch between All / Highlights / Thoughts; a search
/// field and a per-book filter strip narrow the list further. Each card
/// exposes copy, edit and delete actions.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final notes = ref.watch(filteredNotesProvider);
    final books = ref.watch(notesProvider).map((n) => n.mangaId).toSet();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                          onPressed: () => _showCreateSheet(context),
                        ),
                      ),
                    )
                  : SliverList.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _NoteCard(note: notes[i]),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context),
        icon: const Icon(Icons.note_add),
        label: const Text('New note'),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _CreateNoteSheet(),
    );
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
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: bookIds.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return StatusChip(
              label: 'All books',
              selected: selectedBook == null,
              onTap: () =>
                  ref.read(notesBookFilterProvider.notifier).state = null,
            );
          }
          final id = bookIds[i - 1];
          final title = allNotes.firstWhere((n) => n.mangaId == id).mangaTitle;
          return StatusChip(
            label: title,
            selected: selectedBook == id,
            onTap: () => ref.read(notesBookFilterProvider.notifier).state = id,
          );
        },
      ),
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
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
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
                            const SizedBox(height: 8),
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
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _ActionChip(
                                  icon: Icons.copy_outlined,
                                  label: 'Copy',
                                  color: h.accent,
                                  onTap: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: note.content));
                                    if (context.mounted) {
                                      showSnack(ref, context, 'Note copied');
                                    }
                                  },
                                ),
                                const SizedBox(width: 6),
                                _ActionChip(
                                  icon: Icons.edit_outlined,
                                  label: 'Edit',
                                  color: h.accent,
                                  onTap: () => _showEditSheet(context, ref),
                                ),
                                const SizedBox(width: 6),
                                _ActionChip(
                                  icon: Icons.delete_outline,
                                  label: 'Delete',
                                  color: h.danger,
                                  onTap: () async {
                                    if (await _confirmDelete(context) &&
                                        context.mounted) {
                                      // REAL deletion — the notifier watches
                                      // the Isar collection so the list updates.
                                      await ref
                                          .read(notesProvider.notifier)
                                          .delete(note.id);
                                      if (context.mounted) {
                                        showSnack(ref, context, 'Note deleted');
                                      }
                                    }
                                  },
                                ),
                              ],
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
      ),
    );
  }

  /// One muted caption line: manga · chapter · page · time ago.
  String _metaLine() {
    final parts = <String>[
      if (note.mangaTitle.isNotEmpty) note.mangaTitle,
      if (note.chapterId != null) 'Chapter ${note.chapterId}',
      if (note.page > 0) 'Page ${note.page + 1}',
      timeAgo(note.createdAt),
    ];
    return parts.join(' · ');
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showHeroConfirm(
      context: context,
      title: 'Delete note?',
      message: 'This note will be permanently removed.',
      confirmLabel: 'Delete',
      danger: true,
    );
    return result;
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EditNoteSheet(note: note),
    );
  }

  Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.35).clamp(0.0, 1.0)).toColor();
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final c = color ?? h.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: c)),
          ],
        ),
      ),
    );
  }
}

class _CreateNoteSheet extends ConsumerStatefulWidget {
  const _CreateNoteSheet();

  @override
  ConsumerState<_CreateNoteSheet> createState() => _CreateNoteSheetState();
}

class _CreateNoteSheetState extends ConsumerState<_CreateNoteSheet> {
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New note',
              style: HeroTokens.title.copyWith(color: h.foreground)),
          const SizedBox(height: 12),
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
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Text('Color', style: HeroTokens.caption.copyWith(color: h.muted)),
          const SizedBox(height: 6),
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
              const SizedBox(width: 10),
              HeroButton(
                label: 'Save',
                onPressed: () async {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(context);
                  // REAL persistence — general note (mangaId 0). The
                  // notifier's Isar watch refreshes the list automatically.
                  try {
                    await ref.read(notesProvider.notifier).add(
                          mangaId: 0,
                          text: text,
                          type: _type,
                          color: _color,
                        );
                    if (context.mounted) {
                      showSnack(ref, context, 'Note saved');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showSnack(ref, context, 'Could not save note');
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
          const SizedBox(height: 6),
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
              const SizedBox(width: 10),
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
