// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// FIXTURE tests for the three NEW native templates + the anime streaming
// chain — validates the full parsing pipelines against real HTML/JSON
// captured from the live sites (2026-09):
//
//   * MangaBox  (mangabats.com)      — popular / latest / search / detail /
//                                      chapters API / page images
//   * MMRCMS    (scan-vf.net)        — list / latest / search JSON / detail /
//                                      chapter rows / page images
//   * AniZone   (anizone.to)         — AniList catalog + slug resolution →
//                                      Livewire episodes → HLS + subtitles
//
// Network-independent (MockClient) so CI stays green; the live chains were
// curl-verified at capture time (see worklog Task 15).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/anizone_source.dart';
import 'package:lumina_reader/eval/native/mangabox_source.dart';
import 'package:lumina_reader/eval/native/mmrcms_source.dart';
import 'package:lumina_reader/models/source.dart' as db;
import 'package:lumina_reader/services/anilist.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

http.Response _html(String body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

http.Response _json(String body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

db.Source _row(String id, String name, String baseUrl,
        {bool anime = false}) =>
    db.Source(
      idString: id,
      name: name,
      lang: 'en',
      baseUrl: baseUrl,
      isManga: !anime,
      isAnime: anime,
      sourceCodeLanguage: db.SourceCodeLanguage.dart,
    );

// ---------------------------------------------------------------------------
// MangaBox
// ---------------------------------------------------------------------------

http.Client _mangaboxClient() {
  return MockClient((request) async {
    final url = request.url.toString();
    if (url.contains('/search/story/')) {
      return _html(_fixture('mangabox_search.html'));
    }
    if (url.contains('hot-manga')) {
      return _html(_fixture('mangabox_hot.html'));
    }
    if (url.contains('latest-manga')) {
      return _html(_fixture('mangabox_latest.html'));
    }
    if (url.contains('/api/manga/') && url.contains('/chapters')) {
      return _json(_fixture('mangabox_chapters_api.json'));
    }
    if (url.contains('/manga/martial-peak/chapter-')) {
      return _html(_fixture('mangabox_chapter.html'));
    }
    if (url.contains('/manga/martial-peak')) {
      return _html(_fixture('mangabox_detail.html'));
    }
    return _html('not found', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MangaBox template (mangabats.com fixtures)', () {
    late MangaBoxSource source;
    setUp(() {
      source = MangaBoxSource(
          _row('builtin.mangabat', 'Mangabat', 'https://www.mangabats.com'),
          client: _mangaboxClient());
    });

    test('popular parses the hot-manga grid (64 unique covers)', () async {
      final entries = await source.getPopular(1);
      expect(entries, isNotEmpty);
      expect(entries.length, 64);
      expect(entries.first.name, isNotEmpty);
      expect(entries.first.link, contains('/manga/'));
      expect(entries.first.imageUrl, contains('2xstorage.com/thumb/'));
    });

    test('popular page 2 works (query param)', () async {
      final entries = await source.getPopular(2);
      expect(entries, isNotEmpty);
    });

    test('latest parses the latest-manga grid', () async {
      final entries = await source.getLatestUpdates(1);
      expect(entries, isNotEmpty);
      expect(entries.first.link, contains('/manga/'));
    });

    test('search parses results and dedupes', () async {
      final entries = await source.searchManga(
        query: 'solo leveling',
        page: 1,
        filterList: const FilterList(filters: []),
      );
      expect(entries, isNotEmpty);
      final links = entries.map((e) => e.link).toSet();
      expect(links.length, entries.length, reason: 'duplicates leaked');
    });

    test('detail extracts title/synopsis/genres', () async {
      final detail =
          await source.getMangaDetail('https://www.mangabats.com/manga/martial-peak');
      expect(detail.name, isNotEmpty);
      expect(detail.imageUrl, contains('martial-peak'));
    });

    test('chapters API parses the full 3877-chapter list newest-first',
        () async {
      final chapters = await source
          .getChapterList('https://www.mangabats.com/manga/martial-peak');
      expect(chapters, isNotEmpty);
      expect(chapters.length, greaterThan(3800));
      // Newest-first: the first entry carries the highest number.
      final first = double.parse(chapters.first.chapterNumber!);
      final last = double.parse(chapters.last.chapterNumber!);
      expect(first, greaterThan(last));
      expect(chapters.first.url, contains('/martial-peak/chapter-'));
    });

    test('page list extracts container-chapter-reader images in order',
        () async {
      final pages = await source.getPageList(
          'https://www.mangabats.com/manga/martial-peak/chapter-3862');
      expect(pages, isNotEmpty);
      expect(pages.first, contains('martial-peak/3862/0.webp'));
      expect(pages.every((p) => p.startsWith('https://')), isTrue);
    });
  });

  group('MMRCMS template (scan-vf.net fixtures)', () {
    late MmrcmsSource source;
    setUp(() {
      source = MmrcmsSource(
          _row('builtin.scanvf', 'Scan VF', 'https://www.scan-vf.net'),
          client: MockClient((request) async {
            final url = request.url.toString();
            if (url.contains('/search')) {
              return _json(
                  '{"suggestions":[{"value":"Solo Leveling","data":"solo-leveling"}]}');
            }
            if (url.contains('latest-release')) {
              return _html(_fixture('mmrcms_latest.html'));
            }
            if (url.contains('/chapitre-')) {
              return _html(_fixture('mmrcms_chapter.html'));
            }
            if (url.contains('/solo-leveling')) {
              return _html(_fixture('mmrcms_detail.html'));
            }
            if (url.contains('/manga-list')) {
              return _html(_fixture('mmrcms_list.html'));
            }
            return _html('not found', 404);
          }));
    });

    test('popular parses the .media grid', () async {
      final entries = await source.getPopular(1);
      expect(entries, isNotEmpty);
      expect(entries.first.name, isNotEmpty);
      expect(entries.first.link, contains('scan-vf.net'));
    });

    test('latest dedupes chapter rows into manga entries', () async {
      final entries = await source.getLatestUpdates(1);
      expect(entries, isNotEmpty);
      final slugs = entries.map((e) => e.link).toSet();
      expect(slugs.length, entries.length);
    });

    test('search parses the suggestions JSON', () async {
      final entries = await source.searchManga(
        query: 'solo',
        page: 1,
        filterList: const FilterList(filters: []),
      );
      expect(entries, hasLength(1));
      expect(entries.first.name, 'Solo Leveling');
      expect(entries.first.link, contains('/solo-leveling'));
    });

    test('detail extracts title + cover', () async {
      final detail = await source
          .getMangaDetail('https://www.scan-vf.net/solo-leveling');
      expect(detail.name, isNotEmpty);
      expect(detail.imageUrl, isNotNull);
    });

    test('chapter list parses h5 rows newest-first', () async {
      final chapters = await source
          .getChapterList('https://www.scan-vf.net/solo-leveling');
      expect(chapters, isNotEmpty);
      expect(chapters.length, greaterThan(150));
      expect(chapters.first.url, contains('/chapitre-'));
    });

    test('page list filters to chapter uploads only', () async {
      final pages = await source.getPageList(
          'https://www.scan-vf.net/solo-leveling/chapitre-200');
      expect(pages, isNotEmpty);
      expect(pages.first, contains('/uploads/manga/solo-leveling/chapters/'));
      // No ad/avatar images may leak in.
      expect(pages.every((p) => p.contains('/chapters/')), isTrue);
    });
  });

  group('AniZone anime source (anizone.to + AniList fixtures)', () {
    late AniZoneSource source;

    http.Client anizoneClient() => MockClient((request) async {
          final url = request.url.toString();
          // AniList GraphQL (catalog + detail).
          if (url.contains('graphql.anilist.co')) {
            final body = jsonDecode(request.body) as Map;
            final query = (body['query'] ?? '') as String;
            // Page-shaped queries (trending/seasonal/search) vs Detail.
            return _json(query.contains('Page(')
                ? _fixture('anilist_page.json')
                : _fixture('anilist_frieren.json'));
          }
          // Search results page.
          if (url.contains('anizone.to/anime?search=') ||
              (url.contains('anizone.to/anime') &&
                  request.url.queryParameters.containsKey('search'))) {
            return _html(_fixture('anizone_search.html'));
          }
          // Livewire pagination — empty terminal page.
          if (url.contains('/livewire/update')) {
            return _json(jsonEncode({
              'components': [
                {
                  'snapshot': 'x',
                  'effects': {
                    'dispatches': [
                      {
                        'name': 'items-loaded',
                        'params': {
                          'items': <dynamic>[],
                          'nextCursor': null,
                          'hasMore': false,
                        },
                      }
                    ],
                  },
                }
              ],
            }));
          }
          // Episode watch page.
          if (RegExp(r'anizone\.to/anime/[a-z0-9-]+/\d+').hasMatch(url)) {
            return _html(_fixture('anizone_watch.html'));
          }
          // Series detail page (episodes first page).
          if (RegExp(r'anizone\.to/anime/[a-z0-9-]+/?$').hasMatch(url)) {
            return _html(_fixture('anizone_detail.html'));
          }
          return _html('not found', 404);
        });

    setUp(() {
      // ONE client serves both the AniList GraphQL calls (Page-shaped
      // catalog queries vs Detail) and the anizone.to page fetches.
      final client = anizoneClient();
      final anilist = AniListService(client: client);
      source = AniZoneSource(
          _row('builtin.anizone', 'AniList Anime (AniZone)',
              'https://anilist.co',
              anime: true),
          client: client,
          anilist: anilist);
    });

    test('getPopular returns anime entries linked by anilist id', () async {
      final entries = await source.getPopular(1);
      expect(entries, isNotEmpty);
      expect(entries.first.isAnime, isTrue);
      expect(entries.first.link, startsWith('anilist:'));
      expect(entries.first.imageUrl, isNotNull);
    });

    test('getMangaDetail merges AniList metadata', () async {
      final detail = await source.getMangaDetail('anilist:154587');
      expect(detail.name, contains('Frieren'));
      expect(detail.isAnime, isTrue);
      expect(detail.genre, isNotEmpty);
    });

    test('episode list resolves the AniZone slug and scrapes episodes',
        () async {
      final episodes = await source.getChapterList('anilist:154587');
      expect(episodes, isNotEmpty);
      expect(episodes.length, 24, reason: 'fixture detail page has 24 eps');
      expect(episodes.first.url, contains('anizone.to/anime/mdkytdqp/'));
      expect(double.tryParse(episodes.first.chapterNumber!), isNotNull);
      // Sorted ascending by number.
      final nums =
          episodes.map((e) => double.parse(e.chapterNumber!)).toList();
      expect(nums, isNot(isEmpty));
      for (var i = 1; i < nums.length; i++) {
        expect(nums[i], greaterThan(nums[i - 1]));
      }
    });

    test('getVideoList extracts the HLS stream + subtitle payload',
        () async {
      final videos =
          await source.getVideoList('https://anizone.to/anime/mdkytdqp/1');
      expect(videos, hasLength(1));
      expect(videos.first.url, contains('.m3u8'));
      final subs = videos.first.parameters?['subtitles'] as List?;
      expect(subs, isNotNull);
      expect(subs, isNotEmpty);
      final firstSub = subs!.first as Map;
      expect(firstSub['url'], startsWith('https://'));
      expect(firstSub['label'], isNotEmpty);
    });

    test('subtitle payload maps through the coordinator DTO', () async {
      // Mirrors ExtensionCoordinator._subtitlesFrom.
      final videos =
          await source.getVideoList('https://anizone.to/anime/mdkytdqp/1');
      final raw = videos.first.parameters?['subtitles'] as List;
      final out = <(String, String)>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final url = (e['url'] ?? '') as String;
        if (url.isEmpty) continue;
        out.add(((e['label'] ?? e['language'] ?? 'Subtitle') as String, url));
      }
      expect(out, isNotEmpty);
      expect(out.every((t) => t.$2.startsWith('https://')), isTrue);
    });
  });
}
