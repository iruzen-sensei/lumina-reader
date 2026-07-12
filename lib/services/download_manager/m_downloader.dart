// Copyright 2025 Lumina Reader Contributors
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../http/m_client.dart';

/// MDownloader — Download orchestrator for manga chapters and anime episodes.
///
/// Responsibilities:
/// * Download manga chapter page images (parallel, configurable concurrency).
/// * Download anime episodes by fetching m3u8 playlist + every .ts segment
///   and concatenating them into a single .ts file (optionally remuxed
///   later via ffmpeg).
/// * Report granular per-file and overall progress through callbacks.
/// * Convert manga page sets to CBZ archives on completion.
/// * Retry individual file fetches with exponential backoff.
///
/// The downloader is transport-agnostic — it uses [MClient] for HTTP so all
/// cookies, logging, and Cloudflare bypass logic is inherited for free.
library m_downloader;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single image page to fetch for a manga chapter.
class MangaPage {
  const MangaPage({required this.url, required this.index, this.referer});

  /// Direct image URL.
  final String url;

  /// Zero-based page number within the chapter.
  final int index;

  /// Optional `Referer` header. Some sources require this.
  final String? referer;

  Map<String, String> get headers => <String, String>{
        if (referer != null) HttpHeaders.refererHeader: referer!,
      };
}

/// A single segment from an m3u8 playlist.
class M3u8Segment {
  const M3u8Segment({required this.url, required this.index, this.durationSec});

  final String url;
  final int index;
  final double? durationSec;
}

/// Snapshot of an in-progress download.
class DownloadProgress {
  const DownloadProgress({
    required this.total,
    required this.completed,
    required this.bytesDownloaded,
    required this.bytesTotal,
    this.currentFile,
    this.error,
  });

  final int total;
  final int completed;
  final int bytesDownloaded;
  final int bytesTotal;
  final String? currentFile;
  final String? error;

  double get fraction =>
      total == 0 ? 0 : completed / total;

  double get byteFraction =>
      bytesTotal == 0 ? 0 : bytesDownloaded / bytesTotal;

  bool get isComplete => completed >= total && total > 0;
}

/// Callbacks invoked by [MDownloader].
typedef ProgressCallback = void Function(DownloadProgress progress);
typedef CompleteCallback = void Function(File result, DownloadProgress finalProgress);
typedef ErrorCallback = void Function(Object error, StackTrace stack);

// ---------------------------------------------------------------------------
// Parsers
// ---------------------------------------------------------------------------

/// Parse a master or media m3u8 playlist. Returns the list of segment URLs.
///
/// If the playlist is a master playlist (with `#EXT-X-STREAM-INF`), the
/// highest-bandwidth variant is resolved and its segments returned.
Future<List<M3u8Segment>> parseM3u8(
  String playlistText,
  Uri baseUrl,
) async {
  final List<M3u8Segment> segments = <M3u8Segment>[];
  final List<String> lines =
      playlistText.split('\n').map((String l) => l.trim()).toList();

  // Master playlist?
  String? variantUrl;
  double bestBandwidth = -1;
  for (int i = 0; i < lines.length; i++) {
    final String l = lines[i];
    if (l.startsWith('#EXT-X-STREAM-INF:')) {
      final RegExpMatch? m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(l);
      final double bw = m != null ? double.parse(m.group(1)!) : 0;
      // The next non-empty line is the variant URL.
      for (int j = i + 1; j < lines.length; j++) {
        if (lines[j].isNotEmpty && !lines[j].startsWith('#')) {
          if (bw > bestBandwidth) {
            bestBandwidth = bw;
            variantUrl = lines[j];
          }
          break;
        }
      }
    }
  }

  if (variantUrl != null) {
    final Uri variantUri = baseUrl.resolve(variantUrl);
    final http.Response res =
        await MClient.httpClient().get(variantUri);
    if (res.statusCode != 200) {
      throw HttpException('m3u8 variant fetch failed: ${res.statusCode}');
    }
    return parseM3u8(res.body, variantUri);
  }

  // Media playlist.
  int idx = 0;
  double? segDuration;
  for (final String l in lines) {
    if (l.startsWith('#EXTINF:')) {
      final String rest = l.substring('#EXTINF:'.length);
      final int comma = rest.indexOf(',');
      segDuration = double.tryParse(comma >= 0 ? rest.substring(0, comma) : rest);
    } else if (l.isNotEmpty && !l.startsWith('#')) {
      final Uri segUri = baseUrl.resolve(l);
      segments.add(M3u8Segment(
        url: segUri.toString(),
        index: idx,
        durationSec: segDuration,
      ));
      segDuration = null;
      idx++;
    }
  }
  return segments;
}

// ---------------------------------------------------------------------------
// MDownloader
// ---------------------------------------------------------------------------

