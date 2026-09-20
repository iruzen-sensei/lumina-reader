// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// EXTENSION COORDINATOR — the single bridge between the app's providers and
// the extension world (eval/). It:
//   * resolves which service handles a source (getExtensionService),
//   * translates eval DTOs (MManga/MChapter) into presentation DTOs,
//   * resolves chapter/episode deep-links back to their source,
//   * converts failures into empty results + logged diagnostics so a broken
//     source can never crash a screen.
//
// Every network-content provider goes through here — screens never touch
// extension services directly.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lumina_reader/data/library_repository.dart';
import 'package:lumina_reader/data/sources_repository.dart';
import 'package:lumina_reader/eval/interface.dart';
import 'package:lumina_reader/eval/lib.dart' as eval;
import 'package:lumina_reader/eval/model/m_models.dart' as m;
import 'package:lumina_reader/models/models.dart' as dto;
import 'package:lumina_reader/providers/storage_provider.dart';

class ExtensionCoordinator {
  ExtensionCoordinator({
    required SourcesRepository sources,
    required LibraryRepository library,
  })  : _sources = sources,
        _library = library;

  final SourcesRepository _sources;
  final LibraryRepository _library;

  final Map<int, ExtensionService> _services = {};

  // -----------------------------------------------------------------------
  // Service resolution
  // -----------------------------------------------------------------------

  Future<ExtensionService?> _serviceForSourceId(int sourceId) async {
    final cached = _services[sourceId];
    if (cached != null) return cached;
    final row = await _sources.getSource(sourceId);
    if (row == null) return null;
    final service = eval.getExtensionService(row);
    if (service is! eval.NullExtensionService) {
      // NullExtensionService is cheap to rebuild; real services are cached.
      try {
        await service.init();
      } catch (e) {
        debugPrint('ExtensionCoordinator: init($sourceId) failed: $e');
        return null;
      }
      _services[sourceId] = service;
    }
    return service;
  }

  /// HTTP headers the given source requires on EVERY request, including
  /// page-image GETs (Madara-family CDNs 403 hotlinks without a Referer).
  /// The reader passes these to the image widget so scraped sources
  /// actually render.
  Future<Map<String, String>> sourceHeaders(int sourceId) async {
    try {
      final service = await _serviceForSourceId(sourceId);
      if (service == null) return const {};
      return await service.getHeaders();
    } catch (_) {
      return const {};
    }
  }

  // -----------------------------------------------------------------------
  // Catalog operations (Browse)
  // -----------------------------------------------------------------------

  /// Throws on failure — the Browse feed renders an explicit error state
  /// with a retry action. (Previously every failure was silently converted
  /// to an empty list, indistinguishable from "no results", which is why
  /// the extensions screen *looked* like nothing ever loaded.)
  Future<List<dto.Manga>> popular(int sourceId, {int page = 1}) async {
    final service = await _serviceForSourceId(sourceId);
    if (service == null) {
      throw StateError(
          'This source is unavailable or its format is not supported yet.');
    }
    final entries = await service.getPopular(page);
    return entries.map((e) => _mangaToDto(e, sourceId)).toList();
  }

  /// See [popular] — throws on failure for the same reason.
  Future<List<dto.Manga>> latest(int sourceId, {int page = 1}) async {
    final service = await _serviceForSourceId(sourceId);
    if (service == null) {
      throw StateError(
          'This source is unavailable or its format is not supported yet.');
    }
    final entries = await service.getLatestUpdates(page);
    return entries.map((e) => _mangaToDto(e, sourceId)).toList();
  }

  Future<List<dto.Manga>> search(int sourceId, String query,
      {int page = 1}) async {
    final service = await _serviceForSourceId(sourceId);
    if (service == null) return const [];
    try {
      final entries = await service.searchManga(
        query: query,
        page: page,
        filterList: const m.FilterList(filters: []),
      );
      return entries.map((e) => _mangaToDto(e, sourceId)).toList();
    } catch (e) {
      debugPrint('ExtensionCoordinator.search($sourceId, "$query"): $e');
      return const [];
    }
  }

  /// Full detail (description, author, chapters) for a catalog entry.
  Future<dto.Manga> detail(int sourceId, String url) async {
    final service = await _serviceForSourceId(sourceId);
    if (service == null) {
      return dto.Manga(
        id: 0,
        title: url,
        sourceId: sourceId,
        url: url,
        itemType: dto.ItemType.manga,
        dateAdded: DateTime.now(),
      );
    }
    try {
      final info = await service.getMangaDetail(url);
      final chapters = await service.getChapterList(url);
      final result = _mangaToDto(info, sourceId);
      result.chapters = _chaptersToDto(chapters);
      result.totalChapters = result.chapters.length;
      result.unreadCount = result.chapters.length;
      return result;
    } catch (e) {
      debugPrint('ExtensionCoordinator.detail($sourceId, $url): $e');
      rethrow;
    }
  }

  // -----------------------------------------------------------------------
  // Chapter operations (Reader)
  // -----------------------------------------------------------------------

  /// Page image URLs for a chapter, resolved through its manga's source.
  ///
  /// Offline-first: when the chapter was downloaded (DownloadEngine writes
  /// images to `<downloads>/chapters/<mangaId>/<chapterId>/`), the local
  /// `file://` URIs are returned instead of hitting the network.
  Future<List<String>> pageList(int chapterId) async {
    final (manga, chapter) = await _library.resolveChapter(chapterId);
    if (manga == null || chapter == null) return const [];

    // Downloaded chapters — serve from disk.
    if (chapter.isDownloaded) {
      final local = await _localChapterPages(manga.id, chapterId);
      if (local.isNotEmpty) return local;
      // Corrupt/emptied directory → fall through to the network path.
    }

    if (manga.sourceId == 0) return const [];
    final service = await _serviceForSourceId(manga.sourceId);
    if (service == null) return const [];
    try {
      return await service.getPageList(chapter.url);
    } catch (e) {
      debugPrint('ExtensionCoordinator.pageList($chapterId): $e');
      return const [];
    }
  }

