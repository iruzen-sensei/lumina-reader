// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// ANILIST CATALOG SERVICE — the discovery + identity layer for anime in
// Lumina Reader. This mirrors the architecture of leading native anime
// clients (Anilili et al.): AniList's public GraphQL API provides the
// catalog (trending / popular / seasonal / search / detail), while stream
// providers (AniZone, see eval/native/anizone_source.dart) resolve
// episodes and playable HLS URLs.
//
// Endpoint: https://graphql.anilist.co (no auth required for public
// queries; rate limit ~30 req/min — every query here is cacheable by the
// caller and paged at 30 entries).
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/http/m_client.dart';

/// A lightweight anime catalog entry (AniList media).
class AniListAnime {
  AniListAnime({
    required this.id,
    required this.romaji,
    this.english,
    this.native,
    this.coverUrl,
    this.bannerUrl,
    this.description,
    this.format,
    this.status,
    this.seasonYear,
    this.episodes,
    this.durationMinutes,
    this.genres = const [],
    this.averageScore,
    this.isAdult = false,
    this.nextEpisode,
    this.nextAiringAt,
    this.idMal,
  });

  /// AniList media id — the stable identity used by providers.
  final int id;

  final String romaji;
  final String? english;
  final String? native;
  final String? coverUrl;
  final String? bannerUrl;

  /// Plain-text description (HTML stripped).
  final String? description;

  /// TV / TV_SHORT / MOVIE / OVA / ONA / SPECIAL.
  final String? format;

  /// FINISHED / RELEASING / NOT_YET_RELEASED / CANCELLED / HIATUS.
  final String? status;

  final int? seasonYear;
  final int? episodes;
  final int? durationMinutes;
  final List<String> genres;
  final int? averageScore;
  final bool isAdult;

  /// Next episode number + unix air time (airing shows).
  final int? nextEpisode;
  final int? nextAiringAt;

  /// MyAnimeList id cross-reference (AniSkip resolves skip segments by
  /// MAL id — the tag `mal:<id>` is what the AniSkip provider searches).
  final int? idMal;

  String get bestTitle => english?.isNotEmpty == true ? english! : romaji;

  /// All known titles — used by providers for fuzzy matching.
  List<String> get titles =>
      [romaji, english, native].whereType<String>().where((t) => t.isNotEmpty).toList();

