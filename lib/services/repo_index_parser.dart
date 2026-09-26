// Copyright 2024 Lumina Reader Contributors
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

// UNIFIED REPOSITORY INDEX PARSER
//
// Speaks EVERY extension-repo index format in the Tachiyomi / Aniyomi /
// Mihon / Mangayomi ecosystem and normalizes them into [ParsedRepoIndex]:
//
//   * Mangayomi JSON array (index.json — kodjodevf/mangayomi-extensions):
//       {name, id, baseUrl, lang, typeSource, iconUrl, sourceCodeUrl,
//        sourceCodeLanguage, itemType, version, isNsfw, ...}
//   * Tachiyomi/Aniyomi legacy JSON array (index.min.json):
//       {name, pkg, apk, path, code, version, lang, nsfw,
//        sources: [{name, id, lang, baseUrl}]}
//   * v2 JSON store ({"name": ..., "extensions": [...]} — the protobuf-JSON
//     equivalent of index.pb; camelCase keys, int64 ids as strings)
//   * repo.json redirect ({index_v2: <url>, meta: {...}})
//   * index.pb — a proto3 `Index` message, almost always gzip-compressed
//     (files begin 1f 8b). TWO schema variants share the wire format:
//       manga (mihonapp/extensions-lib):  Extension.sources = 8,
//                                         Source.message = 7
//       anime (aniyomiorg/extensions-lib): Extension.isTorrent = 8,
//                                         Extension.sources = 9,
//                                         Source.message = 6
//     The variant is detected PER EXTENSION from the wire type of field 8
//     (varint → anime, length-delimited → manga), which also copes with
//     mixed-variant repositories.
//
// Wire parsing is hand-rolled (no protobuf dependency): varint /
// length-delimited / 32-bit / 64-bit chunks, skipping unknown fields, so
// future schema additions (e.g. the observed Resources.jarUrl = 501) are
// ignored gracefully as proto3 demands.

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// Which on-disk format a parsed index came from.
enum RepoFormat {
  mangayomiJson,
  tachiyomiLegacyJson,
  v2Json,
  protobuf,
}

/// One source inside an APK extension.
class ParsedRepoSource {
  const ParsedRepoSource({
    required this.id,
    required this.name,
    required this.lang,
    this.baseUrl = '',
  });

  /// Numeric Aniyomi/Mihon source id (64-bit).
  final int id;
  final String name;
  final String lang;
  final String baseUrl;
}

/// One extension, normalized across all formats.
class ParsedRepoExtension {
  const ParsedRepoExtension({
    required this.name,
    required this.lang,
    required this.isAnime,
    required this.isNovel,
    this.pkg,
    this.apkUrl,
    this.iconUrl,
    this.versionCode,
    this.versionName,
    this.isNsfw = false,
    this.isTorrent = false,
    this.sources = const [],
    this.mangayomiEntry,
  });

  final String name;

  /// Primary language ("all" for multi-language).
  final String lang;

  /// Anime extension (APK from an Aniyomi repo, or Mangayomi itemType 1).
  final bool isAnime;

  /// Novel extension (Mangayomi itemType 2).
  final bool isNovel;

  /// Android package name (APK extensions), e.g.
  /// `eu.kanade.tachiyomi.animeextension.all.jellyfin`.
  final String? pkg;

  /// Absolute URL of the extension APK, when this is an APK extension.
  final String? apkUrl;

  final String? iconUrl;
  final int? versionCode;
  final String? versionName;
  final bool isNsfw;
  final bool isTorrent;

  /// Sources bundled in the APK (single-element for most extensions).
  final List<ParsedRepoSource> sources;

  /// Raw Mangayomi-format entry (template routing needs the original
  /// fields: typeSource, dateFormat, additionalParams, ...).
  final Map<String, dynamic>? mangayomiEntry;

  bool get isApk => apkUrl != null && pkg != null;
}

/// A parsed repository index.
class ParsedRepoIndex {
  const ParsedRepoIndex({
    required this.format,
    required this.extensions,
    this.storeName,
    this.badge,
  });

  final RepoFormat format;
  final String? storeName;
  final String? badge;
  final List<ParsedRepoExtension> extensions;
}

/// Result of parsing a fetched index: either a parsed index or a redirect
/// (repo.json `index_v2`) that must be fetched and parsed in turn.
class RepoIndexResult {
  const RepoIndexResult._(this.index, this.redirectUrl);

