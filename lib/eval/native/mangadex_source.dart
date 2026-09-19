// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NATIVE MangaDex source — a pure-Dart implementation of [ExtensionService]
// against the public MangaDex API v5 (https://api.mangadex.org). No JS
// interpreter, no scraping: this is the reference implementation for the
// "builtin:" extension scheme dispatched by eval/lib.dart.
//
// Covered endpoints:
//   GET /manga                       — popular (order[followedCount]) /
//                                      latest (order[latestUploadedChapter]) /
//                                      search (title=)
//   GET /manga/{id}                  — detail (+ author/artist/cover rel)
//   GET /manga/{id}/feed             — chapter list (EN, desc)
//   GET /at-home/server/{chapterId}  — page image URLs
// ignore_for_file: avoid_dynamic_calls
// Rationale: this file decodes external JSON/GraphQL API payloads
// (Map<String, dynamic> responses). Member access on the decoded dynamic
// payload is the standard pattern for boundary parsing; every value is
// null-guarded or defaulted at the point of use.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/services/http/m_client.dart';

class MangaDexSource extends BaseExtensionService {
  /// Optional injected client (fixture tests). When null a real MClient is
  /// created lazily — same injection pattern as MadaraSource.
  MangaDexSource(super.source, {http.Client? client}) : _client = client;

  static const String _api = 'https://api.mangadex.org';
  static const String _uploads = 'https://uploads.mangadex.org';
  static const int _limit = 20;

  /// Chapters above this count paginate the feed (rare; 500 per page).
  static const int _maxFeedPages = 2;

