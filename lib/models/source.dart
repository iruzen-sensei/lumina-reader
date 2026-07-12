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

import 'package:isar/isar.dart';

import 'package:lumina_reader/models/category.dart';

part 'source.g.dart';

/// Language of the source code backing an extension.
///
/// Stored in Isar as the enum ordinal (see `@enumeration`).
@enumeration
enum SourceCodeLanguage {
  /// JavaScript / TypeScript source (the most common type).
  javascript,

  /// Pure Dart source (compiled into the app or shipped as AOT).
  dart,

  /// Lua source (planned — currently unsupported).
  lua,
}

/// Strategy used by the source to expose its catalog.
@enumeration
enum SourceType {
  /// Single-language source.
  single,

  /// Multi-language source (catalog exposes several languages).
  multi,

  /// Lightweight source (no full detail page).
  lite,
}

/// Embedded descriptor for the source repository that produced this [Source].
///
/// Stored inline (not in a separate collection) because every [Source] has
/// exactly one [Repo] and the descriptor is immutable for the lifetime of
/// the [Source].
@embedded
class Repo {
  /// Repository display name (e.g. `kodjode33/mangayomi-extensions`).
  String? name;

  /// Base URL of the repository (e.g. `https://github.com/...`).
  String? baseUrl;

  /// Base URL of the repository API (e.g. `https://api.github.com/...`).
  String? apiBaseUrl;

  /// Direct URL to the source manifest file inside the repository.
  String? sourceUrl;

  /// Branch / tag / commit SHA the source was loaded from.
  String? version;

  /// Content type flags mirrored from the source manifest.
  bool? isManga;
  bool? isManhua;
  bool? isManhwa;
  bool? isAnime;
  bool? isNsfw;

  /// Strategy used by the source (mirrored from the manifest).
  String? typeSource;

  /// Icon URL (mirrored from the manifest).
  String? iconUrl;

  /// ISO language code (mirrored from the manifest).
  String? lang;

  /// Raw source code, when the repository ships the source inline.
  String? sourceCode;

  /// Language of the source code (mirrored from the manifest).
  String? sourceCodeLanguage;

  /// Whether the source provides full detail data without extra requests.
  bool? isFullData;

  /// Whether the source is protected by Cloudflare.
  bool? hasCloudflare;

  /// Default HTTP headers used for every request.
  /// Stored as a JSON-encoded map because Isar does not support embedded
  /// `Map<String, String>` directly.
  String? headersJson;

  /// Tags describing the source.
  List<String>? tags;

  /// Number of additional repositories this source depends on (for multi-repo
  /// sources). Defaults to `0`.
  int? additionalRepoCount;

  /// Optional checksum used to verify the integrity of the manifest.
  String? checksum;

  Repo({
    this.name,
    this.baseUrl,
    this.apiBaseUrl,
    this.sourceUrl,
    this.version,
    this.isManga,
    this.isManhua,
    this.isManhwa,
    this.isAnime,
    this.isNsfw,
    this.typeSource,
    this.iconUrl,
    this.lang,
    this.sourceCode,
    this.sourceCodeLanguage,
    this.isFullData,
    this.hasCloudflare,
    this.headersJson,
    this.tags,
    this.additionalRepoCount,
    this.checksum,
  });

  /// Creates an empty [Repo]. Used by Isar when instantiating embedded
  /// objects during deserialisation.
  Repo.empty();
}

/// Isar collection for content sources (extensions).
///
/// A [Source] describes how to talk to a content extension. The actual
/// execution happens through the [ExtensionService] returned by
/// [getExtensionService].
@collection
@Name("Source")
class Source {
  /// Primary key. Auto-incremented by Isar.
  Id id = Isar.autoIncrement;

  /// Stable identifier (typically the package name or repo path).
  String? idString;

  /// Display name of the source.
  String? name;

  /// ISO language code (e.g. `en`, `ja`, `fr`).
  String? lang;

  /// Base URL used for browsing requests.
  String? baseUrl;

  /// Optional API URL when the source exposes a JSON API.
  String? apiUrl;

  /// Icon URL.
  String? iconUrl;

  /// Extension version (semver).
  String? version;

  /// Strategy used by the source (mirrored from [Repo.typeSource] for
  /// backwards compatibility with sources that do not declare a [Repo]).
  String? typeSource;

  /// Content type flags.
  bool? isManga;
  bool? isManhua;
  bool? isManhwa;
  bool? isAnime;
  bool? isNsfw;

  /// Whether the source is protected by Cloudflare.
  bool? hasCloudflare;

  /// Whether the source provides full detail data without extra requests.
  bool? isFullData;

  /// Default HTTP headers, stored as a JSON-encoded string.
  String? headersJson;

  /// Tags describing the source (e.g. `multi`, `nsfw`).
  List<String>? tags;

  /// Inline source code (used by local / custom sources).
  String? sourceCode;

  /// Language of the inline source code. Defaults to `null` for legacy
  /// sources that did not declare a language.
  @enumeration
  SourceCodeLanguage? sourceCodeLanguage;

  /// Filesystem path of the source code for sources loaded from disk.
  String? codePath;

  /// Whether the source was added by the user (vs. discovered via a repo).
  bool? added;

  /// Whether the source is a local source (e.g. CBZ/CBR archives).
  bool? isLocal;

