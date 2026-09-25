// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NATIVE AniZone anime source — Anilili-style anime streaming.
//
// Architecture (same as leading multi-source anime clients):
//   * CATALOG + IDENTITY = AniList GraphQL (lib/services/anilist.dart):
//     trending / popular / seasonal / search / detail.
//   * EPISODES + STREAMS = AniZone (anizone.to, Cloudflare-free,
//     live-verified 2026-09): a Livewire (Laravel) site whose pages embed
//     JSON payloads in JS string literals.
//
// Live-verified chain (Frieren, anilist id 154587):
//   search    GET /anime?search=<q>          → items: JSON.parse('…') slugs
//   episodes  GET /anime/<slug>              → first 24 items + wire:snapshot
//             POST /livewire/update          → paginated item pages
//   watch     GET /anime/<slug>/<ep>         → vidstackPlayer(JSON.parse(…))
//                                             → HLS master.m3u8 + ASS/VTT subs
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/services/anilist.dart';
import 'package:lumina_reader/services/http/m_client.dart';

class AniZoneSource extends BaseExtensionService {
  AniZoneSource(super.source, {http.Client? client, AniListService? anilist})
      : _client = client,
        _anilist = anilist;

  static const String _base = 'https://anizone.to';

  static const String _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36';

  http.Client? _client;
  AniListService? _anilist;

  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 25),
      );

  AniListService get _aniList => _anilist ??= AniListService();

  /// slug resolution cache: anilist id → AniZone slug.
  final Map<int, String> _slugCache = {};

  @override
  Future<Map<String, String>> getHeaders() async => const {
        'User-Agent': _ua,
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': '$_base/',
      };

  // -----------------------------------------------------------------------
  // Catalog (AniList)
  // -----------------------------------------------------------------------

  @override
  Future<List<MManga>> getPopular(int page) async {
    final entries = await _aniList.trending(page: page);
    return entries.map(_toEntry).toList();
  }

  @override
  Future<List<MManga>> getLatestUpdates(int page) async {
    final entries = await _aniList.seasonal(page: page);
    return entries.map(_toEntry).toList();
  }

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async {
    if (query.trim().isEmpty) return const [];
    final entries = await _aniList.search(query.trim(), page: page);
    return entries.map(_toEntry).toList();
  }

  MManga _toEntry(AniListAnime a) => MManga(
        name: a.bestTitle,
        link: 'anilist:${a.id}',
        imageUrl: a.coverUrl,
        description: a.description,
        genre: a.genres.join(','),
        categories: a.genres,
        status: _status(a.status),
        isAnime: true,
        isManga: false,
        isNsfw: a.isAdult,
        source: source.idString,
      );

  String _status(String? s) => switch (s) {
        'RELEASING' => '1',
        'FINISHED' => '2',
        'HIATUS' => '6',
        'CANCELLED' => '5',
        'NOT_YET_RELEASED' => '0',
        _ => '0',
      };

  // -----------------------------------------------------------------------
  // Detail (AniList metadata)
  // -----------------------------------------------------------------------

  int _anilistId(String url) =>
      int.tryParse(url.replaceFirst(RegExp(r'^anilist:'), '').split('/').last) ?? 0;

  @override
  Future<MManga> getMangaDetail(String url) async {
    final id = _anilistId(url);
    final a = await _aniList.detail(id);
    final manga = _toEntry(a);
    // The English title leads; keep romaji visible for matching + users
    // who prefer it.
    if (a.romaji.isNotEmpty && a.romaji != manga.name) {
      manga.artist = 'Romaji: ${a.romaji}';
    }
    if (a.seasonYear != null) {
      manga.author = '${a.seasonYear}';
    }
    return manga;
  }

  // -----------------------------------------------------------------------
  // Episodes (AniZone — Livewire pagination)
  // -----------------------------------------------------------------------

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final id = _anilistId(url);
    final slug = await _resolveSlug(id);
    if (slug == null) return const [];
    final episodes = await _scrapeEpisodes(slug, maxPages: 8);
    final out = <MChapter>[];
    for (final e in episodes) {
      final number = e['number'] as int;
      out.add(MChapter(
        name: e['title'] as String? ?? 'Episode $number',
        url: '$_base/anime/$slug/$number',
        chapterNumber: number.toString(),
      ));
    }
    return out;
  }

  /// Resolves the AniZone slug for an AniList entry: searches AniZone with
  /// every known title, then picks the best fuzzy match (Dice coefficient
  /// on character bigrams — same family as the aggregators' matchers).
  Future<String?> _resolveSlug(int anilistId) async {
    final cached = _slugCache[anilistId];
    if (cached != null) return cached;

    final a = await _aniList.detail(anilistId);
    final expected = a.episodes ?? 0;
    final candidates = <_AniZoneCandidate>[];
    for (final q in _searchQueries(a.titles)) {
      try {
        candidates.addAll(await _search(q));
      } catch (_) {/* per-query failures are fine */}
    }

    _AniZoneCandidate? best;
    for (final c in candidates) {
      // Same-family format filter: AniZone types mirror AniList formats.
      if (_expectedFormat(a.format) != null &&
          c.type.isNotEmpty &&
          c.type != _expectedFormat(a.format)) {
        continue;
      }
      var score = 0.0;
      for (final t in a.titles) {
        score = score > _dice(t, c.title) ? score : _dice(t, c.title);
      }
      // Episode-count sanity: a 24-ep candidate for a 12-ep show is
      // likely a sequel/related entry — penalise but do not reject.
      if (expected > 0 && c.episodeCount > 0) {
        final ratio = c.episodeCount / expected;
        if (ratio > 1.6 || ratio < 0.6) score -= 0.15;
      }
      c.score = score;
      if (best == null || score > best.score) best = c;
    }
    // 0.5 ≈ same words different order / partial match — below that the
    // entry simply is not on AniZone.
    final resolved = best;
    if (resolved == null || resolved.score < 0.5) return null;
    _slugCache[anilistId] = resolved.slug;
    return resolved.slug;
  }

  List<String> _searchQueries(List<String> titles) {
    final out = <String>[];
    for (final t in titles.take(3)) {
      final clean = t.trim();
      if (clean.isEmpty) continue;
      out.add(clean);
      // Strip season suffixes ("Season 2", "Part II") — AniZone indexes
      // sequels as separate entries but often without the suffix.
      final stripped = clean
          .replaceFirst(RegExp(r'\s*(season|part)\s*\d+$', caseSensitive: false), '')
          .trim();
      if (stripped.length >= 3 && stripped != clean) out.add(stripped);
    }
    return out.take(4).toList();
  }

  Future<List<_AniZoneCandidate>> _search(String query) async {
    final res = await _http.get(
      Uri.parse('$_base/anime').replace(queryParameters: {'search': query}),
      headers: await getHeaders(),
    );
    if (res.statusCode != 200) return const [];
    final items = _jsonArgument(utf8.decode(res.bodyBytes), 'items');
    if (items is! List) return const [];
    final out = <_AniZoneCandidate>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final slug = raw['slug'] as String?;
      if (slug == null || !RegExp(r'^[a-z0-9-]+$', caseSensitive: false).hasMatch(slug)) {
        continue;
      }
      final titleList = raw['title_list'] as Map? ?? const {};
      final title =
          (titleList['1'] ?? titleList['5'] ?? raw['main_title'] ?? '') as String;
      if (title.isEmpty) continue;
      out.add(_AniZoneCandidate(
        slug: slug,
        title: title,
        type: _formatName(raw['type'] as String? ?? ''),
        episodeCount: (raw['episode_count'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  String? _expectedFormat(String? format) => switch ((format ?? '').toUpperCase()) {
        'TV' || 'TV_SHORT' => 'tv',
        'MOVIE' => 'movie',
        'OVA' => 'ova',
        'ONA' => 'ona',
        'SPECIAL' => 'special',
        _ => null,
      };

  String _formatName(String type) {
    final t = type.toLowerCase();
    if (t.contains('special')) return 'special';
    if (t.contains('movie')) return 'movie';
    if (t.contains('ova')) return 'ova';
    if (t.contains('web') || t.contains('ona')) return 'ona';
    if (t.contains('tv')) return 'tv';
    return '';
  }

  /// Scrapes the full episode list: the detail page embeds the first ~24
  /// items; the remainder stream through Livewire `loadPage` calls.
  Future<List<Map<String, dynamic>>> _scrapeEpisodes(
    String slug, {
    int limit = 400,
    int maxPages = 8,
  }) async {
    final res = await _http.get(
      Uri.parse('$_base/anime/$slug'),
      headers: await getHeaders(),
    );
    if (res.statusCode != 200) {
      throw StateError('AniZone detail → HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);

    final items = _jsonArgument(body, 'items');
    if (items is! List || items.isEmpty) return const [];
    var snapshot = _wireSnapshot(body);
    final csrf = _csrf(body);
    var cursor = _cursor(body);
    var hasMore = RegExp(r'hasMore:\s*true', caseSensitive: false).hasMatch(body);
    var cookies = _mergeCookies(res.headers['set-cookie']);

    final episodes = <Map<String, dynamic>>[
      for (final e in items) if (e is Map<String, dynamic>) e,
    ];
    var pages = 1;
    while (hasMore &&
        cursor != null &&
        episodes.length < limit &&
        pages < maxPages) {
      final page = await _livewireLoadPage(
          snapshot: snapshot, csrf: csrf, cursor: cursor, cookies: cookies);
      if (page == null) break;
      episodes.addAll(page.items);
      snapshot = page.snapshot;
      cursor = page.cursor;
      hasMore = page.hasMore;
      cookies = page.cookies;
      pages++;
    }

    // Dedupe by episode number, sort ascending.
    final seen = <int>{};
    final out = <Map<String, dynamic>>[];
    for (final e in episodes) {
      final number = _episodeNumber(e);
      if (number == null || !seen.add(number)) continue;
      out.add({'number': number, 'title': _pickTitle(e)});
    }
    out.sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
    return out;
  }

  int? _episodeNumber(Map<String, dynamic> item) {
    final direct = int.tryParse('${item['slug'] ?? ''}');
    if (direct != null && direct > 0) return direct;
    final fromUrl = RegExp(r'/(\d+)/?$')
        .firstMatch((item['url'] ?? '').toString().replaceAll('\\/', '/'));
    return fromUrl == null ? null : int.tryParse(fromUrl.group(1)!);
  }

  String _pickTitle(Map<dynamic, dynamic> item) {
    final titles = item['title_list'] as Map? ?? const {};
    final t = (titles['1'] ?? titles['5'] ?? titles['8'] ?? '') as String;
    return t.isNotEmpty ? t : 'Episode';
  }

  Future<_LivewirePage?> _livewireLoadPage({
    required String snapshot,
    required String csrf,
    required String cursor,
    required String cookies,
  }) async {
    try {
      final res = await _http.post(
        Uri.parse('$_base/livewire/update'),
        headers: {
          'User-Agent': _ua,
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/json',
          'X-Livewire': '',
          'X-CSRF-TOKEN': csrf,
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': _base,
          'Referer': '$_base/',
          if (cookies.isNotEmpty) 'Cookie': cookies,
        },
        body: jsonEncode({
          'components': [
            {
              'snapshot': snapshot,
              'updates': <String, dynamic>{},
              'calls': [
                {
                  'path': '',
                  'method': 'loadPage',
                  'params': [cursor],
                }
              ],
            }
          ],
        }),
      );
      if (res.statusCode != 200) return null;
      final payload = jsonDecode(utf8.decode(res.bodyBytes));
      final component = (payload['components'] as List?)?.firstOrNull;
      if (component is! Map) return null;
      final dispatches = (component['effects']?['dispatches'] as List?)
          ?.whereType<Map<dynamic, dynamic>>()
          .where((d) => d['name'] == 'items-loaded');
      final params = dispatches?.isNotEmpty == true
          ? dispatches!.first['params'] as Map?
          : null;
      final items = params?['items'];
      if (component['snapshot'] == null || items is! List) return null;
      return _LivewirePage(
        items: [for (final e in items) if (e is Map<String, dynamic>) e],
        snapshot: component['snapshot'] as String,
        cursor: params?['nextCursor'] as String?,
        hasMore: params?['hasMore'] == true,
        cookies: _mergeCookies(res.headers['set-cookie']),
      );
    } catch (_) {
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // Streams (AniZone watch page → HLS + subtitles)
  // -----------------------------------------------------------------------

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = await _http.get(Uri.parse(url), headers: {
      ...await getHeaders(),
      'Referer': '$_base/',
    });
    if (res.statusCode != 200) {
      throw StateError('AniZone watch → HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final player = _vidstackPayload(body);
    if (player == null) {
      throw StateError('AniZone: player payload not found at $url');
    }
    final src = (player['src'] ?? '') as String;
    if (src.isEmpty) {
      throw StateError('AniZone: no playable stream at $url');
    }
    final hls = src.replaceAll('\\/', '/');

    // Subtitle tracks (ASS/VTT) — passed through MVideo.parameters to the
    // player layer.
    final subs = <Map<String, dynamic>>[];
    final rawSubs = player['subtitles'];
    if (rawSubs is List) {
      for (final s in rawSubs) {
        if (s is! Map) continue;
        final file = ((s['file'] ?? '') as String).replaceAll('\\/', '/');
        if (file.isEmpty) continue;
        subs.add({
          'url': file,
          'label': (s['title'] ?? s['language'] ?? 'Subtitle') as String,
          'language': (s['language'] ?? '') as String,
          'format': (s['format'] ?? 'vtt') as String,
          'default': s['default'] == true,
        });
      }
    }

    return [
      MVideo(
        url: hls,
        originalUrl: url,
        quality: 'Sub',
        title: 'AniZone',
        headers: {'User-Agent': _ua, 'Referer': '$_base/'},
        parameters: {
          if (subs.isNotEmpty) 'subtitles': subs,
          'type': 'hls',
        },
      ),
    ];
  }

  // -----------------------------------------------------------------------
  // Page list — anime source: no images.
  // -----------------------------------------------------------------------

  @override
  Future<List<String>> getPageList(String url) async => const [];

  @override
  Future<void> dispose() async {
    _client?.close();
    _client = null;
    _anilist?.dispose();
    _anilist = null;
  }
}

// ---------------------------------------------------------------------------
// Payload parsing helpers
// ---------------------------------------------------------------------------

/// Extracts `name: JSON.parse('…')` payloads from AniZone HTML.
///
/// The inner string is a JS single-quoted literal whose escapes must be
/// decoded BEFORE JSON parsing (`\u0022` for quotes, `\\\/` for slashes).
dynamic _jsonArgument(String html, String name) {
  final rx = RegExp(
      "${RegExp.escape(name)}\\s*:\\s*JSON\\.parse\\('((?:[^'\\\\]|\\\\.)*)'\\)",
      caseSensitive: false);
  final match = rx.firstMatch(html);
  if (match == null) return null;
  try {
    return jsonDecode(_jsUnescape(match.group(1)!));
  } catch (_) {
    return null;
  }
}

/// JS single-quoted-string unescape: \\uXXXX, \\', \\\\, \\/ …
String _jsUnescape(String raw) {
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == r'\' && i + 1 < raw.length) {
      final n = raw[i + 1];
      if (n == 'u' && i + 5 < raw.length) {
        final code = int.tryParse(raw.substring(i + 2, i + 6), radix: 16);
        if (code != null) {
          out.writeCharCode(code);
          i += 5;
          continue;
        }
      }
      out.write(n);
      i++;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

Map<String, dynamic>? _vidstackPayload(String html) {
  final rx = RegExp(
      r"vidstackPlayer\s*\(\s*JSON\.parse\('((?:[^'\\]|\\.)*)'\)\s*\)",
      caseSensitive: false);
  final match = rx.firstMatch(html);
  if (match == null) return null;
  try {
    final decoded = jsonDecode(_jsUnescape(match.group(1)!));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String _wireSnapshot(String html) {
  final matches = RegExp(r'wire:snapshot="([^"]*)"').allMatches(html);
  for (final m in matches) {
    final value = _decodeHtmlEntities(m.group(1) ?? '');
    if (value.contains('pages.anime-detail')) return value;
  }
  return '';
}

String _csrf(String html) =>
    RegExp(r'csrf-token"\s+content="([^"]+)"', caseSensitive: false)
            .firstMatch(html)
            ?.group(1) ??
        '';

String? _cursor(String html) =>
    RegExp(r"nextCursor:\s*'([^']+)'", caseSensitive: false)
        .firstMatch(html)
        ?.group(1);

String _mergeCookies(String? setCookie) {
  if (setCookie == null) return '';
  final jar = <String>[];
  for (final raw in setCookie.split(',')) {
    final m = RegExp(r'^\s*([^=;\s]+)=([^;]*)').firstMatch(raw);
    if (m != null) jar.add('${m.group(1)}=${m.group(2)}');
  }
  return jar.join('; ');
}

String _decodeHtmlEntities(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

// ---------------------------------------------------------------------------
// Matching helpers
// ---------------------------------------------------------------------------

/// Dice coefficient over character bigrams: 1.0 = identical, 0 = nothing
/// in common. Language-agnostic (works for romaji vs latin titles).
double _dice(String a, String b) {
  final x = _normalizeTitle(a);
  final y = _normalizeTitle(b);
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  if (x.length < 2 || y.length < 2) return x == y ? 1 : 0;
  final bigrams = <String, int>{};
  for (var i = 0; i < x.length - 1; i++) {
    final g = x.substring(i, i + 2);
    bigrams[g] = (bigrams[g] ?? 0) + 1;
  }
  var hits = 0;
  for (var i = 0; i < y.length - 1; i++) {
    final g = y.substring(i, i + 2);
    final count = bigrams[g] ?? 0;
    if (count > 0) {
      bigrams[g] = count - 1;
      hits++;
    }
  }
  return 2.0 * hits / (x.length - 1 + y.length - 1);
}

String _normalizeTitle(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

class _AniZoneCandidate {
  _AniZoneCandidate({
    required this.slug,
    required this.title,
    required this.type,
    required this.episodeCount,
  });

  final String slug;
  final String title;
  final String type;
  final int episodeCount;
  double score = 0;
}

class _LivewirePage {
  _LivewirePage({
    required this.items,
    required this.snapshot,
    required this.cursor,
    required this.hasMore,
    required this.cookies,
  });

  final List<Map<String, dynamic>> items;
  final String snapshot;
  final String? cursor;
  final bool hasMore;
  final String cookies;
}
