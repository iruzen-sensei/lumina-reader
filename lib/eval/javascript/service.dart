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

/// JsExtensionService — runs JavaScript source extensions through QuickJS
/// via the `flutter_qjs` plugin.
///
/// QuickJS is a small, embeddable JavaScript engine that supports ES2020.
/// `flutter_qjs` ships pre-built native binaries for Android, iOS, and
/// desktop, so extensions authored for Tachiyomi / Aniyomi / Mangayomi
/// can run unmodified inside Lumina Reader.
///
/// The service owns a single [FlutterQjs] engine per source. Each engine
/// is isolated — global state from one source's extension never leaks
/// into another's. Hot-reloads recycle the engine and re-evaluate the
/// extension code from scratch.
///
/// JavaScript extensions talk to the host through a single
/// `bridge.asyncCall(method, args)` entry point exposed under the global
/// `Lumina` object. The host responds with JSON-serialised payloads, which
/// the JavaScript side parses back into objects. This keeps the surface
/// area minimal and matches the way Tachiyomi-style extensions already
/// interact with their host.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_qjs/flutter_qjs.dart' as qjs;

import '../../services/http/m_client.dart';
import '../interface.dart';
import '../model/m_models.dart';

/// Set to `false` at startup if the native QuickJS library failed to load.
/// The factory in `lib/eval/lib.dart` reads this to decide whether to
/// advertise JavaScript source support.
bool isQuickJsAvailable = true;

void _markQuickJsUnavailable() {
  isQuickJsAvailable = false;
  if (kDebugMode) {
    debugPrint('JsExtensionService: QuickJS native library not available.');
  }
}

/// [ExtensionService] implementation backed by QuickJS via flutter_qjs.
class JsExtensionService with ExtensionServiceMixin {
  JsExtensionService({required this.source}) {
    // Lazy: the engine is only constructed on first [init]. We probe the
    // native library here so [isQuickJsAvailable] is set before any
    // factory call tries to instantiate us.
    _probeNative();
  }

  @override
  final MSource source;

  @override
  SourceCodeLanguage get codeLanguage => SourceCodeLanguage.javascript;

  qjs.FlutterQjs? _engine;
  qjs.JsMethodChannel? _channel;
  bool _initialised = false;

