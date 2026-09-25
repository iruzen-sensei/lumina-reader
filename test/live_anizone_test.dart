// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// LIVE-NETWORK integration test — NOT part of the CI gate.
//
// Verifies the Anilili-style anime streaming chain end-to-end against the
// real services (the exact chain ExtensionCoordinator dispatches to for
// the seeded `builtin.anizone` source):
//
//   AniList: trending / seasonal / search / detail
//   AniZone: slug resolution → episode scrape (Livewire pagination) →
//            watch-page HLS + subtitles
//
// Runs the chains inside `tester.runAsync` with a REAL HttpOverrides so
// flutter_test's 400-stub is bypassed (technique proven by
// live_probe_test.dart). Run manually with:
//   flutter test test/live_anizone_test.dart
// Structural assertions only (no specific titles) — tolerant of drift.

@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/anizone_source.dart';
import 'package:lumina_reader/models/source.dart' as db;
import 'package:lumina_reader/services/anilist.dart';

/// Removes flutter_test's stub client factory so `package:http` performs
/// REAL network I/O (dart:io HttpClient direct).
class _LiveOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// anizone.to Cloudflare-gates Dart's TLS fingerprint on datacenter IPs
  /// (live-verified from CI-like sandboxes). The same chain is covered
  /// deterministically by native_templates_fixture_test.dart; this live
  /// suite self-skips when the provider is unreachable instead of failing.
  var anizoneReachable = true;
  setUpAll(() async {
    await HttpOverrides.runWithHttpOverrides(() async {
      try {
        final res = await http.get(
            Uri.parse('https://anizone.to/anime'), headers: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 '
              'Safari/537.36',
        }).timeout(const Duration(seconds: 10));
        anizoneReachable = res.statusCode == 200 &&
            !res.body.contains('Just a moment');
      } catch (_) {
        anizoneReachable = false;
      }
    }, _LiveOverrides());
  });

  AniZoneSource newSource() => AniZoneSource(db.Source(
        idString: 'builtin.anizone',
        name: 'AniList Anime (AniZone)',
        lang: 'en',
        baseUrl: 'https://anilist.co',
        isManga: false,
        isAnime: true,
        sourceCodeLanguage: db.SourceCodeLanguage.dart,
        sourceCode: 'builtin:anizone',
      ));

  testWidgets('AniList: trending / seasonal / search', (tester) async {
    await tester.runAsync(() async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _LiveOverrides();
      try {
        final anilist = AniListService();
        final trending = await anilist.trending();
        expect(trending, isNotEmpty, reason: 'trending empty');
        expect(trending.first.id, greaterThan(0));
        expect(trending.first.romaji, isNotEmpty);

        final seasonal = await anilist.seasonal();
        expect(seasonal, isNotEmpty, reason: 'seasonal empty');

        final search = await anilist.search('frieren');
        expect(search, isNotEmpty, reason: 'search empty');
        expect(
          search.any((e) =>
              e.romaji.toLowerCase().contains('frieren') ||
              (e.english ?? '').toLowerCase().contains('frieren')),
          isTrue,
        );
      } finally {
        HttpOverrides.global = previous;
      }
    });
  });

  testWidgets('AniZone: FULL CHAIN — catalog → detail → episodes → HLS',
      (tester) async {
    if (!anizoneReachable) {
      // ignore: avoid_print
      print('LIVE SKIP: anizone.to Cloudflare-gated from this network '
          '(fixture tests cover the parsing chain)');
      return;
    }
    await tester.runAsync(() async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _LiveOverrides();
      try {
        final source = newSource();

        // 1. Catalog (AniList trending through the source interface).
        final popular = await source.getPopular(1);
        expect(popular, isNotEmpty, reason: 'source popular empty');
        expect(popular.first.isAnime, isTrue);
        expect(popular.first.link, startsWith('anilist:'));

        // 2. Search for a well-known show.
        final entries = await source.searchManga(
          query: 'frieren',
          page: 1,
          filterList: const FilterList(filters: []),
        );
        expect(entries, isNotEmpty, reason: 'source search empty');

        // 3. Detail (AniList metadata).
        final detail = await source.getMangaDetail(entries.first.link!);
        expect(detail.name, isNotEmpty);
        expect(detail.isAnime, isTrue);

        // 4. Episodes (AniZone slug match + Livewire scrape).
        final episodes = await source.getChapterList(entries.first.link!);
        expect(episodes, isNotEmpty, reason: 'no AniZone episodes resolved');
        expect(episodes.first.url, contains('anizone.to'));
        expect(double.tryParse(episodes.first.chapterNumber ?? ''), isNotNull);

        // 5. Streams (watch page → HLS + subtitles).
        final videos = await source.getVideoList(episodes.first.url!);
        expect(videos, isNotEmpty, reason: 'no playable stream');
        expect(videos.first.url, contains('.m3u8'));
        final subs = videos.first.parameters?['subtitles'];
        expect(subs, isA<List<dynamic>>(), reason: 'no subtitle payload');
      } finally {
        HttpOverrides.global = previous;
      }
    });
  });
}