  const RepoIndexResult.parsed(ParsedRepoIndex index) : this._(index, null);
  const RepoIndexResult.redirect(String url) : this._(null, url);

  final ParsedRepoIndex? index;
  final String? redirectUrl;

  bool get isRedirect => redirectUrl != null;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

const int _kMaxIndexBytes = 8 * 1024 * 1024;

/// Parses raw (possibly gzip-compressed) index bytes from [indexUrl].
RepoIndexResult parseRepoIndex(Uint8List bytes, String indexUrl) {
  if (bytes.length > _kMaxIndexBytes) {
    throw Exception('Repository index too large '
        '(${bytes.length} bytes) — refusing.');
  }
  final decoded = _maybeGunzip(bytes);
  if (decoded == null) {
    throw Exception('Empty repository index.');
  }

  // Sniff the first byte: `[` → JSON array, `{` → JSON object, anything
  // else → protobuf (the algorithm Aniyomi/Mihon themselves use).
  if (decoded.isNotEmpty && decoded[0] == 0x5B) {
    return RepoIndexResult.parsed(_parseJsonArray(decoded, indexUrl));
  }
  if (decoded.isNotEmpty && decoded[0] == 0x7B) {
    return _parseJsonObject(decoded);
  }
  return _parseProtobufIndex(decoded);
}

/// Gunzips [bytes] when they carry the gzip magic (1f 8b); returns the
/// decompressed bytes (capped) or the input when not compressed.
Uint8List? _maybeGunzip(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  final bool isGzip =
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  if (!isGzip) return bytes;
  try {
    final out = gzip.decode(bytes);
    if (out.length > _kMaxIndexBytes) {
      throw Exception('Decompressed repository index too large '
          '(${out.length} bytes) — refusing.');
    }
    return Uint8List.fromList(out);
  } catch (e) {
    if (e is Exception && e.toString().contains('too large')) rethrow;
    throw Exception('Repository index is a corrupt gzip stream.');
  }
}

// ---------------------------------------------------------------------------
// JSON formats
// ---------------------------------------------------------------------------

RepoIndexResult _parseJsonObject(Uint8List bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
  } catch (_) {
    throw Exception('Repository index is neither valid JSON nor protobuf.');
  }
  if (decoded is! Map) {
    throw Exception('Unexpected repository index format.');
  }

  // repo.json redirect: {"index_v2": "<url>", "meta": {...}}
  final v2 = decoded['index_v2'] ?? decoded['indexUrl'];
  if (v2 is String && v2.startsWith('http')) {
    return RepoIndexResult.redirect(v2);
  }

  // v2 JSON store: {"name": ..., "badge": ..., "extensions": [...]}
  final exts = decoded['extensions'];
  if (exts is List) {
    return RepoIndexResult.parsed(ParsedRepoIndex(
      format: RepoFormat.v2Json,
      storeName: decoded['name'] as String?,
      badge: decoded['badge'] as String?,
      extensions: [
        for (final e in exts)
          if (e is Map<dynamic, dynamic>) _parseV2Extension(e),
      ],
    ));
  }
  throw Exception('Repository JSON object has no extensions list.');
}

ParsedRepoExtension _parseV2Extension(Map<dynamic, dynamic> e) {
  final pkg = e['packageName'] as String? ?? '';
  final isAnime = _pkgIsAnime(pkg);
  final resources = e['resources'];
  final sources = <ParsedRepoSource>[
    for (final s in (e['sources'] as List? ?? <dynamic>[]))
      if (s is Map)
        ParsedRepoSource(
          id: _parseInt64(s['id']) ?? 0,
          name: s['name'] as String? ?? '',
          lang: s['language'] as String? ?? 'all',
          baseUrl: s['homeUrl'] as String? ?? '',
        ),
  ];
  return ParsedRepoExtension(
    name: e['name'] as String? ?? pkg,
    lang: sources.isNotEmpty ? sources.first.lang : 'all',
    isAnime: isAnime,
    isNovel: false,
    pkg: pkg.isEmpty ? null : pkg,
    apkUrl: (resources is Map) ? resources['apkUrl'] as String? : null,
    iconUrl: (resources is Map) ? resources['iconUrl'] as String? : null,
    versionCode: _parseInt64(e['versionCode']),
    versionName: e['versionName'] as String?,
    isNsfw: _contentWarningIsNsfw(e['contentWarning']),
    isTorrent: isAnime && (e['isTorrent'] == true || e['isTorrent'] == 1),
    sources: sources,
  );
}

