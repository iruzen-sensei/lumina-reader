// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// DOWNLOADS REPOSITORY — persistent download queue state (Isar `Download`
// collection). The transfer engine (services/download_manager) reports state
// changes here; the UI watches the collection and stays in sync across
// app restarts.

import 'package:isar/isar.dart';

import '../models/download.dart' as db;
import '../models/mappers.dart' as map;
import '../models/models.dart' as dto;
import '../providers/storage_provider.dart';

class DownloadsRepository {
  DownloadsRepository(StorageProvider storage) : _isar = storage.isar;
  final Isar _isar;

  Future<List<dto.DownloadTask>> getAll() async {
    final rows = await _isar.downloads.where().sortByRequestedAtDesc().findAll();
    return rows.map(map.downloadToDto).toList();
  }

  /// Enqueues a chapter/episode download (deduplicated by manga+chapter).
  Future<int> enqueue({
    required int mangaId,
    required int chapterId,
    required String mangaTitle,
    required String chapterName,
    required bool isAnime,
    String? mangaCover,
    List<String>? urls,
  }) async {
    final existing = await _isar.downloads
        .filter()
        .mangaIdEqualTo(mangaId)
        .and()
        .chapterIdEqualTo(chapterId)
        .findFirst();
    if (existing != null && existing.isTerminal) {
      // Re-enqueue a finished/cancelled download.
      existing
        ..state = db.DownloadState.queued
        ..success = 0
        ..failed = 0
        ..lastError = null
        ..requestedAt = DateTime.now().millisecondsSinceEpoch;
      await _isar.writeTxn(() async => _isar.downloads.put(existing));
      return existing.id;
    }
    if (existing != null) return existing.id; // already queued/active

    final row = db.Download(
      mangaId: mangaId,
      chapterId: chapterId,
      chapterName: chapterName,
      mangaTitle: mangaTitle,
      mangaCover: mangaCover,
      isAnime: isAnime,
      isManga: !isAnime,
      mediaType:
          isAnime ? db.DownloadMediaType.anime : db.DownloadMediaType.manga,
      state: db.DownloadState.queued,
      priority: db.DownloadPriority.normal,
      urls: urls,
      requestedAt: DateTime.now().millisecondsSinceEpoch,
      retryCount: 0,
      maxRetries: 3,
    );
    return _isar.writeTxn(() async => _isar.downloads.put(row));
  }

  Future<void> updateState(
    int downloadId, {
    required db.DownloadState state,
    int? success,
    int? failed,
    int? total,
    String? error,
    int? downloadedBytes,
    int? fileSize,
    String? savedPath,
  }) async {
    await _isar.writeTxn(() async {
      final d = await _isar.downloads.get(downloadId);
      if (d == null) return;
      d
        ..state = state
        ..updatedAt = DateTime.now().millisecondsSinceEpoch
        ..isDownloaded = state == db.DownloadState.completed
        ..success = success ?? d.success
        ..failed = failed ?? d.failed
        ..total = total ?? d.total
        ..lastError = error
        ..downloadedBytes = downloadedBytes ?? d.downloadedBytes
        ..fileSize = fileSize ?? d.fileSize;
      if (savedPath != null) d.downloadPath = savedPath;
      if (state == db.DownloadState.completed) {
        d.completedAt = DateTime.now().millisecondsSinceEpoch;
      }
      await _isar.downloads.put(d);
    });
  }

  /// Transitions every active row to paused (used on app start to recover
  /// from an unclean shutdown).
  Future<void> recoverOrphans() async {
    await _isar.writeTxn(() async {
      final active = await _isar.downloads
          .filter()
          .stateEqualTo(db.DownloadState.downloading)
          .findAll();
      for (final d in active) {
        d.state = db.DownloadState.queued;
        await _isar.downloads.put(d);
      }
    });
  }

  Future<void> pause(int downloadId) =>
      updateState(downloadId, state: db.DownloadState.paused);

  Future<void> resume(int downloadId) =>
      updateState(downloadId, state: db.DownloadState.queued);

  Future<void> cancel(int downloadId) =>
      updateState(downloadId, state: db.DownloadState.cancelled);

  Future<void> markFailed(int downloadId, String error) =>
      updateState(downloadId, state: db.DownloadState.failed, error: error);

  Future<void> remove(int downloadId) async {
    await _isar.writeTxn(() async {
      await _isar.downloads.delete(downloadId);
    });
  }

  Future<void> clearCompleted() async {
    await _isar.writeTxn(() async {
      final done = await _isar.downloads
          .filter()
          .stateEqualTo(db.DownloadState.completed)
          .findAll();
      await _isar.downloads
          .deleteAll(done.map((d) => d.id).toList());
    });
  }

  Stream<void> watch() {
    return _isar.downloads.watchLazy(fireImmediately: true);
  }
}
