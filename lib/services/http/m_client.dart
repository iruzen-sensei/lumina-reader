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

import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// MClient — Central HTTP client factory for Lumina Reader.
///
/// Provides:
/// * [InterceptedClient] with cookie management and request logging.
/// * [MCookieManager] — file-backed cookie jar (survives restarts) keyed by
///   host, persisted as JSON under the app-support directory.
/// * [LoggerInterceptor] — Pretty request/response logger (secrets redacted).
/// * [ResolveCloudFlareChallenge] — Retry policy that backs off when a
///   Cloudflare interstitial is detected.
/// * Helpers: [setCookie], [getCookiesPref], [deleteAllCookies].
/// * [httpClient] — Convenience factory that returns a fully wired client.
///
/// SECURITY NOTE: an earlier revision exposed a loopback HTTP "webview
/// broker" server (GET /pop, POST /push, POST /fail) meant to hand Cloudflare
/// challenges to a native WebView poller. No such poller ever existed in the
/// Android shell, so challenges always timed out AND the unauthenticated
/// server let any other app on the device read pending challenge URLs or
/// push attacker-chosen cookies into a pending solve. Both the server and
/// the solver plumbing were removed; the retry policy remains an honest
/// exponential backoff.

// ---------------------------------------------------------------------------
// Cookie persistence (file-backed, app-support directory)
// ---------------------------------------------------------------------------

/// Where the cookie jar lives on disk (lazily resolved).
Future<File> _cookieStoreFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'http_cookies.json'));
}

Future<Map<String, dynamic>> _readCookieStore() async {
  try {
    final file = await _cookieStoreFile();
    if (!file.existsSync()) return <String, dynamic>{};
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{}; // corrupt store -> start fresh
  }
}

Future<void> _writeCookieStore(Map<String, dynamic> data) async {
  try {
    final file = await _cookieStoreFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  } catch (_) {
    // Persistence is best-effort (e.g. unit tests without path_provider).
  }
}

/// Cookie preference key prefix.
const String _kCookiePrefix = 'cookies_';

// ---------------------------------------------------------------------------
// MCookieManager
// ---------------------------------------------------------------------------

/// An [InterceptorContract] that injects & persists cookies per host.
///
/// Cookies live in an in-memory map mirrored to
/// `<app-support>/http_cookies.json` (debounced writes), so they survive
/// application restarts. Cloudflare clearances obtained mid-session are
/// therefore still valid on the next launch.
class MCookieManager implements HttpInterceptor {
  MCookieManager();