bool _pkgIsAnime(String pkg) =>
    pkg.contains('animeextension') || pkg.startsWith('aniyomi');

/// contentWarning arrives as an int (0 UNSPECIFIED, 1 SAFE, 2 MIXED,
/// 3 NSFW) in protobuf and as "CONTENT_WARNING_*" in v2 JSON.
bool _contentWarningIsNsfw(dynamic v) {
  if (v is int) return v >= 2;
  if (v is String) return v.contains('NSFW') || v.contains('MIXED');
  return false;
}

int? _parseInt64(dynamic v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v);
  return null;
}

ParsedRepoIndex _parseJsonArray(Uint8List bytes, String indexUrl) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
  } catch (_) {
    throw Exception('Repository index is not valid JSON.');
  }
  if (decoded is! List) {
    throw Exception('Unexpected repository index format.');
  }
  final entries =
      decoded.whereType<Map<dynamic, dynamic>>().toList();
  if (entries.isEmpty) {
    return const ParsedRepoIndex(
        format: RepoFormat.mangayomiJson, extensions: []);
  }

  // Format discrimination: Mangayomi entries carry baseUrl+typeSource at
  // the TOP level; Tachiyomi/Aniyomi legacy entries carry pkg+apk.
  final first = entries.first;
  final bool mangayomi =
      first['baseUrl'] != null || first['sourceCodeUrl'] != null;
  if (mangayomi) {
    return ParsedRepoIndex(
      format: RepoFormat.mangayomiJson,
      extensions: [
        for (final e in entries) _parseMangayomiEntry(e),
      ],
    );
  }
  return ParsedRepoIndex(
    format: RepoFormat.tachiyomiLegacyJson,
    extensions: [
      for (final e in entries) _parseLegacyEntry(e, indexUrl),
    ],
  );
}

ParsedRepoExtension _parseMangayomiEntry(Map<dynamic, dynamic> e) {
  final itemType = e['itemType'];
  // itemType: 0 manga, 1 anime, 2 novel. Legacy kodjodevf indexes only set
  // isManga (all manga); the newer eJ indexes set itemType.
  final bool isAnime = itemType == 1;
  final bool isNovel = itemType == 2;
  return ParsedRepoExtension(
    name: e['name'] as String? ?? '',
    lang: e['lang'] as String? ?? 'en',
    isAnime: isAnime,
    isNovel: isNovel,
    iconUrl: e['iconUrl'] as String?,
    versionName: e['version'] as String?,
    isNsfw: e['isNsfw'] as bool? ?? false,
    sources: const [],
    mangayomiEntry: Map<String, dynamic>.from(e),
  );
}

ParsedRepoExtension _parseLegacyEntry(
    Map<dynamic, dynamic> e, String indexUrl) {
  final pkg = e['pkg'] as String? ?? '';
  final isAnime = _pkgIsAnime(pkg) || pkg.startsWith('aniyomi');
  final sources = <ParsedRepoSource>[
    for (final s in (e['sources'] as List? ?? <dynamic>[]))
      if (s is Map)
        ParsedRepoSource(
          id: _parseInt64(s['id']) ?? 0,
          name: s['name'] as String? ?? '',
          lang: s['lang'] as String? ?? 'all',
          baseUrl: s['baseUrl'] as String? ?? '',
        ),
  ];
  // Legacy indexes only carry the APK FILE NAME — construct the URL from
  // the index base (…/repo/index.min.json → …/repo/apk/<file>).
  final apkFile = e['apk'] as String? ?? '';
  final urls = apkFile.isEmpty || pkg.isEmpty
      ? (apkUrl: '', iconUrl: null)
      : legacyApkUrls(indexUrl: indexUrl, apkFileName: apkFile, pkg: pkg);
  return ParsedRepoExtension(
    name: e['name'] as String? ?? pkg,
    lang: e['lang'] as String? ?? 'all',
    isAnime: isAnime,
    isNovel: false,
    pkg: pkg.isEmpty ? null : pkg,
    apkUrl: urls.apkUrl.isEmpty ? null : urls.apkUrl,
    iconUrl: urls.iconUrl,
    versionCode: _parseInt64(e['code']),
    versionName: e['version'] as String?,
    isNsfw: e['nsfw'] == true || e['nsfw'] == 1,
    isTorrent: false,
    sources: sources,
  );
}