  Future<List<String>> _localChapterPages(int mangaId, int chapterId) async {
    try {
      final base = await StorageProvider().getDownloadsDir();
      final dir = Directory('$base/chapters/$mangaId/$chapterId');
      if (!await dir.exists()) return const [];
      final files = (await dir.list().toList())
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.jpg') ||
              f.path.endsWith('.jpeg') ||
              f.path.endsWith('.png') ||
              f.path.endsWith('.webp') ||
              f.path.endsWith('.gif') ||
              f.path.endsWith('.avif'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return [
        for (final f in files) Uri.file(f.path).toString(),
      ];
    } catch (e) {
      debugPrint('ExtensionCoordinator._localChapterPages($chapterId): $e');
      return const [];
    }
  }

  /// Available video streams for an episode (anime sources).
  Future<List<dto.VideoQuality>> videoList(int episodeId) async {
    final (manga, episode) = await _library.resolveChapter(episodeId);
    if (manga == null || episode == null) return const [];

    // Downloaded episodes — serve the local .ts file instead of the network.
    if (episode.isDownloaded) {
      try {
        final base = await StorageProvider().getDownloadsDir();
        final f = File('$base/chapters/${manga.id}/$episodeId/$episodeId.ts');
        if (await f.exists()) {
          return [
            dto.VideoQuality('Downloaded', Uri.file(f.path).toString(), 0)
          ];
        }
      } catch (_) {/* fall through */}
    }

    // Locally imported video (ItemType.anime with a file path, sourceId 0) —
    // previously unreachable: videoList refused any episode whose manga had
    // no source, so imported videos could never play.
    final epUrl = episode.url;
    if (manga.sourceId == 0 ||
        epUrl.startsWith('/') ||
        epUrl.startsWith('file:')) {
      if (epUrl.isNotEmpty) {
        return [
          dto.VideoQuality(
            'Local file',
            epUrl.startsWith('file:') ? epUrl : Uri.file(epUrl).toString(),
            0,
          )
        ];
      }
      return const [];
    }

    final service = await _serviceForSourceId(manga.sourceId);
    if (service == null) return const [];
    try {
      final videos = await service.getVideoList(episode.url);
      return [
        for (final v in videos)
          dto.VideoQuality(
            v.quality ?? v.title ?? 'Stream',
            v.originalUrl ?? v.url,
            _heightFromLabel(v.quality),
          ),
      ].where((q) => q.url.isNotEmpty).toList();
    } catch (e) {
      debugPrint('ExtensionCoordinator.videoList($episodeId): $e');
      return const [];
    }
  }

  // -----------------------------------------------------------------------
  // DTO translation (eval MManga/MChapter → presentation)
  // -----------------------------------------------------------------------

  dto.Manga _mangaToDto(m.MManga e, int sourceId) {
    return dto.Manga(
      id: 0, // not yet persisted — ids are assigned by Isar on library add
      title: e.name ?? e.link ?? 'Untitled',
      sourceId: sourceId,
      url: e.link ?? '',
      itemType: e.isAnime == true ? dto.ItemType.anime : dto.ItemType.manga,
      author: (e.author == null || e.author!.isEmpty) ? null : e.author,
      artist: (e.artist == null || e.artist!.isEmpty) ? null : e.artist,
      description: (e.description == null || e.description!.trim().isEmpty)
          ? null
          : e.description,
      genre: e.categories ??
          (e.genre?.split(',').map((g) => g.trim()).toList() ?? const []),
      status: _statusFromCode(e.status),
      thumbnailUrl: e.imageUrl,
      favorite: false,
      dateAdded: DateTime.now(),
    );
  }

  List<dto.Chapter> _chaptersToDto(List<m.MChapter> chapters) {
    return [
      for (final c in chapters)
        dto.Chapter(
          id: 0, // assigned on persist
          url: c.url ?? '',
          name: c.name ?? 'Chapter ${c.chapterNumber ?? ''}',
          number: double.tryParse(c.chapterNumber ?? '') ?? 0,
          scanlator: (c.scanlator == null || c.scanlator!.isEmpty)
              ? null
              : c.scanlator,
          dateUploaded: c.dateUpload == null
              ? null
              : DateTime.tryParse(c.dateUpload!) ??
                  DateTime.fromMillisecondsSinceEpoch(
                      int.tryParse(c.dateUpload!) ?? 0),
        ),
    ]..sort((a, b) => b.number.compareTo(a.number)); // newest first
  }

  dto.ItemStatus _statusFromCode(String? code) {
    switch (code) {
      case '1':
        return dto.ItemStatus.ongoing;
      case '2':
        return dto.ItemStatus.completed;
      case '3':
        return dto.ItemStatus.licensed;
      case '4':
        return dto.ItemStatus.publishingFinished;
      case '5':
        return dto.ItemStatus.cancelled;
      case '6':
        return dto.ItemStatus.onHiatus;
      default:
        return dto.ItemStatus.unknown;
    }
  }

  int _heightFromLabel(String? label) {
    if (label == null) return 0;
    final match = RegExp(r'(\d{3,4})').firstMatch(label);
    return match == null ? 0 : int.parse(match.group(1)!) ;
  }

  /// Disposes every cached service (called on logout / source purge).
  Future<void> disposeAll() async {
    for (final s in _services.values) {
      try {
        await s.dispose();
      } catch (_) {}
    }
    _services.clear();
  }
}
