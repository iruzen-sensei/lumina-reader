// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
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

/// DownloadManager — orchestrates manga chapter and anime episode downloads.
///
/// Built on top of the [IsolatePool] declared in `isolate_pool.dart`:
/// the manager owns a single pool of six workers and dispatches download
/// jobs to them, streaming progress back to the UI via Riverpod.
///
/// Supported job kinds:
///   * `mangaChapter` — fetches every page image and packs them into a
///     `.cbz` archive alongside a `ComicInfo.xml` metadata file.
///   * `animeEpisode` — fetches the master m3u8, downloads every segment,
///     and writes them sequentially to a single `.ts` file ready for the
///     player.
///
/// Each job can be paused, resumed, and cancelled. State is persisted to
/// disk so an in-flight download survives an app restart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../http/m_client.dart';
import 'isolate_pool.dart';

/// Discriminator for the two supported download kinds.
enum DownloadKind { mangaChapter, animeEpisode }

/// Lifecycle of a single download.
enum DownloadStatus {
  queued,
  downloading,
  paused,
  converting,
  completed,
  failed,
  canceled,
}

/// Snapshot of a download's progress at a point in time. Streamed by
/// [DownloadManager.statusStream].
class DownloadProgress {
  final String id;
  final DownloadKind kind;
  final DownloadStatus status;

  /// 0.0 – 1.0 — fraction of bytes / pages / segments done.
  final double fraction;

  /// Number of items completed (pages for manga, segments for anime).
  final int itemsDone;

  /// Total items expected. May grow as more become known (e.g. m3u8
  /// segment list isn't known until after the master playlist is parsed).
  final int itemsTotal;

  /// Bytes downloaded so far — useful for bandwidth displays.
  final int bytesDownloaded;

  /// Estimated bytes remaining. Null when unknown.
  final int? bytesRemaining;

  /// Optional message — used for `converting` and `failed` states.
  final String? message;

  /// Wall-clock time the download has been running (paused time excluded).
  final Duration elapsed;

  const DownloadProgress({
    required this.id,
    required this.kind,
    required this.status,
    required this.fraction,
    required this.itemsDone,
    required this.itemsTotal,
    required this.bytesDownloaded,
    this.bytesRemaining,
    this.message,
    required this.elapsed,
  });

  factory DownloadProgress.initial({
    required String id,
    required DownloadKind kind,
  }) =>
      DownloadProgress(
        id: id,
        kind: kind,
        status: DownloadStatus.queued,
        fraction: 0,
        itemsDone: 0,
        itemsTotal: 0,
        bytesDownloaded: 0,
        elapsed: Duration.zero,
      );

  DownloadProgress copyWith({
    DownloadStatus? status,
    double? fraction,
    int? itemsDone,
    int? itemsTotal,
    int? bytesDownloaded,
    int? bytesRemaining,
    String? message,
    Duration? elapsed,
  }) =>
      DownloadProgress(
        id: id,
        kind: kind,
        status: status ?? this.status,
        fraction: fraction ?? this.fraction,
        itemsDone: itemsDone ?? this.itemsDone,
        itemsTotal: itemsTotal ?? this.itemsTotal,
        bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
        bytesRemaining: bytesRemaining ?? this.bytesRemaining,
        message: message ?? this.message,
        elapsed: elapsed ?? this.elapsed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'status': status.name,
        'fraction': fraction,
        'itemsDone': itemsDone,
        'itemsTotal': itemsTotal,
        'bytesDownloaded': bytesDownloaded,
        if (bytesRemaining != null) 'bytesRemaining': bytesRemaining,
        if (message != null) 'message': message,
        'elapsedMs': elapsed.inMilliseconds,
      };

  @override
  String toString() =>
      'DownloadProgress($id, ${status.name}, ${(fraction * 100).toStringAsFixed(1)}%, '
      '$itemsDone/$itemsTotal)';
}

/// Request to download a manga chapter.
class MangaDownloadRequest {
  final String sourceId;
  final String chapterUrl;
  final String chapterName;
  final String chapterScanlator;
  final double chapterNumber;
  final String mangaTitle;
  final String mangaAuthor;
  final String mangaSummary;
  final List<String> mangaGenres;
  final String? coverUrl;

