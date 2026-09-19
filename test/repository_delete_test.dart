// Repository-level regression tests for the delete / progress flows that
// were pure UI theatre before this pass ("can't delete anything").
//
// Uses a throwaway Isar instance in a temp directory — no network, no
// Flutter bindings required beyond flutter_test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:lumina_reader/data/downloads_repository.dart';
import 'package:lumina_reader/data/library_repository.dart';
import 'package:lumina_reader/models/category.dart' as db;
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
import 'package:lumina_reader/models/models.dart' as dto;
import 'package:lumina_reader/providers/storage_provider.dart';

void main() {
  // The Linux Isar core binary (libisar.so) is fetched into the repo root
  // (isar_flutter_libs only ships Android/iOS/Windows/macOS binaries).
  // CI downloads it before running this suite; locally `curl` it once:
  //   curl -sL -o libisar.so \
  //     https://github.com/isar/isar/releases/download/3.1.0%2B1/libisar_linux_x64.so
  late Isar isar;
  late Directory tmp;
  late LibraryRepository library;
  late DownloadsRepository downloads;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('lumina-repo-test-');
    isar = await Isar.open(
      [
        db_m.MangaSchema,
        db_ch.ChapterSchema,
        db.CategorySchema,
        db_dl.DownloadSchema,
        db_h.HistorySchema,
        db_n.NoteSchema,
        db_e.EpisodeSchema,
        db_v.VideoSchema,
        db_rs.ReadingSessionSchema,
        db_rs.ReadingGoalSchema,
        db_s.SettingsSchema,
        db_src.SourceSchema,
        db_u.UpdateSchema,
        db_t.TrackSchema,
      ],
      directory: tmp.path,
      name: 'testDb',
      inspector: false,
    );
  });

  tearDownAll(() async {
    await isar.close(deleteFromDisk: true);
    await tmp.delete(recursive: true);
  });

  setUp(() async {
    await isar.writeTxn(() async {
      await isar.clear();
    });
    library = LibraryRepository(_TestStorage(isar));
    downloads = DownloadsRepository(_TestStorage(isar));
  });

  dto.Manga entry(String title, {dto.ItemType type = dto.ItemType.manga}) =>
      dto.Manga(
        id: 0,
        title: title,
        sourceId: 0,
        url: 'https://example.com/$title',
        itemType: type,
        dateAdded: DateTime.now(),
      );

  group('removeFromLibraryMany (the delete fix)', () {
    test('deletes the manga row, its chapters, its download rows and '
        'history rows', () async {
      final id = await library.addToLibrary(
        entry('Test Manga'),
        chapters: [
          dto.Chapter(
              id: 0, url: 'https://c/1', name: 'Ch 1', number: 1),
          dto.Chapter(
              id: 0, url: 'https://c/2', name: 'Ch 2', number: 2),
        ],
      );
      final chapterId =
          (await library.getChapters(id)).first.id;
      await downloads.enqueue(
        mangaId: id,
        chapterId: chapterId,
        mangaTitle: 'Test Manga',
        chapterName: 'Ch 1',
        isAnime: false,
      );
      await isar.writeTxn(() async {
        await isar.historys.put(db_h.History(
          mangaId: id,
          chapterId: chapterId,
          chapterName: 'Ch 1',
          mangaTitle: 'Test Manga',
          isAnime: false,
          progress: 0.5,
          lastReadAt: DateTime.now().millisecondsSinceEpoch,
        ));
      });

      final removed = await library.removeFromLibraryMany([id]);
      expect(removed, 1);
      expect(await isar.mangas.count(), 0);
      expect(await isar.chapters.count(), 0);
      expect(await isar.downloads.count(), 0);
      expect(await isar.historys.count(), 0);
    });

    test('deleteChapterDownload resets the chapter flag and removes the '
        'queue row', () async {
      final id = await library.addToLibrary(
        entry('Flag Reset'),
        chapters: [
          dto.Chapter(id: 0, url: 'https://f/1', name: 'Ch 1', number: 1),
        ],
      );
      final chapterId = (await library.getChapters(id)).first.id;
      await downloads.enqueue(
        mangaId: id,
        chapterId: chapterId,
        mangaTitle: 'Flag Reset',
        chapterName: 'Ch 1',
        isAnime: false,
      );
      // Simulate a completed download.
      await isar.writeTxn(() async {
        final c = await isar.chapters.get(chapterId);
        c!.isDownloaded = true;
        await isar.chapters.put(c);
      });

      await downloads.removeByChapter(chapterId);

      expect(await isar.downloads.count(), 0, reason: 'queue row removed');
      final after = await library.getChapters(id);
      expect(after.first.isDownloaded, false,
          reason: 'chapter flag reset so the UI shows the honest state');
    });

    test('markAllChaptersRead flips every chapter and the counters', () async {
      final id = await library.addToLibrary(
        entry('Mark Read'),
        chapters: [
          dto.Chapter(id: 0, url: 'https://m/1', name: '1', number: 1),
          dto.Chapter(id: 0, url: 'https://m/2', name: '2', number: 2),
          dto.Chapter(id: 0, url: 'https://m/3', name: '3', number: 3),
        ],
      );
      await library.markAllChaptersRead(id, read: true);
      final chapters = await library.getChapters(id);
      expect(chapters.every((c) => c.isRead), isTrue);

      await library.markAllChaptersRead(id, read: false);
      final after = await library.getChapters(id);
      expect(after.every((c) => !c.isRead), isTrue);
    });

    test('setMangaCategory persists the assignment', () async {
      await library.ensureDefaultCategories();
      final id = await library.addToLibrary(entry('Categorize'));
      final cats = await library.getCategories();
      final reading =
          cats.firstWhere((c) => c.name == 'Reading');

      await library.setMangaCategory(id, reading.id);

      final row = await isar.mangas.get(id);
      expect(row!.category, 'Reading');
    });

    test('saveBookProgress + getBookProgress round-trip', () async {
      final id = await library.addToLibrary(entry('A Book',
          type: dto.ItemType.book));
      await library.saveBookProgress(
        id,
        currentPage: 42,
        totalPages: 300,
        progress: 0.14,
      );
      final (page, total) = await library.getBookProgress(id);
      expect(page, 42);
      expect(total, 300);
    });

    test('chapters are LINKED to their manga after addToLibrary '
        '(Isar async-put link regression)', () async {
      // Regression guard: Isar 3's async put/putAll silently skip link
      // persistence. Before the explicit `chapter.manga.save()` fix, every
      // chapter row was stored as an orphan — the detail screen showed
      // "no chapters" for everything added from Browse, which is exactly
      // the "extensions provide no content" symptom.
      final id = await library.addToLibrary(
        entry('Linked Manga'),
        chapters: [
          dto.Chapter(id: 0, url: 'https://l/1', name: 'Ch 1', number: 1),
          dto.Chapter(id: 0, url: 'https://l/2', name: 'Ch 2', number: 2),
        ],
      );
      final chapters = await library.getChapters(id);
      expect(chapters.length, 2, reason: 'chapters must be linked, not orphaned');

      // And the deep-link resolution used by /reader/:chapterId.
      final (manga, chapter) = await library.resolveChapter(chapters.first.id);
      expect(manga?.id, id);
      expect(chapter?.name, 'Ch 1');

      // And setChapters (the updater path) preserves the links too.
      await library.setChapters(id, [
        dto.Chapter(id: 0, url: 'https://l/1', name: 'Ch 1 v2', number: 1),
        dto.Chapter(id: 0, url: 'https://l/3', name: 'Ch 3', number: 3),
      ]);
      final refreshed = await library.getChapters(id);
      expect(refreshed.length, 2);
      expect(refreshed.map((c) => c.name), containsAll(['Ch 1 v2', 'Ch 3']));
    });

    test('deleteAllFiles keeps imported files (imports/ is not wiped)',
        () async {
      // The "clear download cache" footgun: imports used to live under the
      // same tree that got recursively deleted. deleteAllFiles must only
      // remove chapters/, never imports/.
      final storage = _TestStorage(isar);
      final baseDir = await storage.getDownloadsDir();
      final importsDir = Directory('$baseDir/imports');
      await importsDir.create(recursive: true);
      final imported =
          File('${importsDir.path}/my-novel.txt')..writeAsStringSync('hello');

      await downloads.deleteAllFiles();

      expect(imported.existsSync(), isTrue,
          reason: 'imported files must survive a download wipe');
    });
  });
}

/// Minimal StorageProvider stand-in for tests (the real one wires path_provider
/// through the Flutter binary — not available in a plain unit test).
class _TestStorage implements StorageProvider {
  _TestStorage(this._isar);

  final Isar _isar;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getDownloadsDir) {
      // Route to a temp dir so the imports-preservation test is hermetic.
      return Future.value(
          '${Directory.systemTemp.path}/lumina-downloads-test');
    }
    if (invocation.memberName == #isar) return _isar;
    return super.noSuchMethod(invocation);
  }
}
