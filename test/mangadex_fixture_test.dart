// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// FIXTURE test of the native MangaDex source — validates the full parsing
// pipeline (popular list, detail, chapter feed, at-home page list) against
// real JSON captured from api.mangadex.org (2026-09). Network-independent,
// so CI stays green; refresh the fixtures with curl when the API drifts.
//
// Companion of madara_fixture_test.dart. The live-network variant lives in
// live_mangadex_test.dart (manual only — some CI sandboxes block dart:io
// egress).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/mangadex_source.dart';
import 'package:lumina_reader/models/source.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

http.Response _json(String body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Client _fixtureClient() {
  return MockClient((request) async {
    final url = request.url.toString();
    if (url.contains('/manga?')) {
      return _json(_fixture('mangadex_popular.json'));
    }
    // NOTE: the /feed check MUST precede the /manga/<uuid> detail pattern —
    // the feed URL also contains /manga/<uuid>.
    if (url.contains('/feed')) {
      return _json(_fixture('mangadex_feed.json'));
    }
    if (url.contains(RegExp(r'/manga/[0-9a-f-]{36}'))) {
      return _json(_fixture('mangadex_detail.json'));
    }
    if (url.contains('/at-home/server/')) {
      return _json(_fixture('mangadex_athome.json'));
    }
    return _json('{"result":"error"}', 404);
  });
}

void main() {
  final source = MangaDexSource(
    Source(
      idString: 'builtin.mangadex',
      name: 'MangaDex',
      lang: 'en',
      baseUrl: 'https://api.mangadex.org',
      isManga: true,
      sourceCodeLanguage: SourceCodeLanguage.dart,
      sourceCode: 'builtin:mangadex',
    ),
    client: _fixtureClient(),
  );

  test('popular parses entries with titles, links and cover URLs', () async {
    final entries = await source.getPopular(1);
    expect(entries, isNotEmpty);
    for (final e in entries.take(3)) {
      expect(e.name, isNotNull,
          reason: 'title fallback (en → altTitles → any) must always '
              'produce a displayable name');
      expect(e.link, contains('api.mangadex.org/manga/'));
      expect(e.imageUrl ?? '', contains('uploads.mangadex.org/covers/'));
    }
  });

  test('detail parses description, status, author and cover', () async {
    final entries = await source.getPopular(1);
    final detail = await source.getMangaDetail(entries.first.link!);
    expect(detail.name, isNotEmpty);
    expect(detail.imageUrl ?? '', contains('uploads.mangadex.org/covers/'));
    // The fixture entry carries author/artist relationships — the parser
    // must lift at least a name out of them.
    expect(detail.author ?? detail.artist ?? '', isNotEmpty,
        reason: 'author or artist should be parsed from relationships');
  });

  test('chapter feed parses numbers, scanlators and chapter URLs', () async {
    final entries = await source.getPopular(1);
    final chapters = await source.getChapterList(entries.first.link!);
    expect(chapters, isNotEmpty);
    expect(chapters.first.url, contains('mangadex.org/chapter/'));
    // The coordinator maps chapterNumber through double.tryParse — a null
    // here would silently become 0 and break ordering.
    expect(chapters.first.chapterNumber, isNotNull);
    // publishAt → dateUpload (millis string) — the coordinator parses it
    // back with DateTime.tryParse.
    expect(chapters.first.dateUpload, isNotNull);
  });

  test('at-home server response builds the page image URL list', () async {
    final entries = await source.getPopular(1);
    final chapters = await source.getChapterList(entries.first.link!);
    final pages = await source.getPageList(chapters.first.url!);
    expect(pages, isNotEmpty,
        reason: 'the reader renders this list — empty means a dead reader');
    for (final p in pages) {
      expect(p, startsWith('http'));
      expect(p, contains('/data/'));
    }
  });

  test('search reuses the list pipeline (title= param)', () async {
    final results = await source.searchManga(
      query: 'frieren',
      page: 1,
      filterList: const FilterList(filters: []),
    );
    expect(results, isNotEmpty);
    expect(results.first.link, isNotEmpty);
  });
}
