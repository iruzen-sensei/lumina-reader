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
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/http/m_client.dart';

/// Cached network image utilities for Lumina Reader.
///
/// Three-tier cache:
/// 1. In-memory LRU keyed by URL — capped at [MemoryLruCache.defaultMaxBytes]
///    (50 MB by default).
/// 2. On-disk MD5-keyed file cache — capped at
///    [DiskImageCache.defaultMaxBytes] (500 MB by default).
/// 3. Network — fetched through [MClient] so cookies/CF bypass apply, with
///    exponential-backoff retry (3 attempts) and a dual-HTTP fallback
///    (primary `MClient` → fallback raw `http.Client`).
///
/// Public API:
/// * [coverProvider] — returns a [CachedNetworkImageProvider] sized to 200 KB
///   via [ExtendedResizeImage].
/// * [cachedNetworkImage] — convenience widget wrapper.
/// * [ precacheCover] — eagerly warm the cache.
library cached_network;

// ---------------------------------------------------------------------------
// LRU memory cache
// ---------------------------------------------------------------------------

/// A bounded LRU cache mapping URL → image bytes.
class MemoryLruCache {
  MemoryLruCache({this.defaultMaxBytes = 50 * 1024 * 1024});

  static const int defaultMaxBytes = 50 * 1024 * 1024; // 50 MB

  final int defaultMaxBytes;
  final LinkedHashMap<String, Uint8List> _map =
      LinkedHashMap<String, Uint8List>();
  int _bytes = 0;

  int get bytes => _bytes;

  Uint8List? get(String key) {
    final Uint8List? v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v; // Re-insert to mark as most-recently-used.
    return v;
  }

  void put(String key, Uint8List value) {
    final Uint8List? old = _map.remove(key);
    if (old != null) _bytes -= old.length;
    _map[key] = value;
    _bytes += value.length;
    _evict();
  }

  void _evict() {
    while (_bytes > defaultMaxBytes && _map.isNotEmpty) {
      final String oldest = _map.keys.first;
      final Uint8List v = _map.remove(oldest)!;
      _bytes -= v.length;
    }
  }

  void clear() {
    _map.clear();
    _bytes = 0;
  }
}

// ---------------------------------------------------------------------------
// On-disk MD5 cache
// ---------------------------------------------------------------------------

/// On-disk image cache. Files are stored under `images/<md5>.<ext>` in the
/// platform's application-cache directory. Capped at [defaultMaxBytes]; when
/// exceeded the oldest files (by mtime) are evicted.
class DiskImageCache {
  DiskImageCache._(this._root, {this.defaultMaxBytes = 500 * 1024 * 1024});

  static const int defaultMaxBytes = 500 * 1024 * 1024; // 500 MB

  final Directory _root;
  final int defaultMaxBytes;

  static DiskImageCache? _instance;

