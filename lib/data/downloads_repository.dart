// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// DOWNLOADS REPOSITORY — persistent download queue state (Isar `Download`
// collection). The transfer engine (services/download_manager) reports state
// changes here; the UI watches the collection and stays in sync across
// app restarts.

import 'dart:io';

import 'package:isar/isar.dart';

import '../models/chapter.dart' as db_ch;
import '../models/download.dart' as db;
import '../models/mappers.dart' as map;
import '../models/models.dart' as dto;
import '../providers/storage_provider.dart';

class DownloadsRepository {
  DownloadsRepository(StorageProvider storage)
      : _isar = storage.isar,
        _storage = storage;
  final Isar _isar;
  final StorageProvider _storage;

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

  /// The chapter id a queue row refers to (null for malformed rows).
  Future<int?> chapterIdFor(int downloadId) async {
    final row = await _isar.downloads.get(downloadId);
    return row?.chapterId;
  }

  /// Removes EVERY queue row for a chapter, deletes its downloaded files
  /// on disk and resets the chapter's downloaded flag. This is what the
  /// "delete download" affordances call — previously only the queue row
  /// was removed, so files stayed on disk and the checkmark never cleared.
  Future<void> removeByChapter(int chapterId) async {
    final rows = await _isar.downloads
        .filter()
        .chapterIdEqualTo(chapterId)
        .findAll();
    if (rows.isNotEmpty) {
      await _isar.writeTxn(
          () async => _isar.downloads.deleteAll(rows.map((d) => d.id).toList()));
    }

    final c = await _isar.chapters.get(chapterId);
    if (c != null) {
      await c.manga.load();
      final m = c.manga.value;
      if (m != null) {
        final baseDir = await _storage.getDownloadsDir();
        final dir = Directory('$baseDir/chapters/${m.id}/$chapterId');
        if (dir.existsSync()) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
        // Anime episodes are saved as a single .ts file next to the dir.
        final tsFile = File('$baseDir/chapters/${m.id}/$chapterId.ts');
        if (tsFile.existsSync()) {
          try {
            await tsFile.delete();
          } catch (_) {}
        }
      }
      await _isar.writeTxn(() async {
        c
          ..isDownloaded = false
          ..isDownloading = false
          ..downloadProgress = 0.0;
        await _isar.chapters.put(c);
      });
    }
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

  /// Deletes EVERY download row (any state). Wired to Settings → Delete all
  /// downloads; the caller also removes the on-disk files.
  Future<void> clearAll() async {
    await _isar.writeTxn(() async {
      await _isar.downloads.clear();
    });
  }

  /// Deletes EVERY downloaded chapter/episode file AND resets every
  /// chapter's downloaded flag, while PRESERVING the `imports/` directory
  /// (user-imported EPUB/PDF/CBZ/videos live there — the previous
  /// "delete all" removed the whole downloads dir and destroyed the
  /// source files of imported books).
  Future<void> deleteAllFiles() async {
    await clearAll();
    final baseDir = await _storage.getDownloadsDir();
    final chaptersDir = Directory('$baseDir/chapters');
    if (chaptersDir.existsSync()) {
      try {
        await chaptersDir.delete(recursive: true);
      } catch (_) {}
    }
    // Reset every chapter flag so the UI shows the honest state.
    await _isar.writeTxn(() async {
      final chapters = await _isar.chapters.where().findAll();
      for (final c in chapters) {
        if (c.isDownloaded || c.isDownloading) {
          c
            ..isDownloaded = false
            ..isDownloading = false
            ..downloadProgress = 0.0;
          await _isar.chapters.put(c);
        }
      }
    });
  }

  Stream<void> watch() {
    return _isar.downloads.watchLazy(fireImmediately: true);
  }
}
