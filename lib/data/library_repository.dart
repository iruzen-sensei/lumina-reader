// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// LIBRARY REPOSITORY — the only component allowed to persist manga, chapters
// and categories. Screens talk to providers; providers talk to repositories;
// repositories talk to Isar through the mappers in `models/mappers.dart`.

import 'dart:async';
import 'dart:io';

import 'package:isar/isar.dart';

import '../models/category.dart' as db;
import '../models/chapter.dart' as db;
import '../models/download.dart' as db_dl;
import '../models/history.dart' as db_h;
import '../models/manga.dart' as db;
import '../models/mappers.dart' as map;
import '../models/models.dart' as dto;
import '../models/note.dart' as db_n;
import '../models/reading_session.dart';
import '../models/update.dart';
import '../providers/storage_provider.dart';

class LibraryRepository {
  LibraryRepository(StorageProvider storage)
      : _isar = storage.isar,
        _storage = storage;
  final Isar _isar;
  final StorageProvider _storage;

  // -----------------------------------------------------------------------
  // Reads
  // -----------------------------------------------------------------------

  /// All library entries with their chapters loaded, mapped to DTOs.
  Future<List<dto.Manga>> getLibrary() async {
    final categories = await _categoryIdMap();
    final mangas = await _isar.mangas.where().findAll();
    final result = <dto.Manga>[];
    for (final m in mangas) {
      await m.chapters.load();
      result.add(map.mangaToDto(m,
          chapters: m.chapters.toList(),
          categoryIdsByName: categories));
    }
    return result;
  }

  dto.Manga? getMangaSync(int id) {
    final m = _isar.mangas.getSync(id);
    if (m == null) return null;
    m.chapters.loadSync();
    return map.mangaToDto(m, chapters: m.chapters.toList());
  }

  Future<dto.Manga?> getManga(int id) async {
    final m = await _isar.mangas.get(id);
    if (m == null) return null;
    await m.chapters.load();
    return map.mangaToDto(m, chapters: m.chapters.toList());
  }

  /// Finds a library entry by its source URL — the stable identity of a
  /// catalog item across Browse sessions. Used to detect "already in
  /// library" when the user taps a browse/search result (previously every
  /// browse item opened a fresh preview because browse DTOs carry id 0).
  Future<dto.Manga?> getMangaBySourceUrl(String url) async {
    if (url.isEmpty) return null;
    final m = await _isar.mangas.filter().sourceUrlEqualTo(url).findFirst();
    if (m == null) return null;
    await m.chapters.load();
    return map.mangaToDto(m, chapters: m.chapters.toList());
  }

  /// Finds a library entry by its AniList id cross-reference tag
  /// (`anilist:<id>` in tags). Calendar entries only know the AniList id —
  /// previously the calendar pushed /animeDetail/<anilistId> which resolved
  /// to "Not found" for everything not already in the library.
  Future<dto.Manga?> findByAniListId(int anilistId) async {
    final rows = await _isar.mangas
        .filter()
        .tagsElementEqualTo('anilist:$anilistId')
        .findAll();
    if (rows.isEmpty) return null;
    final m = rows.first;
    await m.chapters.load();
    return map.mangaToDto(m, chapters: m.chapters.toList());
  }

  Future<List<dto.Chapter>> getChapters(int mangaId) async {
    final m = await _isar.mangas.get(mangaId);
    if (m == null) return const [];
    await m.chapters.load();
    return m.chapters.map(map.chapterToDto).toList();
  }

  /// Resolves a chapter deep-link (`/reader/:chapterId`) to its parent manga
  /// and chapter — the routing contract the original skeleton broke.
  Future<(dto.Manga?, dto.Chapter?)> resolveChapter(int chapterId) async {
    final c = await _isar.chapters.get(chapterId);
    if (c == null) return (null, null);
    await c.manga.load();
    final m = c.manga.value;
    if (m == null) return (null, map.chapterToDto(c));
    await m.chapters.load();
    return (
      map.mangaToDto(m, chapters: m.chapters.toList()),
      map.chapterToDto(c),
    );
  }

  // -----------------------------------------------------------------------
  // Writes
  // -----------------------------------------------------------------------

  /// Adds (or refreshes) a discovered item in the library.
  /// Returns the persisted manga id.
  Future<int> addToLibrary(dto.Manga item, {List<dto.Chapter>? chapters}) async {
    final existing = await _findByTitleAndSource(item.title, item.sourceId);
    final manga = map.mangaFromDto(item, existingId: existing?.id);
    final id = await _isar.writeTxn(() async {
      final mangaId = await _isar.mangas.put(manga);
      if (chapters != null && chapters.isNotEmpty) {
        await _replaceChapters(mangaId, chapters);
      }
      return mangaId;
    });
    return id;
  }

