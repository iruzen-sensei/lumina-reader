// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// MIHON / ANIYOMI APK EXTENSION SERVICE.
//
// Talks to the on-device extension server (POST /dalvik) to run a REAL
// Aniyomi/Mihomomi APK extension: popular/latest/search feeds, detail,
// chapter/episode lists, page lists and video lists — the whole browsing
// pipeline works with zero interpreter.
//
// The APK bytes (base64) live in [Source.sourceCode] — identical to
// upstream Mangayomi's storage layout, so repos synced/installed here are
// wire-compatible with the wider ecosystem.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/services/extension_server.dart'
    show ExtensionServerRuntime;
import 'package:lumina_reader/services/http/m_client.dart'
    show MClient, getCookiesPref;

class MihonExtensionService extends BaseExtensionService {
  MihonExtensionService(super.source, this._server);

  /// The shared extension-server runtime; the loopback URL is resolved
  /// lazily on the first call (server start takes a moment).
  final ExtensionServerRuntime _server;


  String? _cachedUrl;

  Future<String> get _serverUrl async =>
      _cachedUrl ??= await _server.ensureStarted() ?? (throw Exception(
          'The APK extension server could not start on this device.'));

  http.Client? _client;
  http.Client get _http => _client ??= MClient.httpClient(useLogger: false);

  bool get _isAnime => source.isAnime == true;

  String get _kind => _isAnime ? 'Anime' : 'Manga';

  Map<String, String> get _cookies {
    final base = source.displayBaseUrl;
    return getCookiesPref(
        Uri.parse(base.isEmpty ? 'https://localhost' : base));
  }

  Map<String, String> _baseBody(String method) => {
        'method': method,
        'data': source.sourceCode ?? '',
        'lang': source.lang ?? 'all',
        'sourceId': _sourceId,
      };

  String get _sourceId {
    final idString = source.idString;
    if (idString != null && idString.contains('#')) {
      return idString.split('#').last;
    }
    return source.id.toString();
  }

  Future<dynamic> _post(Map<String, dynamic> body) async {
    final base = await _serverUrl;
    final res = await _http.post(
      Uri.parse('$base/dalvik'),
      headers: _cookies,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception(
          'Extension server returned HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error != null) {
        throw Exception('Extension "${source.displayName}" error: $error');
      }
    }
    return decoded;
  }

  // ------------------------------------------------------------- catalogue

  /// Parses a page response from the /dalvik bridge (see
  /// [parseMihonPage] — the public, testable core).
  List<MManga> _listFromPageJson(dynamic json) =>
      parseMihonPage(json, displayName: source.displayName, isAnime: _isAnime);

  @override
  Future<List<MManga>> getPopular(int page) async => _listFromPageJson(
      await _post({..._baseBody('getPopular$_kind'), 'page': page, 'search': ''}));

  @override
  Future<List<MManga>> getLatestUpdates(int page) async =>
      _listFromPageJson(await _post(
          {..._baseBody('getLatest$_kind'), 'page': page, 'search': ''}));

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async => _listFromPageJson(await _post(
          {..._baseBody('getSearch$_kind'), 'page': page, 'search': query}));

