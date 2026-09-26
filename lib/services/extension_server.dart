// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// ON-DEVICE APK EXTENSION SERVER BOOTSTRAP.
//
// Aniyomi/Mihon extensions are Android APKs containing Dex code. The
// `m_extension_server` plugin runs a local NanoHTTPD server (loopback only)
// that loads those APKs with a child-first PathClassLoader and speaks a
// small JSON protocol on POST /dalvik:
//
//   { "method": "getPopularAnime" | "getSearchManga" | "getEpisodeList" |
//               "getVideoList" | "getPageList" | ...,
//     "data": "<base64 APK bytes>",
//     "sourceId": "<numeric aniyomi source id>", "lang": "en", ... }
//
// Ported from upstream Mangayomi's services/m_extension_server.dart
// (Android path only; desktop JRE / iOS paths do not apply to this app).
// Plain singleton (no riverpod) because [getExtensionService] is a sync
// factory that must hand the URL to services lazily.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:m_extension_server/m_extension_server.dart';

class ExtensionServerRuntime {
  ExtensionServerRuntime._();
  static final ExtensionServerRuntime instance = ExtensionServerRuntime._();

  String? _baseUrl;
  Future<String?>? _starting;

  String? get baseUrl => _baseUrl;
  bool get isRunning => _baseUrl != null;

  /// Returns the loopback base URL, starting the server first when needed.
  /// Returns null on non-Android platforms or after failed start attempts.
  Future<String?> ensureStarted() async {
    if (!Platform.isAndroid) return null;
    if (_baseUrl != null) return _baseUrl;
    return await (_starting ??= _start().whenComplete(() => _starting = null));
  }

  Future<String?> _start() async {
    try {
      // Bind a free port, release it, then let the plugin server take it.
      for (var attempt = 0; attempt < 3; attempt++) {
        final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        await probe.close();
        try {
          await MExtensionServer().startServer(port);
        } catch (e) {
          debugPrint('ExtensionServer.startServer failed: $e');
          continue;
        }
        final candidate = 'http://127.0.0.1:$port';
        if (await _isOurServer(candidate)) {
          _baseUrl = candidate;
          debugPrint('ExtensionServer running at $candidate');
          return candidate;
        }
        try {
          await MExtensionServer().stopServer();
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('ExtensionServer.start failed: $e');
      return null;
    }
  }

  /// Polls /capabilities until the server is actually up — the marker
  /// string proves the port carries OUR server, not some other loopback
  /// service that grabbed it first.
  Future<bool> _isOurServer(String baseUrl) async {
    for (var i = 0; i < 20; i++) {
      try {
        final res = await http
            .get(Uri.parse('$baseUrl/capabilities'))
            .timeout(const Duration(milliseconds: 500));
        if (res.statusCode == 200 &&
            res.body.contains('mangayomiMihonBridge')) {
          return true;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<void> stop() async {
    try {
      await MExtensionServer().stopServer();
    } catch (_) {}
    _baseUrl = null;
  }
}
