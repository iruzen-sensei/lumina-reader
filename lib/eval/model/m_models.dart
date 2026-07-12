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

import 'package:json_annotation/json_annotation.dart';

part 'm_models.g.dart';

// ---------------------------------------------------------------------------
// Type aliases
// ---------------------------------------------------------------------------

/// Image reference returned by extensions. May be a URL or a data URI.
typedef MImage = String;

/// HTTP headers map.
typedef MHeaders = Map<String, String>;

// ---------------------------------------------------------------------------
// MManga
// ---------------------------------------------------------------------------

/// Data Transfer Object for a manga/anime returned by an extension.
@JsonSerializable(explicitToJson: true)
class MManga {
  /// Title of the manga/anime.
  String? name;

  /// Relative or absolute URL to the detail page.
  String? link;

  /// Cover image URL.
  String? imageUrl;

  /// Long description / synopsis.
  String? description;

  /// Author(s).
  String? author;

  /// Artist(s).
  String? artist;

  /// Publication status. One of:
  ///   - `0` = unknown
  ///   - `1` = ongoing
  ///   - `2` = completed
  ///   - `3` = licensed
  ///   - `4` = publishing finished
  ///   - `5` = cancelled
  ///   - `6` = on hiatus
  String? status;

  /// Comma-separated genre list (legacy compatibility).
  String? genre;

  /// Structured category list.
  List<String>? categories;

  /// Whether this entry is a Japanese manga.
  bool? isManga;

  /// Whether this entry is a Chinese manhua.
  bool? isManhua;

  /// Whether this entry is a Korean manhwa.
  bool? isManhwa;

  /// Whether this entry is an anime.
  bool? isAnime;

  /// Whether this entry is NSFW.
  bool? isNsfw;

  /// Source identifier that produced this entry.
  String? source;

  MManga({
    this.name,
    this.link,
    this.imageUrl,
    this.description,
    this.author,
    this.artist,
    this.status,
    this.genre,
    this.categories,
    this.isManga,
    this.isManhua,
    this.isManhwa,
    this.isAnime,
    this.isNsfw,
    this.source,
  });

  factory MManga.fromJson(Map<String, dynamic> json) =>
      _$MMangaFromJson(json);

  Map<String, dynamic> toJson() => _$MMangaToJson(this);

  @override
  String toString() =>
      'MManga(name: $name, link: $link, imageUrl: $imageUrl, status: $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MManga && (name == other.name && link == other.link);

  @override
  int get hashCode => Object.hash(name, link);
}

// ---------------------------------------------------------------------------
// MChapter
// ---------------------------------------------------------------------------

/// Data Transfer Object for a chapter/episode returned by an extension.
@JsonSerializable(explicitToJson: true)
class MChapter {
  /// Chapter/episode title.
  String? name;

  /// Relative or absolute URL of the chapter/episode page.
  String? url;

  /// Upload date as a UNIX timestamp in milliseconds (as string for JS interop).
  String? dateUpload;

  /// Scanlator / release group name.
  String? scanlator;

  /// Identifier of the parent manga/anime.
  String? mangaId;

  /// Chapter number as string for JS interop.
  String? chapterNumber;

  /// Volume number as string for JS interop.
  String? volumeNumber;

  /// Language code (BCP 47 short tag, e.g. `en`, `ja`, `fr`).
  String? language;

  MChapter({
    this.name,
    this.url,
    this.dateUpload,
    this.scanlator,
    this.mangaId,
    this.chapterNumber,
    this.volumeNumber,
    this.language,
  });

  factory MChapter.fromJson(Map<String, dynamic> json) =>
      _$MChapterFromJson(json);

  Map<String, dynamic> toJson() => _$MChapterToJson(this);

  @override
  String toString() =>
      'MChapter(name: $name, url: $url, chapterNumber: $chapterNumber)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MChapter && (name == other.name && url == other.url);

  @override
  int get hashCode => Object.hash(name, url);
}

// ---------------------------------------------------------------------------
// MPages
// ---------------------------------------------------------------------------

/// Data Transfer Object for the list of pages/frames returned by an extension.
@JsonSerializable(explicitToJson: true)
class MPages {
  /// List of image URLs for manga pages or video thumbnails.
  final List<String> images;

  /// Optional per-image HTTP headers (must be the same length as [images]
  /// when present).
  final List<Map<String, String>>? headers;

  /// Optional per-image referer URLs.
  final List<String>? referer;