  /// The JavaScript shim that bootstraps the host bridge and exposes the
  /// standard extension globals (`Lumina.http`, `Lumina.document`, …).
  /// Evaluated before the user's extension code on every init / reload.
  static const String _bootstrapJs = r'''
    (function (global) {
      "use strict";

      const Lumina = global.Lumina || (global.Lumina = {});

      // ─── Host bridge ───────────────────────────────────────────────────
      // `__luminaBridge` is the JS-side function injected by flutter_qjs's
      // `setMethodChannel`. It accepts `(method: string, args: any[])` and
      // returns either the value directly (sync handlers) or a Promise
      // (async handlers — flutter_qjs awaits them automatically).
      //
      // flutter_qjs exposes the method channel under a few different names
      // depending on the package version — we probe for the most common
      // ones and pick whichever is available. The chosen reference is
      // cached as `__luminaBridge` so the rest of the bootstrap doesn't
      // have to care.
      (function installBridge() {
        var candidates = [
          typeof __luminaBridge !== 'undefined' ? __luminaBridge : null,
          typeof sendMessage !== 'undefined' ? sendMessage : null,
          typeof invokeMethod !== 'undefined' ? invokeMethod : null,
          typeof __flutterQjsBridge !== 'undefined' ? __flutterQjsBridge : null
        ];
        var bridgeFn = null;
        for (var i = 0; i < candidates.length; i++) {
          if (typeof candidates[i] === 'function') {
            bridgeFn = candidates[i];
            break;
          }
        }
        globalThis.__luminaBridge = bridgeFn || function () {
          throw new Error('Lumina bridge is not installed — set up flutter_qjs setMethodChannel first');
        };
      })();

      // Two flavours:
      //   * `_bridge`    — synchronous, fire-and-forget (used by `log`).
      //   * `_bridgeAsync` — returns a Promise, decoded back into a JS value.
      Lumina._bridge = function (method, args) {
        try {
          __luminaBridge(method, args || []);
        } catch (e) {
          // Swallow — log() must never throw.
        }
      };
      Lumina._bridgeAsync = function (method, args) {
        return new Promise(function (resolve, reject) {
          try {
            var raw = __luminaBridge(method, args || []);
            Promise.resolve(raw).then(function (payload) {
              if (payload == null) {
                resolve(null);
                return;
              }
              try {
                resolve(typeof payload === 'string' ? JSON.parse(payload) : payload);
              } catch (e) {
                resolve(payload);
              }
            }).catch(function (err) {
              reject(err instanceof Error ? err : new Error(String(err)));
            });
          } catch (e) {
            reject(e instanceof Error ? e : new Error(String(e)));
          }
        });
      };

      // Sync helpers — extensions can call these synchronously.
      Lumina.encode = function (value) {
        try { return JSON.stringify(value); } catch (e) { return null; }
      };
      Lumina.decode = function (text) {
        try { return JSON.parse(text); } catch (e) { return null; }
      };

      Lumina.log = function () {
        var parts = [];
        for (var i = 0; i < arguments.length; i++) {
          parts.push(typeof arguments[i] === 'object'
            ? JSON.stringify(arguments[i]) : String(arguments[i]));
        }
        Lumina._bridge('log', [parts.join(' ')]);
      };

      // Async dispatch helper. The Dart side calls `Lumina.async('getPopular', [page])`
      // to invoke the extension's top-level `getPopular` function. We look
      // up the function in the global scope and return a Promise that
      // resolves with its return value (or rejects with an error).
      Lumina.async = function (method, args) {
        return new Promise(function (resolve, reject) {
          var fn = null;
          try {
            fn = globalThis[method];
          } catch (e) {
            reject(new Error('Cannot resolve method "' + method + '": ' + e));
            return;
          }
          if (typeof fn !== 'function') {
            reject(new Error('Extension does not export a top-level "' + method + '" function'));
            return;
          }
          try {
            Promise.resolve(fn.apply(null, args || [])).then(resolve, function (err) {
              reject(err instanceof Error ? err : new Error(String(err)));
            });
          } catch (e) {
            reject(e instanceof Error ? e : new Error(String(e)));
          }
        });
      };

      Lumina.http = {
        get: function (url, headers) { return Lumina._bridgeAsync('httpGet', [url, headers || {}]); },
        post: function (url, headers, body) { return Lumina._bridgeAsync('httpPost', [url, headers || {}, body]); },
        put: function (url, headers, body) { return Lumina._bridgeAsync('httpPut', [url, headers || {}, body]); },
        delete: function (url, headers) { return Lumina._bridgeAsync('httpDelete', [url, headers || {}]); },
        head: function (url, headers) { return Lumina._bridgeAsync('httpHead', [url, headers || {}]); }
      };

      // Standard enums mirror the Dart side so JS extensions can write
      // `Lumina.Status.ongoing` etc.
      Lumina.Status = { unknown: 0, ongoing: 1, completed: 2, canceled: 3, onHiatus: 4, publishingFinished: 5 };
      Lumina.ItemType = { manga: 'manga', anime: 'anime', novel: 'novel', book: 'book' };

      // Convenience constructors — extensions build DTOs by returning
      // plain objects with these keys, but the helpers validate.
      Lumina.Manga = function (o) {
        return {
          title: o.title || '',
          author: o.author || '',
          description: o.description || '',
          imageUrl: o.imageUrl || '',
          link: o.link || '',
          genre: o.genre || [],
          status: o.status || 0,
          episodes: o.episodes || null
        };
      };
      Lumina.Chapter = function (o) {
        return {
          name: o.name || '',
          url: o.url || '',
          dateUpload: o.dateUpload || null,
          chapterNumber: o.chapterNumber || 0,
          scanlator: o.scanlator || null
        };
      };
      Lumina.Pages = function (mangaList, hasNextPage) {
        return { mangaList: mangaList || [], hasNextPage: !!hasNextPage };
      };
      Lumina.PageUrl = function (url, headers, base64Image, index) {
        return { url: url, headers: headers || null, base64Image: base64Image || null, index: index || null };
      };
      Lumina.Video = function (o) {
        return {
          url: o.url,
          videoTitle: o.videoTitle || null,
          resolution: o.resolution || null,
          bitrate: o.bitrate || null,
          preferred: !!o.preferred,
          headers: o.headers || {},
          subtitleTracks: o.subtitleTracks || [],
          audioTracks: o.audioTracks || [],
          mpvArgs: o.mpvArgs || {}
        };
      };
      Lumina.Track = function (url, lang) {
        return { url: url, lang: lang };
      };

      global.Lumina = Lumina;
    })(typeof globalThis !== 'undefined' ? globalThis : this);
  ''';

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> init({
    String? sourceCode,
    Map<String, String>? headers,
  }) async {
    if (!isQuickJsAvailable) {
      markError('QuickJS is not available in this build');
      return;
    }

    // Hot-reload: tear down the old engine first.
    if (_initialised) {
      await _teardownEngine();
      _initialised = false;
    }

    markLoading(sourceCode);

    final code = sourceCode ?? '';
    if (code.isEmpty) {
      markError('No source code supplied for ${source.id}');
      return;
    }

    try {
      final engine = qjs.FlutterQjs();
      engine.dispatch();
      _engine = engine;

      // Wire up the host bridge.
      final bridge = _HostBridge(source, headers ?? {});
      _channel = qjs.JsMethodChannel(
        (String method, List args) {
          return bridge.handle(method, args);
        },
      );
      engine.setMethodChannel(_channel!);

      // Bootstrap the standard library + the user's code.
      engine.evaluate(_bootstrapJs, name: 'lumina-bootstrap.js');
      engine.evaluate(code, name: 'extension-${source.id}.js');

      _initialised = true;
      final fingerprint = _fingerprint(code);
      markReady(fingerprint);
    } catch (e, st) {
      markError('QuickJS init failed: $e', cause: e, stack: st);
    }
  }

