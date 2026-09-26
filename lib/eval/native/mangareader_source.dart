// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NATIVE MangaReader multisrc template — covers the 87 mangareader-family
// extensions in the official Mangayomi extension repo (index.json
// `typeSource: "mangareader"`). Port of upstream's
// dart/manga/multisrc/mangareader/mangareader.dart (kodjodove, Apache-2.0),
// adapted to the html package (no :contains() — approximate with the stable
// class selectors).
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/template_utils.dart';
import 'package:lumina_reader/services/http/m_client.dart';

class MangaReaderSource extends BaseExtensionService {
  /// Optional injected client (fixture tests). When null a real MClient is
  /// created lazily — same injection seam as MadaraSource / MangaDexSource.
  MangaReaderSource(super.source, {http.Client? client}) : _client = client;

  http.Client? _client;

  /// Chapters parsed during getMangaDetail, keyed by detail URL (the
  /// coordinator's detail + chapterList pair reuses one page fetch).
  final _chapterCache = <String, List<MChapter>>{};

  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 20),
      );

  @override
  Future<Map<String, String>> getHeaders() async => {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36',
        'Referer': '${getBaseUrl()}/',
      };

  String getBaseUrl() {
    final b = source.displayBaseUrl;
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  bool get _isSushiScan => source.displayName == 'Sushi-Scan';

  String get _mangaDirectory => _isSushiScan ? '/catalogue' : '/manga';

  // -----------------------------------------------------------------------
  // Catalog
  // -----------------------------------------------------------------------

  @override
  Future<List<MManga>> getPopular(int page) => _browse(page, 'popular');

  @override
  Future<List<MManga>> getLatestUpdates(int page) => _browse(page, 'update');

  Future<List<MManga>> _browse(int page, String order) async {
    final res = await _http.get(
      Uri.parse(
          '${getBaseUrl()}$_mangaDirectory/?page=$page&order=$order'),
      headers: await getHeaders(),
    );
    _ensureOk(res, 'browse');
    return _mangaRes(_decode(res));
  }

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async {
    final path = _isSushiScan
        ? '/page/$page/?s=${Uri.encodeQueryComponent(query)}'
        : '/?s=${Uri.encodeQueryComponent(query)}&page=$page';
    final res = await _http.get(Uri.parse('${getBaseUrl()}$path'),
        headers: await getHeaders());
    _ensureOk(res, 'search');
    return _mangaRes(_decode(res));
  }

  List<MManga> _mangaRes(String body) {
    final document = html_parser.parse(body);
    final elements = <dom.Element>[
      ...document.querySelectorAll('.utao .uta .imgu'),
      ...document.querySelectorAll('.listupd .bs .bsx'),
      ...document.querySelectorAll('.listo .bs .bsx'),
    ];
    final list = <MManga>[];
    for (final element in elements) {
      final a = element.querySelector('a');
      if (a == null) continue;
      var img = element.querySelector('img')?.attributes['src'] ?? '';
      if (img.contains('data:image')) {
        img = element.querySelector('img')?.attributes['data-src'] ?? img;
      }
      final name = a.attributes['title']?.trim();
      final href = a.attributes['href'] ?? '';
      if (name == null || name.isEmpty || href.isEmpty) continue;
      list.add(MManga(
        name: name,
        link: _absolute(href),
        imageUrl: img.isEmpty ? null : img,
        isManga: true,
        source: source.idString,
      ));
    }
    return list;
  }

  String _absolute(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    return '${getBaseUrl()}${href.startsWith('/') ? '' : '/'}$href';
  }

  // -----------------------------------------------------------------------
  // Detail
  // -----------------------------------------------------------------------

  @override
  Future<MManga> getMangaDetail(String url) async {
    final withoutDomain = _stripDomain(url);
    final res = await _http.get(Uri.parse('${getBaseUrl()}$withoutDomain'),
        headers: await getHeaders());
    _ensureOk(res, 'detail');
    final document = html_parser.parse(_decode(res));

    final seriesDetails = document.querySelector('div.bigcontent') ??
        document.querySelector('div.animefull') ??
        document.querySelector('div.main-info') ??
        document.querySelector('div.postbody');

    final manga = MManga(
      name: _parseDetailTitle(document),
      link: url,
      isManga: true,
      source: source.idString,
    );

    if (seriesDetails != null) {
      // Author — upstream uses huge multilingual :contains() selector lists;
      // the stable class-based equivalents cover the same elements.
      for (final sel in [
        '.tsinfo .imptdt i',
        '.fmed span',
        '.author-content a',
      ]) {
        final el = seriesDetails.querySelector(sel);
        if (el != null && el.text.trim().isNotEmpty) {
          manga.author = el.text.trim();
          break;
        }
      }

      final desc = seriesDetails.querySelector('.desc') ??
          seriesDetails.querySelector('.entry-content[itemprop=description]');
      manga.description =
          desc == null ? null : desc.text.trim().isEmpty ? null : desc.text.trim();

      // Status.
      String? statusText;
      for (final sel in ['.imptdt', '.status', '.tsinfo']) {
        final el = seriesDetails.querySelector(sel);
        if (el != null && el.text.trim().isNotEmpty) {
          statusText = el.text.trim();
          break;
        }
      }
      manga.status = parseStatus(statusText);

      final categories = <String>{};
      for (final container in ['.gnr', '.mgen', '.seriestugenre']) {
        categories.addAll(seriesDetails
            .querySelectorAll('$container a')
            .map((e) => e.text.trim())
            .where((t) => t.isNotEmpty));
      }
      manga.categories = categories.toList();
    }

    // Chapters.
    final chapterItems = <dom.Element>[
      ...document.querySelectorAll('div.bxcl li'),
      ...document.querySelectorAll('div.cl li'),
      ...document.querySelectorAll('#chapterlist li'),
    ];
    final chapters = <MChapter>[];
    final seenUrls = <String>{};
    for (final element in chapterItems) {
      final urlElement = element.querySelector('a');
      if (urlElement == null) continue;
      final href = urlElement.attributes['href'] ?? '';
      if (href.isEmpty || !seenUrls.add(href)) continue;
      final name = element.querySelector('.lch a')?.text.trim() ??
          element.querySelector('.chapternum')?.text.trim() ??
          urlElement.text.trim();
      final dateText = element.querySelector('.chapterdate')?.text ?? '';
      chapters.add(MChapter(
        name: name.isEmpty ? 'Chapter' : name,
        url: _absolute(href),
        dateUpload: parseChapterDate(
          dateText.isEmpty ? 'today' : dateText,
          dateFormat: source.dateFormat,
          dateFormatLocale: source.dateFormatLocale,
        ).toString(),
      ));
    }
    _chapterCache[url] = chapters;
    return manga;
  }

  /// Series title — MangaReader themes use `h1.entry-title` (with the
  /// `.entry-title` / `.seriestual h1` variants). Same live-verified
  /// regression as Madara: an empty detail name produced nameless library
  /// rows after "Add to library".
  String _parseDetailTitle(dom.Document document) {
    for (final sel in [
      'h1.entry-title',
      '.seriestual h1',
      '.seriestuheader h1',
      'h1.post-title',
      'div.infox h1',
    ]) {
      final el = document.querySelector(sel);
      final text = el?.text.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final cached = _chapterCache[url];
    if (cached != null) return cached;
    await getMangaDetail(url); // populates the cache
    return _chapterCache[url] ?? const [];
  }

  String _stripDomain(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.path + (uri.hasQuery ? '?${uri.query}' : '');
  }

  // -----------------------------------------------------------------------
  // Pages
  // -----------------------------------------------------------------------

  @override
  Future<List<String>> getPageList(String url) async {
    final withoutDomain = _stripDomain(url);
    final res = await _http.get(Uri.parse('${getBaseUrl()}$withoutDomain'),
        headers: await getHeaders());
    _ensureOk(res, 'page list');
    // EFFICIENCY + correctness: decode once (UTF-8, not latin-1 `.body`)
    // and parse the document ONCE — each _readerAreaImages call used to
    // re-parse the whole megabyte-scale body (up to 3 parses per chapter).
    final body = _decode(res);
    final doc = html_parser.parse(body);

    // readerarea images — <p><img> first (upstream order), then bare <img>,
    // then data-src when the src set is a placeholder.
    var pages = _readerAreaImagesFrom(doc, 'src', wrapInP: true);
    if (pages.length <= 1) {
      pages = _readerAreaImagesFrom(doc, 'src', wrapInP: false);
    }
    if (pages.any((p) => p.contains('data:image'))) {
      pages = _readerAreaImagesFrom(doc, 'data-src', wrapInP: false);
    }
    if (pages.length > 1) return pages;

    // JSON "images": [...] fallback (lazy themes).
    final match = RegExp(r'"images"\s*:\s*(\[.*?\])').firstMatch(body);
    if (match != null) {
      try {
        final list = jsonDecode(match.group(1)!) as List;
        return list.whereType<String>().toList();
      } catch (_) {}
    }
    return pages;
  }

  /// Guard: non-200 responses were parsed as content (CF interstitials
  /// yielded a silently empty catalog instead of an honest error).
  void _ensureOk(http.Response res, String what) {
    if (res.statusCode != 200) {
      throw StateError('MangaReader $what failed: HTTP ${res.statusCode} '
          '— site may be blocked or down');
    }
  }

  /// UTF-8 from raw bytes — `.body` falls back to latin-1 when the response
  /// has no charset header (mojibake on non-English mirrors).
  String _decode(http.Response res) => utf8.decode(res.bodyBytes);

  List<String> _readerAreaImagesFrom(dom.Document doc, String attr,
      {required bool wrapInP}) {
    final area = doc.querySelector('#readerarea');
    if (area == null) return const [];
    final imgs = wrapInP
        ? area.querySelectorAll('p img')
        : area.querySelectorAll('img');
    return [
      for (final img in imgs)
        if ((img.attributes[attr] ?? '').isNotEmpty) img.attributes[attr]!,
    ];
  }

  /// Novel chapters on MangaReader themes carry text in `#readerarea` as
  /// <p> paragraphs. Mirrors [MadaraSource.getChapterContent].
  @override
  Future<String?> getChapterContent(String url) async {
    final withoutDomain = _stripDomain(url);
    final res = await _http.get(Uri.parse('${getBaseUrl()}$withoutDomain'),
        headers: await getHeaders());
    // Tolerant by contract (mirrors MadaraSource.getChapterContent): a
    // missing text chapter degrades to null instead of throwing.
    if (res.statusCode != 200) return null;
    final doc = html_parser.parse(_decode(res));
    final area = doc.querySelector('#readerarea') ??
        doc.querySelector('div.reading-content');
    if (area == null) return null;

    area.querySelectorAll('script, style').forEach((e) => e.remove());

    final paragraphs = area.querySelectorAll('p');
    final buffer = StringBuffer();
    if (paragraphs.isNotEmpty) {
      for (final p in paragraphs) {
        final text = p.text.trim();
        if (text.isEmpty) continue;
        buffer.write('<p>${_escapeHtml(text)}</p>');
      }
    } else {
      final text = area.text.trim();
      if (text.isEmpty) return null;
      for (final line in text.split('\n')) {
        final l = line.trim();
        if (l.isEmpty) continue;
        buffer.write('<p>${_escapeHtml(l)}</p>');
      }
    }
    final html = buffer.toString();
    return html.isEmpty ? null : html;
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  Future<void> dispose() async {
    _chapterCache.clear();
    _client?.close();
    _client = null;
  }
}
