/*
 * Lumina Reader - A Mangayomi fork
 * Copyright (C) 2024 Lumina Reader Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Original Mangayomi source: Copyright (c) 2023-2024 kodjode33
 * SPDX-License-Identifier: Apache-2.0
 */

import 'dart:async';

import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/models/source.dart';

/// Result type returned by [ExtensionService.getFilterList].
typedef FilterResult = ({List<Filter> filters, List<dynamic> filterList});

/// Result type returned by [ExtensionService.getGalleryPage].
typedef GalleryResult = ({List<MManga> entries, bool hasNextPage});

/// Service that drives a single content extension.
///
/// Implementations of this interface translate the contracts declared by an
/// [MProvider] into Dart calls. There are two production implementations:
///
///   * `JsExtensionService`  — runs a JavaScript/TypeScript extension inside
///     a lightweight JS host.
///   * `DartExtensionService` — runs a Dart extension directly in-process.
///
/// The host (this Flutter app) never instantiates these classes directly;
/// it always goes through [getExtensionService].
abstract class ExtensionService {
  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialises the extension. Called once before any other method.
  ///
  /// Implementations must be idempotent — subsequent calls must be no-ops.
  Future<void> init();

  /// Releases all resources held by the extension (JS isolate, HTTP client,
  /// caches, ...).
  Future<void> dispose();

  /// Returns the [Source] descriptor this service was created from.
  Source get source;

  // ---------------------------------------------------------------------------
  // Source metadata
  // ---------------------------------------------------------------------------

  /// Returns the resolved [MSource] metadata for this extension.
  ///
  /// On first invocation, the metadata is fetched from the extension. The
  /// result is cached for the lifetime of the service.
  Future<MSource> getSource();

  /// Returns the list of HTTP headers to attach to every outgoing request.
  ///
  /// Defaults to the [MSource.headers] returned by [getSource], but
  /// implementations may add token rotation or CF challenge cookies.
  Future<Map<String, String>> getHeaders();

  // ---------------------------------------------------------------------------
  // Catalog browsing
  // ---------------------------------------------------------------------------

  /// Returns the popular entries for the given 1-indexed [page].
  Future<List<MManga>> getPopular(int page);

  /// Returns the latest updates for the given 1-indexed [page].
  Future<List<MManga>> getLatestUpdates(int page);

  /// Searches the source and returns the matching entries for the page.
  ///
  /// [filterList] carries the user-selected filter values. Implementations
  /// must accept an empty [FilterList] and treat it as "no filters".
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  });

  // ---------------------------------------------------------------------------
  // Detail & chapter data
  // ---------------------------------------------------------------------------

  /// Returns the full detail for the entry located at [url].
  ///
  /// The returned [MManga] must include a populated chapter/episode list
  /// when the source supports it. When the source cannot provide chapters
  /// in the same request, the implementation must perform the follow-up
  /// requests internally.
  Future<MManga> getMangaDetail(String url);

  /// Returns the chapter/episode list for the entry located at [url].
  ///
  /// Implementations should reuse the data already retrieved by
  /// [getMangaDetail] when possible to avoid duplicate network requests.
  Future<List<MChapter>> getChapterList(String url);

  /// Returns the list of image URLs for the chapter/episode at [url].
  Future<List<String>> getPageList(String url);

  // ---------------------------------------------------------------------------
  // Anime / video playback
  // ---------------------------------------------------------------------------

  /// Returns the list of available video streams for the episode at [url].
  ///
  /// For manga-only sources, implementations may return an empty list.
  Future<List<MVideo>> getVideoList(String url);

  // ---------------------------------------------------------------------------
  // Filtering & preferences
  // ---------------------------------------------------------------------------

  /// Returns the list of filters supported by the source.
  Future<List<Filter>> getFilterList();

  /// Returns the list of preferences exposed by the source.
  Future<List<SourcePreference>> getSourcePreferences();

  /// Validates and returns the current value of a source preference.
  Future<dynamic> getSourcePreferenceValue(String key);

  // ---------------------------------------------------------------------------
  // Networking helpers
  // ---------------------------------------------------------------------------

  /// Clears any cached HTTP responses, cookies and challenge tokens.
  void clearClient();

  /// Forces the extension to refresh any tokens or challenge solutions.
  Future<void> refreshClient();

  /// Performs a SauCE-Nao reverse image lookup for [imageUrl] and returns
  /// the best matching source URL, or `null` when no match is found.
  Future<String?> useSauceNao(String imageUrl);

  // ---------------------------------------------------------------------------
  // Cloudflare / challenge support
  // ---------------------------------------------------------------------------

  /// Whether the source is currently waiting for a Cloudflare challenge to
  /// be solved.
  bool get needsCloudflareBypass;

  /// Solves an outstanding Cloudflare challenge. Returns `true` on success.
  Future<bool> solveCloudflare(String url);

  // ---------------------------------------------------------------------------
  // Status reporting
  // ---------------------------------------------------------------------------

  /// Stream that emits progress events while long-running operations
  /// (chapter list fetches, video resolution) are in flight.
  Stream<ExtensionProgress> get progressStream;

  /// Last error thrown by the extension, if any. Cleared on the next
  /// successful operation.
  Object? get lastError;
}

/// Progress payload emitted by [ExtensionService.progressStream].
class ExtensionProgress {
  /// Optional operation identifier (e.g. `getMangaDetail`).
  final String? operation;

  /// Optional message describing the current step.
  final String? message;

  /// Optional progress percentage in the range `0..1` (inclusive). `null`
  /// means "indeterminate".
  final double? progress;

  /// Whether the operation has completed.
  final bool completed;

  const ExtensionProgress({
    this.operation,
    this.message,
    this.progress,
    this.completed = false,
  });

  @override
  String toString() =>
      'ExtensionProgress(operation: $operation, message: $message, '
      'progress: $progress, completed: $completed)';
}