  /// Pre-fetched page URLs. When null, the manager calls the source's
  /// [ExtensionService.getPageList] to fetch them.
  final List<String>? pageUrls;

  /// Per-request HTTP headers (e.g.REFERER) to attach to every page fetch.
  final Map<String, String> pageHeaders;

  const MangaDownloadRequest({
    required this.sourceId,
    required this.chapterUrl,
    required this.chapterName,
    required this.chapterScanlator,
    required this.chapterNumber,
    required this.mangaTitle,
    required this.mangaAuthor,
    required this.mangaSummary,
    required this.mangaGenres,
    this.coverUrl,
    this.pageUrls,
    this.pageHeaders = const {},
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'chapterUrl': chapterUrl,
        'chapterName': chapterName,
        'chapterScanlator': chapterScanlator,
        'chapterNumber': chapterNumber,
        'mangaTitle': mangaTitle,
        'mangaAuthor': mangaAuthor,
        'mangaSummary': mangaSummary,
        'mangaGenres': mangaGenres,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (pageUrls != null) 'pageUrls': pageUrls,
        'pageHeaders': pageHeaders,
      };
}

/// Request to download an anime episode via HLS.
class AnimeDownloadRequest {
  final String sourceId;
  final String episodeUrl;
  final String episodeName;
  final double episodeNumber;
  final String animeTitle;

  /// Master m3u8 URL. When [variantPlaylistUrl] is null, the manager
  /// parses the master playlist and picks the highest-bandwidth variant
  /// automatically.
  final String masterPlaylistUrl;
  final String? variantPlaylistUrl;

  /// Per-request headers for both the playlist and segment fetches.
  final Map<String, String> headers;

  const AnimeDownloadRequest({
    required this.sourceId,
    required this.episodeUrl,
    required this.episodeName,
    required this.episodeNumber,
    required this.animeTitle,
    required this.masterPlaylistUrl,
    this.variantPlaylistUrl,
    this.headers = const {},
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'episodeUrl': episodeUrl,
        'episodeName': episodeName,
        'episodeNumber': episodeNumber,
        'animeTitle': animeTitle,
        'masterPlaylistUrl': masterPlaylistUrl,
        if (variantPlaylistUrl != null) 'variantPlaylistUrl': variantPlaylistUrl,
        'headers': headers,
      };
}

/// Internal mutable state for a single download.
class _DownloadEntry {
  _DownloadEntry({
    required this.id,
    required this.kind,
    required this.request,
    this.mangaRequest,
    this.animeRequest,
  }) : progress = DownloadProgress.initial(id: id, kind: kind);

  final String id;
  final DownloadKind kind;
  final dynamic request;
  final MangaDownloadRequest? mangaRequest;
  final AnimeDownloadRequest? animeRequest;

  DownloadProgress progress;
  IsolateJobHandle? handle;
  Stopwatch stopwatch = Stopwatch();
  int bytesDownloaded = 0;
  int itemsDone = 0;
  int itemsTotal = 0;
  bool paused = false;
  bool canceled = false;

  void resetStopwatch() {
    stopwatch.reset();
  }
}

/// Top-level download manager. Single instance per process — accessed via
/// [DownloadManager.instance] or wired through Riverpod by the app shell.
class DownloadManager {
  DownloadManager._() {
    _pool = IsolatePool(size: 6);
  }

  static final DownloadManager instance = DownloadManager._();

  late final IsolatePool _pool;
  final _entries = <String, _DownloadEntry>{};
  final _statusController =
      StreamController<DownloadProgress>.broadcast();
  final _queue = <String>[];
  bool _started = false;
  Directory? _downloadsRoot;

  /// Live status stream. Emits one event per status change per download.
  Stream<DownloadProgress> get statusStream => _statusController.stream;

  /// Snapshot of every download's current progress, sorted by queue order.
  List<DownloadProgress> get snapshot => [
        ..._queue,
        ..._entries.keys.where((id) => !_queue.contains(id)),
      ]
          .map((id) => _entries[id]?.progress)
          .whereType<DownloadProgress>()
          .toList(growable: false);

