// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// REGRESSION tests for the "extension system returns nothing" bug batch.
// Each test pins a live-verified failure mode:
//
//   1. MangaDex: every EN chapter licensed/external (Solo Leveling et al.)
//      used to yield ZERO chapters → language fallback now serves the
//      readable non-EN chapters with [lang]-tagged names.
//   2. MangaDex: single-language fallback keeps clean chapter names.
//   3. Madara: getMangaDetail used to ship an EMPTY name (library rows
//      saved from Browse were nameless) → post-title parsing.
//   4. MangaReader: same empty-name regression → entry-title parsing.
//   5. MChapter.copyWithName round-trips every field.
//
// All network is mocked; CI stays green.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/madara_source.dart';
import 'package:lumina_reader/eval/native/mangadex_source.dart';
import 'package:lumina_reader/eval/native/mangareader_source.dart';
import 'package:lumina_reader/models/source.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json'},
    );

/// UTF-8-safe HTML response (plain http.Response would latin1-encode and
/// throw on non-ASCII fixture content).
http.Response _html(String body, [int status = 200]) => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

Map<String, dynamic> _chapter(
  String id,
  String number,
  String lang, {
  String? externalUrl,
}) =>
    {
      'id': id,
      'type': 'chapter',
      'attributes': {
        'volume': '1',
        'chapter': number,
        'title': null,
        'translatedLanguage': lang,
        'externalUrl': externalUrl,
        'publishAt': '2026-01-01T00:00:00+00:00',
        'readableAt': '2026-01-01T00:00:00+00:00',
      },
      'relationships': const [],
    };