  /// Optional source identifier that produced this page list.
  final String? source;

  MPages({
    this.images = const [],
    this.headers,
    this.referer,
    this.source,
  });

  factory MPages.fromJson(Map<String, dynamic> json) =>
      _$MPagesFromJson(json);

  Map<String, dynamic> toJson() => _$MPagesToJson(this);

  /// Number of pages in this chapter.
  int get length => images.length;

  /// Whether this page list is empty.
  bool get isEmpty => images.isEmpty;

  /// Whether this page list is not empty.
  bool get isNotEmpty => images.isNotEmpty;

  @override
  String toString() => 'MPages(images: ${images.length} item(s), source: $source)';
}

// ---------------------------------------------------------------------------
// MSource
// ---------------------------------------------------------------------------

/// Data Transfer Object for source metadata produced by an extension.
@JsonSerializable(explicitToJson: true)
class MSource {
  /// Stable unique identifier of the source (typically the package name).
  String? id;

  /// Display name.
  String? name;

  /// ISO language code.
  String? lang;

  /// Base URL for browsing requests.
  String? baseUrl;

  /// Optional API URL (used by sources with a separate JSON API).
  String? apiUrl;

  /// Extension version (semver).
  String? version;

  /// Icon URL.
  String? iconUrl;

  /// Strategy used by the source. One of:
  ///   - `single`     - single-language source
  ///   - `multi`      - multi-language source
  ///   - `lite`       - lightweight source
  String? typeSource;

  /// Content flags.
  bool? isManga;
  bool? isManhua;
  bool? isManhwa;
  bool? isAnime;
  bool? isNsfw;

  /// Whether the source is protected by Cloudflare.
  bool? hasCloudflare;

  /// Default HTTP headers used for every request.
  Map<String, String>? headers;

  /// Optional tags describing the source.
  List<String>? tags;

  /// Whether the source provides full detail data without extra requests.
  bool? isFullData;

  MSource({
    this.id,
    this.name,
    this.lang,
    this.baseUrl,
    this.apiUrl,
    this.version,
    this.iconUrl,
    this.typeSource,
    this.isManga,
    this.isManhua,
    this.isManhwa,
    this.isAnime,
    this.isNsfw,
    this.hasCloudflare,
    this.headers,
    this.tags,
    this.isFullData,
  });

  factory MSource.fromJson(Map<String, dynamic> json) =>
      _$MSourceFromJson(json);

  Map<String, dynamic> toJson() => _$MSourceToJson(this);

  @override
  String toString() => 'MSource(id: $id, name: $name, lang: $lang, baseUrl: $baseUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MSource && (id == other.id && name == other.name);

  @override
  int get hashCode => Object.hash(id, name);
}

// ---------------------------------------------------------------------------
// MVideo
// ---------------------------------------------------------------------------

/// Data Transfer Object for a video stream returned by an extension.
@JsonSerializable(explicitToJson: true)
class MVideo {
  /// Stream URL.
  final String url;

  /// Original URL before any resolution/transformation.
  final String? originalUrl;

  /// Human-readable quality label (e.g. `720p`, `1080p`, `HD`).
  final String? quality;

  /// Optional title for the stream.
  final String? title;

  /// HTTP headers required to access the stream.
  final Map<String, String>? headers;

  /// Optional provider-specific parameters (e.g. HLS subtitle tracks).
  final Map<String, dynamic>? parameters;

  MVideo({
    required this.url,
    this.originalUrl,
    this.quality,
    this.title,
    this.headers,
    this.parameters,
  });

  factory MVideo.fromJson(Map<String, dynamic> json) =>
      _$MVideoFromJson(json);

  Map<String, dynamic> toJson() => _$MVideoToJson(this);

  /// Creates a copy of this video with the given fields replaced.
  MVideo copyWith({
    String? url,
    String? originalUrl,
    String? quality,
    String? title,
    Map<String, String>? headers,
    Map<String, dynamic>? parameters,
  }) =>
      MVideo(
        url: url ?? this.url,
        originalUrl: originalUrl ?? this.originalUrl,
        quality: quality ?? this.quality,
        title: title ?? this.title,
        headers: headers ?? this.headers,
        parameters: parameters ?? this.parameters,
      );

  @override
  String toString() =>
      'MVideo(url: $url, quality: $quality, title: $title)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MVideo && url == other.url && quality == other.quality;

  @override
  int get hashCode => Object.hash(url, quality);
}