  /// Lazily spin up the worker pool. Called automatically by [enqueue].
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    await _pool.start();
    _downloadsRoot ??= await _defaultDownloadsRoot();
    await _restorePendingDownloads();
  }

  /// Public bootstrap — call from main() before the user can tap download.
  Future<void> init() async => ensureStarted();

  static Future<Directory> _defaultDownloadsRoot() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'downloads'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Where the manager will write finished downloads. Per-source subfolders
  /// are created on demand inside this root.
  Directory get downloadsRoot {
    final root = _downloadsRoot;
    if (root == null) {
      throw StateError('DownloadManager.init() must complete before use');
    }
    return root;
  }

  // ─── Enqueue ──────────────────────────────────────────────────────────────

  /// Queue a manga chapter download. Returns the download id.
  Future<String> enqueueMangaChapter(MangaDownloadRequest req) async {
    await ensureStarted();
    final id = _mangaId(req);
    if (_entries.containsKey(id)) return id;
    final entry = _DownloadEntry(
      id: id,
      kind: DownloadKind.mangaChapter,
      request: req,
      mangaRequest: req,
    );
    _entries[id] = entry;
    _queue.add(id);
    _emit(entry);
    _pump();
    return id;
  }

  /// Queue an anime episode download. Returns the download id.
  Future<String> enqueueAnimeEpisode(AnimeDownloadRequest req) async {
    await ensureStarted();
    final id = _animeId(req);
    if (_entries.containsKey(id)) return id;
    final entry = _DownloadEntry(
      id: id,
      kind: DownloadKind.animeEpisode,
      request: req,
      animeRequest: req,
    );
    _entries[id] = entry;
    _queue.add(id);
    _emit(entry);
    _pump();
    return id;
  }

  // ─── Control ──────────────────────────────────────────────────────────────

  /// Pause a running download. The current segment / page finishes, then
  /// the worker is told to stop picking up new ones.
  Future<void> pause(String id) async {
    final entry = _entries[id];
    if (entry == null) return;
    if (entry.paused) return;
    entry.paused = true;
    entry.stopwatch.stop();
    entry.progress = entry.progress.copyWith(
      status: DownloadStatus.paused,
    );
    _emit(entry);
    await _pool.cancel(id);
  }

  /// Resume a paused (or failed) download.
  Future<void> resume(String id) async {
    final entry = _entries[id];
    if (entry == null) return;
    if (!entry.paused && entry.progress.status != DownloadStatus.failed) {
      return;
    }
    entry.paused = false;
    entry.canceled = false;
    entry.resetStopwatch();
    entry.progress = entry.progress.copyWith(
      status: DownloadStatus.queued,
      message: null,
    );
    _emit(entry);
    if (!_queue.contains(id)) _queue.add(id);
    _pump();
  }

  /// Cancel a download and discard partial output.
  Future<void> cancel(String id) async {
    final entry = _entries[id];
    if (entry == null) return;
    entry.canceled = true;
    _pool.cancel(id);
    _queue.remove(id);
    await _deletePartialOutput(entry);
    entry.progress = entry.progress.copyWith(
      status: DownloadStatus.canceled,
    );
    _emit(entry);
    _entries.remove(id);
  }

  /// Cancel every active download. Used by Settings → Stop all downloads.
  Future<void> cancelAll() async {
    final ids = _entries.keys.toList();
    for (final id in ids) {
      await cancel(id);
    }
  }

  // ─── Pump loop ────────────────────────────────────────────────────────────

  void _pump() {
    if (_queue.isEmpty) return;
    while (_queue.isNotEmpty && _pool.activeCount < _pool.workerCount) {
      final id = _queue.removeAt(0);
      final entry = _entries[id];
      if (entry == null) continue;
      if (entry.paused || entry.canceled) continue;
      _dispatch(entry);
    }
  }

