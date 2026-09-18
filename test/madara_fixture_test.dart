// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// FIXTURE test of the native Madara template — validates the full parsing
// pipeline (popular list, detail page, chapter list, page images) against
// real HTML captured from ksgroupscans.com (an entry from the official
// Mangayomi extension index). Network-independent, so CI stays green.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumina_reader/eval/native/madara_source.dart';
import 'package:lumina_reader/models/source.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

http.Response _html(String body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

http.Client _fixtureClient() {
  return MockClient((request) async {
    final url = request.url.toString();
    // Chapter list XHR: admin-ajax returns WordPress "0" (this site), the
    // /ajax/chapters fallback returns the real list.
    if (url.contains('admin-ajax.php')) {
      return _html('0');
    }
    if (url.endsWith('/ajax/chapters')) {
      return _html(_fixture('madara_chapters2.html'));
    }
    if (url.contains('m_orderby=views')) {
      return _html(_fixture('madara_popular.html'));
    }
    if (url.contains('/chapter-')) {
      return _html(_fixture('madara_chapter.html'));
    }
    if (url.contains('hell-mode')) {
      return _html(_fixture('madara_detail.html'));
    }
    return _html('not found', 404);
  });
}

void main() {
  final source = Source(
    idString: 'test-ksgroupscans',
    name: 'KSGroupScans',
    lang: 'en',
    baseUrl: 'https://ksgroupscans.com',
    version: '0.1.3',
    typeSource: 'madara',
    dateFormat: 'MMMM dd, yyyy',
    dateFormatLocale: 'en_us',
    isManga: true,
    sourceCodeLanguage: SourceCodeLanguage.dart,
    sourceCode: 'builtin:madadex'.replaceAll('madadex', 'madara'),
  );

  MadaraSource makeService() => MadaraSource(source, client: _fixtureClient());

  test('popular page parses 12 entries with names, links and covers', () async {
    final entries = await makeService().getPopular(1);
    expect(entries.length, 12);
    for (final e in entries) {
      expect(e.name, isNotEmpty);
      expect(e.link, startsWith('https://ksgroupscans.com/'));
      expect(e.imageUrl, isNotNull);
    }
  });

  test('detail page parses description and genres', () async {
    final detail = await makeService().getMangaDetail(
        'https://ksgroupscans.com/manga/'
        'hell-mode-yarikomi-suki-no-gamer-wa-hai-settei-no-isekai-de-musou-suru/');
    expect(detail.description ?? '', isNotEmpty);
    expect(detail.categories, isNotEmpty);
  });

  test('chapter list falls back to /ajax/chapters and parses 127 chapters',
      () async {
    final chapters = await makeService().getChapterList(
        'https://ksgroupscans.com/manga/'
        'hell-mode-yarikomi-suki-no-gamer-wa-hai-settei-no-isekai-de-musou-suru/');
    expect(chapters.length, 127);
    expect(chapters.first.name, isNotEmpty);
    expect(chapters.first.url, contains('/chapter-'));
    // dateUpload must be epoch-milliseconds (parsable int).
    expect(int.tryParse(chapters.first.dateUpload ?? 'x'), isNotNull);
  });

  test('chapter page parses the image list', () async {
    final pages = await makeService().getPageList(
        'https://ksgroupscans.com/manga/'
        'hell-mode-yarikomi-suki-no-gamer-wa-hai-settei-no-isekai-de-musou-suru/'
        'chapter-103-2/');
    expect(pages.length, greaterThan(5));
    expect(pages.first, startsWith('http'));
  });
}
