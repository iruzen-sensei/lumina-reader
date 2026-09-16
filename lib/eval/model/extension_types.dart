// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Shared support types for the interpreter-backed extension services
// (eval/dart/service.dart, eval/javascript/service.dart).
//
// These types were referenced by the original skeleton but never defined,
// which broke compilation of the entire app. They are defined here once so
// the interpreter backends compile; the native sources
// (eval/native/*.dart) do NOT use them — they speak the clean
// ExtensionService interface directly.

import 'm_models.dart';
import '../../models/source.dart';

/// Lifecycle state of an interpreter-backed extension service.
enum ExtensionState {
  /// Constructed but not initialised.
  created,

  /// init() is running.
  initializing,

  /// Ready to serve requests.
  ready,

  /// A fatal error occurred; the service must be re-initialised.
  error,

  /// dispose() has been called.
  disposed,
}

/// Error thrown by extension services for any recoverable failure.
class ExtensionException implements Exception {
  ExtensionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'ExtensionException: $message${cause == null ? '' : ' ($cause)'}';
}

/// A single page image reference produced by `getPageList`.
class PageUrl {
  PageUrl({
    required this.url,
    this.headers,
    this.base64Image,
    this.index,
  });

  /// Direct image URL (or a data: URI).
  final String url;

  /// Per-image HTTP headers (referer etc.).
  final Map<String, String>? headers;

  /// Pre-fetched image bytes (base64) — some sources inline images.
  final String? base64Image;

  /// 0-based position in the chapter.
  final int? index;

  factory PageUrl.fromJson(Map<String, dynamic> json) => PageUrl(
        url: json['url'] as String? ?? '',
        headers: (json['headers'] as Map?)?.cast<String, String>(),
        base64Image: json['base64Image'] as String?,
        index: json['index'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (headers != null) 'headers': headers,
        if (base64Image != null) 'base64Image': base64Image,
        if (index != null) 'index': index,
      };
}

/// List-of-PageUrl wrapper some extension runtimes return from
/// `getPageList`.
class MPagesList {
  MPagesList(this.pages);

  final List<PageUrl> pages;
}

/// Mixin surface shared by the interpreter services. The interpreters keep
/// their own internal architecture (guard()/state machine, MPages results)
/// rather than conforming to the full [ExtensionService] interface; this
/// mixin declares exactly the members they share so `@override` annotations
/// resolve and cross-cutting helpers live in one place.
mixin ExtensionServiceMixin {
  // -- Abstract surface implemented by the concrete services -------------

  /// Metadata of the source this service executes.
  MSource get source;

  /// Language of the interpreted source code.
  SourceCodeLanguage get codeLanguage;

  Future<void> init({
    String? sourceCode,
    Map<String, String>? headers,
  });

  Future<void> dispose();

  Future<MPages> getPopular(int page);

  Future<MPages> getLatest(int page);

  Future<MPages> search(
    String query,
    int page, {
    List<Filter> filters,
  });

  Future<MManga> getDetail(String url);

  Future<List<PageUrl>> getPageList(String url);

  Future<List<MVideo>> getVideoList(String url);

  Future<List<Filter>> getFilterList();

  Future<List<SourcePreference>> getSourcePreferences();

  Future<void> setPreference(String key, dynamic value);

  // -- Shared helpers ------------------------------------------------------

  /// Wraps an async extension call with uniform error translation.
  Future<T> guard<T>(String operation, Future<T> Function() body) async {
    try {
      return await body();
    } on ExtensionException {
      rethrow;
    } catch (e) {
      throw ExtensionException('$operation failed', cause: e);
    }
  }
}
