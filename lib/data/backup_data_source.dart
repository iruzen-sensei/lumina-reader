// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// ISAR BACKUP DATA SOURCE — the production [BackupDataSource] that binds the
// (previously never-instantiated) BackupService to the app's Isar database.
//
// Fetch methods load IsarLinks so the service serialises parent references
// (chapter→manga, note→manga, session→manga). Upserts persist objects WITH
// their links (Isar `putAll` saves links that have `.value` assigned).

import 'package:isar/isar.dart';

import '../models/category.dart' as db;
import '../models/chapter.dart' as db;
import '../models/history.dart' as db;
import '../models/manga.dart' as db;
import '../models/note.dart' as db;
import '../models/settings.dart' as db;
import '../models/track.dart' as db;
import '../models/update.dart' as db;
import '../models/reading_session.dart' as db;
import '../services/backup.dart';

class IsarBackupDataSource implements BackupDataSource {
  IsarBackupDataSource(this._isar);

  final Isar _isar;

  // -- Fetch --------------------------------------------------------------

  @override
  Future<List<db.Manga>> fetchManga() => _isar.mangas.where().findAll();

  @override
  Future<List<db.Chapter>> fetchChapters() async {
    final chapters = await _isar.chapters.where().findAll();
    for (final c in chapters) {
      await c.manga.load();
    }
    return chapters;
  }

  @override
  Future<List<db.Note>> fetchNotes() async {
    final notes = await _isar.notes.where().findAll();
    for (final n in notes) {
      await n.manga.load();
    }
    return notes;
  }

  @override
  Future<List<db.ReadingSession>> fetchSessions() async {
    final sessions = await _isar.readingSessions.where().findAll();
    for (final s in sessions) {
      await s.manga.load();
    }
    return sessions;
  }

  @override
  Future<List<db.History>> fetchHistory() =>
      _isar.historys.where().findAll();

  @override
  Future<List<db.Category>> fetchCategories() =>
      _isar.categorys.where().findAll();

  @override
  Future<List<db.Track>> fetchTracks() => _isar.tracks.where().findAll();

  @override
  Future<db.Settings?> fetchSettings() async => _isar.settings.get(227);

  // -- Upsert -------------------------------------------------------------

  @override
  Future<void> upsertManga(Iterable<db.Manga> entries) =>
      _isar.writeTxn(() => _isar.mangas.putAll(entries.toList()));

  @override
  Future<void> upsertChapters(Iterable<db.Chapter> entries) =>
      _isar.writeTxn(() => _isar.chapters.putAll(entries.toList()));

  @override
  Future<void> upsertNotes(Iterable<db.Note> entries) =>
      _isar.writeTxn(() => _isar.notes.putAll(entries.toList()));

  @override
  Future<void> upsertSessions(Iterable<db.ReadingSession> entries) =>
      _isar.writeTxn(() => _isar.readingSessions.putAll(entries.toList()));

  @override
  Future<void> upsertHistory(Iterable<db.History> entries) =>
      _isar.writeTxn(() => _isar.historys.putAll(entries.toList()));

  @override
  Future<void> upsertCategories(Iterable<db.Category> entries) =>
      _isar.writeTxn(() => _isar.categorys.putAll(entries.toList()));

  @override
  Future<void> upsertTracks(Iterable<db.Track> entries) =>
      _isar.writeTxn(() => _isar.tracks.putAll(entries.toList()));

  @override
  Future<void> saveSettings(db.Settings settings) =>
      _isar.writeTxn(() => _isar.settings.put(settings));

  // -- Clear --------------------------------------------------------------

  @override
  Future<void> clearAll() async {
    await _isar.writeTxn(() async {
      await _isar.chapters.clear();
      await _isar.mangas.clear();
      await _isar.notes.clear();
      await _isar.readingSessions.clear();
      await _isar.historys.clear();
      await _isar.categorys.clear();
      await _isar.tracks.clear();
      await _isar.updates.clear();
      // Settings row is intentionally preserved (device-specific prefs).
    });
  }
}
