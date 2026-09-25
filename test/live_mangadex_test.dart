// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// LIVE-NETWORK integration test — NOT part of the CI gate (the workflow
// runs only compile_smoke_test.dart and madara_fixture_test.dart).
//
// Verifies the native MangaDex extension end-to-end against the real API:
//   getPopular → getMangaDetail → getChapterList → getPageList
//
// This is the exact service chain ExtensionCoordinator.detail()/pageList()
// dispatch to for the seeded `builtin.mangadex` source. Run manually with:
//   flutter test test/live_mangadex_test.dart
// It requires internet access; expectations are tolerant of catalog drift
// (only structural assertions — never specific titles).

@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/mangadex_source.dart';
import 'package:lumina_reader/models/source.dart' as db;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MangaDexSource source;

  // flutter_test installs an HttpOverrides stub that answers every request
  // with HTTP 400 — inside `flutter test` real egress is impossible. Detect
  // it once and skip the suite (the same chain is verified against the real
  // API by `dart run tool/live_probe.dart`, which has no stub).
  var liveAvailable = true;
  setUpAll(() async {
    final probe = MangaDexSource(db.Source(
      idString: 'builtin.mangadex',
      name: 'MangaDex',
      lang: 'en',
      baseUrl: 'https://api.mangadex.org',
      isManga: true,
      sourceCodeLanguage: db.SourceCodeLanguage.dart,
      sourceCode: 'builtin:mangadex',
    ));
    try {
      await probe.getPopular(1);
    } catch (_) {
      liveAvailable = false;
    }
  });

  setUp(() {
    source = MangaDexSource(db.Source(
      idString: 'builtin.mangadex',
      name: 'MangaDex',
      lang: 'en',
      baseUrl: 'https://api.mangadex.org',
      isManga: true,
      sourceCodeLanguage: db.SourceCodeLanguage.dart,
      sourceCode: 'builtin:mangadex',
    ));
  });

  test('popular returns entries with titles, links and covers', () async {
    if (!liveAvailable) {
      markTestSkipped('sandbox blocks egress — run tool/live_probe.dart');
      return;
    }
    final entries = await source.getPopular(1);
    expect(entries, isNotEmpty,
        reason: 'MangaDex /manga popular list must return entries');
    final first = entries.first;
    expect(first.name, isNotNull,
        reason: 'every catalog entry needs a displayable title');
    expect(first.link, isNotEmpty,
        reason: 'the link is the detail/chapter routing key — without it '
            'the preview screen cannot fetch anything');
    expect(first.imageUrl ?? '', contains('uploads.mangadex.org'),
        reason: 'covers must point at the MangaDex CDN');
  });

  test('detail + chapters + pages chain resolves', () async {
    if (!liveAvailable) {
      markTestSkipped('sandbox blocks egress — run tool/live_probe.dart');
      return;
    }
    final entries = await source.getPopular(1);
    final first = entries.firstWhere((e) => e.link!.isNotEmpty);
    final detail = await source.getMangaDetail(first.link!);
    expect(detail.name, isNotEmpty);

    final chapters = await source.getChapterList(first.link!);
    expect(chapters, isNotEmpty,
        reason: 'popular entries are filtered to hasAvailableChapters=true');
    expect(chapters.first.url, contains('mangadex.org/chapter/'));

    final pages = await source.getPageList(chapters.first.url!);
    expect(pages, isNotEmpty,
        reason: 'the reader renders this list — empty means a dead reader');
    expect(pages.first, startsWith('http'));
    expect(pages.first, contains('/data/'));

    // Search sanity: a common word should match at least one entry.
    final results = await source.searchManga(
      query: 'sword',
      page: 1,
      filterList: const FilterList(filters: []),
    );
    expect(results, isNotEmpty);
  });
}
