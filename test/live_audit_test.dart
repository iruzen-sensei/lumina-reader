// LIVE FUNCTIONAL AUDIT — exercises the app's REAL source chains against the
// real internet (repo sync → install → popular → search → detail → chapters
// → pages) for all three native templates. NOT part of the CI gate.
//
// Usage: flutter test test/live_audit_test.dart
//
// Tolerant, diagnostic-first: every step prints PASS/FAIL with detail so a
// dead template is pinpointed to its exact break point.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:lumina_reader/data/library_repository.dart';
import 'package:lumina_reader/data/sources_repository.dart';
import 'package:lumina_reader/eval/lib.dart' as eval;
import 'package:lumina_reader/eval/model/m_models.dart' as m;
import 'package:lumina_reader/models/category.dart' as db_c;
import 'package:lumina_reader/models/chapter.dart' as db_ch;
import 'package:lumina_reader/models/download.dart' as db_dl;
import 'package:lumina_reader/models/history.dart' as db_h;
import 'package:lumina_reader/models/manga.dart' as db_m;
import 'package:lumina_reader/models/note.dart' as db_n;
import 'package:lumina_reader/models/reading_session.dart' as db_rs;
import 'package:lumina_reader/models/settings.dart' as db_s;
import 'package:lumina_reader/models/source.dart' as db;
import 'package:lumina_reader/models/track.dart' as db_t;
import 'package:lumina_reader/models/update.dart' as db_u;
import 'package:lumina_reader/models/video.dart' as db_v;
import 'package:lumina_reader/providers/storage_provider.dart';
import 'package:lumina_reader/services/extension_coordinator.dart';
import 'package:lumina_reader/services/extension_repo_service.dart';

class _LiveOverrides extends HttpOverrides {
}

int _pass = 0, _fail = 0;
void check(String label, Object? result, {bool passIf = true}) {
  final ok = passIf;
  if (ok) {
    _pass++;

    print('  PASS  $label${result != null ? ' :: $result' : ''}');
  } else {
    _fail++;

    print('  FAIL  $label${result != null ? ' :: $result' : ''}');
  }
}