/// Orchestrates concurrent downloads for a single chapter or episode.
class MDownloader {
  MDownloader({
    this.concurrency = 4,
    this.maxRetries = 3,
    this.baseBackoff = const Duration(seconds: 1),
    this.requestTimeout = const Duration(seconds: 60),
    this.headers = const <String, String>{},
  })  : assert(concurrency > 0),
        assert(maxRetries >= 0);

  /// Number of files fetched in parallel.
  final int concurrency;

  /// Number of retry attempts per file.
  final int maxRetries;

  /// Initial exponential-backoff delay.
  final Duration baseBackoff;

  /// Per-file request timeout.
  final Duration requestTimeout;

  /// Default headers applied to every request.
  final Map<String, String> headers;

  bool _cancelled = false;
  bool _running = false;

  /// Whether this downloader is currently active.
  bool get isRunning => _running;

  /// Cancel the active download. In-flight HTTP requests will be aborted and
  /// the [DownloadProgress.error] field will report 'cancelled'.
  void cancel() {
    _cancelled = true;
  }

  // ---- Manga ---------------------------------------------------------------

  /// Download all [pages] into [chapterDir] and produce a CBZ archive.
  ///
  /// Returns the path to the resulting `.cbz` file.
  Future<String> downloadMangaChapter({
    required List<MangaPage> pages,
    required String chapterDir,
    required String chapterTitle,
    ProgressCallback? onProgress,
    bool createCbz = true,
  }) async {
    _cancelled = false;
    _running = true;
    try {
      final Directory dir = Directory(chapterDir);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      int completed = 0;
      int bytesDownloaded = 0;
      int bytesTotal = 0;

      final List<File> results = List<File>.filled(pages.length, File(''));
      final List<Future<void>> workers = <Future<void>>[];
      final Stopwatch sw = Stopwatch()..start();

      // Simple semaphore using a list of completers.
      final List<Completer<void>> _slots =
          List<Completer<void>>.generate(concurrency, (_) => Completer<void>());

      Future<void> processOne(int i) async {
        if (_cancelled) return;
        final MangaPage page = pages[i];
        final String filename =
            '${i.toString().padLeft(4, '0')}.${_guessExtension(page.url)}';
        final File target = File(p.join(dir.path, filename));
        onProgress?.call(DownloadProgress(
          total: pages.length,
          completed: completed,
          bytesDownloaded: bytesDownloaded,
          bytesTotal: bytesTotal,
          currentFile: filename,
        ));

        try {
          final Uint8List bytes = await _fetchWithRetry(
            page.url,
            headers: <String, String>{...headers, ...page.headers},
          );
          if (_cancelled) return;
          await target.writeAsBytes(bytes, flush: true);
          results[i] = target;
          completed++;
          bytesDownloaded += bytes.length;
          bytesTotal += bytes.length;
          onProgress?.call(DownloadProgress(
            total: pages.length,
            completed: completed,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal,
            currentFile: filename,
          ));
        } catch (e, st) {
          if (_cancelled) return;
          onProgress?.call(DownloadProgress(
            total: pages.length,
            completed: completed,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal,
            currentFile: filename,
            error: '$e\n$st',
          ));
          rethrow;
        }
      }

      // Manual bounded-concurrency scheduler (works in isolates too).
      int next = 0;
      Future<void> worker(int slot) async {
        while (true) {
          final int myIdx = next++;
          if (myIdx >= pages.length) {
            _slots[slot].complete();
            return;
          }
          await processOne(myIdx);
          if (_cancelled) {
            _slots[slot].complete();
            return;
          }
        }
      }

      for (int s = 0; s < concurrency; s++) {
        workers.add(worker(s));
      }
      await Future.wait(_slots.map((Completer<void> c) => c.future));
      await Future.wait(workers);

      sw.stop();
      if (_cancelled) {
        throw StateError('cancelled');
      }

      if (results.any((File f) => f.path.isEmpty)) {
        throw StateError('Some pages failed to download');
      }

      final DownloadProgress finalProgress = DownloadProgress(
        total: pages.length,
        completed: completed,
        bytesDownloaded: bytesDownloaded,
        bytesTotal: bytesTotal,
      );
      onProgress?.call(finalProgress);

      if (!createCbz) {
        return dir.path;
      }

      final String cbzPath = p.join(p.dirname(dir.path), '$chapterTitle.cbz');
      await _writeCbz(results, cbzPath, chapterTitle);
      return cbzPath;
    } finally {
      _running = false;
    }
  }

  // ---- Anime ---------------------------------------------------------------

