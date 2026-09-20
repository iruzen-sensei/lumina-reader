// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// GOLDEN-SCREENSHOT AUDIT HARNESS
//
// Boots the REAL app (router + providers + theme) against a throwaway Isar
// instance seeded with representative data, and captures every screen as a
// PNG so the UI can be reviewed visually (VLM critique) and diffed when the
// design system changes.
//
// RUN WITH --update-goldens, then eyeball / VLM-review the PNGs. Compare
// mode is NOT deterministic yet: the app renders relative timestamps
// ("2h ago") from DateTime.now(), so library/detail/stats goldens shift at
// run boundaries. Gating CI on pixel diffs requires a clock abstraction
// across the app first.
//
// Network is mocked at the HttpClient level: any image URL serves a
// generated demo cover; everything else fails fast so screens render their
// offline / error states deterministically.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:lumina_reader/app.dart';
import 'package:lumina_reader/models/category.dart' as db_c;
import 'package:lumina_reader/models/chapter.dart' as db_ch;
import 'package:lumina_reader/models/download.dart' as db_dl;
import 'package:lumina_reader/models/episode.dart' as db_e;
import 'package:lumina_reader/models/history.dart' as db_h;
import 'package:lumina_reader/models/manga.dart' as db_m;
import 'package:lumina_reader/models/note.dart' as db_n;
import 'package:lumina_reader/models/reading_session.dart' as db_rs;
import 'package:lumina_reader/models/settings.dart' as db_s;
import 'package:lumina_reader/models/source.dart' as db_src;
import 'package:lumina_reader/models/track.dart' as db_t;
import 'package:lumina_reader/models/update.dart' as db_u;
import 'package:lumina_reader/models/video.dart' as db_v;
import 'package:lumina_reader/providers/providers.dart' as app;
import 'package:lumina_reader/providers/storage_provider.dart';
import 'package:lumina_reader/router/router.dart';

// ---------------------------------------------------------------------------
// HTTP fixtures
// ---------------------------------------------------------------------------

class _FixtureHttpOverrides extends HttpOverrides {
  final List<File> covers;
  _FixtureHttpOverrides(this.covers);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FixtureHttpClient(covers);
}

class _FixtureHttpClient implements HttpClient {
  final List<File> covers;
  _FixtureHttpClient(this.covers);

  static const _futureReturning = {
    #postUrl,
    #getUrl,
    #putUrl,
    #deleteUrl,
    #patchUrl,
    #headUrl,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #openUrl || name == #open) {
      final args = invocation.positionalArguments;
      final String url = args.isNotEmpty ? args.last.toString() : '';
      return _FixtureRequest(url, covers);
    }
    if (_futureReturning.contains(name)) {
      final args = invocation.positionalArguments;
      final String url = args.isNotEmpty ? args.first.toString() : '';
      return Future.value(_FixtureRequest(url, covers));
    }
    // TOLERANT fallback: Flutter's NetworkImage creates its shared client
    // with `HttpClient()..autoUncompress = false` — throwing here poisoned
    // the static initializer and made EVERY image load fail silently.
    if (invocation.isGetter && name == #autoUncompress) return false;
    return null;
  }
}

class _FixtureRequest implements HttpClientRequest {
  final String url;
  final List<File> covers;
  final Map<String, String> _headers = {};
  _FixtureRequest(this.url, this.covers);

  @override
  HttpHeaders get headers => _RequestHeaders(_headers);

  bool get _isImage {
    final p = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.png') ||
        p.endsWith('.webp') ||
        url.contains('cover');
  }