  Future<void> removeFromLibrary(int mangaId) async {
    await removeFromLibraryMany([mangaId]);
  }

  /// Removes entries AND everything they own: chapter rows, download-queue
  /// rows, downloaded page files on disk and the imported source file for
  /// local books. Returns the number of entries actually removed.
  ///
  /// This is the ONE call every delete affordance in the app funnels
  /// through (selection bar, detail screen, anime library) — previously the
  /// selection bar's trash icon only showed a snackbar and the detail
  /// screen's button only flipped a favorite bit, which is exactly why
  /// "you can't delete anything" was reported.
  Future<int> removeFromLibraryMany(List<int> mangaIds) async {
    if (mangaIds.isEmpty) return 0;
    final removed = <int>[];
    final baseDir = await _storage.getDownloadsDir();
    for (final id in mangaIds) {
      final m = await _isar.mangas.get(id);
      if (m == null) continue;

      // 1. Chapter rows (collect chapter ids before deleting).
      await m.chapters.load();
      final chapterIds = m.chapters.map((c) => c.id!).toList();

      // 2. Download-queue rows referencing this manga's chapters.
      final dlIds = <int>{};
      for (final cid in chapterIds) {
        final rows =
            await _isar.downloads.filter().chapterIdEqualTo(cid).findAll();
        dlIds.addAll(rows.map((d) => d.id));
      }
      if (dlIds.isNotEmpty) {
        await _isar.writeTxn(
            () async => _isar.downloads.deleteAll(dlIds.toList()));
      }

      // 3. Downloaded page files on disk.
      final mangaChapterDir = Directory('$baseDir/chapters/$id');
      if (mangaChapterDir.existsSync()) {
        try {
          await mangaChapterDir.delete(recursive: true);
        } catch (_) {
          // Best-effort: a locked file must not block the DB removal.
        }
      }

      // 4. Imported local file (epub/pdf/cbz under imports/).
      final imported = m.filePath;
      if (imported != null && imported.isNotEmpty) {
        final f = File(imported);
        if (f.existsSync()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }

      // 5. History + notes rows for this entry.
      final historyRows = await _isar.historys
          .filter()
          .mangaIdEqualTo(id)
          .findAll();
      if (historyRows.isNotEmpty) {
        await _isar.writeTxn(() async => _isar.historys
            .deleteAll(historyRows.map((h) => h.id).toList()));
      }
      final noteRows = await _isar.notes
          .filter()
          .manga((q) => q.idEqualTo(id))
          .findAll();
      if (noteRows.isNotEmpty) {
        await _isar.writeTxn(() async => _isar.notes
            .deleteAll(noteRows.map((n) => n.id!).toList()));
      }

      // 5b. Updates-feed rows + reading sessions for this entry.
      // Without this, deleting a manga leaves dead tiles in the Updates
      // feed ("Not found" on tap) and stats/heatmap/streak keep counting
      // the deleted entry's sessions.
      final updateRows =
          await _isar.updates.filter().mangaIdEqualTo(id).findAll();
      if (updateRows.isNotEmpty) {
        await _isar.writeTxn(() async => _isar.updates
            .deleteAll(updateRows.map((u) => u.id).toList()));
      }
      final sessionRows = await _isar.readingSessions
          .filter()
          .manga((q) => q.idEqualTo(id))
          .findAll();
      if (sessionRows.isNotEmpty) {
        await _isar.writeTxn(() async => _isar.readingSessions
            .deleteAll(sessionRows.map((s) => s.id!).toList()));
      }

      // 6. The manga row + chapters in one transaction.
      await _isar.writeTxn(() async {
        await _isar.chapters.deleteAll(chapterIds);
        await _isar.mangas.delete(id);
      });
      removed.add(id);
    }
    return removed.length;
  }

  /// Deletes the downloaded files of ONE chapter (keeps the library entry).
  /// Also removes any download-queue rows and resets the chapter's
  /// `isDownloaded` flag so the UI immediately shows the honest state.
  Future<void> deleteChapterDownload(int chapterId) async {
    final c = await _isar.chapters.get(chapterId);
    if (c == null) return;
    await c.manga.load();
    final m = c.manga.value;

    final dlRows = await _isar.downloads
        .filter()
        .chapterIdEqualTo(chapterId)
        .findAll();
    if (dlRows.isNotEmpty) {
      await _isar.writeTxn(
          () async => _isar.downloads.deleteAll(dlRows.map((d) => d.id).toList()));
    }

    if (m != null) {
      final baseDir = await _storage.getDownloadsDir();
      final dir = Directory('$baseDir/chapters/${m.id}/$chapterId');
      if (dir.existsSync()) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }

    await _isar.writeTxn(() async {
      c
        ..isDownloaded = false
        ..isDownloading = false
        ..downloadProgress = 0.0;
      await _isar.chapters.put(c);
    });
  }

  /// Marks EVERY chapter/episode of a manga read or unread in one
  /// transaction (selection-bar "Mark as read" / detail "mark all").
  Future<void> markAllChaptersRead(int mangaId, {required bool read}) async {
    final m = await _isar.mangas.get(mangaId);
    if (m == null) return;
    await m.chapters.load();
    final rows = m.chapters.toList();
    if (rows.isEmpty) return;
    for (final c in rows) {
      c.isRead = read;
    }
    await _isar.writeTxn(() async {
      await _isar.chapters.putAll(rows);
      m.readCount = read ? rows.length : 0;
      await _isar.mangas.put(m);
    });
  }

  /// Assigns an entry to a category (the DB stores a single category name
  /// per row; the DTO surface exposes ids through the name→id map).
  Future<void> setMangaCategory(int mangaId, int categoryId) async {
    final cat = await _isar.categorys.get(categoryId);
    if (cat == null) return;
    await _isar.writeTxn(() async {
      final m = await _isar.mangas.get(mangaId);
      if (m == null) return;
      m.category = cat.name;
      await _isar.mangas.put(m);
    });
  }

  /// Reads the persisted reading position for imported books.
  /// Returns (currentPage, totalPages).
  Future<(int, int)> getBookProgress(int mangaId) async {
    final m = await _isar.mangas.get(mangaId);
    return ((m?.currentPage ?? 1).clamp(1, 1000000), m?.totalPages ?? 0);
  }

  /// Persists reading position for imported books (EPUB / PDF / CBZ).
  /// The manga row already carries currentPage/totalPages/progress — this
  /// just makes the readers actually write to it.
  Future<void> saveBookProgress(
    int mangaId, {
    int? currentPage,
    int? totalPages,
    double? progress,
    bool? isFinished,
  }) async {
    await _isar.writeTxn(() async {
      final m = await _isar.mangas.get(mangaId);
      if (m == null) return;
      if (currentPage != null) m.currentPage = currentPage;
      if (totalPages != null && totalPages > 0) m.totalPages = totalPages;
      if (progress != null) m.progress = progress.clamp(0.0, 1.0);
      if (isFinished != null) m.isFinished = isFinished;
      m.lastReadAt = DateTime.now();
      await _isar.mangas.put(m);
    });
  }

  Future<void> toggleFavorite(int mangaId) async {
    await _isar.writeTxn(() async {
      final m = await _isar.mangas.get(mangaId);
      if (m == null) return;
      m.isFavorite = !m.isFavorite;
      await _isar.mangas.put(m);
    });
  }

  /// Upserts the chapter list for a manga from an extension's detail result.
  /// Preserves read/download progress on chapters that already exist
  /// (matched by URL).
  Future<void> setChapters(int mangaId, List<dto.Chapter> chapters) async {
    await _isar.writeTxn(() => _replaceChapters(mangaId, chapters));
  }

  /// Persists reading progress for one chapter. Called by the reader on page
  /// changes / chapter completion.
  Future<void> saveChapterProgress(
    int chapterId, {
    int? lastPageRead,
    bool? isRead,
    bool? isBookmarked,
    int? pageCount,
  }) async {
    await _isar.writeTxn(() async {
      final c = await _isar.chapters.get(chapterId);
      if (c == null) return;
      if (lastPageRead != null) c.lastPageRead = lastPageRead;
      if (isRead != null) c.isRead = isRead;
      if (isBookmarked != null) c.isBookmarked = isBookmarked;
      if (pageCount != null && pageCount > 0) c.pageCount = pageCount;
      await _isar.chapters.put(c);
      // Bump the parent's lastReadAt so "sort by last read" stays truthful.
      await c.manga.load();
      final m = c.manga.value;
      if (m != null) {
        m.lastReadAt = DateTime.now();
        await _isar.mangas.put(m);
      }
    });
  }

  /// Marks a chapter read/unread and updates the parent counters.
  Future<void> markChapterRead(int chapterId, {required bool read}) async {
    await saveChapterProgress(chapterId, isRead: read);
  }

  // -----------------------------------------------------------------------
  // Categories
  // -----------------------------------------------------------------------

  Future<List<dto.Category>> getCategories() async {
    final cats = await _isar.categorys.where().sortByPosition().findAll();
    if (cats.isEmpty) return const [];
    return cats.map(map.categoryToDto).toList();
  }

  /// Seeds the default categories on first run and returns them.
  Future<List<dto.Category>> ensureDefaultCategories() async {
    final existing = await _isar.categorys.where().findAll();
    if (existing.isNotEmpty) {
      return existing.map(map.categoryToDto).toList();
    }
    final defaults = [
      db.Category(name: 'Default', position: 0, isDefault: true, type: db.CategoryType.mixed),
      db.Category(name: 'Reading', position: 1, type: db.CategoryType.mixed),
      db.Category(name: 'Plan to read', position: 2, type: db.CategoryType.mixed),
    ];
    await _isar.writeTxn(() async {
      await _isar.categorys.putAll(defaults);
    });
    return defaults.map(map.categoryToDto).toList();
  }

  // -----------------------------------------------------------------------
  // Streams (reactive UI)
  // -----------------------------------------------------------------------

  /// Emits whenever any manga/chapter/category row changes. Watches the
  /// chapters collection too, so download/read flag writes (which touch
  /// only chapter rows) also re-emit — previously a finished download's
  /// checkmark appeared only after the next manga-row write.
  Stream<void> watchLibrary() {
    return _mergeStreams([
      _isar.mangas.watchLazy(fireImmediately: true),
      _isar.chapters.watchLazy(fireImmediately: false),
    ]);
  }

  /// Fan-in helper: emits when any source stream emits. (package:async's
  /// StreamGroup is not a direct dependency; a small controller avoids
  /// adding it to pubspec just for this.)
  static Stream<void> _mergeStreams(List<Stream<void>> streams) {
    // The controller is handed to the consumer; cancelling the returned
    // stream subscription drives onCancel below.
    // ignore: close_sinks
    final controller = StreamController<void>();
    final subs = <StreamSubscription<void>>[];
    controller.onListen = () {
      for (final s in streams) {
        subs.add(s.listen((_) {
          if (!controller.isClosed) controller.add(null);
        }));
      }
    };
    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  Stream<void> watchCategories() {
    return _isar.categorys.watchLazy(fireImmediately: true);
  }

  // -----------------------------------------------------------------------
  // Internals
  // -----------------------------------------------------------------------

  Future<db.Manga?> _findByTitleAndSource(String title, int sourceId) async {
    if (sourceId == 0) return null;
    return _isar.mangas
        .filter()
        .nameEqualTo(title)
        .and()
        .sourceIdEqualTo(sourceId)
        .findFirst();
  }

  Future<Map<String, int>> _categoryIdMap() async {
    final cats = await _isar.categorys.where().findAll();
    return {for (final c in cats) c.name: c.id};
  }

  Future<void> _replaceChapters(int mangaId, List<dto.Chapter> chapters) async {
    final m = await _isar.mangas.get(mangaId);
    if (m == null) return;
    await m.chapters.load();
    final existingByUrl = {
      for (final c in m.chapters) c.url: c,
    };
    final toPut = <db.Chapter>[];
    for (final dtoChapter in chapters) {
      final existing = existingByUrl[dtoChapter.url];
      final dbChapter = map.chapterFromDto(
        dtoChapter,
        existingId: existing?.id,
      );
      // Preserve user progress over the extension's stale state.
      if (existing != null) {
        dbChapter.isRead = existing.isRead;
        dbChapter.lastPageRead = existing.lastPageRead;
        dbChapter.isDownloaded = existing.isDownloaded;
        dbChapter.isBookmarked = existing.isBookmarked;
      }
      dbChapter.manga.value = m;
      toPut.add(dbChapter);
    }
    await _isar.chapters.putAll(toPut);
    // ⚠ Isar 3's ASYNC put/putAll do NOT persist links — only the *_Sync
    // APIs do. The explicit save() below is what actually links each
    // chapter to its manga. Without it every chapter row was stored as an
    // ORPHAN: the detail screen then showed "no chapters" for everything
    // added from Browse — the root cause of "extensions provide no
    // content" even after the routing bugs were fixed.
    for (final c in toPut) {
      await c.manga.save();
    }
    // Delete chapters that no longer exist upstream.
    final newUrls = chapters.map((c) => c.url).toSet();
    final stale = m.chapters.where((c) => !newUrls.contains(c.url)).toList();
    if (stale.isNotEmpty) {
      await _isar.chapters.deleteAll(stale.map((c) => c.id!).toList());
    }
    m.chapterCount = toPut.length;
    await _isar.mangas.put(m);
  }
}