  Future<void> _dispatch(_DownloadEntry entry) async {
    entry.stopwatch.start();
    entry.progress = entry.progress.copyWith(
      status: DownloadStatus.downloading,
    );
    _emit(entry);

    final IsolateJob<DownloadPayload> job;
    if (entry.kind == DownloadKind.mangaChapter) {
      job = _buildMangaJob(entry);
    } else {
      job = _buildAnimeJob(entry);
    }

    final handle = _pool.submit(job);
    entry.handle = handle;

    handle.results.listen(
      (result) => _onIsolateResult(entry, result),
      onError: (Object e, StackTrace st) {
        _markFailed(entry, e.toString());
      },
      onDone: () {
        // Worker finished — either done, failed, or canceled. The
        // [IsolateResult] stream will have already emitted a terminal
        // event via [_onIsolateResult] which updates the entry state.
      },
    );
  }

  void _onIsolateResult(_DownloadEntry entry, IsolateResult result) {
    switch (result.kind) {
      case IsolateResultKind.progress:
        final bytes = (result.bytesProcessed ?? 0);
        entry.bytesDownloaded = bytes;
        if (result.bytesTotal != null && entry.itemsTotal == 0) {
          entry.itemsTotal = result.bytesTotal!;
        }
        entry.itemsDone = result.progress != null
            ? (result.progress! * entry.itemsTotal).round()
            : entry.itemsDone;
        entry.progress = entry.progress.copyWith(
          status: DownloadStatus.downloading,
          fraction: result.progress ?? entry.progress.fraction,
          itemsDone: entry.itemsDone,
          itemsTotal: entry.itemsTotal,
          bytesDownloaded: entry.bytesDownloaded,
          elapsed: entry.stopwatch.elapsed,
        );
        _emit(entry);
        break;
      case IsolateResultKind.log:
        if (kDebugMode) {
          debugPrint('Download ${entry.id}: ${result.value}');
        }
        break;
      case IsolateResultKind.done:
        if (entry.canceled) return;
        entry.progress = entry.progress.copyWith(
          status: DownloadStatus.completed,
          fraction: 1.0,
          itemsDone: entry.itemsTotal == 0
              ? entry.itemsDone
              : entry.itemsTotal,
          elapsed: entry.stopwatch.elapsed,
        );
        _emit(entry);
        _persistState(entry);
        _pump();
        break;
      case IsolateResultKind.error:
        _markFailed(entry, result.error ?? 'unknown error');
        _pump();
        break;
    }
  }

  void _markFailed(_DownloadEntry entry, String message) {
    entry.progress = entry.progress.copyWith(
      status: DownloadStatus.failed,
      message: message,
      elapsed: entry.stopwatch.elapsed,
    );
    _emit(entry);
    _persistState(entry);
  }

  void _emit(_DownloadEntry entry) {
    _statusController.add(entry.progress);
  }

  // ─── Manga worker ─────────────────────────────────────────────────────────

  IsolateJob<DownloadPayload> _buildMangaJob(_DownloadEntry entry) {
    final req = entry.mangaRequest!;
    final outputDir = _chapterDir(req);
    final payload = DownloadPayload({
      'kind': 'manga',
      'id': entry.id,
      'sourceId': req.sourceId,
      'chapterUrl': req.chapterUrl,
      'chapterName': req.chapterName,
      'chapterScanlator': req.chapterScanlator,
      'chapterNumber': req.chapterNumber,
      'mangaTitle': req.mangaTitle,
      'mangaAuthor': req.mangaAuthor,
      'mangaSummary': req.mangaSummary,
      'mangaGenres': req.mangaGenres,
      'coverUrl': req.coverUrl ?? '',
      'pageUrls': req.pageUrls ?? <String>[],
      'pageHeaders': req.pageHeaders,
      'outputDir': outputDir.path,
    });
    return IsolateJob<DownloadPayload>(
      id: entry.id,
      payload: payload,
      entry: _mangaWorker,
    );
  }