  /// Shared instance state — every [MCookieManager] sees the same jar
  /// (they all delegate here), matching the previous single-instance
  /// behaviour while keeping the class instantiable for tests.
  static final Map<String, dynamic> _store = <String, dynamic>{};
  static bool _loaded = false;
  static Timer? _saveTimer;
  static bool _writing = false;

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true; // set first to avoid re-entrancy
    _store.addAll(await _readCookieStore());
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _flushNow);
  }

  static Future<void> _flushNow() async {
    if (_writing) {
      _scheduleSave(); // retry shortly
      return;
    }
    _writing = true;
    try {
      await _writeCookieStore(Map<String, dynamic>.of(_store));
    } finally {
      _writing = false;
    }
  }

  /// Flush pending cookie writes to disk immediately (app pause / exit).
  static Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_loaded) await _flushNow();
  }

  /// Reload the jar from disk and drop in-memory state (tests / resets).
  static Future<void> resetFromDisk() async {
    _store.clear();
    _loaded = false;
    await _ensureLoaded();
  }

  /// Load the persisted jar into memory if it has not been loaded yet
  /// (called once at app boot; harmless afterwards).
  Future<void> preloadFromDisk() async => _ensureLoaded();

  Map<String, Map<String, String>> _loadAll() {
    final Map<String, Map<String, String>> result =
        <String, Map<String, String>>{};
    for (final String key in _store.keys.toList()) {
      if (!key.startsWith(_kCookiePrefix)) continue;
      final String host = key.substring(_kCookiePrefix.length);
      final dynamic raw = _store[key];
      if (raw is String) {
        try {
          final Map<String, dynamic> decoded =
              jsonDecode(raw) as Map<String, dynamic>;
          result[host] =
              decoded.map((String k, dynamic v) => MapEntry(k, v.toString()));
        } catch (_) {
          // Ignore corrupt entries.
        }
      }
    }
    return result;
  }

  Map<String, String> _loadFor(Uri uri) {
    final String key = '$_kCookiePrefix${uri.host}';
    final dynamic raw = _store[key];
    if (raw is String && raw.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(raw) as Map<String, dynamic>;
        return decoded
            .map((String k, dynamic v) => MapEntry(k, v.toString()));
      } catch (_) {
        /* fall-through */
      }
    }
    return <String, String>{};
  }

  Future<void> _saveFor(Uri uri, Map<String, String> cookies) async {
    final String key = '$_kCookiePrefix${uri.host}';
    _store[key] = jsonEncode(cookies);
    _scheduleSave();
  }

  /// Build a `name=value; name2=value2` cookie header from the store.
  String _buildHeader(Uri uri) {
    final Map<String, String> cookies = _loadFor(uri);
    if (cookies.isEmpty) return '';
    return cookies.entries
        .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
        .join('; ');
  }

  /// Parse `Set-Cookie` response headers and persist them.
  Future<void> _absorbResponse(http.BaseResponse response) async {
    if (response is! http.StreamedResponse) return;
    final Uri? url = response.request?.url;
    if (url == null) return;
    final Map<String, String> existing = _loadFor(url);
    bool changed = false;
    final String? header = response.headers['set-cookie'];
    if (header != null) {
      for (final String value in splitSetCookieHeader(header)) {
        final String? pair = _parseSetCookie(value);
        if (pair == null) continue;
        final int eq = pair.indexOf('=');
        if (eq <= 0) continue;
        final String name = pair.substring(0, eq).trim();
        final String val = pair.substring(eq + 1).trim();
        if (existing[name] != val) {
          existing[name] = val;
          changed = true;
        }
      }
    }
    if (changed) {
      await _saveFor(url, existing);
    }
  }

  /// Split a merged `set-cookie` header on commas, but only where a new
  /// cookie actually starts. Public + static so the parsing is testable. The http package folds multiple `Set-Cookie`
  /// lines into one comma-joined string; cookie values themselves may
  /// contain commas (`Expires=Wed, 09 Jun 2021 ...`), so a naive split
  /// corrupts them.
  static List<String> splitSetCookieHeader(String header) {
    final List<String> parts = <String>[];
    final buffer = StringBuffer();
    final int len = header.length;
    for (var i = 0; i < len; i++) {
      final String ch = header[i];
      if (ch != ',') {
        buffer.write(ch);
        continue;
      }
      // A comma only ends a cookie when what follows (after optional
      // spaces) looks like `token=` or `token =` — i.e. a fresh name=value
      // pair, not a continuation such as a date.
      var j = i + 1;
      while (j < len && (header[j] == ' ' || header[j] == '\t')) {
        j++;
      }
      var k = j;
      while (k < len &&
          header[k] != '=' &&
          header[k] != ';' &&
          header[k] != ',' &&
          header[k] != ' ') {
        k++;
      }
      final bool newCookieStarts =
          k > j && k < len && header[k] == '=';
      if (newCookieStarts) {
        parts.add(buffer.toString());
        buffer.clear();
        i = j - 1; // skip the spaces we consumed
      } else {
        buffer.write(ch);
      }
    }
    parts.add(buffer.toString());
    return parts;
  }

  String? _parseSetCookie(String header) {
    // Set-Cookie: name=value; Path=/; HttpOnly; ...
    final int semi = header.indexOf(';');
    final String seg = semi >= 0 ? header.substring(0, semi) : header;
    if (!seg.contains('=')) return null;
    return seg.trim();
  }

  // ---- InterceptedClient contract ------------------------------------------

  @override
  Future<BaseRequest> interceptRequest({
    required BaseRequest request,
  }) async {
    await _ensureLoaded();
    final String cookieHeader = _buildHeader(request.url);
    if (cookieHeader.isNotEmpty) {
      request.headers[HttpHeaders.cookieHeader] = cookieHeader;
    }
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async {
    await _ensureLoaded();
    await _absorbResponse(response);
    return response;
  }

  @override
  Future<bool> shouldInterceptRequest({required BaseRequest request}) async =>
      true;

  @override
  Future<bool> shouldInterceptResponse({required BaseResponse response}) async =>
      true;

  // ---- Public helpers ------------------------------------------------------

  /// Return all cookies for a given host as a `Map<name, value>`.
  Map<String, String> getCookiesFor(Uri uri) => _loadFor(uri);

  /// Return all cookies across all hosts.
  Map<String, Map<String, String>> getAllCookies() => _loadAll();

  /// Explicitly set/overwrite the cookies for a host.
  Future<void> setCookiesFor(Uri uri, Map<String, String> cookies) =>
      _saveFor(uri, cookies);

  /// Delete every persisted cookie for every host.
  Future<void> deleteAll() async {
    final List<String> keys = _store.keys
        .where((String k) => k.startsWith(_kCookiePrefix))
        .toList();
    for (final String k in keys) {
      _store.remove(k);
    }
    _scheduleSave();
  }
}

// ---------------------------------------------------------------------------
// LoggerInterceptor
// ---------------------------------------------------------------------------