// ---------------------------------------------------------------------------
// MProvider
// ---------------------------------------------------------------------------

/// Abstract interface implemented by every content extension.
///
/// Concrete implementations live in `JsExtensionService` (JavaScript sources)
/// and `DartExtensionService` (Dart sources). Extensions are responsible for
/// translating the source's logic into the contracts declared here.
abstract class MProvider {
  /// Display name of the source.
  String get name;

  /// Base URL used for browsing requests.
  String get baseUrl;

  /// ISO language code of the source.
  String get lang;

  /// API URL when the source exposes a JSON API.
  String get apiUrl;

  /// Icon URL.
  String get iconUrl;

  /// Strategy used by the source (e.g. `single`, `multi`).
  String get typeSource;

  /// Extension version.
  int get version;

  /// Default HTTP headers used for every request.
  Map<String, String> get headers;

  /// Content type flags.
  bool get isManga;
  bool get isManhua;
  bool get isManhwa;
  bool get isAnime;
  bool get isNsfw;

  /// Whether the source is protected by Cloudflare.
  bool get hasCloudflare;

  /// Whether the source provides full detail data.
  bool get isFullData;

  /// Returns the popular entries for the given 1-indexed page.
  Future<MPages> getPopular(int page);

  /// Returns the latest updates for the given 1-indexed page.
  Future<MPages> getLatestUpdates(int page);

  /// Searches the source and returns the matching entries for the page.
  Future<MPages> search(String query, int page, FilterList filterList);

  /// Returns the full detail for the entry at [url].
  Future<MManga> getDetail(String url);

  /// Returns the list of pages for the given chapter.
  Future<MPages> getPageList(MChapter chapter);

  /// Returns the list of videos for the given episode URL.
  Future<List<MVideo>> getVideoList(String url);

  /// Returns the list of filters supported by the source.
  Future<List<Filter>> getFilterList();

  /// Returns the list of preferences exposed by the source.
  Future<List<SourcePreference>> getSourcePreferences();
}

// ---------------------------------------------------------------------------
// FilterList
// ---------------------------------------------------------------------------

/// Wrapper around a list of [Filter]s.
///
/// Serialisation is handled manually (rather than via `@JsonSerializable`)
/// because the [Filter] hierarchy is polymorphic and each subclass needs
/// type-aware decoding. The JS bridge consumes the resulting JSON array
/// directly.
class FilterList {
  final List<Filter> filters;

  const FilterList({this.filters = const []});

