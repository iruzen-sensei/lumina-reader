// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// DOWNLOAD ENGINE — drains the Isar download queue.
//
// The real transfer machinery (MDownloader: bounded concurrency, retries
// with backoff) existed since the remediation but was NEVER instantiated —
// enqueued chapters sat "queued" forever and every download button was
// theatre. This engine:
//   * watches the downloads collection,
//   * picks up queued rows (respecting the parallel-downloads setting),
//   * resolves page URLs through the ExtensionCoordinator,
//   * fetches the images into per-chapter directories,
//   * writes downloading → completed state + progress,
//   * flags the chapter row as downloaded (offline reads).
//
// Pause / cancel / resume work through the repository state machine: the
// engine re-checks row state between progress ticks and aborts the active
// downloader when the user pauses.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:isar/isar.dart';

import 'package:lumina_reader/data/downloads_repository.dart';
import 'package:lumina_reader/data/library_repository.dart';
import 'package:lumina_reader/data/sources_repository.dart';
import 'package:lumina_reader/models/chapter.dart';
import 'package:lumina_reader/models/download.dart' as db;
import 'package:lumina_reader/models/models.dart' show ItemType;
import 'package:lumina_reader/models/settings.dart';
import 'package:lumina_reader/providers/storage_provider.dart';
import 'package:lumina_reader/services/download_manager/m_downloader.dart';
import 'package:lumina_reader/services/extension_coordinator.dart';

class DownloadEngine {
  DownloadEngine(StorageProvider storage)
      : _isar = storage.isar,
        _downloads = DownloadsRepository(storage),
        _coordinator = ExtensionCoordinator(
          sources: SourcesRepository(storage),
          library: LibraryRepository(storage),
        );

  final Isar _isar;
  final DownloadsRepository _downloads;
  final ExtensionCoordinator _coordinator;

  StreamSubscription<void>? _sub;
  final Map<int, MDownloader> _active = {};
  bool _draining = false;
  bool _stopped = false;

  /// Starts watching the queue. Idempotent.
  void start() {
    if (_sub != null) return;
    _stopped = false;
    _sub = _isar.downloads
        .watchLazy(fireImmediately: true)
        .listen((_) => _drain());
    unawaited(_drain());
  }

  Future<void> stop() async {
    _stopped = true;
    await _sub?.cancel();
    _sub = null;
    _recheckTimer?.cancel();
    _recheckTimer = null;
    for (final d in _active.values) {
      d.cancel();
    }
    _active.clear();
  }

  // -----------------------------------------------------------------------
  // Queue drain
  // -----------------------------------------------------------------------

  Future<int> _parallelLimit() async {
    try {
      final s = await _isar.settings.get(227);
      final v = s?.downloadConcurrent ?? 3;
      return v.clamp(1, 6);
    } catch (_) {
      return 3;
    }
  }