  @override
  Future<void> dispose() async {
    await _teardownEngine();
    await disposeMixin();
  }

  Future<void> _teardownEngine() async {
    final engine = _engine;
    _engine = null;
    _channel = null;
    if (engine != null) {
      try {
        engine.close();
      } catch (_) {
        // Best-effort.
      }
    }
  }

  void _probeNative() {
    try {
      // Construction is the cheapest way to probe — if the native lib is
      // missing, the constructor throws synchronously.
      // We don't keep this engine; it's just a ping.
      // ignore: unused_local_variable
      final probe = qjs.FlutterQjs();
      probe.dispatch();
      probe.close();
    } catch (e) {
      _markQuickJsUnavailable();
    }
  }

  // ─── Provider surface ────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) => guard(
        'getPopular',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('getPopular', [page]);
          return _coercePages(result);
        },
      );

  @override
  Future<MPages> getLatest(int page) => guard(
        'getLatest',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('getLatest', [page]);
          return _coercePages(result);
        },
      );

  @override
  Future<MPages> search(
    String query,
    int page, {
    List<Filter> filters = const [],
  }) =>
      guard(
        'search',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('search', [
            query,
            page,
            filters.map((f) => f.toJson()).toList(),
          ]);
          return _coercePages(result);
        },
      );

  @override
  Future<MManga> getDetail(String url) => guard(
        'getDetail',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('getDetail', [url]);
          return _coerceManga(result);
        },
      );

  @override
  Future<List<PageUrl>> getPageList(String url) => guard(
        'getPageList',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('getPageList', [url]);
          return _coercePageList(result);
        },
      );

  @override
  Future<List<MVideo>> getVideoList(String url) => guard(
        'getVideoList',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('getVideoList', [url]);
          return _coerceVideoList(result);
        },
      );

  @override
  Future<List<Filter>> getFilterList() => guard(
        'getFilterList',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('getFilterList', const []);
          if (result == null) return const [];
          if (result is! List) return const [];
          return result
              .whereType<Map>()
              .map((m) => Filter.fromJson(m.cast<String, dynamic>()))
              .toList(growable: false);
        },
        countsAsRequest: false,
      );

  @override
  Future<List<SourcePreference>> getSourcePreferences() => guard(
        'getSourcePreferences',
        () async {
          await _ensureReady();
          final result = await _invokeAsync('getSourcePreferences', const []);
          if (result == null) return const [];
          if (result is! List) return const [];
          return result
              .whereType<Map>()
              .map((m) =>
                  SourcePreference.fromJson(m.cast<String, dynamic>()))
              .toList(growable: false);
        },
        countsAsRequest: false,
      );

  @override
  Future<void> setPreference(String key, dynamic value) => guard(
        'setPreference',
        () async {
          await _ensureReady();
          await _invokeAsync('onPreferenceChanged', [key, value]);
        },
        countsAsRequest: false,
      );

  // ─── QuickJS invocation ─────────────────────────────────────────────────

  Future<void> _ensureReady() async {
    if (state != ExtensionState.ready || !_initialised || _engine == null) {
      throw ExtensionException(
        sourceId: source.id,
        method: '_ensureReady',
        message: 'QuickJS engine not ready (state=${state.name})',
      );
    }
  }

  /// Evaluate `Lumina.async('method', args)` and await the resulting
  /// Promise. Returns the JSON-decoded payload from the host bridge.
  Future<dynamic> _invokeAsync(String method, List<dynamic> args) async {
    final engine = _engine;
    if (engine == null) {
      throw ExtensionException(
        sourceId: source.id,
        method: method,
        message: 'QuickJS engine disposed',
      );
    }

    try {
      // The bootstrap defines `Lumina.async(method, args)` which returns a
      // Promise. `evaluateAsync` awaits Promises automatically.
      final raw = await engine.evaluateAsync(
        'Lumina.async(${jsonEncode(method)}, ${jsonEncode(args)})',
      );
      if (raw is String) {
        return jsonDecode(raw);
      }
      return raw;
    } catch (e, st) {
      throw ExtensionException(
        sourceId: source.id,
        method: method,
        message: 'QuickJS call failed: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ─── Coercion helpers (shared with the Dart service) ─────────────────────

  MPages _coercePages(dynamic raw) {
    if (raw is MPages) return raw;
    if (raw is Map) {
      final mangaList = (raw['mangaList'] as List? ?? const [])
          .map((m) => m is MManga
              ? m
              : MManga.fromJson((m as Map).cast<String, dynamic>()))
          .toList(growable: false);
      final hasNext = raw['hasNextPage'] as bool? ?? false;
      return MPages(mangaList: mangaList, hasNextPage: hasNext);
    }
    throw ExtensionException(
      sourceId: source.id,
      method: '_coercePages',
      message: 'Expected MPages-compatible value, got ${raw.runtimeType}',
    );
  }

  MManga _coerceManga(dynamic raw) {
    if (raw is MManga) return raw;
    if (raw is Map) {
      return MManga.fromJson(raw.cast<String, dynamic>());
    }
    throw ExtensionException(
      sourceId: source.id,
      method: '_coerceManga',
      message: 'Expected MManga-compatible value, got ${raw.runtimeType}',
    );
  }

  List<PageUrl> _coercePageList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((p) => p is PageUrl
              ? p
              : p is String
                  ? PageUrl(url: p)
                  : PageUrl.fromJson((p as Map).cast<String, dynamic>()))
          .toList(growable: false);
    }
    if (raw is MPagesList) return raw.pages;
    throw ExtensionException(
      sourceId: source.id,
      method: '_coercePageList',
      message: 'Expected List<PageUrl>, got ${raw.runtimeType}',
    );
  }

  List<MVideo> _coerceVideoList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((v) => v is MVideo
              ? v
              : MVideo.fromJson((v as Map).cast<String, dynamic>()))
          .toList(growable: false);
    }
    throw ExtensionException(
      sourceId: source.id,
      method: '_coerceVideoList',
      message: 'Expected List<MVideo>, got ${raw.runtimeType}',
    );
  }

  // ─── Misc ────────────────────────────────────────────────────────────────

  String _fingerprint(String code) {
    final digest = sha256.convert(utf8.encode(code));
    return digest.toString();
  }
}

