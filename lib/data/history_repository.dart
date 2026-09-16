// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// HISTORY REPOSITORY — reading/watching timeline persistence.

import 'package:isar/isar.dart';

import '../models/chapter.dart' as db;
import '../models/history.dart' as db;
import '../models/mappers.dart' as map;
import '../models/models.dart' as dto;
import '../providers/storage_provider.dart';

class HistoryRepository {
  HistoryRepository(StorageProvider storage) : _isar = storage.isar;
  final Isar _isar;

  Future<List<dto.HistoryEntry>> getHistory() async {
    final entries = await _isar.historys
        .where()
        .sortByLastReadAtDesc()
        .findAll();
    return entries.map(map.historyToDto).toList();
  }

  /// Records that the user opened/progressed a chapter. Upserts by
  /// (mangaId, chapterId) so the timeline shows one row per chapter.
  Future<void> recordRead({
    required int mangaId,
    required int chapterId,
    required String chapterName,
    required double chapterNumber,
    required String mangaTitle,
    String? mangaCover,
    required bool isAnime,
    required double progress,
    int? page,
    int? totalPages,
  }) async {
    final now = DateTime.now();
    final existing = await _isar.historys
        .filter()
        .mangaIdEqualTo(mangaId)
        .and()
        .chapterIdEqualTo(chapterId)
        .findFirst();
    final entry = existing ??
        db.History(
          mangaId: mangaId,
          chapterId: chapterId,
          startedAt: now.millisecondsSinceEpoch,
        );
    entry
      ..chapterName = chapterName
      ..chapterNumber = chapterNumber.toString()
      ..mangaTitle = mangaTitle
      ..mangaCover = mangaCover
      ..isAnime = isAnime
      ..isManga = !isAnime
      ..progress = progress.clamp(0.0, 1.0)
      ..lastReadPage = page
      ..totalPages = totalPages
      ..mediaType =
          isAnime ? db.HistoryMediaType.anime : db.HistoryMediaType.manga
      ..lastReadAt = now.millisecondsSinceEpoch
      ..isCompleted = progress >= 1.0;
    await _isar.writeTxn(() async {
      await _isar.historys.put(entry);
    });
  }

  Future<void> remove(int historyId) async {
    await _isar.writeTxn(() async {
      await _isar.historys.delete(historyId);
    });
  }

  Future<void> clearAll() async {
    await _isar.writeTxn(() async {
      await _isar.historys.clear();
    });
  }

  Stream<void> watchHistory() {
    return _isar.historys.watchLazy(fireImmediately: true);
  }

  /// Convenience: the chapter DB row for a chapter id (used by readers that
  /// need scanlator / page metadata for history rows).
  Future<db.Chapter?> chapterById(int chapterId) =>
      _isar.chapters.get(chapterId);
}
