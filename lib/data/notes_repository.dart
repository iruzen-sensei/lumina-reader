// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NOTES REPOSITORY — highlights & thoughts persistence (7-color semantic
// system, ordinal-aligned with the presentation NoteColor enum).

import 'package:isar/isar.dart';

import '../models/manga.dart' as db;
import '../models/mappers.dart' as map;
import '../models/models.dart' as dto;
import '../models/note.dart' as db;
import '../providers/storage_provider.dart';

class NotesRepository {
  NotesRepository(StorageProvider storage) : _isar = storage.isar;
  final Isar _isar;

  Future<List<dto.Note>> getNotes() async {
    final notes = await _isar.notes.where().sortByCreatedAtDesc().findAll();
    final results = <dto.Note>[];
    for (final n in notes) {
      await n.manga.load();
      final manga = n.manga.value;
      results.add(map.noteToDto(n,
          mangaId: manga?.id,
          mangaTitle: manga?.name));
    }
    return results;
  }

  /// Creates a note linked to its manga. Returns the persisted id.
  ///
  /// [mangaId] `0` creates a GENERAL note not attached to any book (the
  /// notes screen's "New note" button) — previously this threw for every
  /// standalone note because no manga row with id 0 exists.
  Future<int> addNote({
    required int mangaId,
    required String text,
    required dto.NoteType type,
    required dto.NoteColor color,
    int? chapterId,
    String? chapterName,
    int page = 0,
    List<String> tags = const [],
  }) async {
    db.Manga? manga;
    if (mangaId != 0) {
      manga = await _isar.mangas.get(mangaId);
      if (manga == null) {
        throw ArgumentError('Cannot attach a note to missing manga #$mangaId');
      }
    }
    final now = DateTime.now();
    final note = db.Note(
      pageNumber: page,
      text: text,
      noteType: type == dto.NoteType.highlight
          ? db.NoteType.highlight
          : db.NoteType.thought,
      color: color.index,
      tags: tags,
      createdAt: now,
      updatedAt: now,
      chapterId: chapterId,
      chapterName: chapterName,
    );
    if (manga != null) note.manga.value = manga;
    return _isar.writeTxn(() async => _isar.notes.put(note));
  }

  Future<void> updateNote(int noteId,
      {String? text, dto.NoteColor? color, List<String>? tags}) async {
    await _isar.writeTxn(() async {
      final n = await _isar.notes.get(noteId);
      if (n == null) return;
      if (text != null) n.text = text;
      if (color != null) n.color = color.index;
      if (tags != null) n.tags = tags;
      n.updatedAt = DateTime.now();
      await _isar.notes.put(n);
    });
  }

  Future<void> deleteNote(int noteId) async {
    await _isar.writeTxn(() async {
      await _isar.notes.delete(noteId);
    });
  }

  Stream<void> watchNotes() {
    return _isar.notes.watchLazy(fireImmediately: true);
  }
}