/// Host-side bridge invoked by the JavaScript `Lumina.async` / `Lumina.log`
/// helpers. Receives a method name + args, returns the JSON-serialised
/// response, or throws to surface as a JS exception.
class _HostBridge {
  _HostBridge(this._source, this._defaultHeaders);

  final MSource _source;
  final Map<String, String> _defaultHeaders;
  MClient? _client;

  Future<MClient> _client_() async {
    final existing = _client;
    if (existing != null) return existing;
    final fresh = await MClient.forSource(_source.id);
    _client = fresh;
    return fresh;
  }

  /// Entry point — called by flutter_qjs's method channel.
  Future<dynamic> handle(String method, List<dynamic> args) async {
    switch (method) {
      case 'log':
        debugPrint('[ext/${_source.id}] ${args.join(' ')}');
        return null;

      case 'httpGet':
        return _httpSend('GET', args);
      case 'httpPost':
        return _httpSend('POST', args);
      case 'httpPut':
        return _httpSend('PUT', args);
      case 'httpDelete':
        return _httpSend('DELETE', args);
      case 'httpHead':
        return _httpSend('HEAD', args);

      default:
        throw ArgumentError('Unknown host method "$method"');
    }
  }

  Future<Map<String, dynamic>> _httpSend(
    String method,
    List<dynamic> args,
  ) async {
    if (args.isEmpty) {
      throw ArgumentError('httpSend: missing URL argument');
    }
    final url = args[0].toString();
    final headersArg = (args.length > 1 && args[1] is Map)
        ? (args[1] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};
    final body = args.length > 2 ? args[2] : null;

    final client = await _client_();
    final merged = <String, String>{}
      ..addAll(_defaultHeaders)
      ..addAll(headersArg);

    final response = await switch (method) {
      'GET' => client.get(url, headers: merged),
      'POST' => client.post(url, headers: merged, body: body),
      'PUT' => client.put(url, headers: merged, body: body),
      'DELETE' => client.delete(url, headers: merged, body: body),
      'HEAD' => client.head(url, headers: merged),
      _ => client.get(url, headers: merged),
    };

    return {
      'statusCode': response.statusCode,
      'body': response.body,
      'headers': response.headers,
      'url': url,
    };
  }
}