/// Pretty-prints every HTTP request & response.
///
/// Sensitive header values (cookies, authorization) are redacted so debug
/// logs never leak session credentials. Body output is truncated to 1 KiB to
/// keep logs readable. Toggle by setting [enabled] to `false`.
class LoggerInterceptor implements HttpInterceptor {
  LoggerInterceptor({this.enabled = true, this.maxBody = 1024});

  final bool enabled;
  final int maxBody;

  static const Set<String> _redactedHeaders = {
    'cookie',
    'set-cookie',
    'authorization',
    'proxy-authorization',
  };

  String _fmtDuration(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    return '${d.inSeconds}.${(d.inMilliseconds % 1000) ~/ 100}s';
  }

  void _log(String line) {
    if (!enabled) return;
    // ignore: avoid_print
    print('[MClient] $line');
  }

  String _fmtHeader(String name, String value) =>
      _redactedHeaders.contains(name.toLowerCase())
          ? '$name: <redacted>'
          : '$name: $value';

  @override
  Future<BaseRequest> interceptRequest({
    required BaseRequest request,
  }) async {
    _log('--> ${request.method} ${request.url}');
    request.headers
        .forEach((String k, String v) => _log('  ${_fmtHeader(k, v)}'));
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async {
    final DateTime? sent = response.request != null
        ? DateTime.tryParse(response.request!.headers['x-lumina-ts'] ?? '')
        : null;
    final Duration elapsed = sent != null
        ? DateTime.now().difference(sent)
        : Duration.zero;
    _log('<-- ${response.statusCode} ${response.request?.url} '
        '(${_fmtDuration(elapsed)})');
    return response;
  }

  @override
  Future<bool> shouldInterceptRequest({required BaseRequest request}) async =>
      enabled;

  @override
  Future<bool> shouldInterceptResponse({required BaseResponse response}) async =>
      enabled;
}

// ---------------------------------------------------------------------------
// ResolveCloudFlareChallenge
// ---------------------------------------------------------------------------

/// Retry policy that detects Cloudflare interstitials and backs off.
///
/// Detection logic: HTTP status is 403, 429, 503, or 521-523 **and** the
/// response carries `server: cloudflare`. There is no challenge solver in
/// this build (the old loopback webview broker never had a native poller
/// and was removed), so the policy retries with exponential backoff up to
/// [maxRetries] times and then surfaces the failure to the caller.
class ResolveCloudFlareChallenge implements RetryPolicy {
  ResolveCloudFlareChallenge({
    this.maxRetries = 3,
  });

  final int maxRetries;

  @override
  int get maxRetryAttempts => maxRetries;

  @override
  Duration delayRetryAttemptOnException({required int retryAttempt}) =>
      Duration(seconds: 1 << retryAttempt.clamp(0, 4));

  @override
  Duration delayRetryAttemptOnResponse({required int retryAttempt}) =>
      Duration(seconds: 1 << retryAttempt.clamp(0, 4));

  @override
  FutureOr<bool> shouldAttemptRetryOnException(
    Exception reason,
    BaseRequest request,
  ) async =>
      false; // connection errors are handled by callers' own retry logic

  @override
  FutureOr<bool> shouldAttemptRetryOnResponse(BaseResponse response) async {
    final int code = response.statusCode;
    // 429 is EXCLUDED: it is rate limiting, not a challenge — retrying a
    // 429 burns more quota (MangaDex's limiter answered every retry with
    // another 429 during bulk library updates). Rate-limited APIs get their
    // own backoff at the source layer (see MangaDexSource._getJson).
    final bool suspicious = code == 403 ||
        code == 503 ||
        (code >= 521 && code <= 523);
    if (!suspicious) return false;

    // Detection is header-based only: reading (and thereby consuming) the
    // body stream here would corrupt the response the caller eventually
    // receives. Cloudflare's edge sets `server: cloudflare` on challenge
    // interstitials.
    return (response.headers['server'] ?? '').toLowerCase() == 'cloudflare';
  }
}

// ---------------------------------------------------------------------------
// Public helpers
// ---------------------------------------------------------------------------

/// Persist a single cookie for the given [uri].
Future<void> setCookie(Uri uri, String name, String value) async {
  final MCookieManager mgr = MCookieManager();
  final Map<String, String> cookies = mgr.getCookiesFor(uri);
  cookies[name] = value;
  await mgr.setCookiesFor(uri, cookies);
}

/// Get all cookies (as `name=value` map) persisted for [uri].
Map<String, String> getCookiesPref(Uri uri) => MCookieManager().getCookiesFor(uri);

/// Remove every cookie from every host.
Future<void> deleteAllCookies() => MCookieManager().deleteAll();

/// Flush the cookie jar to disk (call on app pause / lifecycle changes).
Future<void> persistCookies() => MCookieManager.flush();

// ---------------------------------------------------------------------------
// MClient
// ---------------------------------------------------------------------------

/// Central HTTP client factory.
///
/// Usage:
/// ```dart
/// final client = MClient.httpClient();
/// final res = await client.get(Uri.parse('https://manga.site/list'));
/// ```
class MClient {
  MClient._();

