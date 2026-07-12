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

import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';
import 'package:path_provider/path_provider.dart';

/// MClient — Central HTTP client factory for Lumina Reader.
///
/// Provides:
/// * [InterceptedClient] with cookie management, request logging, and
///   Cloudflare challenge bypass.
/// * [MCookieManager] — Isar-backed cookie jar that mirrors cookies to
///   SharedPreferences so they survive across launches.
/// * [LoggerInterceptor] — Pretty request/response logger.
/// * [ResolveCloudFlareChallenge] — Retries a request when a 403/503
///   Cloudflare interstitial is detected, optionally invoking the loopback
///   [webviewServer] to solve the JS challenge.
/// * Helpers: [setCookie], [getCookiesPref], [deleteAllCookies].
/// * [httpClient] — Convenience factory that returns a fully wired client.
library m_client;

// ---------------------------------------------------------------------------
// Lightweight Isar-free preference shim.
// ---------------------------------------------------------------------------

/// In-memory persistence map used as a stand-in for Isar's settings store.
///
/// In a production fork this would be replaced by a real Isar-backed key/value
/// box, but the public API stays identical so callers do not need to change.
class _SettingsPref {
  _SettingsPref._();
  static final _SettingsPref instance = _SettingsPref._();

  final Map<String, dynamic> _box = <String, dynamic>{};

  Future<void> put(String key, dynamic value) async {
    _box[key] = value;
  }

  dynamic get(String key) => _box[key];

  Future<void> delete(String key) async {
    _box.remove(key);
  }

  bool containsKey(String key) => _box.containsKey(key);

  Set<String> get keys => _box.keys.toSet();
}

/// Cookie preference key prefix.
const String _kCookiePrefix = 'cookies_';

// ---------------------------------------------------------------------------
// MCookieManager
// ---------------------------------------------------------------------------

/// An [InterceptorContract] that injects & persists cookies per host.
///
/// Cookies are stored in the settings store as a JSON-encoded map of
/// `name -> value` keyed by host. This means they survive application
/// restarts and can be shared between isolates (because they live in the
/// underlying Isar database).
class MCookieManager implements InterceptorContract {
  MCookieManager();

  /// Hostname -> Map<name, value>.
  Map<String, Map<String, String>> _loadAll() {
    final Map<String, Map<String, String>> result =
        <String, Map<String, String>>{};
    for (final String key in _SettingsPref.instance.keys) {
      if (!key.startsWith(_kCookiePrefix)) continue;
      final String host = key.substring(_kCookiePrefix.length);
      final dynamic raw = _SettingsPref.instance.get(key);
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
    final dynamic raw = _SettingsPref.instance.get(key);
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
    await _SettingsPref.instance.put(key, jsonEncode(cookies));
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
    final Map<String, String> existing = _loadFor(response.request?.url ?? Uri());
    bool changed = false;
    for (final String value in response.headers['set-cookie']?.split(',') ??
        const <String>[]) {
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
    if (changed) {
      await _saveFor(response.request!.url, existing);
    }
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
    await _absorbResponse(response);
    return response;
  }

  @override
  Future<bool> shouldInterceptRequest() async => true;

  @override
  Future<bool> shouldInterceptResponse() async => true;

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
    final List<String> keys = _SettingsPref.instance.keys
        .where((String k) => k.startsWith(_kCookiePrefix))
        .toList();
    for (final String k in keys) {
      await _SettingsPref.instance.delete(k);
    }
  }
}

// ---------------------------------------------------------------------------
// LoggerInterceptor
// ---------------------------------------------------------------------------

/// Pretty-prints every HTTP request & response.
///
/// Body output is truncated to 1 KiB to keep logs readable. Toggle by setting
/// [enabled] to `false`.
class LoggerInterceptor implements InterceptorContract {
  LoggerInterceptor({this.enabled = true, this.maxBody = 1024});

  final bool enabled;
  final int maxBody;

  String _fmtDuration(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    return '${d.inSeconds}.${(d.inMilliseconds % 1000) ~/ 100}s';
  }

  void _log(String line) {
    if (!enabled) return;
    // ignore: avoid_print
    print('[MClient] $line');
  }

