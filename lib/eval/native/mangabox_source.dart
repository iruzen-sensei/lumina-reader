// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NATIVE MangaBox template — pure-Dart implementation for the classic
// "MangaBox" family of sites (Mangabat, Mangakakalot, Manganato, Mangairo,
// Manganelo clones). This is one of the four non-madara clusters in the
// Mangayomi extension index (4 of the 363 entries) and includes some of
// the most-requested English sources.
//
// Live-verified chain against https://www.mangabats.com (the family
// member without Cloudflare friction):
//   popular   GET /manga-list/hot-manga?page=N      → 44 covers/page
//   latest    GET /manga-list/latest-manga?page=N   → 44 covers/page
//   search    GET /search/story/<query>             → needs Referer header
//   detail    GET /manga/<slug>                     → ul.manga-info-text
//   chapters  GET /api/manga/<slug>/chapters        → JSON (lazy-loaded
//             list; the HTML embeds data-api-url) with XHR headers
//   pages     GET /manga/<slug>/<chapter-slug>      → .container-chapter-reader img
// ignore_for_file: avoid_dynamic_calls
// Rationale: decodes external JSON/HTML payloads; boundary parsing with
// null-guards at the point of use.

import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/services/http/m_client.dart';

/// The list page's item anchor: carries the detail URL and the title.
final RegExp _kStoryItemHref = RegExp(
    r'<a[^>]+href="(https?://[^"]+/manga/[^"]+)"[^>]+title="([^"]+)"');

class MangaBoxSource extends BaseExtensionService {
  MangaBoxSource(super.source, {http.Client? client}) : _client = client;