  /// Whether the source was the most recently used source.
  bool? isLastUsed;

  /// Whether the source is currently enabled.
  bool? isEnabled;

  /// Timestamp (milliseconds since epoch) of the last successful update.
  int? lastUpdateAt;

  /// Optional custom name override set by the user.
  String? customName;

  /// Optional custom source code override (user-edited). When present, the
  /// [ExtensionService] must prefer this over [sourceCode].
  String? customSourceCode;

  /// Optional custom headers override (JSON-encoded).
  String? customHeadersJson;

  /// Optional custom base URL override. When present, overrides [baseUrl].
  String? customBaseUrl;

  /// Embedded repository descriptor.
  Repo? repo;

  /// Whether the source is currently the default source for new searches.
  bool? isDefault;

  /// Number of times the source has been used for browsing.
  int? useCount;

  /// Optional error message captured the last time the source failed to
  /// initialise. Cleared on the next successful operation.
  String? lastError;

  /// Whether the source supports filter-based search.
  bool? supportsFilter;

  /// Whether the source supports the latest-updates feed.
  bool? supportsLatest;

  /// Whether the source supports video listing (anime sources).
  bool? supportsVideo;

  /// Aggregate count of manga entries belonging to this source. Maintained
  /// by the data layer so the UI can render counts without a full table
  /// scan.
  int? mangaCount;

  /// Aggregate count of anime entries belonging to this source.
  int? animeCount;

  // -- Links ---------------------------------------------------------------

  /// Categories associated with this source.
  ///
  /// NOTE: When the `Manga` and `Anime` Isar collections are introduced in a
  /// future revision, the following forward references should be added back
  /// so that bidirectional navigation works through IsarLinks:
  ///
  ///   @Backlink(to: 'source')
  ///   final manga = IsarLinks<Manga>();
  ///
  ///   @Backlink(to: 'source')
  ///   final anime = IsarLinks<Anime>();
  ///
  /// Until then, the link counts are exposed via [mangaCount] / [animeCount]
  /// and the relationships are resolved lazily by the data layer using
  /// `mangaId` / `sourceId` integer references.
  @Backlink(to: 'source')
  final categories = IsarLinks<Category>();

  // -- Indexes -------------------------------------------------------------

  /// Index on [idString] for fast lookups by stable identifier.
  @Index(unique: true, replace: true)
  String? get idStringIndex => idString;

  /// Index on [name] for fast search.
  @Index()
  String get nameIndex => name ?? '';

  /// Index on [lang] for fast filtering by language.
  @Index()
  String get langIndex => lang ?? '';

  /// Composite index on (lang, isManga) for the most common browse queries.
  @Index(composite: [CompositeIndex('isManga')])
  String get langMangaIndex => lang ?? '';

  /// Index on [isLastUsed] for fast retrieval of the last used source.
  @Index()
  bool get isLastUsedIndex => isLastUsed ?? false;

  /// Index on [isEnabled] for fast retrieval of enabled sources only.
  @Index()
  bool get isEnabledIndex => isEnabled ?? true;

  /// Index on [isLocal] for fast retrieval of local sources.
  @Index()
  bool get isLocalIndex => isLocal ?? false;

  // -- Constructors --------------------------------------------------------

  Source({
    this.id = Isar.autoIncrement,
    this.idString,
    this.name,
    this.lang,
    this.baseUrl,
    this.apiUrl,
    this.iconUrl,
    this.version,
    this.typeSource,
    this.isManga,
    this.isManhua,
    this.isManhwa,
    this.isAnime,
    this.isNsfw,
    this.hasCloudflare,
    this.isFullData,
    this.headersJson,
    this.tags,
    this.sourceCode,
    this.sourceCodeLanguage,
    this.codePath,
    this.added,
    this.isLocal,
    this.isLastUsed,
    this.isEnabled,
    this.lastUpdateAt,
    this.customName,
    this.customSourceCode,
    this.customHeadersJson,
    this.customBaseUrl,
    this.repo,
    this.isDefault,
    this.useCount,
    this.lastError,
    this.supportsFilter,
    this.supportsLatest,
    this.supportsVideo,
    this.mangaCount,
    this.animeCount,
  });

  /// Returns the effective display name (honouring [customName]).
  String get displayName => customName?.isNotEmpty == true ? customName! : (name ?? '');

  /// Returns the effective base URL (honouring [customBaseUrl]).
  String get displayBaseUrl =>
      customBaseUrl?.isNotEmpty == true ? customBaseUrl! : (baseUrl ?? '');

  /// Returns the effective source code (honouring [customSourceCode]).
  String? get displaySourceCode =>
      customSourceCode?.isNotEmpty == true ? customSourceCode : sourceCode;

  /// Returns `true` when the source is usable for the given content type.
  bool supportsContentType({bool? manga, bool? anime}) {
    if (manga == true && !(isManga == true || isManhua == true || isManhwa == true)) {
      return false;
    }
    if (anime == true && isAnime != true) {
      return false;
    }
    return true;
  }

  @override
  String toString() =>
      'Source(id: $id, name: $name, lang: $lang, baseUrl: $baseUrl, '
      'version: $version)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Source && (id == other.id || idString == other.idString);

  @override
  int get hashCode => id.hashCode ^ idString.hashCode;
}
