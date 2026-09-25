// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NATIVE Madara (WordPress) multisrc template — covers the 151 Madara-family
// extensions in the official Mangayomi extension repo (index.json
// `typeSource: "madara"`). Behaviour is a 1:1 port of upstream's
// dart/manga/multisrc/madara/madara.dart (kodjodove, Apache-2.0), adapted to
// the html package (no :has()/:contains() selectors — manual filtering).
//
// Config per site (from the repo index): baseUrl, dateFormat,
// dateFormatLocale, additionalParams.
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/template_utils.dart';
import 'package:lumina_reader/services/http/m_client.dart';

class MadaraSource extends BaseExtensionService {
  /// Optional injected client (fixture tests). When null a real MClient is
  /// created lazily.
  MadaraSource(super.source, {http.Client? client}) : _client = client;

  http.Client? _client;

  /// Chapters parsed during getMangaDetail, keyed by detail URL — the
  /// coordinator calls getMangaDetail + getChapterList back-to-back, and
  /// Madara needs the same page fetch for both (saves a round-trip).
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

  /// Some Madara sites rename the /manga path segment (upstream map).
  String getMangaSubString() {
    const sourceTypeMap = {
      'Olaoe': 'works',
      'Mangax Core': 'works',
      'Azora': 'series',
      'Manga Crab': 'series',
      'KlikManga': 'series',
      'Hwago': 'komik',
    };
    return sourceTypeMap[source.displayName] ?? 'manga';
  }

  // -----------------------------------------------------------------------
  // Catalog
  // -----------------------------------------------------------------------

  @override
  Future<List<MManga>> getPopular(int page) =>
      _browse(page, 'views');

  @override
  Future<List<MManga>> getLatestUpdates(int page) =>
      _browse(page, 'latest');

  Future<List<MManga>> _browse(int page, String orderBy) async {
    final res = await _http.get(
      Uri.parse(
          '${getBaseUrl()}/${getMangaSubString()}/page/$page/?m_orderby=$orderBy'),
      headers: await getHeaders(),
    );
    final doc = html_parser.parse(res.body);
    return _mangaFromElements([
      ...doc.querySelectorAll('div.page-item-detail'),
      ...doc.querySelectorAll('div.manga__item'),
    ]);
  }

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async {
    final url =
        '${getBaseUrl()}/?s=${Uri.encodeQueryComponent(query)}&post_type=wp-manga';
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    final doc = html_parser.parse(res.body);
    return _mangaFromElements(doc.querySelectorAll('div.c-tabs-item__content'));
  }

  List<MManga> _mangaFromElements(List<dom.Element> elements) {
    final list = <MManga>[];
    for (final el in elements) {
      // "div.post-title a:not(:has(span.manga-title-badges))" — the html
      // package has no :has(); filter manually.
      dom.Element? postTitle;
      for (final a in el.querySelectorAll('div.post-title a')) {
        if (a.querySelector('span.manga-title-badges') == null) {
          postTitle = a;
          break;
        }
      }
      if (postTitle == null) continue;
      final href = postTitle.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final image = extractImageUrl(el.querySelector('img'));

      list.add(MManga(
        name: postTitle.text.trim(),
        link: _absolute(href),
        imageUrl: image == null ? null : substringBefore(image, ' '),
        isManga: true,
        source: source.idString,
      ));
    }
    return list;
  }

  /// Resolves relative hrefs against the site base URL.
  String _absolute(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    return '$getBaseUrl()${href.startsWith('/') ? '' : '/'}$href';
  }

  // -----------------------------------------------------------------------
  // Detail
  // -----------------------------------------------------------------------