  @override
  Future<MManga> getMangaDetail(String url) async {
    final data = await _post({
      ..._baseBody('getDetails$_kind'),
      if (_isAnime) 'animeData': {'url': url} else 'mangaData': {'url': url},
    });
    if (data is! Map) {
      throw Exception(
          'Extension "${source.displayName}" returned an unreadable '
          'details response.');
    }
    final chapters = await getChapterList(url);
    final link = stripMihonMemo(data['url']?.toString() ?? '');
    return MManga(
      name: data['title']?.toString(),
      link: link.isNotEmpty ? link : url,
      imageUrl: data['thumbnail_url']?.toString() ??
          data['thumbnailUrl']?.toString(),
      description: data['description']?.toString(),
      author: data['author']?.toString(),
      artist: data['artist']?.toString(),
      status: data['status']?.toString(),
      genre: data['genre'] is List
          ? (data['genre'] as List).join(', ')
          : data['genre']?.toString(),
      chapters: chapters,
      isAnime: _isAnime,
    );
  }

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final data = await _post({
      ..._baseBody(_isAnime ? 'getEpisodeList' : 'getChapterList'),
      if (_isAnime) 'animeData': {'url': url} else 'mangaData': {'url': url},
    });
    if (data is! List) {
      throw Exception(
          'Extension "${source.displayName}" returned an unreadable '
          '${_isAnime ? 'episode' : 'chapter'} list.');
    }
    return [
      for (final e in data)
        if (e is Map)
          MChapter(
            name: e['name']?.toString(),
            url: stripMihonMemo(e['url']?.toString() ?? ''),
            dateUpload: (e['date_upload'] ?? e['dateUpload'])?.toString(),
            scanlator: e['scanlator']?.toString(),
            // The bridge serializes JChapter.chapter_number /
            // JEpisode.episode_number as floats — feeding them through
            // directly keeps ordering stable (no keyword recovery).
            chapterNumber: (e['chapter_number'] ?? e['episode_number'])
                ?.toString(),
          )
    ];
  }

  @override
  Future<List<String>> getPageList(String url) async {
    final data = await _post({
      ..._baseBody('getPageList'),
      'chapterData': {'url': url},
    });
    if (data is! List) {
      throw Exception(
          'Extension "${source.displayName}" returned an unreadable '
          'page list.');
    }
    return [
      for (final e in data)
        if (e is Map) (e['imageUrl'] ?? e['url'] ?? '').toString()
    ];
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final data = await _post({
      ..._baseBody('getVideoList'),
      'episodeData': {'url': url},
    });
    if (data is! List) {
      throw Exception(
          'Extension "${source.displayName}" returned an unreadable '
          'video list.');
    }
    final out = <MVideo>[];
    for (final e in data) {
      if (e is! Map) continue;
      // okhttp serialises multi-map headers as namesAndValues$okhttp (flat
      // alternating list) — upstream unwraps the same way.
      final rawHeaders = (e['headers'] as Map?)?['namesAndValues\$okhttp'];
      final headers = <String, String>{};
      if (rawHeaders is List) {
        for (var i = 0; i + 1 < rawHeaders.length; i += 2) {
          headers[rawHeaders[i].toString()] = rawHeaders[i + 1].toString();
        }
      } else if (e['headers'] is Map) {
        (e['headers'] as Map).forEach((k, v) => headers[k.toString()] = v.toString());
      }
      final subs = (e['subtitleTracks'] as List? ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map((s) => {
                'url': (s['file'] ?? s['url'] ?? '').toString(),
                'label': (s['label'] ?? s['lang'] ?? 'Subtitle').toString(),
                'language': (s['lang'] ?? '').toString(),
              })
          .where((s) => (s['url'] ?? '').isNotEmpty)
          .toList();
      final audios = (e['audioTracks'] as List? ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map((a) => {
                'url': (a['file'] ?? a['url'] ?? '').toString(),
                'label': (a['label'] ?? a['lang'] ?? '').toString(),
              })
          .where((a) => (a['url'] ?? '').isNotEmpty)
          .toList();
      final url0 = (e['videoUrl'] ?? e['url'] ?? '').toString();
      if (url0.isEmpty) continue;
      out.add(MVideo(
        url: url0,
        originalUrl: (e['url'] ?? url0).toString(),
        quality: e['quality']?.toString(),
        headers: headers,
        parameters: {
          if (subs.isNotEmpty) 'subtitles': subs,
          if (audios.isNotEmpty) 'audios': audios,
        },
      ));
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    _client?.close();
    _client = null;
  }
}

/// The m_extension_server bridge appends `|mangayomi-memo|<base64>` to
/// URLs that carry TachiyomiX 1.6 memo metadata. The bridge keeps its own
/// copy of that metadata (MihonMetadataCache, keyed by the RAW url), so
/// stripping the suffix client-side keeps URLs STABLE — the library
/// dedupes entries by source URL and the memo payload changes between
/// calls, which would have re-added the same entry twice.
String stripMihonMemo(String raw) {
  if (raw.isEmpty) return raw;
  final i = raw.indexOf('|mangayomi-memo|');
  return i < 0 ? raw : raw.substring(0, i);
}

/// Parses a /dalvik catalogue page.
///
/// WIRE FORMAT (m_extension_server ResponseModels.kt): manga lists are
/// serialized under `mangas`, anime lists under `animes`, and the entry
/// fields are `url` / `title` / `author` / `artist` / `description` /
/// `genre` (comma string) / `status` (int) / `thumbnail_url`. The old
/// parser looked for `list`/`mangaList`/`animeList` + `thumbnailUrl` —
/// keys that NEVER occur on this wire — so every APK extension browse
/// silently returned an EMPTY list (the "keiyoushi / NSFW / anime
/// extensions fetch nothing" report).
List<MManga> parseMihonPage(
  dynamic json, {
  required String displayName,
  required bool isAnime,
}) {
  if (json is! Map) {
    throw Exception(
        'Extension "$displayName" returned an unreadable catalogue '
        'response.');
  }
  final list = json['mangas'] ??
      json['animes'] ??
      json['list'] ??
      json['mangaList'] ??
      json['animeList'];
  if (list == null) {
    throw Exception(
        'Extension "$displayName" sent a catalogue response without a '
        'result list.');
  }
  if (list is! List) {
    throw Exception(
        'Extension "$displayName" sent a malformed result list.');
  }
  return [
    for (final e in list)
      if (e is Map)
        MManga(
          name: e['title']?.toString() ?? e['name']?.toString(),
          link: stripMihonMemo(e['url']?.toString() ?? ''),
          imageUrl: e['thumbnail_url']?.toString() ??
              e['thumbnailUrl']?.toString() ??
              e['imageUrl']?.toString(),
          description: e['description']?.toString(),
          author: e['author']?.toString(),
          artist: e['artist']?.toString(),
          status:
              e['status'] is int ? e['status'].toString() : e['status']?.toString(),
          genre: e['genre'] is List
              ? (e['genre'] as List).join(', ')
              : e['genre']?.toString(),
          // CRITICAL: without this, anime APK extensions are typed as
          // MANGA downstream (the coordinator keys off MManga.isAnime),
          // so episodes opened the IMAGE reader with zero pages and the
          // CTA said "Start reading".
          isAnime: isAnime,
        )
  ];
}