  /// Initialise (or fetch) the singleton. Safe to call repeatedly.
  static Future<DiskImageCache> instance() async {
    if (_instance != null) return _instance!;
    final Directory base = await getTemporaryDirectory();
    final Directory dir = Directory(p.join(base.path, 'lumina_images'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _instance = DiskImageCache._(dir);
    return _instance!;
  }

  Directory get root => _root;

  static String md5Of(String s) => md5.convert(utf8.encode(s)).toString();

  File fileFor(String url, {String ext = 'jpg'}) {
    final String hash = md5Of(url);
    return File(p.join(_root.path, '$hash.$ext'));
  }

  Future<bool> exists(String url, {String ext = 'jpg'}) {
    return fileFor(url, ext: ext).exists();
  }

  Future<Uint8List?> read(String url, {String ext = 'jpg'}) async {
    final File f = fileFor(url, ext: ext);
    if (!f.existsSync()) return null;
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String url, Uint8List bytes,
      {String ext = 'jpg'}) async {
    final File f = fileFor(url, ext: ext);
    try {
      await f.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Best-effort.
    }
    unawaited(_maybeEvict());
  }

  Future<void> _maybeEvict() async {
    try {
      final List<FileSystemEntity> files =
          _root.listSync(followLinks: false).whereType<File>().toList();
      int total = 0;
      for (final FileSystemEntity f in files) {
        total += await (f as File).length();
      }
      if (total <= defaultMaxBytes) return;

      // Sort by mtime ascending; delete oldest until under cap.
      final List<File> sorted = List<File>.from(files)
        ..sort((File a, File b) {
          final DateTime ta = a.statSync().modified;
          final DateTime tb = b.statSync().modified;
          return ta.compareTo(tb);
        });
      for (final File f in sorted) {
        if (total <= defaultMaxBytes) break;
        final int size = await f.length();
        await f.delete();
        total -= size;
      }
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> clear() async {
    try {
      await for (final FileSystemEntity f in _root.list()) {
        await f.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort.
    }
  }
}

// ---------------------------------------------------------------------------
// Three-tier fetcher with retry + dual fallback
// ---------------------------------------------------------------------------

/// Result of a [ThreeTierImage.fetch] call.
class FetchResult {
  const FetchResult({required this.bytes, required this.fromTier});
  final Uint8List bytes;
  /// 'memory' | 'disk' | 'network'
  final String fromTier;
}

/// Coordinates the memory → disk → network cache hierarchy.
class ThreeTierImage {
  ThreeTierImage._();

  static final MemoryLruCache memory = MemoryLruCache();
  static DiskImageCache? _disk;
  static final http.Client _fallbackClient = http.Client();

  static Future<DiskImageCache> _diskCache() async {
    return _disk ??= await DiskImageCache.instance();
  }

  /// Fetch [url] honouring the three-tier hierarchy.
  ///
  /// Network failures are retried up to 3 times with exponential backoff
  /// (300 ms → 600 ms → 1.2 s). If the primary [MClient] fails, a plain
  /// [http.Client] is tried as fallback.
  static Future<FetchResult> fetch(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String ext = 'jpg',
  }) async {
    // 1. Memory
    final Uint8List? memHit = memory.get(url);
    if (memHit != null) {
      return FetchResult(bytes: memHit, fromTier: 'memory');
    }

    // 2. Disk
    final DiskImageCache disk = await _diskCache();
    final Uint8List? diskHit = await disk.read(url, ext: ext);
    if (diskHit != null) {
      memory.put(url, diskHit);
      return FetchResult(bytes: diskHit, fromTier: 'disk');
    }

    // 3. Network (with retry + fallback)
    final Uint8List bytes = await _fetchNetworkWithRetry(url, headers: headers);
    memory.put(url, bytes);
    await disk.write(url, bytes, ext: ext);
    return FetchResult(bytes: bytes, fromTier: 'network');
  }

  static Future<Uint8List> _fetchNetworkWithRetry(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    const int maxAttempts = 3;
    Duration backoff = const Duration(milliseconds: 300);

    Object? lastError;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final Uint8List? primary = await _fetchViaMClient(url, headers);
        if (primary != null) return primary;
        // Try fallback.
        final Uint8List? fallback = await _fetchViaFallback(url, headers);
        if (fallback != null) return fallback;
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(backoff);
      backoff *= 2;
    }
    throw lastError ?? Exception('image-fetch-failed: $url');
  }

  static Future<Uint8List?> _fetchViaMClient(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final Uri uri = Uri.parse(url);
      final http.StreamedResponse res =
          await MClient.httpClient().send(http.Request('GET', uri)
            ..headers.addAll(headers));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final List<int> data = <int>[];
      await for (final List<int> chunk in res.stream) {
        data.addAll(chunk);
      }
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _fetchViaFallback(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final http.Response res =
          await _fallbackClient.get(Uri.parse(url), headers: headers);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Public widget API
// ---------------------------------------------------------------------------

/// Provider that yields a [CachedNetworkImageProvider] for the given cover
/// URL, capped at 200 KB via [ExtendedResizeImage].
ImageProvider coverProvider(
  String url, {
  Map<String, String>? headers,
  double maxWidth = 600,
  double maxHeight = 900,
  int maxBytes = 200 * 1024,
}) {
  return ExtendedResizeImage(
    ExtendedNetworkImageProvider(
      url,
      headers: headers,
      cache: true,
      retries: 3,
      timeRetry: const Duration(milliseconds: 300),
      cacheRawData: true,
      cacheManager: _ThreeTierCacheManager(),
    ),
    width: maxWidth,
    height: maxHeight,
    maxBytes: maxBytes,
    compressionRatio: 0.85,
  );
}

/// Convenience widget — mirrors the API of `CachedNetworkImage` so call sites
/// don't need to learn a new surface.
Widget cachedNetworkImage(
  String url, {
  Key? key,
  Map<String, String>? headers,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
  Widget Function(BuildContext, LoadState)? loadStateChanged,
  bool isCover = true,
}) {
  final ImageProvider provider = isCover
      ? coverProvider(url, headers: headers)
      : ExtendedNetworkImageProvider(
          url,
          headers: headers,
          cache: true,
          retries: 3,
          cacheRawData: true,
          cacheManager: _ThreeTierCacheManager(),
        );

  final Widget image = ExtendedImage(
    key: key,
    image: provider,
    width: width,
    height: height,
    fit: fit,
    loadStateChanged: loadStateChanged ??
        (BuildContext ctx, LoadState state) {
          switch (state) {
            case LoadState.loading:
              return _Placeholder(width: width, height: height);
            case LoadState.failed:
              return _ErrorPlaceholder(width: width, height: height);
            case LoadState.completed:
              return ExtendedRawImage(
                image: ExtendedImage.forState(ctx)?.image,
                width: width,
                height: height,
                fit: fit,
              );
          }
        },
  );

  if (borderRadius == null) {
    return image;
  }

  return ClipRRect(
    borderRadius: borderRadius,
    child: image,
  );
}

/// Pre-warm the cache for a cover URL.
Future<void> precacheCover(
  String url, {
  Map<String, String>? headers,
}) async {
  await ThreeTierImage.fetch(url, headers: headers ?? const <String, String>{});
}

// ---------------------------------------------------------------------------
// Placeholder widgets
// ---------------------------------------------------------------------------

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.width, this.height});
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFEEEEEE),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({this.width, this.height});
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF5F5F5),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: Color(0xFF999999)),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom cache manager that bridges extended_image to our 3-tier cache.
// ---------------------------------------------------------------------------

/// `extended_image` allows plugging in a custom [ImageCacheManager]. We
/// implement one that delegates to [ThreeTierImage] so memory/disk hit-rates
/// are shared across every cover thumbnail in the app.
class _ThreeTierCacheManager implements ImageCacheManager {
  _ThreeTierCacheManager();