// ---------------------------------------------------------------------------
// Protobuf (index.pb) — hand-rolled wire-format reader
// ---------------------------------------------------------------------------

/// Minimal protobuf wire-format cursor.
class _PbReader {
  _PbReader(this.bytes);

  final Uint8List bytes;
  int pos = 0;

  bool get eof => pos >= bytes.length;

  /// Reads a base-128 varint (up to 64 bits).
  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (pos >= bytes.length) {
        throw const FormatException('truncated varint');
      }
      final b = bytes[pos++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
      if (shift > 63) {
        throw const FormatException('varint too long');
      }
    }
    return result;
  }

  /// Returns (field number, wire type) or null at end of message.
  ({int field, int wireType})? readTag() {
    if (eof) return null;
    final tag = readVarint();
    return (field: tag >> 3, wireType: tag & 0x7);
  }

  Uint8List readBytes() {
    final len = readVarint();
    if (len < 0 || pos + len > bytes.length) {
      throw const FormatException('truncated bytes field');
    }
    final out = Uint8List.sublistView(bytes, pos, pos + len);
    pos += len;
    return out;
  }

  String readString() => utf8.decode(readBytes(), allowMalformed: true);

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
      case 1:
        pos += 8;
      case 2:
        readBytes();
      case 5:
        pos += 4;
      default:
        throw FormatException('unsupported wire type $wireType');
    }
  }

  /// Reads a nested message as a sub-reader.
  _PbReader readMessage() => _PbReader(readBytes());
}

RepoIndexResult _parseProtobufIndex(Uint8List bytes) {
  final r = _PbReader(bytes);
  String? name, badge;
  List<Map<dynamic, dynamic>> rawExtensions = [];
  String? extensionListUrl;

  while (true) {
    final tag = r.readTag();
    if (tag == null) break;
    switch (tag.field) {
      case 1:
        name = r.readString();
      case 2:
        badge = r.readString();
      case 3: // signingKey — trust fingerprint, not needed for parsing.
      case 4: // contact submessage.
        r.skip(tag.wireType);
      case 101:
        rawExtensions = _readExtensionList(r.readMessage());
      case 102:
        extensionListUrl = r.readString();
      default:
        r.skip(tag.wireType);
    }
  }

  if (extensionListUrl != null && rawExtensions.isEmpty) {
    // The index parks its extension list at a separate URL — surface it as
    // a redirect so the caller fetches and parses it in turn (symmetrical
    // with repo.json `index_v2` redirects).
    return RepoIndexResult.redirect(extensionListUrl);
  }
  return RepoIndexResult.parsed(ParsedRepoIndex(
    format: RepoFormat.protobuf,
    storeName: name,
    badge: badge,
    extensions: [
      for (final raw in rawExtensions) _extensionFromRaw(raw),
    ],
  ));
}

List<Map<dynamic, dynamic>> _readExtensionList(_PbReader r) {
  final out = <Map<dynamic, dynamic>>[];
  while (true) {
    final tag = r.readTag();
    if (tag == null) break;
    if (tag.field == 1 && tag.wireType == 2) {
      out.add(_readExtensionRaw(r.readMessage()));
    } else {
      r.skip(tag.wireType);
    }
  }
  return out;
}