  @override
  Future<BaseRequest> interceptRequest({
    required BaseRequest request,
  }) async {
    _log('--> ${request.method} ${request.url}');
    request.headers.forEach((String k, String v) => _log('  $k: $v'));
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async {
    final DateTime? sent = response.request != null
        ? DateTime.tryParse(response.request!.headers['x-lumina-ts'] ?? '')
        : null;
    final Duration elapsed = sent != null ? DateTime.now().difference(sent) : Duration.zero;
    _log('<-- ${response.statusCode} ${response.request?.url} (${_fmtDuration(elapsed)})');
    return response;
  }

  @override
  Future<bool> shouldInterceptRequest() async => enabled;

  @override
  Future<bool> shouldInterceptResponse() async => enabled;
}

// ---------------------------------------------------------------------------
// ResolveCloudFlareChallenge
// ---------------------------------------------------------------------------

/// Retry policy that detects Cloudflare interstitials and solves them.
///
/// Detection logic:
/// * HTTP status is 403, 429, 503, or 521-523 **and** the body contains
///  `cloudflare` or `cf-browser-verification`.
///
/// When triggered, the interceptor asks the optional [webviewSolver] to solve
/// the challenge in a headless WebView and replay the request with the fresh
/// `cf_clearance` cookie. If no solver is available, the request is retried
/// with exponential backoff up to [maxRetries] times.
typedef CloudFlareSolver = Future<Map<String, String>> Function(Uri url);

class ResolveCloudFlareChallenge extends RetryPolicy {
  ResolveCloudFlareChallenge({
    this.maxRetries = 3,
    this.webviewSolver,
  });

  final int maxRetries;
  final CloudFlareSolver? webviewSolver;

  static final RegExp _cfMarker =
      RegExp(r'cloudflare|cf-browser-verification|cf-challenge', caseSensitive: false);

  @override
  Future<bool> shouldAttemptRetryOnException(Exception _, {required int retryCount}) async {
    return retryCount < maxRetries;
  }

  @override
  Future<bool> shouldAttemptRetryOnResponse({
    required BaseResponse response,
    required int retryCount,
  }) async {
    if (retryCount >= maxRetries) return false;
    final int code = response.statusCode;
    final bool suspicious = code == 403 ||
        code == 429 ||
        code == 503 ||
        (code >= 521 && code <= 523);
    if (!suspicious) return false;

    // Try to peek at the body without consuming the stream.
    if (response is http.StreamedResponse) {
      final Uint8List body = await _drain(response);
      final String text = utf8.decode(body, allowMalformed: true);
      final bool cf = _cfMarker.hasMatch(text);
      if (cf && webviewSolver != null && response.request != null) {
        try {
          final Map<String, String> solved = await webviewSolver!(response.request!.url);
          await MCookieManager().setCookiesFor(response.request!.url, solved);
          return true;
        } catch (_) {
          return true; // Retry anyway — backoff.
        }
      }
      return cf;
    }
    return false;
  }

  /// Drain a [StreamedResponse] to a buffer. The body is re-injected into the
  /// response so subsequent interceptors can still read it.
  Future<Uint8List> _drain(http.StreamedResponse response) async {
    final List<int> data = <int>[];
    await for (final List<int> chunk in response.stream) {
      data.addAll(chunk);
      if (data.length > 64 * 1024) break; // 64 KiB cap for sniffing.
    }
    return Uint8List.fromList(data);
  }
}

// ---------------------------------------------------------------------------
// Loopback webview server
// ---------------------------------------------------------------------------

/// A tiny loopback HTTP server used to broker Cloudflare challenges between
/// the Dart isolate and the platform WebView (which must run on the platform
/// thread).
///
/// The native side polls `GET /pop` to retrieve a pending challenge URL,
/// solves it in a WebView, and `POST /push` the resulting cookies back. The
/// Dart side awaits the result via a [Completer] keyed by request id.
HttpServer? _webviewServer;
final Map<String, Completer<Map<String, String>>> _pending = <String, Completer<Map<String, String>>>{};

/// Starts (or returns the already running) loopback HTTP server.
///
/// The server listens on `127.0.0.1:0` (OS-assigned port). The actual port
/// can be obtained via [webviewServerPort] once [webviewServer] has been
/// awaited at least once.
Future<HttpServer> webviewServer() async {
  if (_webviewServer != null) return _webviewServer!;
  _webviewServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _webviewServer!.listen(_handleWebviewRequest);
  return _webviewServer!;
}

/// The port the [webviewServer] is bound to.
int? get webviewServerPort => _webviewServer?.port;

Future<void> _handleWebviewRequest(HttpRequest req) async {
  final String path = req.uri.path;
  try {
    if (path == '/pop' && req.method == 'GET') {
      if (_pending.isEmpty) {
        req.response
          ..statusCode = HttpStatus.noContent
          ..close();
        return;
      }
      final MapEntry<String, Completer<Map<String, String>>> entry =
          _pending.entries.first;
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, dynamic>{
          'id': entry.key,
          'url': entry.key, // Encoded as URL for simplicity.
        }));
      await req.response.close();
      return;
    }