  factory AniListAnime.fromMedia(dynamic media) {
    final m = media as Map<String, dynamic>? ?? const {};
    String? desc = m['description'] as String?;
    if (desc != null) {
      // AniList descriptions carry markdown/HTML — strip to plain text.
      desc = desc
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#039;', "'")
          .trim();
      if (desc.isEmpty) desc = null;
    }
    final airing = m['nextAiringEpisode'] as Map<String, dynamic>?;
    return AniListAnime(
      id: (m['id'] as num?)?.toInt() ?? 0,
      romaji: (m['title']?['romaji'] as String?) ?? '',
      english: m['title']?['english'] as String?,
      native: m['title']?['native'] as String?,
      coverUrl: m['coverImage']?['large'] as String?,
      bannerUrl: m['bannerImage'] as String?,
      description: desc,
      format: m['format'] as String?,
      status: m['status'] as String?,
      seasonYear: (m['seasonYear'] as num?)?.toInt(),
      episodes: (m['episodes'] as num?)?.toInt(),
      durationMinutes: (m['duration'] as num?)?.toInt(),
      genres: ((m['genres'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      averageScore: (m['averageScore'] as num?)?.toInt(),
      isAdult: m['isAdult'] as bool? ?? false,
      nextEpisode: (airing?['episode'] as num?)?.toInt(),
      nextAiringAt: (airing?['airingAt'] as num?)?.toInt(),
      idMal: (m['idMal'] as num?)?.toInt(),
    );
  }
}

class AniListService {
  AniListService({http.Client? client}) : _client = client;

  static const String _endpoint = 'https://graphql.anilist.co';
  static const int perPage = 30;

  http.Client? _client;
  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 20),
      );

  static const String _mediaFields = '''
      id
      title { romaji english native }
      coverImage { large }
      bannerImage
      format
      status
      seasonYear
      episodes
      duration
      genres
      averageScore
      isAdult
      idMal
      nextAiringEpisode { episode airingAt }
  ''';

  Future<List<AniListAnime>> _page(String query, Map<String, dynamic> vars) async {
    final res = await _http.post(
      Uri.parse(_endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'query': query, 'variables': vars}),
    );
    if (res.statusCode != 200) {
      throw StateError('AniList → HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['errors'] != null) {
      throw StateError('AniList error: ${body['errors']}');
    }
    final media = (body['data']?['Page']?['media'] as List?) ?? const [];
    return [for (final m in media) AniListAnime.fromMedia(m)];
  }

  /// Trending now (the "Popular" tab).
  Future<List<AniListAnime>> trending({int page = 1}) => _page('''
    query Trending(\$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) {
        media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { $_mediaFields }
      }
    }''', {'page': page, 'perPage': perPage});

  /// All-time popular.
  Future<List<AniListAnime>> popular({int page = 1}) => _page('''
    query Popular(\$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) {
        media(type: ANIME, sort: POPULARITY_DESC, isAdult: false) { $_mediaFields }
      }
    }''', {'page': page, 'perPage': perPage});

  /// Currently-airing season (the "Latest" tab).
  Future<List<AniListAnime>> seasonal({int page = 1}) => _page('''
    query Seasonal(\$page: Int, \$perPage: Int, \$season: MediaSeason, \$year: Int) {
      Page(page: \$page, perPage: \$perPage) {
        media(type: ANIME, season: \$season, seasonYear: \$year,
              status: RELEASING, sort: POPULARITY_DESC, isAdult: false) {
          $_mediaFields
        }
      }
    }''', {'page': page, 'perPage': perPage, ..._currentSeason()});

  /// Full-text search across romaji/english/native titles.
  Future<List<AniListAnime>> search(String query, {int page = 1}) => _page('''
    query Search(\$q: String, \$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) {
        media(type: ANIME, search: \$q, sort: SEARCH_MATCH, isAdult: false) {
          $_mediaFields
        }
      }
    }''', {'q': query, 'page': page, 'perPage': perPage});

  /// Unified Netflix-style browse with filters. Every parameter is optional;
  /// combinations map straight onto AniList's media query arguments.
  Future<List<AniListAnime>> browse({
    int page = 1,
    String? search,
    String? genre,
    int? year,
    String? season, // WINTER / SPRING / SUMMER / FALL
    String? format, // TV / TV_SHORT / MOVIE / OVA / ONA / SPECIAL
    String? status, // FINISHED / RELEASING / NOT_YET_RELEASED / CANCELLED / HIATUS
    String sort = 'TRENDING_DESC', // *_DESC sorts from [sortOptions]
  }) =>
      _page('''
    query Browse(\$page: Int, \$perPage: Int, \$search: String, \$genre: String,
                \$year: Int, \$season: MediaSeason, \$format: MediaFormat,
                \$status: MediaStatus, \$sort: [MediaSort]) {
      Page(page: \$page, perPage: \$perPage) {
        media(type: ANIME, isAdult: false, search: \$search, genre: \$genre,
              seasonYear: \$year, season: \$season, format: \$format,
              status: \$status, sort: \$sort) {
          $_mediaFields
        }
      }
    }''', {
        'page': page,
        'perPage': perPage,
        if (search != null && search.isNotEmpty) 'search': search,
        if (genre != null && genre.isNotEmpty) 'genre': genre,
        if (year != null) 'year': year,
        if (season != null && season.isNotEmpty) 'season': season,
        if (format != null && format.isNotEmpty) 'format': format,
        if (status != null && status.isNotEmpty) 'status': status,
        'sort': [sort],
      });

  /// All-time top-rated (the Top 10 row).
  Future<List<AniListAnime>> topRated({int page = 1}) => _page('''
    query Top(\$page: Int, \$perPage: Int) {
      Page(page: \$page, perPage: \$perPage) {
        media(type: ANIME, sort: SCORE_DESC, isAdult: false) { $_mediaFields }
      }
    }''', {'page': page, 'perPage': perPage});

  /// Upcoming NEXT season — the "Coming Soon" row.
  Future<List<AniListAnime>> upcoming({int page = 1}) {
    final next = _nextSeason();
    return _page('''
    query Upcoming(\$page: Int, \$perPage: Int, \$season: MediaSeason, \$year: Int) {
      Page(page: \$page, perPage: \$perPage) {
        media(type: ANIME, season: \$season, seasonYear: \$year,
              sort: POPULARITY_DESC, isAdult: false) { $_mediaFields }
      }
    }''', {'page': page, 'perPage': perPage, ...next});
  }

  /// "More like this" — recommendations for one entry.
  Future<List<AniListAnime>> recommendations(int anilistId,
      {int limit = 12}) async {
    const recFields = '''
          id
          title { romaji english native }
          coverImage { large }
          bannerImage
          format
          status
          seasonYear
          episodes
          genres
          averageScore
          isAdult
    ''';
    const query = '''
      query Recs(\$id: Int, \$perPage: Int) {
        Media(id: \$id, type: ANIME) {
          recommendations(sort: RATING_DESC, perPage: \$perPage) {
            nodes { mediaRecommendation { $recFields } }
          }
        }
      }''';
    final res = await _http.post(
      Uri.parse(_endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'query': query,
        'variables': {'id': anilistId, 'perPage': limit},
      }),
    );
    if (res.statusCode != 200) {
      throw StateError(
          'AniList recommendations -> HTTP ${res.statusCode}');
    }
    final body =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final nodes = (body['data']?['Media']?['recommendations']?['nodes']
        as List?) ??
        const [];
    return [
      for (final n in nodes)
        if (n is Map && n['mediaRecommendation'] != null)
          AniListAnime.fromMedia(n['mediaRecommendation']),
    ];
  }