void main() {
  // -------------------------------------------------------------------
  // 1 + 2. MangaDex chapter language fallback.
  // -------------------------------------------------------------------
  group('MangaDex chapter fallback', () {
    MangaDexSource makeSource({
      required List<Map<String, dynamic>> enFeed,
      required List<Map<String, dynamic>> allFeed,
    }) {
      return MangaDexSource(
        Source(
          idString: 'builtin.mangadex',
          name: 'MangaDex',
          lang: 'en',
          baseUrl: 'https://api.mangadex.org',
          isManga: true,
          sourceCodeLanguage: SourceCodeLanguage.dart,
          sourceCode: 'builtin:mangadex',
        ),
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.contains('/feed')) {
            // EN-only query → enFeed; language-less fallback → allFeed.
            final isEn =
                url.contains('translatedLanguage%5B%5D=en') ||
                    url.contains('translatedLanguage[]=en');
            return _json({
              'result': 'ok',
              'total': isEn ? enFeed.length : allFeed.length,
              'data': isEn ? enFeed : allFeed,
            });
          }
          return _json({'result': 'error'}, 404);
        }),
      );
    }

    test('all-EN-licensed title falls back to other languages, tagged', () async {
      // Solo Leveling shape: every EN chapter is external (licensed), other
      // languages have readable chapters.
      final source = makeSource(
        enFeed: [
          _chapter('ext-1', '1', 'en',
              externalUrl: 'https://publisher.example/chapter-1'),
          _chapter('ext-2', '2', 'en',
              externalUrl: 'https://publisher.example/chapter-2'),
        ],
        allFeed: [
          _chapter('ka-1', '1', 'ka'),
          _chapter('pt-1', '1', 'pt-br'),
          _chapter('ka-2', '2', 'ka'),
        ],
      );

      final chapters =
          await source.getChapterList('https://api.mangadex.org/manga/solo-leveling');
      expect(chapters, isNotEmpty,
          reason: 'the #1 popular title must not show zero chapters');
      expect(chapters.length, 3);
      // External chapters never leak into the reader (they cannot render).
      expect(chapters.every((c) => !c.url!.contains('ext-')), isTrue);
      // Mixed languages → every name carries its language tag (order is
      // the feed's newest-first sort, not insertion order).
      expect(chapters.map((c) => c.language).toSet(), {'ka', 'pt-br'});
      for (final c in chapters) {
        expect(c.name, contains('[${c.language}]'));
      }
    });

    test('single-language fallback keeps clean names', () async {
      final source = makeSource(
        enFeed: const [],
        allFeed: [
          _chapter('ka-1', '1', 'ka'),
          _chapter('ka-2', '2', 'ka'),
        ],
      );
      final chapters = await source
          .getChapterList('https://api.mangadex.org/manga/solo-leveling');
      expect(chapters.length, 2);
      expect(chapters[0].name, isNot(contains('[')),
          reason: 'one language needs no per-chapter tags');
    });

    test('readable EN chapters skip the fallback entirely', () async {
      final source = makeSource(
        enFeed: [_chapter('en-1', '1', 'en')],
        allFeed: [
          _chapter('en-1', '1', 'en'),
          _chapter('ka-1', '1', 'ka'),
        ],
      );
      final chapters = await source
          .getChapterList('https://api.mangadex.org/manga/normal-title');
      expect(chapters.length, 1,
          reason: 'EN-first: no mixed feed when EN is readable');
      expect(chapters[0].language, 'en');
    });
  });

  // -------------------------------------------------------------------
  // 3. Madara detail title.
  // -------------------------------------------------------------------
  group('Madara detail title', () {
    test('parses post-title h1 from the detail fixture', () async {
      final fixture =
          File('test/fixtures/madara_detail.html').readAsStringSync();
      final source = MadaraSource(
        Source(
          idString: 'repo-x-1',
          name: 'MangaRead',
          lang: 'en',
          baseUrl: 'https://www.mangaread.org',
          typeSource: 'madara',
          isManga: true,
        ),
        client: MockClient((request) async {
          if (request.url.toString().contains('/manga/hell-mode')) {
            return _html(fixture);
          }
          // admin-ajax + ajax/chapters chapter endpoints.
          return http.Response('', 200);
        }),
      );
      final detail =
          await source.getMangaDetail('https://www.mangaread.org/manga/hell-mode/');
      expect(detail.name, isNotEmpty,
          reason: 'library rows persisted from Browse must never be '
              'nameless');
      expect(detail.name, contains('Hell Mode'));
    });
  });

  // -------------------------------------------------------------------
  // 4. MangaReader detail title.
  // -------------------------------------------------------------------
  group('MangaReader detail title', () {
    test('parses h1.entry-title', () async {
      const detailHtml = '''
        <html><body>
          <h1 class="entry-title">Solo Leveling</h1>
          <div class="bigcontent">
            <div class="tsinfo"><span class="imptdt">Author: <i>Chugong</i></span></div>
            <div class="desc"><p>A hunter story.</p></div>
          </div>
          <div id="chapterlist"><ul>
            <li><a href="/chapter/1">Chapter 1</a></li>
          </ul></div>
        </body></html>
      ''';
      final source = MangaReaderSource(
        Source(
          idString: 'repo-x-2',
          name: 'MangaReader',
          lang: 'en',
          baseUrl: 'https://mangareader.to',
          typeSource: 'mangareader',
          isManga: true,
        ),
        client: MockClient(
            (request) async => _html(detailHtml)),
      );
      final detail = await source
          .getMangaDetail('https://mangareader.to/manga/solo-leveling/');
      expect(detail.name, 'Solo Leveling');
      final chapters =
          await source.getChapterList('https://mangareader.to/manga/solo-leveling/');
      expect(chapters.length, 1);
    });
  });

  // -------------------------------------------------------------------
  // 5. MChapter.copyWithName round-trip.
  // -------------------------------------------------------------------
  test('MChapter.copyWithName preserves every field', () {
    final c = MChapter(
      name: 'Chapter 1',
      url: 'https://x/c/1',
      dateUpload: '1700000000000',
      scanlator: 'Group',
      mangaId: 'm1',
      chapterNumber: '1',
      volumeNumber: '1',
      language: 'en',
    );
    final copy = c.copyWithName('Chapter 1 [ka]');
    expect(copy.name, 'Chapter 1 [ka]');
    expect(copy.url, c.url);
    expect(copy.dateUpload, c.dateUpload);
    expect(copy.scanlator, c.scanlator);
    expect(copy.mangaId, c.mangaId);
    expect(copy.chapterNumber, c.chapterNumber);
    expect(copy.volumeNumber, c.volumeNumber);
    expect(copy.language, c.language);
  });
}