  /// Deserialises a [FilterList] from a JSON map. The expected shape is:
  ///
  /// ```json
  /// { "filters": [ { "type": "TextFilter", "name": "...", "value": "..." }, ... ] }
  /// ```
  factory FilterList.fromJson(Map<String, dynamic> json) {
    final rawList = json['filters'] as List<dynamic>? ?? const [];
    return FilterList(
      filters: rawList
          .map((e) => Filter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Serialises this [FilterList] to a JSON map.
  Map<String, dynamic> toJson() => {
        'filters': filters.map((f) => f.toJson()).toList(),
      };

  /// Returns a mutable list of filter states keyed by filter name. Used when
  /// forwarding user-selected filter values to an extension.
  Map<String, dynamic> toStateMap() {
    final out = <String, dynamic>{};
    for (final f in filters) {
      out[f.name] = f.state;
    }
    return out;
  }

  /// Returns the filter with the given [name], or `null` when not present.
  Filter? operator [](String name) {
    for (final f in filters) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Returns the number of filters in this list.
  int get length => filters.length;

  /// Returns `true` when this filter list is empty.
  bool get isEmpty => filters.isEmpty;

  /// Returns `true` when this filter list is not empty.
  bool get isNotEmpty => filters.isNotEmpty;

  @override
  String toString() => 'FilterList(${filters.length} filter(s))';
}

// ---------------------------------------------------------------------------
// Filter hierarchy
// ---------------------------------------------------------------------------

/// Base class for all filters.
///
/// Filter subclasses are intentionally **not** JSON-serialisable via
/// `json_serializable` because the JS bridge inspects them through a custom
/// adapter that flattens the polymorphic structure to a plain JS object.
class Filter {
  /// Display name of the filter.
  final String name;

  /// Current state of the filter (type varies per subclass).
  dynamic get state => null;

  const Filter({required this.name});

  Map<String, dynamic> toJson() => {
        'type': runtimeType.toString(),
        'name': name,
      };

  /// Deserialises a [Filter] from a JSON map, dispatching on the `type`
  /// field to the correct subclass.
  factory Filter.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    switch (type) {
      case 'HeaderFilter':
        return HeaderFilter(name: name);
      case 'SeparatorFilter':
        return SeparatorFilter(name: name);
      case 'TextFilter':
        return TextFilter(
          name: name,
          defaultValue: json['defaultValue'] as String?,
        )..value = (json['value'] as String?) ?? (json['defaultValue'] as String?) ?? '';
      case 'CheckBoxFilter':
        return CheckBoxFilter(
          name: name,
          defaultValue: json['defaultValue'] as bool? ?? false,
        )..value = json['value'] as bool? ?? json['defaultValue'] as bool? ?? false;
      case 'CheckBoxGroupFilter':
        final valuesRaw = json['values'] as List<dynamic>? ?? const [];
        return CheckBoxGroupFilter(
          name: name,
          values: valuesRaw
              .map((e) => CheckBoxGroup(
                    name: (e as Map<String, dynamic>)['name'] as String? ?? '',
                    value: e['value'] as String? ?? '',
                    state: e['state'] as bool? ?? false,
                  ))
              .toList(),
        );
      case 'SortFilter':
        final valuesRaw = json['values'] as List<dynamic>? ?? const [];
        return SortFilter(
          name: name,
          values: valuesRaw
              .map((e) => SortSelect(
                    name: (e as Map<String, dynamic>)['name'] as String? ?? '',
                    value: e['value'] as String? ?? '',
                  ))
              .toList(),
          defaultIndex: json['defaultIndex'] as int?,
        )
          ..selection = json['selection'] as int?
          ..ascending = json['ascending'] as bool? ?? false;
      case 'SelectFilter':
        final valuesRaw = json['values'] as List<dynamic>? ?? const [];
        return SelectFilter(
          name: name,
          values: valuesRaw
              .map((e) => SelectOption(
                    name: (e as Map<String, dynamic>)['name'] as String? ?? '',
                    value: e['value'] as String? ?? '',
                  ))
              .toList(),
          defaultIndex: json['defaultIndex'] as int?,
        )..selection = json['selection'] as int?;
      default:
        // Unknown filter type — degrade gracefully to a header so the UI
        // does not crash when an extension ships a new filter type.
        return HeaderFilter(name: name.isEmpty ? type : name);
    }
  }

  @override
  String toString() => '$runtimeType($name)';
}

/// A non-interactive header that separates filter groups in the UI.
class HeaderFilter extends Filter {
  const HeaderFilter({required super.name});

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'HeaderFilter', 'name': name};
}

/// A visual separator.
class SeparatorFilter extends Filter {
  const SeparatorFilter({required super.name});

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'SeparatorFilter', 'name': name};
}

/// Free-form text filter.
class TextFilter extends Filter {
  final String? defaultValue;

  String value;

  TextFilter({required super.name, this.defaultValue})
      : value = defaultValue ?? '';

  @override
  dynamic get state => value;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'TextFilter',
        'name': name,
        'defaultValue': defaultValue,
        'value': value,
      };
}

/// Single checkbox filter.
class CheckBoxFilter extends Filter {
  final bool defaultValue;

  bool value;

  CheckBoxFilter({required super.name, this.defaultValue = false})
      : value = defaultValue;

  @override
  dynamic get state => value;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'CheckBoxFilter',
        'name': name,
        'defaultValue': defaultValue,
        'value': value,
      };
}

/// A single option within a [CheckBoxGroupFilter].
class CheckBoxGroup {
  final String name;
  final String value;
  final bool state;

  const CheckBoxGroup({
    required this.name,
    required this.value,
    this.state = false,
  });

  CheckBoxGroup copyWith({bool? state}) => CheckBoxGroup(
        name: name,
        value: value,
        state: state ?? this.state,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'state': state,
      };

  @override
  String toString() => 'CheckBoxGroup($name=$value, state=$state)';
}

/// Multi-checkbox filter composed of [CheckBoxGroup] options.
class CheckBoxGroupFilter extends Filter {
  final List<CheckBoxGroup> values;

  CheckBoxGroupFilter({required super.name, required this.values});

  @override
  dynamic get state => values.where((e) => e.state).map((e) => e.value).toList();

  @override
  Map<String, dynamic> toJson() => {
        'type': 'CheckBoxGroupFilter',
        'name': name,
        'values': values.map((e) => e.toJson()).toList(),
      };
}

