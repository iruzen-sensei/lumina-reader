// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// LIBRARY UPDATER — checks every library entry with a source for new
// chapters/episodes and records them in the Isar `Update` collection (the
// Updates feed).
//
// This is a full rewrite: the previous version defined its own parallel
// Manga/Chapter/Source/Update classes (name-colliding with the canonical
// models), placed imports after declarations (a Dart syntax error), and
// relied on a SourceRegistry that nothing ever populated. It now works
// exclusively through the canonical repositories + ExtensionCoordinator.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../data/downloads_repository.dart';
import '../data/library_repository.dart';
import '../models/category.dart' as db_c;
import '../models/chapter.dart';
import '../models/manga.dart' as db_m;
import '../models/models.dart' as dto;
import '../models/settings.dart' as db_s;
import '../models/update.dart' as db;
import '../providers/storage_provider.dart';
import 'extension_coordinator.dart';

class LibraryUpdater {
  LibraryUpdater({
    required StorageProvider storage,
    required LibraryRepository library,
    required ExtensionCoordinator coordinator,
    this.interval = const Duration(minutes: 30),
    this.maxConcurrent = 3,
  })  : _isar = storage.isar,
        _storage = storage,
        _library = library,
        _coordinator = coordinator;

  final Isar _isar;
  final StorageProvider _storage;
  final LibraryRepository _library;
  final ExtensionCoordinator _coordinator;
  final Duration interval;
  final int maxConcurrent;

  Timer? _timer;
  bool _running = false;
  DateTime? _lastRun;

  bool get isRunning => _running;
  DateTime? get lastRun => _lastRun;

  /// Starts the periodic check (no-op if already started).
  void start() {
    _timer ??= Timer.periodic(interval, (_) => runOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One update pass across every source-backed library entry. Safe to call
  /// concurrently — extra invocations return immediately.
  Future<int> runOnce() async {
    if (_running) return 0;
    _running = true;
    var newChapters = 0;
    try {
      // Wi-Fi gate: skip the pass on metered connections when the user
      // enabled the setting elsewhere; library updates are light, so we
      // only skip when completely offline.
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        debugPrint('LibraryUpdater: offline, skipping pass');
        return 0;
      }

      final library = await _library.getLibrary();
      final sourceBacked = library
          .where((m) => m.sourceId != 0 && m.chapters.isNotEmpty)
          .toList();
      if (sourceBacked.isEmpty) return 0;

      // Bounded concurrency across entries.
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < sourceBacked.length) {
          final manga = sourceBacked[cursor++];
          try {
            newChapters += await _checkEntry(manga);
          } catch (e) {
            debugPrint('LibraryUpdater: ${manga.title} failed: $e');
          }
        }
      }

      await Future.wait(
        List.generate(maxConcurrent.clamp(1, 8), (_) => worker()),
      );
      _lastRun = DateTime.now();
    } finally {
      _running = false;
    }
    return newChapters;
  }

  /// Fetches the current chapter list for one entry, persists new chapters,
  /// and records an [db.Update] row per discovery. Returns the number of
  /// new chapters found.
  Future<int> _checkEntry(dto.Manga manga) async {
    if (manga.sourceId == 0) return 0;
    final fresh = await _coordinator.detail(manga.sourceId, manga.url);
    if (fresh.chapters.isEmpty) return 0;

    final existingUrls = manga.chapters.map((c) => c.url).toSet();
    final newOnes =
        fresh.chapters.where((c) => !existingUrls.contains(c.url)).toList();
    if (newOnes.isEmpty) return 0;

    // Persist the refreshed chapter list (progress-preserving upsert).
    await _library.setChapters(manga.id, fresh.chapters);

    // Resolve the persisted chapter rows so each Update row carries the
    // Isar chapter id + download flag. Without chapterId the Updates feed's
    // download / delete-download quick actions can never fire (they guard
    // on chapterId == null), which left the buttons decorative.
    final persistedChapters = await _isar.chapters
        .filter()
        .manga((q) => q.idEqualTo(manga.id))
        .findAll();
    final persistedByUrl = {
      for (final pc in persistedChapters) pc.url: pc,
    };

    // Record an Update row per new chapter for the Updates feed.
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = [
      for (final c in newOnes)
        db.Update(
          mangaId: manga.id,
          chapterId: persistedByUrl[c.url]?.id,
          isDownloaded: persistedByUrl[c.url]?.isDownloaded ?? false,
          chapterName: c.name,
          chapterNumber: c.number.toString(),
          chapterNumberValue: c.number,
          url: c.url,
          isAnime: manga.isAnime,
          isManga: !manga.isAnime,
          mangaTitle: manga.title,
          mangaCover: manga.thumbnailUrl,
          state: db.UpdateState.unread,
          date: now,
          discoveredAt: now,
        ),
    ];
    await _isar.writeTxn(() async {
      await _isar.updates.putAll(rows);
    });

    // AUTO-DOWNLOAD: when the user enabled it (Settings → Downloads), new
    // chapters of entries in the selected categories are queued through
    // the download engine automatically. Previously the toggle and the
    // category picker were persisted but nothing ever consumed them.
    await _maybeAutoDownload(manga, newOnes);
    return newOnes.length;
  }

  Future<void> _maybeAutoDownload(
      dto.Manga manga, List<dto.Chapter> newChapters) async {
    try {
      final s = await _isar.settings.get(227);
      if (s?.downloadAutoNew != true) return;

      // Category gate: when the user picked specific categories, only
      // entries in those categories auto-download.
      final cats = s?.downloadAutoCategories;
      if (cats != null && cats.isNotEmpty) {
        final catNames = (await _isar.categorys.where().findAll())
            .where((c) => cats.contains(c.id))
            .map((c) => c.name)
            .toSet();
        if (catNames.isNotEmpty) {
          final row = await _isar.mangas.get(manga.id);
          if (row?.category == null || !catNames.contains(row!.category)) {
            return;
          }
        }
      }

      final downloads = DownloadsRepository(_storage);
      final refreshed = await _isar.mangas.get(manga.id);
      if (refreshed == null) return;
      await refreshed.chapters.load();
      final byUrl = {for (final c in refreshed.chapters) c.url: c};
      for (final c in newChapters) {
        final row = byUrl[c.url];
        if (row == null || row.id == null || row.isDownloaded) continue;
        await downloads.enqueue(
          mangaId: manga.id,
          chapterId: row.id!,
          mangaTitle: manga.title,
          chapterName: c.name,
          isAnime: manga.isAnime,
          mangaCover: manga.thumbnailUrl,
        );
      }
    } catch (e) {
      debugPrint('LibraryUpdater auto-download failed: $e');
    }
  }

  /// Marks every update row as seen (called when the Updates tab opens).
  Future<void> markAllSeen() async {
    await _isar.writeTxn(() async {
      final unseen = await _isar.updates
          .filter()
          .isSeenEqualTo(false)
          .or()
          .isSeenIsNull()
          .findAll();
      for (final u in unseen) {
        u.isSeen = true;
      }
      await _isar.updates.putAll(unseen);
    });
  }

  /// Unread update count (badge on the library nav item).
  Future<int> unreadCount() => _isar.updates
      .filter()
      .stateEqualTo(db.UpdateState.unread)
      .count();
}
