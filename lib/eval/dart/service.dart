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

/// DartExtensionService — runs Dart source extensions through the d4rt
/// interpreter.
///
/// d4rt is a pure-Dart interpreter that supports a substantial subset of
/// Dart, enough to host a typical Mangayomi-style extension. We bridge
/// between the interpreter's object model and our DTOs by serialising to
/// / from `Map<String, dynamic>` at the boundary — that keeps the surface
/// area minimal and avoids leaking d4rt types into the rest of the app.
///
/// The service owns a single [d4rt.Interpreter] per source. Reloads (e.g.
/// when the user upgrades the extension code) tear down the old interpreter
/// and spin up a fresh one in place — d4rt interpreters are cheap to
/// create and there's no shared state to leak.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:d4rt/d4rt.dart' as d4rt;
import 'package:flutter/foundation.dart';

import '../../services/http/m_client.dart';
import '../interface.dart';
import '../model/m_models.dart';

/// [ExtensionService] implementation backed by the d4rt Dart interpreter.
class DartExtensionService with ExtensionServiceMixin {
  DartExtensionService({required this.source});

  @override
  final MSource source;

  @override
  SourceCodeLanguage get codeLanguage => SourceCodeLanguage.dart;

  d4rt.Interpreter? _interpreter;
  bool _initialised = false;

  @override
  Future<void> init({
    String? sourceCode,
    Map<String, String>? headers,
  }) async {
    // Hot-reload: tear down the old interpreter first so its globals
    // don't leak into the new evaluation.
    if (_initialised) {
      await _teardownInterpreter();
    }

    markLoading(sourceCode);

    final code = sourceCode ?? '';
    if (code.isEmpty) {
      markError('No source code supplied for ${source.id}');
      return;
    }

    try {
      final interpreter = d4rt.Interpreter();
      _installBridges(interpreter, headers ?? {});
      interpreter.evaluate(code);
      _interpreter = interpreter;
      _initialised = true;
      final fingerprint = _fingerprint(code);
      markReady(fingerprint);
    } catch (e, st) {
      markError('d4rt evaluation failed: $e', cause: e, stack: st);
    }
  }

  @override
  Future<void> dispose() async {
    await _teardownInterpreter();
    await disposeMixin();
  }

  Future<void> _teardownInterpreter() async {
    _interpreter = null;
    _initialised = false;
    // d4rt interpreters are GC'd when their reference drops — there's no
    // explicit close() to call.
  }

  // ─── Provider surface ────────────────────────────────────────────────────

  @override
  Future<MPages> getPopular(int page) => guard(
        'getPopular',
        () async {
          await _ensureReady();
          final result = await _invokeMethod('getPopular', [page]);
          return _coercePages(result);
        },
      );

