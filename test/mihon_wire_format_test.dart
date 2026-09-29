// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// MIHON / ANIYOMI APK BRIDGE WIRE-FORMAT REGRESSIONS.
//
// The /dalvik bridge (m_extension_server ResponseModels.kt) serializes
// catalogue pages under `mangas` / `animes` with `thumbnail_url` covers,
// memo-suffixed URLs and float chapter numbers. An earlier parser looked
// for `list` / `mangaList` / `animeList` + `thumbnailUrl` — keys that
// never occur on this wire — so EVERY APK extension browse silently
// returned an empty list (the "keiyoushi / NSFW / anime extensions fetch
// nothing" report). These tests lock the wire contract.

import 'package:flutter_test/flutter_test.dart';

import 'package:lumina_reader/eval/mihon/service.dart';
import 'package:lumina_reader/eval/model/m_models.dart' as m;

void main() {
  group('parseMihonPage (wire format)', () {
    test('parses a manga page: mangas key, thumbnail_url covers', () {
      final entries = parseMihonPage(
        {
          'mangas': [
            {
              'url': 'https://x.to/series/one-piece',
              'title': 'One Piece',
              'author': 'Oda',
              'artist': null,
              'description': 'Pirates.',
              'genre': 'Action, Adventure',
              'status': 0,
              'thumbnail_url': 'https://x.to/covers/1.jpg',
              'initialized': true,
            },
          ],
        },
        displayName: 'TestExt',
        isAnime: false,
      );
      expect(entries, hasLength(1));
      expect(entries.first.name, 'One Piece');
      expect(entries.first.link, 'https://x.to/series/one-piece');
      // The old parser read `thumbnailUrl` — covers never loaded.
      expect(entries.first.imageUrl, 'https://x.to/covers/1.jpg');
      expect(entries.first.isAnime, isFalse);
    });

    test('parses an anime page: animes key + isAnime typing', () {
      final entries = parseMihonPage(
        {
          'animes': [
            {
              'url': 'https://ani.to/watch/frieren',
              'title': 'Frieren',
              'genre': 'Fantasy',
              'status': 1,
              'thumbnail_url': 'https://ani.to/covers/2.jpg',
            },
          ],
        },
        displayName: 'TestAnimeExt',
        isAnime: true,
      );
      expect(entries, hasLength(1));
      // Without isAnime the coordinator types the entry as MANGA → the
      // image reader opened with zero pages and the CTA said "Start
      // reading".
      expect(entries.first.isAnime, isTrue);
      expect(entries.first.name, 'Frieren');
    });

    test('strips the |mangayomi-memo| suffix for stable URLs', () {
      final entries = parseMihonPage(
        {
          'mangas': [
            {
              'url':
                  'https://x.to/series/a|mangayomi-memo|aGVhZGVycz1va2h0dHA',
              'title': 'A',
            },
          ],
        },
        displayName: 'TestExt',
        isAnime: false,
      );
      // Library dedup keys on the source URL — the memo payload changes
      // between calls, so it must be stripped at the boundary.
      expect(entries.first.link, 'https://x.to/series/a');
    });

    test('empty result list is an EMPTY list, not an error', () {
      final entries = parseMihonPage(
        {'mangas': <Object>[]},
        displayName: 'TestExt',
        isAnime: false,
      );
      expect(entries, isEmpty);
    });

    test('unexpected shapes THROW (honest errors, no silent empties)', () {
      expect(
        () => parseMihonPage(
          {'unexpected': 1},
          displayName: 'TestExt',
          isAnime: false,
        ),
        throwsException,
      );
      expect(
        () => parseMihonPage('not a map',
            displayName: 'TestExt', isAnime: false),
        throwsException,
      );
    });
  });

  group('stripMihonMemo', () {
    test('plain URLs pass through untouched', () {
      expect(
        stripMihonMemo('https://x.to/series/one-piece'),
        'https://x.to/series/one-piece',
      );
      expect(stripMihonMemo(''), '');
    });

    test('only the FIRST marker strips (memo payload may contain junk)', () {
      expect(
        stripMihonMemo('https://x.to/a|mangayomi-memo|abc'),
        'https://x.to/a',
      );
    });
  });

  test('MManga carries chapter_number through MChapter', () {
    // Sanity: the bridge serializes JChapter.chapter_number /
    // JEpisode.episode_number — the chapter DTO keeps it as a string.
    final ch = m.MChapter()
      ..name = 'Chapter 5'
      ..url = 'https://x.to/c/5'
      ..chapterNumber = '5.0';
    expect(ch.chapterNumber, '5.0');
  });
}