  /// Top-level isolate entry — must be static / top-level so the isolate
  /// can resolve it. Receives the [DownloadPayload] describing the chapter.
  static Future<void> _mangaWorker(
    DownloadPayload payload,
    SendPort sendPort,
  ) async {
    final outputDir = Directory(payload['outputDir'] as String);
    await outputDir.create(recursive: true);

    final pageUrls = (payload['pageUrls'] as List).cast<String>();
    final pageHeaders =
        (payload['pageHeaders'] as Map?)?.cast<String, String>() ?? {};
    final sourceId = payload['sourceId'] as String;

    final client = await MClient.forSource(sourceId);
    final archive = Archive();
    final total = pageUrls.length;
    var done = 0;
    var bytesTotal = 0;

    for (final url in pageUrls) {
      try {
        final response = await client.get(
          url,
          headers: pageHeaders,
        );
        if (response.statusCode >= 400) {
          sendPort.send(IsolateResult.error(
            jobId: payload['id'] as String,
            error: 'HTTP ${response.statusCode} for $url',
          ));
          return;
        }
        final bytes = response.bodyBytes;
        bytesTotal += bytes.length;
        final filename = '${(done + 1).toString().padLeft(4, '0')}.jpg';
        archive.addFile(ArchiveFile.bytes(filename, bytes));
        done += 1;
        sendPort.send(IsolateResult.progress(
          jobId: payload['id'] as String,
          progress: done / total,
          bytesProcessed: bytesTotal,
          bytesTotal: null,
        ));
      } catch (e, st) {
        sendPort.send(IsolateResult.error(
          jobId: payload['id'] as String,
          error: e.toString(),
          stackTrace: st.toString(),
        ));
        return;
      }
    }

    // Attach ComicInfo.xml.
    final comicInfo = _buildComicInfoXml(payload);
    archive.addFile(ArchiveFile.string('ComicInfo.xml', comicInfo));

    final cbzBytes = ZipEncoder().encode(archive);
    if (cbzBytes == null) {
      sendPort.send(IsolateResult.error(
        jobId: payload['id'] as String,
        error: 'CBZ encoding failed',
      ));
      return;
    }
    final cbzPath = p.join(outputDir.path, _safeChapterName(payload));
    final cbzFile = File('$cbzPath.cbz');
    await cbzFile.writeAsBytes(cbzBytes, flush: true);

    sendPort.send(IsolateResult.done(
      jobId: payload['id'] as String,
      value: cbzFile.path,
    ));
  }

