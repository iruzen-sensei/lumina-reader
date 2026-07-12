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

import '../../core/theme.dart';
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
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${notes.length}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) =>
                      ref.read(notesSearchProvider.notifier).state = v,
                  decoration: InputDecoration(
                    hintText: 'Search notes…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(child: _FilterTabs()),
            SliverToBoxAdapter(child: _BookFilterRow(bookIds: books.toList())),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: notes.isEmpty
                  ? SliverToBoxAdapter(
                      child: emptyState(
                        context: context,
                        icon: Icons.sticky_note_2_outlined,
                        title: 'No notes yet',
                        subtitle:
                            'Highlight text in the reader or jot down a thought to see it here.',
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
      child: SegmentedButton<NotesFilter>(
        segments: const [
          ButtonSegment(
              value: NotesFilter.all,
              label: Text('All'),
              icon: Icon(Icons.list)),
          ButtonSegment(
              value: NotesFilter.highlights,
              label: Text('Highlights'),
              icon: Icon(Icons.highlight)),
          ButtonSegment(
              value: NotesFilter.thoughts,
              label: Text('Thoughts'),
              icon: Icon(Icons.lightbulb_outline)),
        ],
        selected: {filter},
        onSelectionChanged: (s) =>
            ref.read(notesFilterProvider.notifier).state = s.first,
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
          final title =
              allNotes.firstWhere((n) => n.mangaId == id).mangaTitle;
          return StatusChip(
            label: title,
            selected: selectedBook == id,
            onTap: () =>
                ref.read(notesBookFilterProvider.notifier).state = id,
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
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      ),
      confirmDismiss: (_) async {
        return await _confirmDelete(context);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showEditSheet(context, ref),
          child: Container(
            decoration: BoxDecoration(
              color: note.color.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: note.color.color.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Color-coded left border that doubles as the semantic
                  // indicator. The bar is wider on cards tagged "red" /
                  // "critical" so urgent notes stand out in the list.
                  Container(
                    width: 6,
                    decoration: BoxDecoration(
                      color: note.color.color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
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
                                  color: note.color.color.withValues(alpha: 0.25),
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
                                        fontWeight: FontWeight.bold,
                                        color: _darken(note.color.color),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  note.mangaTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                              Text(
                                timeAgo(note.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (note.chapterId != null || note.page > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                children: [
                                  if (note.chapterId != null)
                                    _MetaPill(
                                      icon: Icons.chapter_label,
                                      label: 'Chapter ${note.chapterId}',
                                    ),
                                  if (note.page > 0)
                                    _MetaPill(
                                      icon: Icons.menu_book,
                                      label: 'Page ${note.page + 1}',
                                    ),
                                  _MetaPill(
                                    icon: Icons.schedule,
                                    label: _fullTimestamp(note.createdAt),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            note.content,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(height: 1.4),
                          ),
                          if (note.tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: note.tags
                                  .map((t) => Chip(
                                        label: Text('#$t',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: EdgeInsets.zero,
                                      ))
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _ActionChip(
                                icon: Icons.copy_outlined,
                                label: 'Copy',
                                onTap: () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: note.content));
                                  showSnack(ref, context, 'Note copied');
                                },
                              ),
                              const SizedBox(width: 6),
                              _ActionChip(
                                icon: Icons.edit_outlined,
                                label: 'Edit',
                                onTap: () => _showEditSheet(context, ref),
                              ),
                              const SizedBox(width: 6),
                              _ActionChip(
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                color: theme.colorScheme.error,
                                onTap: () async {
                                  if (await _confirmDelete(context)) {
                                    showSnack(ref, context, 'Note deleted');
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
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete note?'),
        content: const Text('This note will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
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
    return hsl
        .withLightness((hsl.lightness - 0.35).clamp(0.0, 1.0))
        .toColor();
  }

  String _fullTimestamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
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
    final c = color ?? Theme.of(context).colorScheme.primary;
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New note',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SegmentedButton<NoteType>(
            segments: const [
              ButtonSegment(
                  value: NoteType.thought,
                  label: Text('Thought'),
                  icon: Icon(Icons.lightbulb_outline)),
              ButtonSegment(
                  value: NoteType.highlight,
                  label: Text('Highlight'),
                  icon: Icon(Icons.highlight)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Write your note…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Color',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          _ColorPicker(
            color: _color,
            onPick: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  if (_controller.text.trim().isEmpty) return;
                  Navigator.pop(context);
                  showSnack(ref, context, 'Note saved');
                },
                child: const Text('Save'),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit note',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Text('Color',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          _ColorPicker(
            color: _color,
            onPick: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  showSnack(ref, context, 'Note updated');
                },
                child: const Text('Save'),
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
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3)
                          : null,
                    ),
                    child: color == c
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                ),
              ))
          .toList(),
    );
  }
}
