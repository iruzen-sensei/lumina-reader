// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// LIBRARY REPOSITORY — the only component allowed to persist manga, chapters
// and categories. Screens talk to providers; providers talk to repositories;
// repositories talk to Isar through the mappers in `models/mappers.dart`.

import 'dart:async';

import 'package:isar/isar.dart';

import '../models/category.dart' as db;
import '../models/chapter.dart' as db;
import '../models/manga.dart' as db;
import '../models/mappers.dart' as map;
import '../models/models.dart' as dto;
import '../providers/storage_provider.dart';

class LibraryRepository {
  LibraryRepository(StorageProvider storage) : _isar = storage.isar;
  final Isar _isar;

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
    await _isar.writeTxn(() async {
      final m = await _isar.mangas.get(mangaId);
      if (m != null) {
        await m.chapters.load();
        await _isar.chapters.deleteAll(m.chapters.map((c) => c.id!).toList());
      }
      await _isar.mangas.delete(mangaId);
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

  /// Emits whenever any manga/chapter/category row changes.
  Stream<void> watchLibrary() {
    return _isar.mangas.watchLazy(fireImmediately: true);
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