  static String _buildComicInfoXml(DownloadPayload payload) {
    final title = _escapeXml(payload['mangaTitle'] as String? ?? '');
    final author = _escapeXml(payload['mangaAuthor'] as String? ?? '');
    final summary = _escapeXml(payload['mangaSummary'] as String? ?? '');
    final chapter = payload['chapterNumber'] as num? ?? 0;
    final chapterName = _escapeXml(payload['chapterName'] as String? ?? '');
    final scanlator = _escapeXml(payload['chapterScanlator'] as String? ?? '');
    final genres = (payload['mangaGenres'] as List? ?? const [])
        .map((g) => _escapeXml(g.toString()))
        .join(', ');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Series>$title</Series>
  <Author>$author</Author>
  <Summary>$summary</Summary>
  <Genre>$genres</Genre>
  <Number>$chapter</Number>
  <Title>$chapterName</Title>
  <Translator>$scanlator</Translator>
  <PageCount>${(payload['pageUrls'] as List?)?.length ?? 0}</PageCount>
</ComicInfo>''';
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _safeChapterName(DownloadPayload payload) {
    final raw = payload['chapterName'] as String? ?? 'chapter';
    final num = payload['chapterNumber'] as num? ?? 0;
    return '${_sanitize(raw)}_ch${num.toStringAsFixed(2)}';
  }

  static String _sanitize(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  Directory _chapterDir(MangaDownloadRequest req) {
    final root = downloadsRoot;
    final dir = Directory(p.join(
      root.path,
      _sanitize(req.sourceId),
      _sanitize(req.mangaTitle),
      'ch_${req.chapterNumber.toStringAsFixed(2)}',
    ));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ─── Anime worker ─────────────────────────────────────────────────────────

  IsolateJob<DownloadPayload> _buildAnimeJob(_DownloadEntry entry) {
    final req = entry.animeRequest!;
    final outputDir = _episodeDir(req);
    final payload = DownloadPayload({
      'kind': 'anime',
      'id': entry.id,
      'sourceId': req.sourceId,
      'episodeUrl': req.episodeUrl,
      'episodeName': req.episodeName,
      'episodeNumber': req.episodeNumber,
      'animeTitle': req.animeTitle,
      'masterPlaylistUrl': req.masterPlaylistUrl,
      'variantPlaylistUrl': req.variantPlaylistUrl ?? '',
      'headers': req.headers,
      'outputDir': outputDir.path,
    });
    return IsolateJob<DownloadPayload>(
      id: entry.id,
      payload: payload,
      entry: _animeWorker,
    );
  }

  /// Top-level isolate entry for HLS downloads.
  static Future<void> _animeWorker(
    DownloadPayload payload,
    SendPort sendPort,
  ) async {
    final outputDir = Directory(payload['outputDir'] as String);
    await outputDir.create(recursive: true);

    final sourceId = payload['sourceId'] as String;
    final client = await MClient.forSource(sourceId);
    final headers =
        (payload['headers'] as Map?)?.cast<String, String>() ?? {};

    final masterUrl = payload['masterPlaylistUrl'] as String;
    final variantUrlOverride = payload['variantPlaylistUrl'] as String;

    // Resolve variant playlist.
    final variantUrl = variantUrlOverride.isEmpty
        ? await _resolveVariantPlaylist(client, masterUrl, headers)
        : variantUrlOverride;

    if (variantUrl.isEmpty) {
      sendPort.send(IsolateResult.error(
        jobId: payload['id'] as String,
        error: 'No variant playlist found in master m3u8',
      ));
      return;
    }

    final segments = await _fetchSegmentList(client, variantUrl, headers);
    if (segments.isEmpty) {
      sendPort.send(IsolateResult.error(
        jobId: payload['id'] as String,
        error: 'No segments found in variant playlist',
      ));
      return;
    }

    final total = segments.length;
    var done = 0;
    var bytesTotal = 0;

    final outPath = p.join(
      outputDir.path,
      '${_sanitize(payload['episodeName'] as String)}_ep'
      '${(payload['episodeNumber'] as num? ?? 0).toStringAsFixed(2)}.ts',
    );
    final sink = File(outPath).openWrite();

    try {
      for (final segmentUrl in segments) {
        final response = await client.get(segmentUrl, headers: headers);
        if (response.statusCode >= 400) {
          sendPort.send(IsolateResult.error(
            jobId: payload['id'] as String,
            error: 'HTTP ${response.statusCode} for segment $segmentUrl',
          ));
          await sink.close();
          return;
        }
        final bytes = response.bodyBytes;
        bytesTotal += bytes.length;
        sink.add(bytes);
        done += 1;
        sendPort.send(IsolateResult.progress(
          jobId: payload['id'] as String,
          progress: done / total,
          bytesProcessed: bytesTotal,
          bytesTotal: bytesTotal,
        ));
      }
      await sink.flush();
      await sink.close();
      sendPort.send(IsolateResult.done(
        jobId: payload['id'] as String,
        value: outPath,
      ));
    } catch (e, st) {
      await sink.close();
      sendPort.send(IsolateResult.error(
        jobId: payload['id'] as String,
        error: e.toString(),
        stackTrace: st.toString(),
      ));
    }
  }

  /// Helper that fetches the master m3u8 and returns the highest-bandwidth
  /// variant playlist URL (resolving relative URLs against the master).
  static Future<String> _resolveVariantPlaylist(
    MClient client,
    String masterUrl,
    Map<String, String> headers,
  ) async {
    final response = await client.get(masterUrl, headers: headers);
    if (response.statusCode >= 400) return '';
    final lines = response.body.split('\n');
    String? bestUri;
    var bestBandwidth = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final bw = int.tryParse(bwMatch?.group(1) ?? '') ?? 0;
        if (bw > bestBandwidth && i + 1 < lines.length) {
          bestBandwidth = bw;
          bestUri = lines[i + 1].trim();
        }
      }
    }
    if (bestUri == null) return masterUrl; // Already a media playlist.
    return Uri.parse(masterUrl).resolve(bestUri).toString();
  }

  /// Helper that fetches a variant playlist and returns the list of
  /// segment URLs (resolving relative URLs against the playlist URL).
  static Future<List<String>> _fetchSegmentList(
    MClient client,
    String playlistUrl,
    Map<String, String> headers,
  ) async {
    final response = await client.get(playlistUrl, headers: headers);
    if (response.statusCode >= 400) return const [];
    final lines = response.body.split('\n');
    final segments = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      segments.add(Uri.parse(playlistUrl).resolve(t).toString());
    }
    return segments;
  }

  Directory _episodeDir(AnimeDownloadRequest req) {
    final root = downloadsRoot;
    final dir = Directory(p.join(
      root.path,
      _sanitize(req.sourceId),
      _sanitize(req.animeTitle),
      'ep_${req.episodeNumber.toStringAsFixed(2)}',
    ));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ─── Persistence ──────────────────────────────────────────────────────────

  File _stateFile() => File(p.join(downloadsRoot.path, 'pending.json'));

  Future<void> _persistState(_DownloadEntry entry) async {
    try {
      final file = _stateFile();
      Map<String, dynamic> state = {};
      if (await file.exists()) {
        state =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      state[entry.id] = {
        'kind': entry.kind.name,
        'request': entry.request is MangaDownloadRequest
            ? (entry.request as MangaDownloadRequest).toJson()
            : (entry.request as AnimeDownloadRequest).toJson(),
        'progress': entry.progress.toJson(),
      };
      await file.writeAsString(jsonEncode(state), flush: true);
    } catch (e) {
      debugPrint('DownloadManager: persist state failed — $e');
    }
  }

  Future<void> _restorePendingDownloads() async {
    try {
      final file = _stateFile();
      if (!await file.exists()) return;
      final state =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final entry in state.entries) {
        final id = entry.key;
        final value = entry.value as Map<String, dynamic>;
        final kindStr = value['kind'] as String;
        final reqJson = value['request'] as Map<String, dynamic>;
        final progressJson = value['progress'] as Map<String, dynamic>;
        final kind = kindStr == 'animeEpisode'
            ? DownloadKind.animeEpisode
            : DownloadKind.mangaChapter;
        final entryObj = _DownloadEntry(
          id: id,
          kind: kind,
          request: kind == DownloadKind.mangaChapter
              ? MangaDownloadRequest(
                  sourceId: reqJson['sourceId'] as String,
                  chapterUrl: reqJson['chapterUrl'] as String,
                  chapterName: reqJson['chapterName'] as String,
                  chapterScanlator:
                      reqJson['chapterScanlator'] as String? ?? '',
                  chapterNumber:
                      (reqJson['chapterNumber'] as num?)?.toDouble() ?? 0.0,
                  mangaTitle: reqJson['mangaTitle'] as String,
                  mangaAuthor: reqJson['mangaAuthor'] as String? ?? '',
                  mangaSummary: reqJson['mangaSummary'] as String? ?? '',
                  mangaGenres: (reqJson['mangaGenres'] as List? ?? const [])
                      .map((e) => e.toString())
                      .toList(growable: false),
                  coverUrl: reqJson['coverUrl'] as String?,
                  pageUrls: (reqJson['pageUrls'] as List?)
                      ?.map((e) => e.toString())
                      .toList(growable: false),
                  pageHeaders: (reqJson['pageHeaders'] as Map?)
                          ?.map((k, v) =>
                              MapEntry(k.toString(), v.toString())) ??
                      const {},
                )
              : AnimeDownloadRequest(
                  sourceId: reqJson['sourceId'] as String,
                  episodeUrl: reqJson['episodeUrl'] as String,
                  episodeName: reqJson['episodeName'] as String,
                  episodeNumber:
                      (reqJson['episodeNumber'] as num?)?.toDouble() ?? 0.0,
                  animeTitle: reqJson['animeTitle'] as String,
                  masterPlaylistUrl: reqJson['masterPlaylistUrl'] as String,
                  variantPlaylistUrl: reqJson['variantPlaylistUrl'] as String?,
                  headers: (reqJson['headers'] as Map?)
                          ?.map((k, v) =>
                              MapEntry(k.toString(), v.toString())) ??
                      const {},
                ),
          mangaRequest: kind == DownloadKind.mangaChapter
              ? MangaDownloadRequest(
                  sourceId: reqJson['sourceId'] as String,
                  chapterUrl: reqJson['chapterUrl'] as String,
                  chapterName: reqJson['chapterName'] as String,
                  chapterScanlator:
                      reqJson['chapterScanlator'] as String? ?? '',
                  chapterNumber:
                      (reqJson['chapterNumber'] as num?)?.toDouble() ?? 0.0,
                  mangaTitle: reqJson['mangaTitle'] as String,
                  mangaAuthor: reqJson['mangaAuthor'] as String? ?? '',
                  mangaSummary: reqJson['mangaSummary'] as String? ?? '',
                  mangaGenres: (reqJson['mangaGenres'] as List? ?? const [])
                      .map((e) => e.toString())
                      .toList(growable: false),
                  coverUrl: reqJson['coverUrl'] as String?,
                  pageUrls: (reqJson['pageUrls'] as List?)
                      ?.map((e) => e.toString())
                      .toList(growable: false),
                  pageHeaders: (reqJson['pageHeaders'] as Map?)
                          ?.map((k, v) =>
                              MapEntry(k.toString(), v.toString())) ??
                      const {},
                )
              : null,
          animeRequest: kind == DownloadKind.animeEpisode
              ? AnimeDownloadRequest(
                  sourceId: reqJson['sourceId'] as String,
                  episodeUrl: reqJson['episodeUrl'] as String,
                  episodeName: reqJson['episodeName'] as String,
                  episodeNumber:
                      (reqJson['episodeNumber'] as num?)?.toDouble() ?? 0.0,
                  animeTitle: reqJson['animeTitle'] as String,
                  masterPlaylistUrl: reqJson['masterPlaylistUrl'] as String,
                  variantPlaylistUrl: reqJson['variantPlaylistUrl'] as String?,
                  headers: (reqJson['headers'] as Map?)
                          ?.map((k, v) =>
                              MapEntry(k.toString(), v.toString())) ??
                      const {},
                )
              : null,
        );
        // Persisted downloads start in `paused` state so the user can
        // opt-in to resuming them.
        entryObj.progress = DownloadProgress(
          id: id,
          kind: kind,
          status: DownloadStatus.paused,
          fraction: (progressJson['fraction'] as num?)?.toDouble() ?? 0.0,
          itemsDone: progressJson['itemsDone'] as int? ?? 0,
          itemsTotal: progressJson['itemsTotal'] as int? ?? 0,
          bytesDownloaded: progressJson['bytesDownloaded'] as int? ?? 0,
          bytesRemaining: progressJson['bytesRemaining'] as int?,
          message: progressJson['message'] as String?,
          elapsed: Duration(
            milliseconds: progressJson['elapsedMs'] as int? ?? 0,
          ),
        );
        entryObj.paused = true;
        _entries[id] = entryObj;
        _emit(entryObj);
      }
    } catch (e) {
      debugPrint('DownloadManager: restore state failed — $e');
    }
  }

  Future<void> _deletePartialOutput(_DownloadEntry entry) async {
    try {
      if (entry.kind == DownloadKind.mangaChapter) {
        final req = entry.mangaRequest!;
        final dir = _chapterDir(req);
        if (await dir.exists()) await dir.delete(recursive: true);
      } else {
        final req = entry.animeRequest!;
        final dir = _episodeDir(req);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('DownloadManager: delete partial failed — $e');
    }
  }

  // ─── ID helpers ───────────────────────────────────────────────────────────

  String _mangaId(MangaDownloadRequest req) =>
      'manga:${req.sourceId}:${_sanitize(req.mangaTitle)}:'
      '${req.chapterNumber.toStringAsFixed(2)}';

  String _animeId(AnimeDownloadRequest req) =>
      'anime:${req.sourceId}:${_sanitize(req.animeTitle)}:'
      '${req.episodeNumber.toStringAsFixed(2)}';

  /// Tear down the pool and close the status stream. Used by tests.
  Future<void> dispose() async {
    await _pool.dispose();
    await _statusController.close();
    _entries.clear();
    _queue.clear();
  }
}