  http.Client? _client;

  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 20),
      );

  @override
  Future<Map<String, String>> getHeaders() async => const {
        'User-Agent':
            'LuminaReader/1.0 (Android; MangaDex client; +github.com/lumina)',
      };

  // -----------------------------------------------------------------------
  // Catalog
  // -----------------------------------------------------------------------

  @override
  Future<List<MManga>> getPopular(int page) =>
      _listManga(page, orderBy: 'followedCount');

  @override
  Future<List<MManga>> getLatestUpdates(int page) =>
      _listManga(page, orderBy: 'latestUploadedChapter');

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) =>
      _listManga(page, title: query);

  Future<List<MManga>> _listManga(
    int page, {
    String? orderBy,
    String? title,
  }) async {
    final offset = (page - 1) * _limit;
    final params = <String>[
      'limit=$_limit',
      'offset=$offset',
      'includes[]=cover_art',
      'contentRating[]=safe',
      'contentRating[]=suggestive',
      'hasAvailableChapters=true',
      if (orderBy != null) 'order[$orderBy]=desc',
      if (title != null && title.isNotEmpty) 'title=${Uri.encodeQueryComponent(title)}',
    ];
    final json = await _getJson('$_api/manga?${params.join('&')}');
    final data = (json['data'] as List? ?? const []);
    return data.map(_mangaFromApi).where((m) => m.name != null).toList();
  }

  MManga _mangaFromApi(dynamic entry) {
    final attrs = entry['attributes'] as Map<String, dynamic>? ?? const {};
    final id = entry['id'] as String? ?? '';
    final rels = entry['relationships'] as List? ?? const [];
    String? coverFile;
    for (final r in rels) {
      if (r is Map && r['type'] == 'cover_art') {
        final coverAttrs = r['attributes'];
        coverFile = coverAttrs is Map ? coverAttrs['fileName'] as String? : null;
        break;
      }
    }
    final cover = coverFile == null
        ? null
        : '$_uploads/covers/$id/$coverFile.512.jpg';
    final titles = attrs['altTitles'] as List? ?? const [];
    String? englishTitle;
    for (final t in titles) {
      final tt = t as Map<String, dynamic>?;
      if (tt != null && tt.containsKey('en')) {
        englishTitle = tt['en'] as String?;
        break;
      }
    }
    final tags = (attrs['tags'] as List? ?? const [])
        .map((t) => t['attributes']?['name']?['en'])
        .whereType<String>()
        .toList();

    // MangaDex can return titles in many languages; prefer English, then an
    // alt English title, then any non-empty title value.
    final titleMap = attrs['title'] as Map<String, dynamic>? ?? const {};
    String? name = titleMap['en'] as String? ?? englishTitle;
    if (name == null || name.isEmpty) {
      for (final v in titleMap.values) {
        if (v is String && v.isNotEmpty) {
          name = v;
          break;
        }
      }
    }

    return MManga(
      name: name,
      link: '$_api/manga/$id',
      imageUrl: cover,
      description:
          (attrs['description']?['en'] as String?)?.trim().isEmpty == true
              ? null
              : attrs['description']?['en'] as String?,
      status: _statusToCode(attrs['status'] as String?),
      categories: tags,
      genre: tags.join(','),
      isManga: true,
      source: source.idString,
    );
  }

  String _statusToCode(String? mdStatus) {
    switch (mdStatus) {
      case 'ongoing':
        return '1';
      case 'completed':
        return '2';
      case 'hiatus':
        return '6';
      case 'cancelled':
        return '5';
      case 'publication_completed':
        return '4';
      default:
        return '0';
    }
  }

  // -----------------------------------------------------------------------
  // Detail & chapters
  // -----------------------------------------------------------------------

  @override
  Future<MManga> getMangaDetail(String url) async {
    final id = _mangaId(url);
    final json = await _getJson(
        '$_api/manga/$id?includes[]=cover_art&includes[]=author&includes[]=artist');
    final manga = _mangaFromApi(json['data']);

    // Attach author / artist from relationships.
    final rels = json['data']?['relationships'] as List? ?? const [];
    for (final r in rels) {
      final name = r['attributes']?['name'] as String?;
      if (name == null) continue;
      if (r['type'] == 'author' && (manga.author == null || manga.author!.isEmpty)) {
        manga.author = name;
      } else if (r['type'] == 'artist' && (manga.artist == null || manga.artist!.isEmpty)) {
        manga.artist = name;
      }
    }
    return manga;
  }

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final id = _mangaId(url);
    final chapters = <MChapter>[];
    for (var page = 0; page < _maxFeedPages; page++) {
      final offset = page * 500;
      final json = await _getJson(
          '$_api/manga/$id/feed?translatedLanguage[]=en&order[chapter]=desc'
          '&limit=500&offset=$offset&contentRating[]=safe'
          '&contentRating[]=suggestive&contentRating[]=erotica'
          '&includes[]=scanlation_group');
      final data = (json['data'] as List? ?? const []);
      for (final entry in data) {
        final attrs = entry['attributes'] as Map<String, dynamic>? ?? const {};
        final number = attrs['chapter'] as String?;
        if (number == null || number.isEmpty) continue; // skip novel-format
        final rels = entry['relationships'] as List? ?? const [];
        String? group;
        for (final r in rels) {
          if (r['type'] == 'scanlation_group') {
            group = r['attributes']?['name'] as String?;
            break;
          }
        }
        final published = DateTime.tryParse(
                (attrs['publishAt'] ?? attrs['readableAt'] ?? '') as String)
            ?.millisecondsSinceEpoch;
        final title = (attrs['title'] as String?)?.trim();
        chapters.add(MChapter(
          name: title == null || title.isEmpty
              ? 'Chapter $number'
              : 'Chapter $number — $title',
          url: 'https://mangadex.org/chapter/${entry['id']}',
          dateUpload: published?.toString(),
          scanlator: group,
          chapterNumber: number,
          language: attrs['translatedLanguage'] as String?,
        ));
      }
      final total = (json['total'] as num?)?.toInt() ?? 0;
      if (offset + 500 >= total || data.isEmpty) break;
    }
    return chapters;
  }

  // -----------------------------------------------------------------------
  // Pages
  // -----------------------------------------------------------------------

  @override
  Future<List<String>> getPageList(String url) async {
    final chapterId = _chapterId(url);
    final json = await _getJson('$_api/at-home/server/$chapterId');
    final baseUrl = json['baseUrl'] as String? ?? '';
    final hash = json['chapter']?['hash'] as String? ?? '';
    final data = (json['chapter']?['data'] as List? ?? const [])
        .whereType<String>()
        .toList();
    if (baseUrl.isEmpty || hash.isEmpty || data.isEmpty) return const [];
    return [
      for (final file in data) '$baseUrl/data/$hash/$file',
    ];
  }

  // -----------------------------------------------------------------------
  // Internals
  // -----------------------------------------------------------------------

  String _mangaId(String url) {
    final match = RegExp(r'/manga/([0-9a-f-]{8,})').firstMatch(url);
    return match?.group(1) ?? url.replaceAll(RegExp(r'[^0-9a-f-]'), '');
  }

  String _chapterId(String url) {
    final match = RegExp(r'/chapter/([0-9a-f-]{8,})').firstMatch(url);
    return match?.group(1) ?? url.replaceAll(RegExp(r'[^0-9a-f-]'), '');
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MangaDex API $url → HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