  @override
  Future<File> getFile(String url,
      {Map<String, String>? headers}) async {
    final FetchResult res =
        await ThreeTierImage.fetch(url, headers: headers ?? const <String, String>{});
    final Directory tmp = await getTemporaryDirectory();
    final File f = File(p.join(tmp.path, '${DiskImageCache.md5Of(url)}.jpg'));
    await f.writeAsBytes(res.bytes, flush: true);
    return f;
  }

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    final StreamController<FileResponse> ctrl =
        StreamController<FileResponse>();
    () async {
      try {
        final File f = await getFile(url, headers: headers);
        ctrl.add(FileInfo(f, FileSource.online, DateTime.now().add(const Duration(days: 30)), url));
      } catch (e) {
        ctrl.addError(e);
      } finally {
        await ctrl.close();
      }
    }();
    return ctrl.stream;
  }

  @override
  Future<File> downloadFile(String url,
      {String? key, Map<String, String>? authHeaders, bool force = false}) {
    return getFile(url, headers: authHeaders ?? const <String, String>{});
  }

  @override
  Future<File> getSingleFile(String url,
      {String? key, Map<String, String>? headers}) {
    return getFile(url, headers: headers ?? const <String, String>{});
  }

  @override
  Future<void> removeFile(String key) async {
    // Best-effort: key here is the URL hash; we just remove the disk file.
    try {
      final Directory tmp = await getTemporaryDirectory();
      final File f = File(p.join(tmp.path, '${DiskImageCache.md5Of(key)}.jpg'));
      if (f.existsSync()) await f.delete();
    } catch (_) {/* ignore */}
  }

  @override
  Future<FileInfo?> getFileFromCache(String key,
      {bool ignoreMemCache = false}) async {
    try {
      final DiskImageCache disk = await DiskImageCache.instance();
      final File f = disk.fileFor(key);
      if (!f.existsSync()) return null;
      return FileInfo(f, FileSource.cache,
          DateTime.now().add(const Duration(days: 30)), key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<FileInfo?> getFileFromMemory(String key) async {
    final Uint8List? mem = ThreeTierImage.memory.get(key);
    if (mem == null) return null;
    final Directory tmp = await getTemporaryDirectory();
    final File f = File(p.join(tmp.path, '${DiskImageCache.md5Of(key)}.jpg'));
    if (!f.existsSync()) await f.writeAsBytes(mem, flush: true);
    return FileInfo(f, FileSource.cache,
        DateTime.now().add(const Duration(days: 30)), key);
  }

  @override
  Future<void> putFile(File file, String url,
      {Duration maxAge = const Duration(days: 30),
      String fileExtension = 'jpg'}) async {
    // No-op — our cache is populated on first network fetch.
  }

  @override
  Future<void> emptyCache() async {
    ThreeTierImage.memory.clear();
    final DiskImageCache disk = await DiskImageCache.instance();
    await disk.clear();
  }

  @override
  Future<FileInfo?> getFileFromMemoryAndDisk(String url,
      {bool ignoreMemCache = false}) {
    return getFileFromCache(url, ignoreMemCache: ignoreMemCache);
  }

  @override
  Future<bool> canReUseCachedFile(String url, String fileKey) async => true;
}

// ---------------------------------------------------------------------------
// Late-loaded imports (kept at the bottom to avoid cycle with m_client).
// ---------------------------------------------------------------------------

// ignore: avoid_relative_lib_imports
import 'package:http/http.dart' as http;
// ignore: avoid_relative_lib_imports
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show
        ImageCacheManager,
        FileResponse,
        FileInfo,
        FileSource;