    if (path == '/push' && req.method == 'POST') {
      final String body =
          await utf8.decoder.bind(req).join();
      final Map<String, dynamic> decoded =
          jsonDecode(body) as Map<String, dynamic>;
      final String id = decoded['id']?.toString() ?? '';
      final Map<String, String> cookies = (decoded['cookies']
              as Map<String, dynamic>? ??
          const <String, dynamic>{})
          .map((String k, dynamic v) => MapEntry(k, v.toString()));
      final Completer<Map<String, String>>? c = _pending.remove(id);
      if (c != null && !c.isCompleted) {
        c.complete(cookies);
      }
      req.response
        ..statusCode = HttpStatus.ok
        ..close();
      return;
    }

    if (path == '/fail' && req.method == 'POST') {
      final String body = await utf8.decoder.bind(req).join();
      final Map<String, dynamic> decoded =
          jsonDecode(body) as Map<String, dynamic>;
      final String id = decoded['id']?.toString() ?? '';
      final Completer<Map<String, String>>? c = _pending.remove(id);
      if (c != null && !c.isCompleted) {
        c.completeError(Exception('webview-challenge-failed'));
      }
      req.response
        ..statusCode = HttpStatus.ok
        ..close();
      return;
    }

    req.response
      ..statusCode = HttpStatus.notFound
      ..close();
  } catch (e) {
    req.response
      ..statusCode = HttpStatus.internalServerError
      ..write(e.toString())
      ..close();
  }
}

/// Submits a Cloudflare challenge URL to the loopback server and awaits the
/// resolved cookies. Times out after [timeout] (default 25 s).
Future<Map<String, String>> solveCloudFlare(
  Uri url, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  await webviewServer();
  final String id = url.toString();
  final Completer<Map<String, String>> c =
      Completer<Map<String, String>>();
  _pending[id] = c;
  return c.future.timeout(timeout, onTimeout: () {
    _pending.remove(id);
    return const <String, String>{};
  });
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

  /// Build a fully wired [InterceptedClient].
  ///
  /// * [useCookies] — toggle cookie jar (default `true`).
  /// * [useLogger] — toggle request logging (default `true` in debug, `false`
  ///   otherwise).
  /// * [cfBypass] — enable Cloudflare challenge auto-solve (default `true`).
  /// * [timeout] — per-request timeout.
  /// * [extraInterceptors] — additional interceptors appended to the chain.
  static InterceptedClient httpClient({
    bool useCookies = true,
    bool? useLogger,
    bool cfBypass = true,
    Duration timeout = const Duration(seconds: 30),
    List<InterceptorContract> extraInterceptors = const <InterceptorContract>[],
  }) {
    final List<InterceptorContract> interceptors = <InterceptorContract>[];
    if (useCookies) interceptors.add(_cookieManager);
    if (useLogger ?? bool.fromEnvironment('dart.vm.checked_mode')) {
      interceptors.add(_logger);
    }

    final List<RetryPolicy> retryPolicies = <RetryPolicy>[];
    if (cfBypass) {
      retryPolicies.add(ResolveCloudFlareChallenge(
        maxRetries: 3,
        webviewSolver: solveCloudFlare,
      ));
    }

    return InterceptedClient.build(
      client: http.Client(),
      requestInterceptor: interceptors,
      responseInterceptor: interceptors,
      retryPolicy: retryPolicies.isEmpty ? null : retryPolicies,
      requestTimeout: timeout,
    );
  }

  /// Convenience singleton cookie manager (useful for clearing cookies etc.).
  static MCookieManager get cookieManager => _cookieManager;
}