/// A single sortable option within a [SortFilter].
class SortSelect {
  final String name;
  final String value;

  const SortSelect({required this.name, required this.value});

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  @override
  String toString() => 'SortSelect($name=$value)';
}

/// Sort filter with a selectable criterion and ascending/descending toggle.
class SortFilter extends Filter {
  final List<SortSelect> values;
  final int? defaultIndex;

  /// Index of the currently selected [SortSelect] in [values], or `null`
  /// if nothing is selected.
  int? selection;

  /// Whether the sort should be ascending.
  bool ascending;

  SortFilter({
    required super.name,
    required this.values,
    this.defaultIndex,
  })  : selection = defaultIndex,
        ascending = false;

  @override
  dynamic get state => {
        'index': selection,
        'ascending': ascending,
      };

  @override
  Map<String, dynamic> toJson() => {
        'type': 'SortFilter',
        'name': name,
        'values': values.map((e) => e.toJson()).toList(),
        'defaultIndex': defaultIndex,
        'selection': selection,
        'ascending': ascending,
      };
}

/// A single selectable option within a [SelectFilter].
class SelectOption {
  final String name;
  final String value;

  const SelectOption({required this.name, required this.value});

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  @override
  String toString() => 'SelectOption($name=$value)';
}

/// Drop-down select filter.
class SelectFilter extends Filter {
  final List<SelectOption> values;
  final int? defaultIndex;

  /// Index of the currently selected [SelectOption] in [values].
  int? selection;

  SelectFilter({
    required super.name,
    required this.values,
    this.defaultIndex,
  }) : selection = defaultIndex;

  @override
  dynamic get state => selection;

  String? get selectedValue =>
      (selection != null && selection! >= 0 && selection! < values.length)
          ? values[selection!].value
          : null;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'SelectFilter',
        'name': name,
        'values': values.map((e) => e.toJson()).toList(),
        'defaultIndex': defaultIndex,
        'selection': selection,
      };
}

// ---------------------------------------------------------------------------
// SourcePreference hierarchy
// ---------------------------------------------------------------------------

/// Base class for preferences exposed by a source through its settings page.
class SourcePreference {
  /// Storage key used by the source to read the preference value.
  final String key;

  /// Human-readable title shown in the UI.
  final String title;

  /// Optional helper text shown below the title.
  final String? summary;

  /// Optional default value rendered before the user interacts with the
  /// preference. Concrete subclasses override its type.
  dynamic get defaultValue => null;

  const SourcePreference({
    required this.key,
    required this.title,
    this.summary,
  });

  Map<String, dynamic> toJson() => {
        'type': runtimeType.toString(),
        'key': key,
        'title': title,
        'summary': summary,
      };

  /// Deserialises a [SourcePreference] from a JSON map, dispatching on the
  /// `type` field to the correct subclass.
  factory SourcePreference.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final key = json['key'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    final summary = json['summary'] as String?;
    switch (type) {
      case 'SwitchPreferenceCompat':
        return SwitchPreferenceCompat(
          key: key,
          title: title,
          summary: summary,
          defaultValue: json['defaultValue'] as bool?,
        );
      case 'EditTextPreference':
        return EditTextPreference(
          key: key,
          title: title,
          summary: summary,
          defaultValue: json['defaultValue'] as String?,
        );
      case 'ListPreference':
        return ListPreference(
          key: key,
          title: title,
          summary: summary,
          entries: (json['entries'] as List<dynamic>?)?.cast<String>() ?? const [],
          entryValues:
              (json['entryValues'] as List<dynamic>?)?.cast<String>() ?? const [],
          defaultValue: json['defaultValue'] as String?,
        );
      case 'MultiSelectListPreference':
        return MultiSelectListPreference(
          key: key,
          title: title,
          summary: summary,
          entries: (json['entries'] as List<dynamic>?)?.cast<String>() ?? const [],
          entryValues:
              (json['entryValues'] as List<dynamic>?)?.cast<String>() ?? const [],
          defaultValues:
              (json['defaultValues'] as List<dynamic>?)?.cast<String>(),
        );
      default:
        // Unknown preference type — degrade gracefully to a text preference.
        return EditTextPreference(
          key: key,
          title: title,
          summary: summary,
        );
    }
  }

  @override
  String toString() => '$runtimeType($key)';
}

/// Boolean toggle preference.
class SwitchPreferenceCompat extends SourcePreference {
  @override
  final bool? defaultValue;