  http.Client? _client;

  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 20),
      );

  String get _base {
    final b = source.displayBaseUrl;
    if (b.isEmpty) return 'https://www.mangabats.com';
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  @override
  Future<Map<String, String>> getHeaders() async => const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36',
        // Live-verified: /search/story/* 403s without a same-origin
        // Referer (Cloudflare rule on this family).
        'Referer': 'https://www.mangabats.com/',
      };

  // -----------------------------------------------------------------------
  // Catalog
  // -----------------------------------------------------------------------

  @override
  Future<List<MManga>> getPopular(int page) =>
      _listPage('/manga-list/hot-manga', page);

  @override
  Future<List<MManga>> getLatestUpdates(int page) =>
      _listPage('/manga-list/latest-manga', page);

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async {
    if (query.trim().isEmpty) return const [];
    final url = '$_base/search/story/${Uri.encodeQueryComponent(query.trim())}';
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MangaBox search → HTTP ${res.statusCode}');
    }
    return _parseGrid(utf8.decode(res.bodyBytes));
  }

  Future<List<MManga>> _listPage(String path, int page) async {
    final url = page <= 1 ? '$_base$path' : '$_base$path?page=$page';
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MangaBox $path → HTTP ${res.statusCode}');
    }
    return _parseGrid(utf8.decode(res.bodyBytes));
  }

  /// Parses the shared grid markup:
  /// `<a class="list-story-item …" href="<detail>" title="<name>">` with a
  /// sibling/child `<img src="<thumb>">`.
  List<MManga> _parseGrid(String body) {
    final out = <MManga>[];
    final seen = <String>{};
    for (final m in _kStoryItemHref.allMatches(body)) {
      final link = m.group(1)!;
      final name = m.group(2)!.trim();
      if (name.isEmpty || !seen.add(link)) continue;
      // Thumb URL is deterministic: img-r1.2xstorage.com/thumb/<slug>.webp
      final slug = link.split('/manga/').last.split('?').first;
      out.add(MManga(
        name: name,
        link: link,
        imageUrl: 'https://img-r1.2xstorage.com/thumb/$slug.webp',
        isManga: true,
        source: source.idString,
      ));
    }
    return out;
  }

  // -----------------------------------------------------------------------
  // Detail
  // -----------------------------------------------------------------------

  @override
  Future<MManga> getMangaDetail(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MangaBox detail → HTTP ${res.statusCode}');
    }
    final doc = html_parser.parse(utf8.decode(res.bodyBytes));

    final manga = MManga(
      name: _titleFromUrl(url),
      link: url,
      isManga: true,
      source: source.idString,
    );

    // The h1/manga-info-text block carries title/author/status/genres.
    final infoRows = doc.querySelectorAll('ul.manga-info-text li, '
        'div.manga-info-text li, .variations-tableInfo tr');
    for (final li in infoRows) {
      final text = li.text.trim();
      if (manga.author == null && text.toLowerCase().contains('author')) {
        manga.author = _afterColon(text);
      } else if (text.toLowerCase().contains('status')) {
        final s = _afterColon(text).toLowerCase();
        manga.status = s.contains('ongo')
            ? '1'
            : s.contains('completed')
                ? '2'
                : '0';
      }
    }

    // Alternate modern layout: meta rows keyed by label.
    if (manga.author == null) {
      for (final row in doc.querySelectorAll('.manga-info-text, '
          '.table-value, .info-item')) {
        final t = row.text.trim();
        if (t.toLowerCase().startsWith('author')) {
          manga.author = _afterColon(t);
          break;
        }
      }
    }

    // Title from the page if the URL slug guess was wrong.
    final h1 = doc.querySelector('h1, .title-detail, .story-name');
    if (h1 != null && h1.text.trim().isNotEmpty) {
      manga.name = h1.text.trim();
    }

    // Synopsis.
    final summary = doc.querySelector('#contentBox, .panel-story-info '
        '.summary, .story-detail-right .detail, #noidungm');
    if (summary != null) {
      final text = summary.text.trim();
      // Trim the boilerplate "X summary:" prefix the theme prints.
      manga.description = text.replaceFirst(RegExp(r'^.*?summary\s*:?\s*',
              caseSensitive: false, dotAll: true),
          text.length > 400 ? text.substring(text.length - 400) : text);
      if (manga.description!.length > 1200) {
        manga.description = manga.description!.substring(0, 1200);
      }
    }

    // Cover: deterministic thumb works for every family site verified.
    final slug = url.split('/manga/').last.split('?').first;
    manga.imageUrl = 'https://img-r1.2xstorage.com/thumb/$slug.webp';

    // Genres.
    final genres = <String>[];
    for (final a in doc.querySelectorAll('a[href*="/genre/"]')) {
      final g = a.text.trim();
      if (g.isNotEmpty) genres.add(g);
    }
    if (genres.isNotEmpty) {
      manga.categories = genres;
      manga.genre = genres.join(',');
    }
    return manga;
  }

  String _afterColon(String text) {
    final i = text.indexOf(':');
    return i < 0 ? text.trim() : text.substring(i + 1).trim();
  }

  String _titleFromUrl(String url) {
    final slug = url.split('/manga/').last.split('?').first;
    // kebab/case → Title Case (best-effort until the detail HTML loads).
    return slug
        .split(RegExp(r'[-_]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // -----------------------------------------------------------------------
  // Chapters (JSON API — the HTML list is lazy-loaded)
  // -----------------------------------------------------------------------

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final slug = url.split('/manga/').last.split('?').first;
    // Live-verified: the API returns only 50 chapters by default — a high
    // limit yields the full list (Martial Peak: 3877 chapters in one go).
    final api = Uri.parse('$_base/api/manga/$slug/chapters?limit=5000');
    final res = await _http.get(api, headers: {
      ...await getHeaders(),
      'Accept': 'application/json, text/plain, */*',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': url,
    });
    if (res.statusCode != 200) {
      throw StateError('MangaBox chapters API → HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final chaptersJson =
        ((decoded as Map)['data']?['chapters'] as List?) ?? const [];
    final out = <MChapter>[];
    for (final e in chaptersJson) {
      if (e is! Map) continue;
      final num = e['chapter_num'];
      final chapterSlug = e['chapter_slug'] as String?;
      if (chapterSlug == null) continue;
      final dateRaw = e['updated_at'] as String?;
      final parsed = dateRaw == null ? null : DateTime.tryParse(dateRaw);
      out.add(MChapter(
        name: (e['chapter_name'] as String?) ?? 'Chapter $num',
        url: '$_base/manga/$slug/$chapterSlug',
        chapterNumber: num?.toString() ?? chapterSlug.replaceFirst('chapter-', ''),
        dateUpload: parsed?.millisecondsSinceEpoch.toString(),
      ));
    }
    // API already returns newest-first; normalise to be safe.
    out.sort((a, b) =>
        (double.tryParse(b.chapterNumber ?? '') ?? 0)
            .compareTo(double.tryParse(a.chapterNumber ?? '') ?? 0));
    return out;
  }

  // -----------------------------------------------------------------------
  // Pages
  // -----------------------------------------------------------------------

  @override
  Future<List<String>> getPageList(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MangaBox chapter → HTTP ${res.statusCode}');
    }
    final doc = html_parser.parse(utf8.decode(res.bodyBytes));
    final imgs = doc.querySelectorAll('.container-chapter-reader img, '
        '.container-chapter-reader > img');
    final pages = <String>[];
    for (final img in imgs) {
      final src = img.attributes['src'] ??
          img.attributes['data-src'] ??
          img.attributes['data-original'];
      if (src != null && src.startsWith('http')) pages.add(src.trim());
    }
    if (pages.isEmpty) {
      throw StateError('MangaBox: no pages found at $url '
          '(layout change or Cloudflare interstitial)');
    }
    return pages;
  }

  @override
  Future<void> dispose() async {
    _client?.close();
    _client = null;
  }
}