  /// AniList's genre collection (static — the API's genre collection is
  /// stable and cached at zero cost).
  static const List<String> genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy', 'Horror',
    'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance',
    'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller',
  ];

  /// Sort options for the filter sheet.
  static const Map<String, String> sortOptions = {
    'Trending': 'TRENDING_DESC',
    'Popularity': 'POPULARITY_DESC',
    'Rating': 'SCORE_DESC',
    'Newest': 'START_DATE_DESC',
    'Episodes': 'EPISODES_DESC',
  };

  static const Map<String, String> formatOptions = {
    'TV': 'TV',
    'TV Short': 'TV_SHORT',
    'Movie': 'MOVIE',
    'OVA': 'OVA',
    'ONA': 'ONA',
    'Special': 'SPECIAL',
  };

  static const Map<String, String> statusOptions = {
    'Finished': 'FINISHED',
    'Airing': 'RELEASING',
    'Not yet aired': 'NOT_YET_RELEASED',
    'Cancelled': 'CANCELLED',
    'Hiatus': 'HIATUS',
  };

  /// Full detail for one entry (richer description + relations).
  Future<AniListAnime> detail(int id) async {
    const query = '''
      query Detail(\$id: Int) {
        Media(id: \$id, type: ANIME) {
          id
          title { romaji english native }
          coverImage { large extraLarge }
          bannerImage
          description(asHtml: false)
          format
          status
          seasonYear
          season
          episodes
          duration
          genres
          averageScore
          isAdult
          idMal
          studios(isMain: true) { nodes { name } }
          nextAiringEpisode { episode airingAt }
        }
      }''';
    final res = await _http.post(
      Uri.parse(_endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'query': query, 'variables': {'id': id}}),
    );
    if (res.statusCode != 200) {
      throw StateError('AniList detail → HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final media = body['data']?['Media'];
    if (media == null) throw StateError('AniList: no media $id');
    return AniListAnime.fromMedia(media);
  }

  /// Next season (for the Coming Soon row).
  static Map<String, dynamic> _nextSeason() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9)); // JST
    const seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    var idx = (now.month - 1) ~/ 3;
    var year = now.year;
    idx = (idx + 1) % 4;
    if (idx == 0) year += 1;
    return {'season': seasons[idx], 'year': year};
  }

  /// Current season name + year (AniList seasons: WINTER/SPRING/SUMMER/FALL).
  static Map<String, dynamic> _currentSeason() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9)); // JST
    const seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    // AniList season boundaries (approximate month starts):
    // WINTER Jan–Mar, SPRING Apr–Jun, SUMMER Jul–Sep, FALL Oct–Dec.
    final idx = (now.month - 1) ~/ 3;
    return {'season': seasons[idx], 'year': now.year};
  }

  void dispose() {
    _client?.close();
    _client = null;
  }
}