  const SwitchPreferenceCompat({
    required super.key,
    required super.title,
    super.summary,
    this.defaultValue,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'SwitchPreferenceCompat',
        'key': key,
        'title': title,
        'summary': summary,
        'defaultValue': defaultValue,
      };
}

/// Free-form text preference.
class EditTextPreference extends SourcePreference {
  @override
  final String? defaultValue;

  const EditTextPreference({
    required super.key,
    required super.title,
    super.summary,
    this.defaultValue,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'EditTextPreference',
        'key': key,
        'title': title,
        'summary': summary,
        'defaultValue': defaultValue,
      };
}

/// Single-choice list preference.
class ListPreference extends SourcePreference {
  final List<String> entries;
  final List<String> entryValues;
  @override
  final String? defaultValue;

  const ListPreference({
    required super.key,
    required super.title,
    super.summary,
    required this.entries,
    required this.entryValues,
    this.defaultValue,
  }) : assert(entries.length == entryValues.length,
            'entries and entryValues must have the same length');

  @override
  Map<String, dynamic> toJson() => {
        'type': 'ListPreference',
        'key': key,
        'title': title,
        'summary': summary,
        'entries': entries,
        'entryValues': entryValues,
        'defaultValue': defaultValue,
      };
}

/// Multi-choice list preference.
class MultiSelectListPreference extends SourcePreference {
  final List<String> entries;
  final List<String> entryValues;
  final List<String>? defaultValues;

  const MultiSelectListPreference({
    required super.key,
    required super.title,
    super.summary,
    required this.entries,
    required this.entryValues,
    this.defaultValues,
  }) : assert(entries.length == entryValues.length,
            'entries and entryValues must have the same length');

  @override
  Map<String, dynamic> toJson() => {
        'type': 'MultiSelectListPreference',
        'key': key,
        'title': title,
        'summary': summary,
        'entries': entries,
        'entryValues': entryValues,
        'defaultValues': defaultValues,
      };
}

// ---------------------------------------------------------------------------
// Document / Element — abstract HTML parsing surface
// ---------------------------------------------------------------------------

/// Abstract HTML/XML document surface used by extensions.
///
/// Concrete implementations are provided by the JS bridge (via `cheerio` /
/// `DOMParser`) and by the Dart fallback parser. Extensions code against this
/// interface so they can be ported between JavaScript and Dart hosts without
/// modification.
abstract class Document {
  /// Parses the supplied HTML string and returns a new [Document].
  Document parse(String html);

  /// Returns the first element matching [selector], or `null`.
  Element? selectFirst(String selector);

  /// Returns all elements matching [selector].
  List<Element> select(String selector);

  /// Returns the text content of the first element matching [selector], or
  /// `null`.
  String? selectText(String selector);

  /// Returns the value of attribute [attr] on the first element matching
  /// [selector], or `null`.
  String? selectAttr(String selector, String attr);

  /// Returns the raw text content of the entire document.
  String? text();

  /// Returns the inner HTML of the document.
  String? html();

  /// Returns the outer HTML of the document (including the root element).
  String? outerHtml();

  /// Returns the document title, if any.
  String? title();

  /// Returns the `<base href>` value of the document, if any.
  String? baseUrl();
}

/// Abstract element surface used by extensions.
abstract class Element {
  /// Tag name of the element (e.g. `div`, `a`).
  String? tagName();

  /// The `id` attribute of the element.
  String? id();

  /// The `class` attribute of the element as a single string.
  String? className();

  /// The list of CSS classes applied to the element.
  List<String> classList();

  /// Returns the value of the attribute [name], or `null`.
  String? attr(String name);

  /// Returns the values of [name] for every element matching [selector] that
  /// is a descendant of this element.
  List<String> attrs(String selector, String name);

  /// Returns the inner text of this element.
  String? text();

  /// Returns the inner HTML of this element.
  String? html();

  /// Returns the outer HTML of this element.
  String? outerHtml();

  /// Returns the first descendant element matching [selector], or `null`.
  Element? selectFirst(String selector);

  /// Returns all descendant elements matching [selector].
  List<Element> select(String selector);

  /// Returns the parent element, or `null` if this is the root.
  Element? parent();

  /// Returns the next sibling element, or `null`.
  Element? nextSibling();

  /// Returns the previous sibling element, or `null`.
  Element? previousSibling();

  /// Removes this element from its parent.
  void remove();

  /// Returns the child elements of this element.
  List<Element> children();
}