  @override
  Future<HttpClientResponse> close() async {
    if (_isImage && covers.isNotEmpty) {
      final h = url.hashCode.abs();
      final bytes = covers[h % covers.length].readAsBytesSync();
      return _FixtureResponse(200, Uint8List.fromList(bytes));
    }
    return _FixtureResponse(503, Uint8List(0));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.isSetter || invocation.isGetter ? null : null;
}

class _RequestHeaders implements HttpHeaders {
  final Map<String, String> _values;
  _RequestHeaders(this._values);
  @override
  String? value(String name) => _values[name];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name] = value.toString();
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name] = value.toString();
  @override
  void forEach(void Function(String name, List<String> values) f) {}
  @override
  void clear() => _values.clear();
  @override
  List<String>? operator [](String name) =>
      _values.containsKey(name) ? [_values[name]!] : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FixtureResponse extends Stream<List<int>> implements HttpClientResponse {
  final int _statusCode;
  final Uint8List body;
  _FixtureResponse(this._statusCode, this.body);

  @override
  int get statusCode => _statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([body]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  int get contentLength => body.length;

  @override
  Future<HttpClientResponse> redirect(
          [String? method, Uri? url, bool? followLoops]) async =>
      this;

  @override
  List<Cookie> get cookies => const [];

  @override
  HttpHeaders get headers => const _FakeHeaders();

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => '';

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  Future<Socket> detachSocket() async => throw UnsupportedError('');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  const _FakeHeaders();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Data seeding
// ---------------------------------------------------------------------------

class SeedIds {
  int mangaWithChapters = 0;
  int animeWithEpisodes = 0;
}

const _titles = [
  'Blade of the Immortal Wind',
  'Neon Tokyo Nights',
  'Sakura Rebellion',
  'Crimson Alchemy',
  'Starlight Academy',
  'Shadow Realm Saga',
  'Ocean of Stars',
  'Frost Iron Chronicle',
  'Golden Kamuy Tales',
  'Emerald Dragon',
  'Monochrome Heart',
  'Velvet Moon',
];

/// Seeds a rich, representative dataset covering every screen's needs.
Future<SeedIds> seedDatabase(Isar isar, {bool dark = true}) async {
  final now = DateTime.now();
  final ids = SeedIds();

  db_m.Manga mkManga(
    int i, {
    required db_m.ItemType type,
    int chapters = 24,
    int readCount = 8,
    double rating = 4.2,
  }) =>
      db_m.Manga(
        name: _titles[i % _titles.length],
        author: 'Author ${String.fromCharCode(65 + (i % 26))}. Tanaka',
        description:
            'When the ancient seal broke, the world changed forever — and '
            'only a handful of unlikely heroes stand between humanity and '
            'the rising tide of shadows. A sweeping tale of adventure, loss '
            'and self-discovery, critically acclaimed and beautifully drawn.',
        coverUrl: 'https://covers.lumina.test/cover-$i.jpg',
        itemType: type,
        tags: ['Action', 'Drama', 'Fantasy'],
        rating: rating,
        chapterCount: chapters,
        isFavorite: true,
        lastReadAt: now.subtract(Duration(hours: 1 + i)),
        addedAt: now.subtract(Duration(days: 30 - i)),
        totalPages: chapters * 20,
        currentPage: readCount * 20,
        progress: chapters == 0 ? 0 : readCount / chapters,
        isFinished: readCount >= chapters,
        readCount: readCount,
        sourceUrl: 'https://source.lumina.test/manga/$i',
        sourceId: 1,
        sourceName: 'MangaDex',
      );

  final mangaRows = <db_m.Manga>[
    mkManga(0, type: db_m.ItemType.manga, readCount: 8, chapters: 24),
    mkManga(1, type: db_m.ItemType.manga, readCount: 24, chapters: 24),
    mkManga(2, type: db_m.ItemType.manga, readCount: 3, chapters: 120),
    mkManga(3, type: db_m.ItemType.manga, readCount: 0, chapters: 12),
    mkManga(4, type: db_m.ItemType.manga, readCount: 55, chapters: 90),
    mkManga(5, type: db_m.ItemType.manga, readCount: 12, chapters: 48),
    mkManga(6, type: db_m.ItemType.novel, readCount: 2, chapters: 9),
    mkManga(7, type: db_m.ItemType.book, readCount: 1, chapters: 1),
  ];
  final animeRows = <db_m.Manga>[
    mkManga(8, type: db_m.ItemType.anime, chapters: 12, readCount: 5),
    mkManga(9, type: db_m.ItemType.anime, chapters: 25, readCount: 25),
    mkManga(10, type: db_m.ItemType.anime, chapters: 13, readCount: 0),
  ];

  final idMap = <db_m.Manga, int>{};
  await isar.writeTxn(() async {
    for (final m in mangaRows.followedBy(animeRows)) {
      idMap[m] = await isar.mangas.put(m);
    }
  });

  Future<void> addChapters(db_m.Manga m, int count, int readCount) async {
    final m2 = await isar.mangas.get(idMap[m]!);
    final chapters = <db_ch.Chapter>[];
    for (var i = 1; i <= count; i++) {
      chapters.add(db_ch.Chapter(
        name: 'Chapter $i',
        url: '${m.sourceUrl}/c/$i',
        chapterNumber: i,
        dateUpload: now.subtract(Duration(days: (count - i) * 7)),
        isRead: i <= readCount,
        isBookmarked: i == readCount,
        pageCount: 18 + (i % 5),
        lastPageRead: i <= readCount ? 18 : 0,
      ));
    }
    await isar.writeTxn(() async {
      for (final c in chapters) {
        await isar.chapters.put(c);
        c.manga.value = m2;
        await c.manga.save();
        await isar.chapters.put(c);
      }
      m2!.chapters.addAll(chapters);
      await m2.chapters.save();
      await isar.mangas.put(m2);
    });
  }

  await addChapters(mangaRows[0], 24, 8);
  await addChapters(mangaRows[1], 24, 24);
  await addChapters(mangaRows[2], 12, 3);
  await addChapters(mangaRows[6], 9, 2);
  await addChapters(animeRows[0], 12, 5);
  await addChapters(animeRows[1], 25, 25);
  await addChapters(animeRows[2], 13, 0);

  Future<void> addEpisodes(db_m.Manga m, int count, int seen) async {
    final m2 = await isar.mangas.get(idMap[m]!);
    await isar.writeTxn(() async {
      for (var i = 1; i <= count; i++) {
        final e = db_e.Episode(
          name: 'Episode $i',
          url: '${m.sourceUrl}/ep/$i',
          episodeNumber: i.toDouble(),
          seen: i <= seen,
          lastSecondSeen: i <= seen ? 1420 : 0,
          totalSeconds: 1420,
          isDownloaded: i <= seen && i.isEven,
          summary: 'The journey continues as new threats emerge across the '
              'horizon, testing the bonds forged in battle.',
          dateUpload: now.subtract(Duration(days: count - i)),
        );
        await isar.episodes.put(e);
        e.manga.value = m2;
        await e.manga.save();
        await isar.episodes.put(e);
      }
    });
  }

  await addEpisodes(animeRows[0], 12, 5);
  await addEpisodes(animeRows[1], 25, 25);
  await addEpisodes(animeRows[2], 13, 0);

  ids.mangaWithChapters = idMap[mangaRows[0]]!;
  ids.animeWithEpisodes = idMap[animeRows[0]]!;

  final rand = _Det(7);
  await isar.writeTxn(() async {
    // History — the screen shows mangaTitle / chapterName / lastReadAt.
    for (var i = 0; i < 14; i++) {
      final m = mangaRows[i % mangaRows.length];
      await isar.historys.put(db_h.History()
        ..mangaId = idMap[m]
        ..mangaIdString = idMap[m].toString()
        ..chapterName = 'Chapter ${i + 1}'
        ..chapterNumber = '${i + 1}'
        ..url = 'history-$i'
        ..progress = 0.8
        ..mangaTitle = m.name
        ..mangaCover = m.coverUrl
        ..isManga = m.itemType == db_m.ItemType.manga
        ..lastReadAt =
            now.subtract(Duration(hours: i * 5)).millisecondsSinceEpoch);
    }
    // Notes.
    for (var i = 0; i < 4; i++) {
      final n = db_n.Note(
        text: 'Great panel composition in this chapter — the double-page '
            'spread with the rain is stunning. Note #$i',
        pageNumber: 3 + i,
        color: i % 6,
        tags: ['favorite-moments'],
        createdAt: now.subtract(Duration(days: i)),
        updatedAt: now.subtract(Duration(days: i)),
      )..manga.value = await isar.mangas.get(ids.mangaWithChapters);
      await isar.notes.put(n);
    }
    // Sources.
    final srcs = <db_src.Source>[
      db_src.Source()
        ..idString = 'builtin.mangadex'
        ..name = 'MangaDex'
        ..lang = 'EN'
        ..baseUrl = 'https://api.mangadex.org'
        ..isManga = true
        ..version = '1.4.0'
        ..typeSource = 'mangadex',
      db_src.Source()
        ..idString = 'builtin.manganato'
        ..name = 'Manganato'
        ..lang = 'EN'
        ..baseUrl = 'https://manganato.com'
        ..isManga = true
        ..version = '1.2.3'
        ..typeSource = 'mangareader',
      db_src.Source()
        ..idString = 'builtin.animepahe'
        ..name = 'AnimePahe'
        ..lang = 'EN'
        ..baseUrl = 'https://animepahe.com'
        ..isAnime = true
        ..version = '1.1.0'
        ..typeSource = 'anime',
      db_src.Source()
        ..idString = 'builtin.anilist'
        ..name = 'AniList'
        ..lang = 'EN'
        ..baseUrl = 'https://graphql.anilist.co'
        ..isAnime = true
        ..version = '1.0.4'
        ..typeSource = 'anilist',
      db_src.Source()
        ..idString = 'builtin.lightnovels'
        ..name = 'LightNovelTV'
        ..lang = 'EN'
        ..baseUrl = 'https://lightnoveltv.com'
        ..isNsfw = false
        ..version = '1.0.0'
        ..typeSource = 'novel',
    ];
    for (final s in srcs) {
      await isar.sources.put(s);
    }
    // Downloads in mixed states.
    const dlStates = [
      db_dl.DownloadState.downloading,
      db_dl.DownloadState.queued,
      db_dl.DownloadState.completed,
      db_dl.DownloadState.failed,
      db_dl.DownloadState.paused,
    ];
    for (var i = 0; i < 6; i++) {
      final m = mangaRows[i % 3];
      await isar.downloads.put(db_dl.Download()
        ..mangaId = idMap[m]
        ..mangaIdString = idMap[m].toString()
        ..mangaTitle = m.name
        ..mangaCover = m.coverUrl
        ..chapterName = 'Chapter ${20 + i}'
        ..chapterNumber = '${20 + i}'
        ..url = 'dl-$i'
        ..mediaType = db_dl.DownloadMediaType.manga
        ..isManga = true
        ..state = dlStates[i % dlStates.length]
        ..success = i * 4
        ..failed = i == 3 ? 2 : 0
        ..total = 20
        ..requestedAt =
            now.subtract(Duration(minutes: i * 3)).millisecondsSinceEpoch);
    }
    // Updates feed.
    for (var i = 0; i < 9; i++) {
      final m = mangaRows[i % mangaRows.length];
      await isar.updates.put(db_u.Update()
        ..mangaId = idMap[m]
        ..mangaIdString = idMap[m].toString()
        ..mangaTitle = m.name
        ..mangaCover = m.coverUrl
        ..chapterName = 'Chapter ${100 + i}'
        ..chapterNumber = '${100 + i}'
        ..chapterNumberValue = (100 + i).toDouble()
        ..url = 'update-$i'
        ..mediaType = db_u.UpdateMediaType.manga
        ..isManga = true
        ..state = i < 3 ? db_u.UpdateState.read : db_u.UpdateState.unread
        ..isRead = i < 3
        ..date = now.subtract(Duration(hours: i * 9)).millisecondsSinceEpoch);
    }
    // Reading sessions for stats (28 days).
    for (var d = 0; d < 28; d++) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
      final sessions = 1 + rand.next(3);
      for (var s = 0; s < sessions; s++) {
        final rs = db_rs.ReadingSession(
          startTime: day.add(Duration(hours: 20 + s)),
          endTime: day.add(Duration(hours: 20 + s, minutes: 18)),
          durationSeconds: 600 + rand.next(1500),
          pagesRead: 8 + rand.next(16),
          date: day,
        )..manga.value = await isar.mangas
            .get(idMap[mangaRows[rand.next(mangaRows.length)]]!);
        await isar.readingSessions.put(rs);
      }
    }
    await isar.readingGoals.put(db_rs.ReadingGoal(
      type: db_rs.GoalType.dailyPages,
      target: 60,
      current: 34,
      date: DateTime(now.year, now.month, now.day),
    ));
    for (final name in ['Reading', 'Plan to read', 'Favorites']) {
      await isar.categorys.put(db_c.Category(name: name));
    }
    await isar.settings
        .put(db_s.Settings.defaults()..themeMode = dark ? 'dark' : 'light');
  });

  return ids;
}

class _Det {
  int _state;
  _Det(this._state);
  int next(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return max == 0 ? 0 : _state % max;
  }
}

// ---------------------------------------------------------------------------
// Boot + navigation + capture
// ---------------------------------------------------------------------------

/// Loads real font files so golden captures show real text + icons.
/// Tries FLUTTER_ROOT first (CI), then the sandbox-local SDK path.
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null && root.isNotEmpty)
      '$root/bin/cache/artifacts/material_fonts',
    '/home/z/my-project/flutter/bin/cache/artifacts/material_fonts',
  ];
  final fontDir = candidates
      .map(Directory.new)
      .cast<Directory?>()
      .firstWhere((d) => d!.existsSync(), orElse: () => null);
  final families = <String, FontLoader>{};
  if (fontDir == null) {
    // System font dir unavailable — still load the app's bundled families
    // below so golden typography stays real.
  } else {
    for (final f in fontDir.listSync().whereType<File>()) {
      final name = f.path.split(Platform.pathSeparator).last;
      final family = switch (name) {
        'Roboto-Regular.ttf' ||
        'Roboto-Medium.ttf' ||
        'Roboto-Bold.ttf' ||
        'Roboto-Black.ttf' ||
        'Roboto-Light.ttf' =>
          'Roboto',
        'MaterialIcons-Regular.otf' => 'MaterialIcons',
        _ => null,
      };
      if (family == null) continue;
      final loader = families.putIfAbsent(family, () => FontLoader(family));
      loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
  }
  // The app's BUNDLED families (Inter body + Spectral Light display) —
  // without these the golden text falls back to Roboto/tofu and the
  // captures misrepresent the real typography.
  final bundledLoaders = <FontLoader>[];
  const bundled = <String, List<String>>{
    'Inter': [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
    ],
    'Spectral': ['assets/fonts/Spectral-Light.ttf'],
  };
  for (final entry in bundled.entries) {
    final loader = FontLoader(entry.key);
    var any = false;
    for (final path in entry.value) {
      final f = File(path);
      if (f.existsSync()) {
        loader.addFont(
            Future.value(ByteData.view(f.readAsBytesSync().buffer)));
        any = true;
      }
    }
    if (any) bundledLoaders.add(loader);
  }
  await Future.wait(
      [...families.values, ...bundledLoaders].map((l) => l.load()));
}

