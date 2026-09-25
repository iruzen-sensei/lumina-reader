// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NATIVE MMRCMS template — pure-Dart implementation for the "MMRCMS"
// family (scan-vf.net, onma.top, readcomicsonline.ru …): 3 entries in the
// Mangayomi extension index and the dominant French-language cluster.
//
// Live-verified chain against https://www.scan-vf.net:
//   popular   GET /manga-list                  → .media blocks
//   latest    GET /latest-release              → chapter rows → parent slugs
//   search    GET /search?query=<q>            → JSON autocomplete
//             {"suggestions":[{"value":"Title","data":"slug"}]}
//   detail    GET /<slug>                      → h5 chapter rows + summary
//   chapters  GET /<slug>                      → <h5><a href="/<slug>/chapitre-N">
//   pages     GET /<slug>/chapitre-N           → uploads/manga/<slug>/chapters/… img
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/services/http/m_client.dart';

class MmrcmsSource extends BaseExtensionService {
  MmrcmsSource(super.source, {http.Client? client}) : _client = client;

  http.Client? _client;

  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 20),
      );

  String get _base {
    final b = source.displayBaseUrl;
    if (b.isEmpty) return 'https://www.scan-vf.net';
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  @override
  Future<Map<String, String>> getHeaders() async => const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36',
      };

  // -----------------------------------------------------------------------
  // Catalog
  // -----------------------------------------------------------------------

  @override
  Future<List<MManga>> getPopular(int page) async {
    // The list is a single long page (no pagination on the family).
    if (page > 1) return const [];
    final res =
        await _http.get(Uri.parse('$_base/manga-list'), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MMRCMS list → HTTP ${res.statusCode}');
    }
    final doc = html_parser.parse(utf8.decode(res.bodyBytes));
    final out = <MManga>[];
    final seen = <String>{};
    for (final media in doc.querySelectorAll('div.media')) {
      final a = media.querySelector('a.thumbnail, a[href*="/"]');
      final heading = media.querySelector('h5 a, .media-heading a');
      final img = media.querySelector('img');
      final href = heading?.attributes['href'] ?? a?.attributes['href'];
      if (href == null) continue;
      final link = href.startsWith('http') ? href : '$_base$href';
      // Only detail pages (site-root slugs), not nav/filter links.
      final path = Uri.parse(link).path;
      if (path.isEmpty || path == '/' || path.startsWith('/manga-list')) {
        continue;
      }
      final name = heading?.text.trim();
      if (name == null || name.isEmpty || !seen.add(link)) continue;
      String? cover = img?.attributes['src'];
      if (cover != null && cover.startsWith('/')) cover = '$_base$cover';
      out.add(MManga(
        name: name,
        link: link,
        imageUrl: cover,
        isManga: true,
        source: source.idString,
      ));
    }
    return out;
  }

  @override
  Future<List<MManga>> getLatestUpdates(int page) async {
    if (page > 1) return const [];
    final res = await _http
        .get(Uri.parse('$_base/latest-release'), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MMRCMS latest → HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final out = <MManga>[];
    final seen = <String>{};
    // Chapter rows: href="<base>/<slug>/chapitre-N" — the PARENT manga is
    // the slug segment; one entry per manga (first row = newest chapter).
    final rx = RegExp(r'href="([^"]+/([a-z0-9-]+)/chapitre-\d+[^"]*)"',
        caseSensitive: false);
    for (final m in rx.allMatches(body)) {
      final slug = m.group(2)!;
      final link = '$_base/$slug';
      if (!seen.add(slug)) continue;
      out.add(MManga(
        name: _titleFromSlug(slug),
        link: link,
        // Cover is deterministic: /uploads/manga/<slug>/cover/cover_250x350.jpg
        imageUrl: '$_base/uploads/manga/$slug/cover/cover_250x350.jpg',
        isManga: true,
        source: source.idString,
      ));
    }
    return out;
  }

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async {
    if (query.trim().isEmpty || page > 1) return const [];
    final res = await _http.get(
        Uri.parse('$_base/search')
            .replace(queryParameters: {'query': query.trim()}),
        headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MMRCMS search → HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final suggestions =
        ((decoded as Map)['suggestions'] as List?) ?? const [];
    return [
      for (final s in suggestions)
        if (s is Map && s['data'] is String && (s['data'] as String).isNotEmpty)
          MManga(
            name: (s['value'] as String?) ?? (s['data'] as String),
            link: '$_base/${s['data']}',
            imageUrl: '$_base/uploads/manga/${s['data']}/cover/cover_250x350.jpg',
            isManga: true,
            source: source.idString,
          ),
    ];
  }

  String _titleFromSlug(String slug) => slug
      .split(RegExp(r'[-_]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  // -----------------------------------------------------------------------
  // Detail + chapters (single page)
  // -----------------------------------------------------------------------

  @override
  Future<MManga> getMangaDetail(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MMRCMS detail → HTTP ${res.statusCode}');
    }
    final doc = html_parser.parse(utf8.decode(res.bodyBytes));
    final manga = MManga(
      name: _titleFromSlug(url.split('/').last),
      link: url,
      isManga: true,
      source: source.idString,
    );

    final h1 = doc.querySelector('h2, h1, .title');
    if (h1 != null && h1.text.trim().isNotEmpty) manga.name = h1.text.trim();

    final img = doc.querySelector('img[src*="cover"], .cover img, .thumbnail img');
    String? cover = img?.attributes['src'];
    if (cover != null && cover.startsWith('/')) cover = '$_base$cover';
    if (cover != null) manga.imageUrl = cover;

    // Synopsis.
    final desc = doc.querySelector('.well, .summary, .description, '
        '.manga-details, .detail .content');
    if (desc != null) {
      final t = desc.text.trim();
      if (t.isNotEmpty && t.length < 2000) manga.description = t;
    }

    // Genres.
    final genres = <String>[];
    for (final a in doc.querySelectorAll('a[href*="genre"], .label a')) {
      final g = a.text.trim();
      if (g.isNotEmpty && g.length < 30) genres.add(g);
    }
    if (genres.isNotEmpty) {
      manga.categories = genres.take(12).toList();
      manga.genre = genres.take(12).join(',');
    }

    // Status / author from the info rows.
    for (final el in doc.querySelectorAll('dl dd, .manga-info li, .info p, '
        'table tr')) {
      final t = el.text.trim();
      final lower = t.toLowerCase();
      if (manga.author == null && lower.contains('auteur')) {
        manga.author = _afterColon(t, 'auteur');
      }
      if (lower.contains('statut') || lower.contains('status')) {
        final s = _afterColon(t, lower.contains('statut') ? 'statut' : 'status');
        manga.status = s.contains('cours')
            ? '1'
            : s.contains('termin') || s.contains('complete')
                ? '2'
                : '0';
      }
    }
    return manga;
  }

  String _afterColon(String text, String label) {
    final i = text.toLowerCase().indexOf(label);
    if (i < 0) return text.trim();
    final rest = text.substring(i + label.length).trim();
    return rest.replaceFirst(':', '').trim();
  }

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    if (res.statusCode != 200) {
      throw StateError('MMRCMS chapters → HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final out = <MChapter>[];
    final rx = RegExp(r'href="([^"]+/chapitre-(\d+)[^"]*)"[^>]*>([^<]+)<');
    final seen = <String>{};
    for (final m in rx.allMatches(body)) {
      final link = m.group(1)!.startsWith('http') ? m.group(1)! : '$_base${m.group(1)!}';
      if (!seen.add(link)) continue;
      final num = m.group(2)!;
      final name = m.group(3)!.trim();
      final parsed = double.tryParse(num);
      out.add(MChapter(
        name: name.isEmpty ? 'Chapitre $num' : name,
        url: link,
        chapterNumber: parsed?.toString(),
      ));
    }
    out.sort((a, b) => (double.tryParse(b.chapterNumber ?? '') ?? 0)
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
      throw StateError('MMRCMS chapter → HTTP ${res.statusCode}');
    }
    final doc = html_parser.parse(utf8.decode(res.bodyBytes));
    final pages = <String>[];
    for (final img in doc.querySelectorAll('img')) {
      final src = (img.attributes['src'] ?? img.attributes['data-src'] ?? '')
          .trim();
      // Chapter pages live under /uploads/manga/<slug>/chapters/… — this
      // filter skips ads/avatars/UI icons.
      if (src.contains('/uploads/manga/') && src.contains('/chapters/')) {
        pages.add(src);
      }
    }
    if (pages.isEmpty) {
      throw StateError('MMRCMS: no pages at $url (layout change?)');
    }
    return pages;
  }

  @override
  Future<void> dispose() async {
    _client?.close();
    _client = null;
  }
}