/// One protobuf Extension message → raw field map. Handles BOTH schema
/// variants: manga (sources=8) and anime (isTorrent=8, sources=9). The
/// variant is detected from the WIRE TYPE of field 8: varint → anime
/// (isTorrent is a bool), length-delimited → manga (sources submessage).
Map<dynamic, dynamic> _readExtensionRaw(_PbReader r) {
  final out = <dynamic, dynamic>{};
  final sources = <Map<dynamic, dynamic>>[];
  while (true) {
    final tag = r.readTag();
    if (tag == null) break;
    switch (tag.field) {
      case 1:
        out['name'] = r.readString();
      case 2:
        out['pkg'] = r.readString();
      case 3:
        final res = r.readMessage();
        final m = <dynamic, dynamic>{};
        while (true) {
          final t = res.readTag();
          if (t == null) break;
          switch (t.field) {
            case 1:
              m['apkUrl'] = res.readString();
            case 2:
              m['iconUrl'] = res.readString();
            default:
              res.skip(t.wireType);
          }
        }
        out['resources'] = m;
      case 4:
        out['extensionLib'] = r.readString();
      case 5:
        out['versionCode'] = r.readVarint();
      case 6:
        out['versionName'] = r.readString();
      case 7:
        out['contentWarning'] = r.readVarint();
      case 8:
        if (tag.wireType == 0) {
          // ANIME variant: isTorrent bool.
          out['isTorrent'] = r.readVarint() != 0;
          out['variant'] = 'anime';
        } else {
          // MANGA variant: sources start here.
          out['variant'] = 'manga';
          sources.add(_readSourceRaw(r.readMessage()));
        }
      case 9:
        // ANIME variant sources (manga variant never defines field 9).
        sources.add(_readSourceRaw(r.readMessage()));
      default:
        r.skip(tag.wireType);
    }
  }
  out['sources'] = sources;
  return out;
}

Map<dynamic, dynamic> _readSourceRaw(_PbReader r) {
  final out = <dynamic, dynamic>{};
  while (true) {
    final tag = r.readTag();
    if (tag == null) break;
    switch (tag.field) {
      case 1:
        out['id'] = r.readVarint();
      case 2:
        out['name'] = r.readString();
      case 3:
        out['language'] = r.readString();
      case 4:
        out['homeUrl'] = r.readString();
      case 5:
        out.putIfAbsent('mirrorUrls', () => <String>[]);
        (out['mirrorUrls'] as List<String>).add(r.readString());
      case 6:
      case 7: // message — manga uses 7, anime uses 6.
        r.skip(tag.wireType);
      default:
        r.skip(tag.wireType);
    }
  }
  return out;
}

ParsedRepoExtension _extensionFromRaw(Map<dynamic, dynamic> raw0) {
  final pkg = raw0['pkg'] as String? ?? '';
  final resources = raw0['resources'] as Map<dynamic, dynamic>?;
  final sources = <ParsedRepoSource>[
    for (final raw in (raw0['sources'] as List))
      if (raw is Map<dynamic, dynamic>)
        ParsedRepoSource(
          id: raw['id'] as int? ?? 0,
          name: raw['name'] as String? ?? '',
          lang: raw['language'] as String? ?? 'all',
          baseUrl: raw['homeUrl'] as String? ?? '',
        ),
  ];
  return ParsedRepoExtension(
    name: raw0['name'] as String? ?? pkg,
    lang: sources.isNotEmpty ? sources.first.lang : 'all',
    isAnime: raw0['variant'] == 'anime' || _pkgIsAnime(pkg),
    isNovel: false,
    pkg: pkg.isEmpty ? null : pkg,
    apkUrl: resources?['apkUrl'] as String?,
    iconUrl: resources?['iconUrl'] as String?,
    versionCode: raw0['versionCode'] as int?,
    versionName: raw0['versionName'] as String?,
    isNsfw: _contentWarningIsNsfw(raw0['contentWarning']),
    isTorrent: raw0['isTorrent'] == true,
    sources: sources,
  );
}

// ---------------------------------------------------------------------------
// URL helpers
// ---------------------------------------------------------------------------

/// Strips the index file name from [indexUrl] to get the repo base path
/// (`.../repo/index.min.json` → `.../repo`).
String repoBaseFromIndexUrl(String indexUrl) {
  var u = indexUrl;
  // github.com/.../raw/... → keep as-is; only strip the last segment.
  final slash = u.lastIndexOf('/');
  final last = slash >= 0 ? u.substring(slash + 1) : u;
  if (last.contains('.') && !u.endsWith('/')) {
    u = u.substring(0, slash);
  }
  return u;
}

/// Constructs the absolute APK/icon URLs for a legacy-format entry.
({String apkUrl, String? iconUrl}) legacyApkUrls({
  required String indexUrl,
  required String apkFileName,
  required String pkg,
}) {
  final base = repoBaseFromIndexUrl(indexUrl);
  return (
    apkUrl: '$base/apk/$apkFileName',
    iconUrl: pkg.isEmpty ? null : '$base/icon/$pkg.png',
  );
}