  /// A shared cookie manager — every client uses the same instance so cookies
  /// stay in sync.
  static final MCookieManager _cookieManager = MCookieManager();
  static final LoggerInterceptor _logger = LoggerInterceptor();

  // -------------------------------------------------------------------------
  // Transport (Cronet on Android, dart:io elsewhere)
  // -------------------------------------------------------------------------

  /// Shared Cronet engine. WHY: Cloudflare fronts (AniZone, many Madara
  /// mirrors) fingerprint dart:io HttpClient's TLS ClientHello (JA3) and
  /// answer it with a challenge page from ANY IP — verified from the same
  /// host where curl and Cronet (Chrome's network stack) get straight 200s.
  /// Cronet therefore unblocks real-device access to those sources. The
  /// engine is shared (per-client `closeEngine: false`) and lives for the
  /// process lifetime.
  static CronetEngine? _cronetEngine;
  static bool _cronetFailed = false;

  /// Best available `package:http` transport for the current platform.
  static http.Client _transportClient() {
    if (!kIsWeb && Platform.isAndroid && !_cronetFailed) {
      try {
        return CronetClient.fromCronetEngine(_ensureCronetEngine(),
            closeEngine: false);
      } catch (e) {
        _cronetFailed = true;
        debugPrint('MClient: Cronet unavailable ($e) — dart:io fallback. '
            'CF-gated sources may be blocked on this device.');
      }
    }
    return http.Client();
  }

  static CronetEngine _ensureCronetEngine() {
    return _cronetEngine ??= CronetEngine.build(
          cacheMode: CacheMode.memory,
          cacheMaxSize: 4 * 1024 * 1024,
          enableBrotli: true,
          enableHttp2: true,
          enableQuic: true,
        );
  }

  /// Build a fully wired [InterceptedClient].
  ///
  /// * [useCookies] — toggle cookie jar (default `true`).
  /// * [useLogger] — toggle request logging (default `true` in debug, `false`
  ///   otherwise).
  /// * [cfBypass] — enable Cloudflare-aware retry/backoff (default `true`).
  /// * [timeout] — per-request timeout.
  /// * [extraInterceptors] — additional interceptors appended to the chain.
  static InterceptedClient httpClient({
    bool useCookies = true,
    bool? useLogger,
    Duration timeout = const Duration(seconds: 30),
    List<HttpInterceptor> extraInterceptors = const <HttpInterceptor>[],
    @Deprecated('No solver exists in this build; kept for source compat')
        bool cfBypass = true,
  }) {
    final List<HttpInterceptor> interceptors = <HttpInterceptor>[];
    if (useCookies) interceptors.add(_cookieManager);
    if (useLogger ?? const bool.fromEnvironment('dart.vm.checked_mode')) {
      interceptors.add(_logger);
    }

    final List<RetryPolicy> retryPolicies = <RetryPolicy>[
      ResolveCloudFlareChallenge(maxRetries: 3),
    ];

    return InterceptedClient.build(
      client: _transportClient(),
      interceptors: interceptors,
      retryPolicy: retryPolicies.first,
      requestTimeout: timeout,
    );
  }

  /// Convenience singleton cookie manager (useful for clearing cookies etc.).
  static MCookieManager get cookieManager => _cookieManager;

  /// Per-source client cache. Extensions call this with their numeric source
  /// id to get a client whose cookies are scoped per host (cookies are shared
  /// through [_cookieManager]) and whose lifetime is managed centrally.
  static final Map<String, InterceptedClient> _sourceClients = {};

  /// Returns a cached [InterceptedClient] for the given [sourceId].
  ///
  /// The cache key includes the id's runtime type, so a numeric Isar id and
  /// a String extension id never collide (String.hashCode == int.hashCode is
  /// possible, which previously cross-shared a client between sources).
  static http.Client forSource(Object? sourceId, {bool useCookies = true}) {
    if (sourceId == null) {
      return httpClient(useCookies: useCookies, useLogger: false);
    }
    final key = '${sourceId.runtimeType}#$sourceId';
    return _sourceClients[key] ??= httpClient(
      useCookies: useCookies,
      useLogger: false,
    );
  }

  /// Closes and drops every cached per-source client (used on logout /
  /// cookie purge).
  static void closeAllSourceClients() {
    for (final c in _sourceClients.values) {
      c.close();
    }
    _sourceClients.clear();
  }
}