Future<T?> guard<T>(String label, Future<T> Function() body) async {
  try {
    return await body();
  } catch (e) {
    check(label, 'threw: $e', passIf: false);
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LIVE AUDIT: full source chains', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = _LiveOverrides();
      final tmp = await Directory.systemTemp.createTemp('lumina-live-');
      final isar = await Isar.open(
        [
          db_m.MangaSchema,
          db_ch.ChapterSchema,
          db_v.VideoSchema,
          db_n.NoteSchema,
          db_rs.ReadingSessionSchema,
          db_rs.ReadingGoalSchema,
          db_s.SettingsSchema,
          db.SourceSchema,
          db_c.CategorySchema,
          db_h.HistorySchema,
          db_dl.DownloadSchema,
          db_u.UpdateSchema,
          db_t.TrackSchema,
        ],
        directory: tmp.path,
        name: 'liveAudit${DateTime.now().microsecondsSinceEpoch}',
      );
      StorageProvider().initForTesting(isar);

      final sources = SourcesRepository(StorageProvider());
      final library = LibraryRepository(StorageProvider());
      final repoService = ExtensionRepoService(isar);
      final coordinator = ExtensionCoordinator(sources: sources, library: library);

      // ---------------------------------------------------------------
      // 1. Builtin seeding
      // ---------------------------------------------------------------
      print('== PHASE 1: builtin seed ==');
      await guard('ensureBuiltinSources', sources.ensureBuiltinSources);
      final all = await sources.getSources();
      check('builtin MangaDex present', all.length,
          passIf: all.any((s) => s.name == 'MangaDex'));
      final mangadex = all.firstWhere((s) => s.name == 'MangaDex');
      final mdService = eval.getExtensionService(
          (await sources.getSource(mangadex.id))!);
      check('MangaDex service is functional',
          mdService.runtimeType,
          passIf: mdService is! eval.NullExtensionService);

      // ---------------------------------------------------------------
      // 2. MangaDex native chain
      // ---------------------------------------------------------------
      print('== PHASE 2: MangaDex chain ==');
      final mdPopular = await guard<List<m.MManga>>(
          'mangadex getPopular', () => mdService.getPopular(1));
      check('mangadex popular entries', mdPopular?.length,
          passIf: (mdPopular?.length ?? 0) >= 5);
      if (mdPopular != null && mdPopular.isNotEmpty) {
        final entry = mdPopular.first;
        print('     first: ${entry.name} -> ${entry.link}');
        final detail = await guard<m.MManga>('mangadex getMangaDetail',
            () => mdService.getMangaDetail(entry.link!));
        check('mangadex detail has description',
            (detail?.description ?? '').length > 20,
            passIf: (detail?.description ?? '').length > 20);
        final chapters = await guard<List<m.MChapter>>(
            'mangadex getChapterList',
            () => mdService.getChapterList(entry.link!));
        // Multi-language fix: Solo Leveling's EN chapters are licensed away
        // (externalUrl); the feed must surface the non-EN chapters instead
        // of returning 0 (the old EN-only filter dead-ended the reader on
        // the FIRST title users tap).
        check('mangadex chapters (multi-language)', chapters?.length,
            passIf: (chapters?.length ?? 0) > 0);
        if (chapters != null && chapters.isNotEmpty) {
          print('     chapter langs: '
              '${chapters.map((c) => c.language ?? '?').toSet().toList()}');
          check('mangadex EN-first ordering',
              chapters.first.language,
              passIf: chapters.first.language == 'en' ||
                  chapters.every((c) => c.language != 'en'));
          final pages = await guard<List<String>>('mangadex getPageList',
              () => mdService.getPageList(chapters.first.url!));
          check('mangadex pages', pages?.length,
              passIf: (pages?.length ?? 0) > 0);
          if (pages != null && pages.isNotEmpty) {
            print('     page url: ${pages.first}');
          }
        }
        final search = await guard<List<m.MManga>>('mangadex search',
            () => mdService.searchManga(
                query: 'one piece',
                page: 1,
                filterList: const m.FilterList(filters: [])));
        check('mangadex search', search?.length,
            passIf: (search?.length ?? 0) > 0);
      }

      // ---------------------------------------------------------------
      // 2b. Seeded builtin template sources (fresh-install content)
      // ---------------------------------------------------------------
      print('== PHASE 2b: builtin seed chains ==');
      const seeds = <(String, String, String)>[
        ('builtin.mangasushi', 'Mangasushi', 'madara'),
        ('builtin.lhtranslation', 'LHTranslation', 'madara'),
        ('builtin.ravenscans', 'Raven Scans', 'mangareader'),
      ];
      for (final (id, name, _) in seeds) {
        final row = await sources.getSourceByIdString(id);
        check('seed $name present', row != null, passIf: row != null);
        if (row == null) continue;
        final svc = eval.getExtensionService(row);
        check('seed $name dispatches natively',
            svc.runtimeType,
            passIf: svc is! eval.NullExtensionService);
        final popular = await guard<List<m.MManga>>(
            'seed $name popular', () => svc.getPopular(1));
        check('seed $name popular', popular?.length ?? 0,
            passIf: (popular?.length ?? 0) > 0);
      }

      // ---------------------------------------------------------------
      // 3. Repo sync
      // ---------------------------------------------------------------
      print('== PHASE 3: default repo sync ==');
      final repoCount = await guard<int>('syncRepo(default)',
          () => repoService.syncRepo('https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json'));
      check('repo index entries', repoCount, passIf: (repoCount ?? 0) > 100);

      final catalog = await repoService.catalog();
      print('     catalog rows: ${catalog.length}');
      final byTemplate = <String, int>{};
      for (final c in catalog) {
        byTemplate[c.typeSource ?? '?'] = (byTemplate[c.typeSource ?? '?'] ?? 0) + 1;
      }
      print('     by template: $byTemplate');

      // ---------------------------------------------------------------
      // 4. Install + exercise madara sources (ALIVE candidates)
      // ---------------------------------------------------------------
      // NOTE: the repo index is full of dead domains (~60% at last probe) —
      // candidates are picked from scripts/probe_sites.py's alive list.
      print('== PHASE 4: madara template chain ==');
      const madaraCandidates = <(String, String)>[
        ('Mangasushi', 'https://mangasushi.org'),
        ('LHTranslation', 'https://lhtranslation.net'),
        ('SamuraiScan', 'https://samuraiscan.com'),
        ('Ragnarok Scanlation', 'https://ragnarokscanlation.org'),
      ];
      var madaraChainsOk = 0;
      for (final (name, base) in madaraCandidates) {
        print('   -- madara candidate: $name ($base)');
        final row = db.Source(
          idString: 'live-madara-$name',
          name: name,
          lang: 'en',
          baseUrl: base,
          typeSource: 'madara',
          isManga: true,
          isEnabled: true,
        );
        final svc = eval.getExtensionService(row);
        if (svc is eval.NullExtensionService) {
          check('madara $name service', 'NullExtensionService', passIf: false);
          continue;
        }
        final popular = await guard<List<m.MManga>>(
            'madara $name popular', () => svc.getPopular(1));
        if (popular == null || popular.isEmpty) {
          check('madara $name popular', popular?.length ?? 0, passIf: false);
          continue;
        }
        check('madara $name popular', popular.length, passIf: true);
        print('     first: ${popular.first.name} -> ${popular.first.link}');
        final chapters = await guard<List<m.MChapter>>(
            'madara $name chapters',
            () => svc.getChapterList(popular.first.link!));
        check('madara $name chapters', chapters?.length ?? 0,
            passIf: (chapters?.length ?? 0) > 0);
        if (chapters != null && chapters.isNotEmpty) {
          final pages = await guard<List<String>>(
              'madara $name pages',
              () => svc.getPageList(chapters.first.url!));
          check('madara $name pages', pages?.length ?? 0,
              passIf: (pages?.length ?? 0) > 0);
          if ((pages?.length ?? 0) > 0) {
            print('     page url: ${pages!.first}');
            madaraChainsOk++;
          }
        }
      }
      check('madara FULL chains (>=3 sites)', madaraChainsOk,
          passIf: madaraChainsOk >= 3);

      // ---------------------------------------------------------------
      // 5. Install + exercise mangareader sources (ALIVE candidates)
      // ---------------------------------------------------------------
      print('== PHASE 5: mangareader template chain ==');
      const readerCandidates = <(String, String)>[
        ('Raven Scans', 'https://ravenscans.com'),
        ('SkyMangas', 'https://skymangas.com'),
        ('Manga Flame', 'https://mangaflame.org'),
      ];
      var readerChainsOk = 0;
      for (final (name, base) in readerCandidates) {
        print('   -- mangareader candidate: $name ($base)');
        final row = db.Source(
          idString: 'live-reader-$name',
          name: name,
          lang: 'en',
          baseUrl: base,
          typeSource: 'mangareader',
          isManga: true,
          isEnabled: true,
        );
        final svc = eval.getExtensionService(row);
        if (svc is eval.NullExtensionService) continue;
        final popular = await guard<List<m.MManga>>(
            'mangareader $name popular', () => svc.getPopular(1));
        if ((popular?.length ?? 0) == 0) {
          check('mangareader $name popular', popular?.length ?? 0,
              passIf: false);
          continue;
        }
        check('mangareader $name popular', popular!.length, passIf: true);
        final chapters = await guard<List<m.MChapter>>(
            'mangareader $name chapters',
            () => svc.getChapterList(popular.first.link!));
        check('mangareader $name chapters', chapters?.length ?? 0,
            passIf: (chapters?.length ?? 0) > 0);
        if (chapters != null && chapters.isNotEmpty) {
          final pages = await guard<List<String>>(
              'mangareader $name pages',
              () => svc.getPageList(chapters.first.url!));
          check('mangareader $name pages', pages?.length ?? 0,
              passIf: (pages?.length ?? 0) > 0);
          if ((pages?.length ?? 0) > 0) {
            print('     page url: ${pages!.first}');
            readerChainsOk++;
          }
        }
      }
      check('mangareader FULL chains (>=1 site)', readerChainsOk,
          passIf: readerChainsOk >= 1);

      // ---------------------------------------------------------------
      // 6. Coordinator-level integration (the layer the UI calls)
      // ---------------------------------------------------------------
      print('== PHASE 6: coordinator (UI-layer) integration ==');
      final mdId = mangadex.id;
      final cPopular = await guard('coordinator.popular(mangadex)',
          () => coordinator.popular(mdId));
      check('coordinator popular', cPopular?.length ?? 0,
          passIf: (cPopular?.length ?? 0) > 0);
      if ((cPopular?.length ?? 0) > 0) {
        final cDetail = await guard('coordinator.detail(mangadex)',
            () => coordinator.detail(mdId, cPopular!.first.url));
        check('coordinator detail + chapters',
            cDetail?.chapters.length ?? 0,
            passIf: (cDetail?.chapters.length ?? 0) > 0);
      }

      print('== AUDIT SUMMARY: $_pass passed, $_fail failed ==');

      // CORE invariants — these are OUR code, not third-party site health.
      // (Dead repo sites fail above as diagnostics; the template code is
      // proven by the alive candidates.)
      expect(
          (await sources.getSources())
              .where((s) => s.isInstalled)
              .length,
          greaterThanOrEqualTo(4),
          reason: 'MangaDex + 3 verified-alive seeds must be installed');
      final mdChapters = await mdService
          .getChapterList('https://api.mangadex.org/manga/'
              '32d76d19-8a05-4db0-9fc2-e0b0648fe9d0');
      expect(mdChapters, isNotEmpty,
          reason: 'MangaDex multi-language chapter list must not be empty '
              '(Solo Leveling has 38 readable non-EN chapters)');
      final mdPages = await mdService.getPageList(mdChapters.first.url!);
      expect(mdPages, isNotEmpty,
          reason: 'MangaDex page resolution must work');
      await isar.close(deleteFromDisk: true);
    });
  }, timeout: const Timeout(Duration(minutes: 8)));
}