  /// Download every segment of an m3u8 playlist and concatenate them into a
  /// single `.ts` file at [outputPath].
  Future<String> downloadAnimeEpisode({
    required String m3u8Url,
    required String outputPath,
    ProgressCallback? onProgress,
  }) async {
    _cancelled = false;
    _running = true;
    try {
      final Uri baseUri = Uri.parse(m3u8Url);
      final http.Response res =
          await MClient.httpClient().get(baseUri);
      if (res.statusCode != 200) {
        throw HttpException('m3u8 fetch failed: ${res.statusCode}');
      }
      final List<M3u8Segment> segments =
          await parseM3u8(res.body, baseUri);

      final File outFile = File(outputPath);
      final IOSink sink = outFile.openWrite();

      int completed = 0;
      int bytesDownloaded = 0;
      int bytesTotal = 0;
      final List<Future<void>> workers = <Future<void>>[];
      final List<Completer<void>> _slots = List<Completer<void>>.generate(
          concurrency, (_) => Completer<void>());

      final List<Uint8List> ordered =
          List<Uint8List>.filled(segments.length, Uint8List(0));

      Future<void> processSeg(int i) async {
        if (_cancelled) return;
        final M3u8Segment seg = segments[i];
        onProgress?.call(DownloadProgress(
          total: segments.length,
          completed: completed,
          bytesDownloaded: bytesDownloaded,
          bytesTotal: bytesTotal,
          currentFile: 'seg-${seg.index}.ts',
        ));
        try {
          final Uint8List bytes = await _fetchWithRetry(
            seg.url,
            headers: headers,
          );
          if (_cancelled) return;
          ordered[i] = bytes;
          completed++;
          bytesDownloaded += bytes.length;
          bytesTotal += bytes.length;
          onProgress?.call(DownloadProgress(
            total: segments.length,
            completed: completed,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal,
            currentFile: 'seg-${seg.index}.ts',
          ));
        } catch (e, st) {
          if (_cancelled) return;
          onProgress?.call(DownloadProgress(
            total: segments.length,
            completed: completed,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal,
            currentFile: 'seg-${seg.index}.ts',
            error: '$e\n$st',
          ));
          rethrow;
        }
      }

      int next = 0;
      Future<void> worker(int slot) async {
        while (true) {
          final int myIdx = next++;
          if (myIdx >= segments.length) {
            _slots[slot].complete();
            return;
          }
          await processSeg(myIdx);
          if (_cancelled) {
            _slots[slot].complete();
            return;
          }
        }
      }

      for (int s = 0; s < concurrency; s++) {
        workers.add(worker(s));
      }
      await Future.wait(_slots.map((Completer<void> c) => c.future));
      await Future.wait(workers);

      if (_cancelled) {
        await sink.close();
        throw StateError('cancelled');
      }

      for (final Uint8List chunk in ordered) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      onProgress?.call(DownloadProgress(
        total: segments.length,
        completed: completed,
        bytesDownloaded: bytesDownloaded,
        bytesTotal: bytesTotal,
      ));

      return outFile.path;
    } finally {
      _running = false;
    }
  }

  // ---- Internals -----------------------------------------------------------

  /// Fetch a single URL with exponential backoff.
  Future<Uint8List> _fetchWithRetry(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final Uri uri = Uri.parse(url);
    int attempt = 0;
    Object? lastError;
    while (attempt <= maxRetries) {
      if (_cancelled) throw StateError('cancelled');
      try {
        final Stopwatch sw = Stopwatch()..start();
        final http.StreamedResponse res = await MClient.httpClient(
                requestTimeout: requestTimeout)
            .send(http.Request('GET', uri)
              ..headers.addAll(<String, String>{
                ...headers,
                'x-lumina-ts': DateTime.now().toIso8601String(),
              }));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final List<int> body = <int>[];
          await for (final List<int> chunk in res.stream) {
            body.addAll(chunk);
          }
          sw.stop();
          return Uint8List.fromList(body);
        }
        throw HttpException('HTTP ${res.statusCode} for $url');
      } catch (e) {
        lastError = e;
        attempt++;
        if (attempt > maxRetries) break;
        final Duration delay = baseBackoff * (1 << (attempt - 1));
        await Future<void>.delayed(delay);
      }
    }
    throw lastError ?? StateError('download-failed');
  }

  /// Pack an ordered list of image files into a `.cbz` (zip) archive.
  Future<void> _writeCbz(
      List<File> files, String outPath, String chapterTitle) async {
    final Archive archive = Archive();
    for (int i = 0; i < files.length; i++) {
      final File f = files[i];
      if (!f.existsSync()) continue;
      final List<int> data = await f.readAsBytes();
      archive.addFile(ArchiveFile(p.basename(f.path), data.length, data));
    }
    final List<int>? encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('cbz-encode-failed');
    }
    final File out = File(outPath);
    await out.writeAsBytes(encoded, flush: true);
  }

  /// Best-effort guess of file extension from URL.
  String _guessExtension(String url) {
    final Uri uri = Uri.parse(url);
    final String path = uri.path.toLowerCase();
    for (final String ext in const <String>['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp']) {
      if (path.endsWith('.$ext')) return ext;
    }
    return 'jpg';
  }
}

// ---------------------------------------------------------------------------
// Singleton convenience
// ---------------------------------------------------------------------------

/// Shared singleton used by the UI layer to spawn downloads.
final MDownloader globalDownloader = MDownloader();