/// The single Isar instance shared by every test in this binary. A second
/// Isar.open inside one flutter_test isolate deadlocks, so it is opened
/// once and reused.
Isar? _sharedIsar;

/// True once [setupFixture] has run in this binary.
bool get fixtureReady => _sharedIsar != null;

/// The shared instance (throws if [setupFixture] has not run yet).
Isar get sharedIsar => _sharedIsar!;

/// Installs ONLY the fixture HTTP overrides (no DB).
void installFixtureHttp() {
  final coversDir = Directory('test/fixtures/covers');
  final covers = coversDir.existsSync()
      ? (coversDir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  HttpOverrides.global = _FixtureHttpOverrides(covers);
}

/// Installs fixture HTTP + opens the SHARED Isar (once per binary) and
/// seeds it. Later calls are no-ops for the DB but still return the handle.
Future<Isar> setupFixture({bool dark = true}) async {
  if (_sharedIsar != null) return _sharedIsar!;
  // Close any instance left over from a previous test — two live Isar
  // instances in the flutter_test isolate deadlock each other.
  final coversDir = Directory('test/fixtures/covers');
  final covers = coversDir.existsSync()
      ? (coversDir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  HttpOverrides.global = _FixtureHttpOverrides(covers);

  final tmp = await Directory.systemTemp.createTemp('lumina-golden-');
  final opened = await Isar.open(
    [
      db_m.MangaSchema,
      db_ch.ChapterSchema,
      db_e.EpisodeSchema,
      db_v.VideoSchema,
      db_n.NoteSchema,
      db_rs.ReadingSessionSchema,
      db_rs.ReadingGoalSchema,
      db_s.SettingsSchema,
      db_src.SourceSchema,
      db_c.CategorySchema,
      db_h.HistorySchema,
      db_dl.DownloadSchema,
      db_u.UpdateSchema,
      db_t.TrackSchema,
    ],
    directory: tmp.path,
    name: 'goldenDb${DateTime.now().microsecondsSinceEpoch}',
  );
  _sharedIsar = opened;
  StorageProvider().initForTesting(opened);
  await seedDatabase(opened, dark: dark);
  return opened;
}

/// Pre-reads every data provider inside a REAL async zone (runAsync) so
/// Isar's async transactions complete against the real event loop. The
/// widgets then simply watch the already-loaded state.
///
/// [detailIds] / [animeIds] pre-warm the per-id detail providers for the
/// screens being captured.
Future<void> warmUpProviders(
  WidgetTester tester,
  ProviderContainer c, {
  Iterable<int> detailIds = const [1],
  Iterable<int> animeIds = const [9],
}) async {
  await tester.runAsync(() async {
    // Library lists.
    c.read(app.mangaLibraryProvider);
    c.read(app.animeLibraryProvider);
    c.read(app.novelLibraryProvider);
    c.read(app.bookLibraryProvider);
    c.read(app.libraryOptionsProvider);
    c.read(app.sourcesProvider);
    c.read(app.historyProvider);
    c.read(app.notesProvider);
    c.read(app.downloadsProvider);
    c.read(app.updatesProvider);
    c.read(app.appSettingsProvider);
    c.read(app.statsSummaryProvider);
    c.read(app.statsGoalsProvider);
    c.read(app.streakProvider);
    c.read(app.statsHeatmapProvider);
    for (final id in detailIds) {
      c.read(app.mangaDetailProvider(id));
    }
    // Anime detail screens reuse mangaDetailProvider with the anime id.
    for (final id in animeIds) {
      c.read(app.mangaDetailProvider(id));
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  });
}

Future<ProviderContainer> bootApp(
  WidgetTester tester, {
  Size logical = const Size(412, 915),
  double dpr = 2.0,
  bool warmUp = true,
  Iterable<int> detailIds = const [1],
  Iterable<int> animeIds = const [9],
}) async {
  tester.view.physicalSize = logical * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);

  if (warmUp) {
    await warmUpProviders(tester, container,
        detailIds: detailIds, animeIds: animeIds);
  }

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const LuminaApp(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

/// Navigate through the REAL router.
Future<void> go(WidgetTester tester, ProviderContainer c, String path) async {
  c.read(routerProvider).go(path);
  await tester.pump();
  await flush(tester);
}

/// Drives the fake-async test zone together with the real event loop so
/// Isar native calls + provider chains complete and the UI settles.
/// [rounds] iterations of (real 150ms flush + fake 150ms pump).
Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 150));
  }
  // Let any in-flight animations finish (bounded).
  var guard = 0;
  while (tester.binding.hasScheduledFrame && guard++ < 60) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Kept for API compatibility — same as [flush].
Future<void> settle(WidgetTester tester, {int rounds = 8}) =>
    flush(tester, rounds: rounds);

Future<void> capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp).first,
    matchesGoldenFile('goldens/$name.png'),
  );
}