  @override
  Future<MManga> getMangaDetail(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    final document = html_parser.parse(res.body);

    final manga = MManga(
      name: _parseDetailTitle(document),
      link: url,
      isManga: true,
      source: source.idString,
    );
    manga.author =
        document.querySelector('div.author-content > a')?.text.trim() ?? '';

    // Description — upstream tries several containers and prefers their <p>
    // contents joined with blank lines.
    final descSelectors = [
      'div.summary_content div.post-content_item > h5 + div',
      'div.summary_content div.manga-excerpt',
      '.manga-summary',
      'div.c-page__content div.modal-contenido',
    ];
    String? description;
    // Primary container (most Madara themes).
    final primary = document
        .querySelector('div.description-summary div.summary__content');
    if (primary != null) {
      final paragraphs = primary.querySelectorAll('p');
      final nonEmpty =
          paragraphs.where((p) => p.text.trim().isNotEmpty).toList();
      description = nonEmpty.isNotEmpty
          ? nonEmpty.map((p) => p.text.trim()).join('\n\n')
          : primary.text.trim();
    }
    if (description == null || description.isEmpty) {
      for (final sel in descSelectors) {
        final el = document.querySelector(sel);
        if (el != null && el.text.trim().isNotEmpty) {
          description = el.text.trim();
          break;
        }
      }
    }
    manga.description =
        (description == null || description.isEmpty) ? null : description;

    manga.imageUrl = extractImageUrl(
        document.querySelector('div.summary_image img'));

    // Status — upstream queries several summary containers; approximate by
    // scanning the known status-value containers.
    String? statusText;
    for (final sel in [
      '.summary-content > .tags-content',
      'div.summary-content',
    ]) {
      final el = document.querySelector(sel);
      if (el != null && el.text.trim().isNotEmpty) {
        statusText = el.text.trim();
        break;
      }
    }
    manga.status = parseStatus(statusText);

    manga.categories = document
        .querySelectorAll('div.genres-content a')
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // Chapters — XHR: admin-ajax.php (older themes) with /ajax/chapters
    // fallback (newer themes).
    final holder =
        document.querySelector('div[id^=manga-chapters-holder]');
    final mangaId = holder?.attributes['data-id'] ?? '';

    final headers = {
      'Referer': '${getBaseUrl()}/',
      'X-Requested-With': 'XMLHttpRequest',
    };
    String chaptersHtml;
    final ajax = await _http.post(
      Uri.parse('${getBaseUrl()}/wp-admin/admin-ajax.php'),
      headers: headers,
      body: {'action': 'manga_get_chapters', 'manga': mangaId},
    );
    if (ajax.statusCode == 400) {
      chaptersHtml = await _postChapterAjax(url, headers);
    } else {
      chaptersHtml = ajax.body;
    }
    var chapters = _parseChapters(chaptersHtml);
    if (chapters.isEmpty) {
      chaptersHtml = await _postChapterAjax(url, headers);
      chapters = _parseChapters(chaptersHtml);
    }
    _chapterCache[url] = chapters;
    return manga;
  }

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final cached = _chapterCache[url];
    if (cached != null) return cached;
    await getMangaDetail(url); // populates the cache
    return _chapterCache[url] ?? const [];
  }

  /// Series title — Madara themes render it as `div.post-title h1`/`h3`
  /// (some also use `.series-title` / `h1.entry-title`). Live-verified
  /// regression: the detail object used to ship an EMPTY name, and because
  /// the Browse → detail → "Add to library" flow persists the FETCHED
  /// detail, library rows saved from Madara sources were nameless.
  String _parseDetailTitle(dom.Document document) {
    for (final sel in [
      'div.post-title h1',
      'div.post-title h3',
      'div.post-title',
      '.series-title h2',
      'h1.entry-title',
    ]) {
      final el = document.querySelector(sel);
      final text = el?.text.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Future<String> _postChapterAjax(
      String url, Map<String, String> headers) async {
    final target = url.endsWith('/') ? '${url}ajax/chapters' : '$url/ajax/chapters';
    final res = await _http.post(Uri.parse(target), headers: headers);
    return res.body;
  }

  List<MChapter> _parseChapters(String html) {
    if (html.isEmpty) return const [];
    final doc = html_parser.parse(html);
    final chapters = <MChapter>[];
    for (final element in doc.querySelectorAll('li.wp-manga-chapter')) {
      final a = element.querySelector('a');
      if (a == null) continue;
      var url = a.attributes['href'] ?? '';
      if (url.isEmpty) continue;
      url = substringBefore(url, '?style=paged');
      final dateText =
          element.querySelector('span.chapter-release-date')?.text ?? '';
      final dateUpload = dateText.trim().isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : parseChapterDate(
              dateText,
              dateFormat: source.dateFormat,
              dateFormatLocale: source.dateFormatLocale,
            ).toString();
      chapters.add(MChapter(
        name: a.text.trim(),
        url: _absolute(url),
        dateUpload: dateUpload,
      ));
    }
    return chapters;
  }

  // -----------------------------------------------------------------------
  // Pages
  // -----------------------------------------------------------------------

  @override
  Future<List<String>> getPageList(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    final document = html_parser.parse(res.body);

    var images = _imagesFromPage(document);
    if (images.length == 1) {
      images = _buildPageUrls(images, document);
    }
    if (images.isNotEmpty) return images;
    return _parseProtectorImages(document);
  }

  /// Novel chapters on Madara themes carry the text in the SAME
  /// `div.reading-content` container that holds `div.page-break` images for
  /// manga — as <p> paragraphs instead of <img> tags. Returns the cleaned
  /// inner HTML so the novel reader can render it; `null` when the page has
  /// no text content (an image chapter / wrong URL).
  @override
  Future<String?> getChapterContent(String url) async {
    final res = await _http.get(Uri.parse(url), headers: await getHeaders());
    final document = html_parser.parse(res.body);
    final container = document.querySelector('div.reading-content') ??
        document.querySelector('div.entry-content') ??
        document.querySelector('article .entry-content');
    if (container == null) return null;

    // Strip reader noise: page-break image spacers, scripts, inline styles.
    container.querySelectorAll('script, style, .code-block, .adsbygoogle')
        .forEach((e) => e.remove());

    final paragraphs = container.querySelectorAll('p');
    final buffer = StringBuffer();
    if (paragraphs.isNotEmpty) {
      for (final p in paragraphs) {
        final text = p.text.trim();
        if (text.isEmpty) continue;
        // Basic sanitisation: escape raw < > so flutter_html renders text.
        buffer.write('<p>${_escapeHtml(text)}</p>');
      }
    } else {
      final text = container.text.trim();
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

  List<String> _imagesFromPage(dom.Document doc) {
    final urls = <String>[];
    // "div.page-break img" is the canonical Madara container; the gallery +
    // text-left selectors are theme variants.
    for (final sel in [
      'div.page-break img',
      'li.blocks-gallery-item img',
      '.reading-content .text-left img',
      '.reading-content img',
    ]) {
      for (final e in doc.querySelectorAll(sel)) {
        final u = extractImageUrl(e)?.trim();
        if (u != null && u.isNotEmpty && !urls.contains(u)) urls.add(u);
      }
      if (urls.isNotEmpty) break;
    }
    return urls;
  }

  /// Sites that only embed page 1 with a <select id="single-pager"> pager:
  /// generate the remaining URLs by replacing the 01 index.
  List<String> _buildPageUrls(List<String> imgs, dom.Document document) {
    final options = document.querySelectorAll('#single-pager option');
    if (options.isEmpty) return imgs;
    final pages = options.length;
    final imgUrl = imgs.first;
    final pageUrls = <String>[];
    for (var i = 0; i < pages; i++) {
      final val = i + 1;
      pageUrls.add(i.toString().length == 1
          ? imgUrl.replaceAll('01', '0$val')
          : imgUrl.replaceAll('01', '$val'));
    }
    return pageUrls;
  }

  /// "wpmangaprotector" — AES-encrypted image list embedded in the page.
  List<String> _parseProtectorImages(dom.Document document) {
    final container = document.querySelector('.chapter-protector') ??
        document.querySelector('#chapter-protector');
    final protectorData = container?.innerHtml;
    if (protectorData == null) return const [];

    final pwMatch =
        RegExp(r"wpmangaprotectornonce='(.*?)';").firstMatch(protectorData);
    final dataMatch =
        RegExp(r"chapter_data='(.*?)';").firstMatch(protectorData);
    if (pwMatch == null || dataMatch == null) return const [];
    final password = pwMatch.group(1)!;
    final chapterDataStr = dataMatch.group(1)!.replaceAll(r'\/', '/');

    try {
      final chapterData = jsonDecode(chapterDataStr) as Map<String, dynamic>;
      final salt = _hexToBytes(chapterData['s'] as String);
      final ct = base64Decode(chapterData['ct'] as String);
      final completeCipher =
          utf8.encode('Salted__') + salt + ct;
      final decrypted =
          CryptoAES.decryptAESCryptoJS(base64Encode(completeCipher), password);
      if (decrypted == null) return const [];
      final list = jsonDecode(jsonDecode(decrypted) as String) as List;
      return list.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  @override
  Future<void> dispose() async {
    _chapterCache.clear();
    _client?.close();
    _client = null;
  }
}