  /// The persisted "Only download on Wi-Fi" switch — previously the
  /// setting was stored but the engine never consulted it.
  Future<bool> _wifiOnly() async {
    try {
      final s = await _isar.settings.get(227);
      return s?.downloadOnlyOverWifi ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _connectionAllowed() async {
    if (!await _wifiOnly()) return true;
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  /// Re-checks connectivity periodically while tasks wait for Wi-Fi —
  /// otherwise a queued task would sit unnoticed until the next DB write.
  void _scheduleRecheck() {
    _recheckTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      if (_stopped) {
        _recheckTimer?.cancel();
        _recheckTimer = null;
        return;
      }
      unawaited(_drain());
    });
  }

  Timer? _recheckTimer;

  Future<void> _drain() async {
    if (_draining || _stopped) return;
    _draining = true;
    try {
      // Abort active downloads the user paused / cancelled.
      await _syncActiveStates();

      while (!_stopped) {
        final limit = await _parallelLimit();
        if (_active.length >= limit) break;

        // Wi-Fi gate: when the user requires Wi-Fi and the network is
        // metered, leave the queue untouched and retry later.
        if (!await _connectionAllowed()) {
          _scheduleRecheck();
          break;
        }
        _recheckTimer?.cancel();
        _recheckTimer = null;

        final activeIds = _active.keys.toSet();
        final queued = await _isar.downloads
            .filter()
            .stateEqualTo(db.DownloadState.queued)
            .findAll();
        // Urgent > high > normal > low; then FIFO by request time.
        int rank(db.DownloadPriority? p) => switch (p) {
              db.DownloadPriority.urgent => 0,
              db.DownloadPriority.high => 1,
              db.DownloadPriority.normal => 2,
              db.DownloadPriority.low => 3,
              null => 2,
            };
        queued.sort((a, b) {
          final byPriority = rank(a.priority).compareTo(rank(b.priority));
          if (byPriority != 0) return byPriority;
          return (a.requestedAt ?? 0).compareTo(b.requestedAt ?? 0);
        });
        final next = queued.where((r) => !activeIds.contains(r.id)).toList();
        if (next.isEmpty) break;
        for (final row in next.take(limit - _active.length)) {
          unawaited(_process(row.id));
        }
        // One pass per watch event; the completion of each task re-drains.
        break;
      }
    } catch (e) {
      // The engine must never die — a broken drain just retries on the next
      // collection event.
      _log('drain failed: $e');
    } finally {
      _draining = false;
    }
  }

  /// Cancels in-flight downloads whose row state changed to a non-active
  /// state (paused / cancelled / removed).
  Future<void> _syncActiveStates() async {
    if (_active.isEmpty) return;
    final ids = _active.keys.toList();
    for (final id in ids) {
      final row = await _isar.downloads.get(id);
      if (row == null || row.state != db.DownloadState.downloading) {
        _active[id]?.cancel();
        _active.remove(id);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Single task
  // -----------------------------------------------------------------------

  Future<void> _process(int downloadId) async {
    final row = await _isar.downloads.get(downloadId);
    if (row == null || row.state != db.DownloadState.queued) return;
    final chapterId = row.chapterId;
    if (chapterId == null) {
      await _downloads.markFailed(downloadId, 'Download row has no chapter');
      return;
    }

    // Per-source HTTP headers (Referer / User-Agent). Madara-family CDNs
    // 403 every hotlinked page image without a Referer — downloads were
    // failing on exactly those sources while the online reader worked.
    final (manga, _) = await _coordinator.resolveForDownload(chapterId);
    var sourceHeaders = const <String, String>{};
    if (manga != null && manga.sourceId != 0) {
      sourceHeaders = await _coordinator.sourceHeaders(manga.sourceId);
    }

    final downloader = MDownloader(
      concurrency: 3,
      headers: sourceHeaders,
    );
    _active[downloadId] = downloader;
    await _downloads.updateState(
        downloadId, state: db.DownloadState.downloading);

    try {
      final baseDir = await StorageProvider().getDownloadsDir();
      final chapterDir = '$baseDir/chapters/${row.mangaId}/$chapterId';

      if (row.isAnime == true) {
        // ---- Anime episode: resolve stream URLs, download m3u8. ----
        final videos = await _coordinator.videoList(chapterId);
        if (videos.isEmpty) {
          throw StateError('No video streams resolved for episode #$chapterId');
        }
        final best = videos.reduce(
            (a, b) => a.height >= b.height ? a : b);
        await Directory(chapterDir).create(recursive: true);
        final outPath = '$chapterDir/$chapterId.ts';

        var lastWrite = DateTime.now();
        final savedPath = await downloader.downloadAnimeEpisode(
          m3u8Url: best.url,
          outputPath: outPath,
          // Stream-level headers (browser UA + Referer) — the m3u8/segment
          // CDN 403s requests without them.
          extraHeaders: best.headers,
          onProgress: (p) {
            final now = DateTime.now();
            if (now.difference(lastWrite) < const Duration(seconds: 1)) return;
            lastWrite = now;
            unawaited(_downloads.updateState(
              downloadId,
              state: db.DownloadState.downloading,
              success: p.completed,
              total: p.total,
              downloadedBytes: p.bytesDownloaded,
            ));
          },
        );

        if (_stopped || !_active.containsKey(downloadId)) return;

        await _downloads.updateState(
          downloadId,
          state: db.DownloadState.completed,
          savedPath: savedPath,
        );
        await _markChapterDownloaded(downloadId, chapterId, chapterDir, 1);
        _log('completed episode ${row.mangaTitle} / ${row.chapterName}');
        return;
      }

      // ---- Novel chapter: fetch the chapter TEXT as HTML. ----
      // (Text chapters have no page images — the image path below would
      // fail every novel download with "No pages resolved".)
      if (manga != null && manga.itemType == ItemType.novel) {
        final html = await _coordinator.chapterText(chapterId);
        if (html == null || html.isEmpty) {
          throw StateError(
              'No text resolved for novel chapter #$chapterId');
        }
        await Directory(chapterDir).create(recursive: true);
        final outPath = '$chapterDir/chapter.html';
        await File(outPath).writeAsString(html, flush: true);

        if (_stopped || !_active.containsKey(downloadId)) return;

        await _downloads.updateState(
          downloadId,
          state: db.DownloadState.completed,
          savedPath: outPath,
          downloadedBytes: html.length,
        );
        await _markChapterDownloaded(downloadId, chapterId, chapterDir, 1);
        _log('completed novel chapter ${row.mangaTitle} / ${row.chapterName}');
        return;
      }

      // ---- Manga chapter: resolve page URLs, fetch images. ----
      // 1. Resolve the page URLs through the source chain.
      final urls = await _coordinator.pageList(chapterId);
      if (urls.isEmpty) {
        throw StateError('No pages resolved for chapter #$chapterId');
      }

      // 2. Fetch into the per-chapter directory (raw images — the offline
      //    reader path consumes files directly).
      await Directory(chapterDir).create(recursive: true);

      var lastWrite = DateTime.now();
      final cbzPath = await downloader.downloadMangaChapter(
        pages: [
          for (var i = 0; i < urls.length; i++)
            MangaPage(url: urls[i], index: i),
        ],
        chapterDir: chapterDir,
        chapterTitle: row.chapterName ?? 'Chapter',
        createCbz: false,
        onProgress: (p) {
          // Throttle DB writes to ~1/s to avoid write amplification.
          final now = DateTime.now();
          if (now.difference(lastWrite) < const Duration(seconds: 1)) return;
          lastWrite = now;
          unawaited(_downloads.updateState(
            downloadId,
            state: db.DownloadState.downloading,
            success: p.completed,
            total: p.total,
            downloadedBytes: p.bytesDownloaded,
          ));
        },
      );

      if (_stopped || !_active.containsKey(downloadId)) {
        return; // cancelled mid-flight; state already moved by the UI
      }

      // 3. Persist completion + flag the chapter for offline reading.
      await _downloads.updateState(
        downloadId,
        state: db.DownloadState.completed,
        success: urls.length,
        total: urls.length,
        savedPath: cbzPath,
      );
      await _markChapterDownloaded(
          downloadId, chapterId, chapterDir, urls.length);
      _log('completed ${row.mangaTitle} / ${row.chapterName}');
    } catch (e) {
      // If the row was paused/cancelled meanwhile, keep the user's state.
      final current = await _isar.downloads.get(downloadId);
      if (current != null &&
          (current.state == db.DownloadState.paused ||
              current.state == db.DownloadState.cancelled)) {
        return;
      }
      await _downloads.markFailed(downloadId, e.toString());
      _log('failed ${row.mangaTitle} / ${row.chapterName}: $e');
    } finally {
      _active.remove(downloadId);
      unawaited(_drain());
    }
  }

  Future<void> _markChapterDownloaded(
      int downloadId, int chapterId, String dir, int pageCount) async {
    try {
      // Race guard: if the user deleted this download while the transfer
      // was finishing, the queue row is gone (or no longer completed) — do
      // NOT re-flag the chapter as downloaded, or it will claim files that
      // no longer exist on disk.
      final row = await _isar.downloads.get(downloadId);
      if (row == null || row.state != db.DownloadState.completed) {
        _log('skip flagging chapter $chapterId — download row removed');
        return;
      }
      await _isar.writeTxn(() async {
        final c = await _isar.chapters.get(chapterId);
        if (c == null) return;
        c
          ..isDownloaded = true
          ..isDownloading = false
          ..downloadProgress = 1.0
          ..pageCount = c.pageCount == 0 ? pageCount : c.pageCount;
        await _isar.chapters.put(c);
      });
    } catch (e) {
      _log('markChapterDownloaded($chapterId) failed: $e');
    }
  }

  void _log(String message) {
    // Cheap logging hook — wired to debugPrint only in debug builds via
    // assert side effects is overkill; keep it unconditional and quiet.
    // ignore: avoid_print
    print('[DownloadEngine] $message');
  }
}