  @override
  Future<MPages> getLatest(int page) => guard(
        'getLatest',
        () async {
          await _ensureReady();
          final result = await _invokeMethod('getLatest', [page]);
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
          final result = await _invokeMethod('search', [
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
          final result = await _invokeMethod('getDetail', [url]);
          return _coerceManga(result);
        },
      );

  @override
  Future<List<PageUrl>> getPageList(String url) => guard(
        'getPageList',
        () async {
          await _ensureReady();
          final result = await _invokeMethod('getPageList', [url]);
          return _coercePageList(result);
        },
      );

  @override
  Future<List<MVideo>> getVideoList(String url) => guard(
        'getVideoList',
        () async {
          await _ensureReady();
          final result = await _invokeMethod('getVideoList', [url]);
          return _coerceVideoList(result);
        },
      );

  @override
  Future<List<Filter>> getFilterList() => guard(
        'getFilterList',
        () async {
          await _ensureReady();
          final result = await _invokeMethod('getFilterList', const []);
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
          final result =
              await _invokeMethod('getSourcePreferences', const []);
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
          await _invokeMethod('onPreferenceChanged', [key, value]);
        },
        countsAsRequest: false,
      );

  // ─── d4rt bridging ───────────────────────────────────────────────────────

  /// Install every host-side bridge the extension can reach. The set is
  /// intentionally minimal — extensions that need more (e.g. file system
  /// access) should declare it via the source's manifest and we'll wire
  /// up additional bridges here.
  void _installBridges(
    d4rt.Interpreter interpreter,
    Map<String, String> headers,
  ) {
    final env = _environmentOf(interpreter);

    // Source descriptor — extensions read their own baseUrl / lang / etc.
    // from here rather than embedding them as string literals.
    _define(env, 'source', source.toJson());

    // HTTP — a thin wrapper around the MClient stack. Extensions call
    // `http.get(url, {headers: {...}})` etc.
    _define(env, 'http', _HttpBridge(source.id, headers));

    // DOM — Document / Element wrappers from m_models.dart.
    _define(env, 'Document', Document.html);
    _define(env, 'Element', Element.html);

    // JSON helpers.
    _define(env, 'jsonEncode', jsonEncode);
    _define(env, 'jsonDecode', jsonDecode);

    // Logger — extensions can call `log('message')` and it lands in the
    // app's debug console.
    _define(env, 'log', (Object? message) {
      debugPrint('[ext/${source.id}] $message');
    });

    // Status / ItemType enums so extensions can construct DTOs cleanly.
    _define(env, 'Status', {
      for (final v in Status.values) v.name: v,
    });
    _define(env, 'ItemType', {
      for (final v in ItemType.values) v.name: v,
    });
  }

  /// d4rt exposes its global environment via different accessors depending
  /// on the package version — try the most common ones. Returns the first
  /// that resolves, or null if none do (in which case bridging silently
  /// falls back to define-on-interpreter below).
  dynamic _environmentOf(d4rt.Interpreter interpreter) {
    try {
      // ignore: avoid_dynamic_calls
      final env = (interpreter as dynamic).environment;
      if (env != null) return env;
    } catch (_) {
      // Older / newer d4rt versions may not expose `environment`.
    }
    return interpreter;
  }

  void _define(dynamic env, String name, Object? value) {
    try {
      // Preferred API: Environment.define.
      // ignore: avoid_dynamic_calls
      (env as dynamic).define(name, value);
    } catch (_) {
      try {
        // Fallback: Interpreter.defineGlobal.
        // ignore: avoid_dynamic_calls
        (env as dynamic).defineGlobal(name, value);
      } catch (_) {
        // Last-resort: set on the interpreter itself.
        // ignore: avoid_dynamic_calls
        (env as dynamic).setGlobal(name, value);
      }
    }
  }

  Future<void> _ensureReady() async {
    if (state != ExtensionState.ready) {
      throw ExtensionException(
        sourceId: source.id,
        method: '_ensureReady',
        message: 'Service is in ${state.name} state, not ready',
      );
    }
    if (!_initialised || _interpreter == null) {
      throw ExtensionException(
        sourceId: source.id,
        method: '_ensureReady',
        message: 'd4rt interpreter not initialised',
      );
    }
  }

  /// Invoke [name] on the extension's top-level function table. Returns
  /// whatever the function returns; the caller is responsible for
  /// coercing into the right DTO.
  Future<dynamic> _invokeMethod(String name, List<dynamic> args) async {
    final interp = _interpreter;
    if (interp == null) {
      throw ExtensionException(
        sourceId: source.id,
        method: name,
        message: 'd4rt interpreter not initialised',
      );
    }

    // Fast path — some d4rt versions expose `callFunction(name, args)`
    // directly, which is both a lookup and an invocation in one call.
    try {
      // ignore: avoid_dynamic_calls
      final result = (interp as dynamic).callFunction(name, args);
      if (result is Future) return await result;
      return result;
    } on ExtensionException {
      rethrow;
    } catch (_) {
      // callFunction doesn't exist on this d4rt version — fall through to
      // the manual lookup path below.
    }

    // Resolve the function via whatever d4rt API the installed version
    // exposes. We try several accessors in turn — d4rt's surface has
    // shifted across releases and we don't want a hard dependency on a
    // specific version.
    dynamic fn;
    try {
      // ignore: avoid_dynamic_calls
      fn = (interp as dynamic).lookup(name);
    } catch (_) {
      // lookup() doesn't exist on this d4rt version — try the next one.
    }
    if (fn == null) {
      try {
        // ignore: avoid_dynamic_calls
        fn = (interp as dynamic).getFunction(name);
      } catch (_) {
        // getFunction() also not present — fall through to the lookup-by-
        // environment path below.
      }
    }
    if (fn == null) {
      try {
        // ignore: avoid_dynamic_calls
        final env = (interp as dynamic).environment;
        // ignore: avoid_dynamic_calls
        fn = env != null ? env.lookup(name) : null;
      } catch (_) {
        // Last resort — leave fn null and let the error below fire.
      }
    }

    if (fn == null) {
      throw ExtensionException(
        sourceId: source.id,
        method: name,
        message: 'Extension does not export a top-level "$name" function',
      );
    }

    try {
      // d4rt's interpreted functions expose a `call(args)` method that
      // dispatches through the interpreter. Plain Dart functions (e.g.
      // closures registered as globals) go through `Function.apply`.
      dynamic result;
      // ignore: avoid_dynamic_calls
      if (fn is d4rt.InterpretedFunction ||
          (fn.runtimeType.toString().contains('InterpretedFunction'))) {
        // ignore: avoid_dynamic_calls
        result = (fn as dynamic).call(args);
      } else if (fn is Function) {
        result = Function.apply(fn, args);
      } else {
        // Some d4rt versions wrap functions in a callable proxy — try
        // invoking directly.
        // ignore: avoid_dynamic_calls
        result = (fn as dynamic)(args);
      }
      if (result is Future) return await result;
      return result;
    } catch (e, st) {
      throw ExtensionException(
        sourceId: source.id,
        method: name,
        message: 'Failed to invoke "$name": $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ─── Coercion helpers ────────────────────────────────────────────────────

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

/// Bridge object exposed to d4rt extensions under the name `http`. The
/// methods are async and return plain Dart `Map`s (responses decoded into
/// `{statusCode, body, headers, url}`) so the interpreter never sees
/// platform types.
class _HttpBridge {
  _HttpBridge(this._sourceId, this._defaultHeaders);

  final String _sourceId;
  final Map<String, String> _defaultHeaders;
  MClient? _client;

  Future<MClient> _client_() async {
    final existing = _client;
    if (existing != null) return existing;
    final fresh = await MClient.forSource(_sourceId);
    _client = fresh;
    return fresh;
  }

  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? headers,
  }) =>
      _send('GET', url, headers: headers);

  Future<Map<String, dynamic>> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _send('POST', url, headers: headers, body: body);

  Future<Map<String, dynamic>> put(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _send('PUT', url, headers: headers, body: body);

  Future<Map<String, dynamic>> delete(
    String url, {
    Map<String, String>? headers,
  }) =>
      _send('DELETE', url, headers: headers);

  Future<Map<String, dynamic>> head(
    String url, {
    Map<String, String>? headers,
  }) =>
      _send('HEAD', url, headers: headers);

  Future<Map<String, dynamic>> _send(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final client = await _client_();
    final merged = <String, String>{}
      ..addAll(_defaultHeaders)
      ..addAll(headers ?? {});
    final response = await switch (method) {
      'GET' => client.get(url, headers: merged),
      'POST' => client.post(url, headers: merged, body: body),
      'PUT' => client.put(url, headers: merged, body: body),
      'DELETE' => client.delete(url, headers: merged),
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
