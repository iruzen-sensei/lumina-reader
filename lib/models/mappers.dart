// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// MODEL MAPPERS — the single bridge between the Isar persistence layer
// (lib/models/*.dart, the source of truth) and the presentation DTO layer
// (lib/models/models.dart, the shapes screens consume).
//
// RULES:
//  * This is the ONLY file allowed to import both model systems.
//  * Repositories call these mappers; screens never see Isar types.
//  * Field drift between the two layers must be resolved HERE, in one place.

import 'package:isar/isar.dart' show Isar;

import 'manga.dart' as db;
import 'chapter.dart' as db;
import 'note.dart' as db;
import 'history.dart' as db;
import 'update.dart' as db;
import 'source.dart' as db;
import 'category.dart' as db;
import 'download.dart' as db;
import 'settings.dart' as db;
import 'models.dart' as dto;

// ---------------------------------------------------------------------------
// Manga
// ---------------------------------------------------------------------------

dto.ItemType _itemTypeToDto(db.ItemType type) => dto.ItemType.values[type.index];

db.ItemType _itemTypeFromDto(dto.ItemType type) => db.ItemType.values[type.index];

dto.ItemStatus _statusToDto(db.Status status) {
  switch (status) {
    case db.Status.ongoing:
      return dto.ItemStatus.ongoing;
    case db.Status.completed:
      return dto.ItemStatus.completed;
    case db.Status.canceled:
      return dto.ItemStatus.cancelled;
    case db.Status.onHiatus:
      return dto.ItemStatus.onHiatus;
    case db.Status.publishingFinished:
      return dto.ItemStatus.publishingFinished;
    case db.Status.unknown:
      return dto.ItemStatus.unknown;
  }
}

db.Status _statusFromDto(dto.ItemStatus status) {
  switch (status) {
    case dto.ItemStatus.ongoing:
      return db.Status.ongoing;
    case dto.ItemStatus.completed:
      return db.Status.completed;
    case dto.ItemStatus.licensed:
      // No Isar equivalent — model as ongoing with a note in tags upstream.
      return db.Status.ongoing;
    case dto.ItemStatus.publishingFinished:
      return db.Status.publishingFinished;
    case dto.ItemStatus.onHiatus:
      return db.Status.onHiatus;
    case dto.ItemStatus.cancelled:
      return db.Status.canceled;
    case dto.ItemStatus.unknown:
      return db.Status.unknown;
  }
}

/// Converts a persisted [db.Manga] (with its chapters) into the presentation
/// [dto.Manga] consumed by screens.
dto.Manga mangaToDto(
  db.Manga m, {
  List<db.Chapter> chapters = const [],
  Map<String, int> categoryIdsByName = const {},
}) {
  final dtoChapters = chapters.map(chapterToDto).toList();
  final unread =
      dtoChapters.where((c) => !c.isRead).length;
  double lastRead = 0;
  for (final c in dtoChapters) {
    if (c.isRead && c.number > lastRead) lastRead = c.number;
  }
  return dto.Manga(
    id: m.id ?? 0,
    title: m.name,
    sourceId: m.sourceId ?? 0,
    url: m.sourceUrl ?? m.filePath ?? '',
    itemType: _itemTypeToDto(m.itemType),
    author: m.author.isEmpty ? null : m.author,
    artist: m.artist,
    description: m.description.isEmpty ? null : m.description,
    genre: m.tags,
    status: _statusToDto(m.status),
    thumbnailUrl: m.coverUrl.isEmpty ? null : m.coverUrl,
    favorite: m.isFavorite,
    categoryIds: [
      if (m.category != null && categoryIdsByName[m.category] != null)
        categoryIdsByName[m.category]!,
    ],
    chapters: dtoChapters,
    lastReadAt: m.lastReadAt,
    dateAdded: m.addedAt,
    rating: m.rating,
    unreadCount: unread,
    totalChapters: dtoChapters.length,
    lastChapterRead: lastRead,
  );
}

/// Converts a presentation [dto.Manga] back to a persistable [db.Manga].
///
/// Used when adding items discovered in Browse to the library. Does NOT copy
/// progress fields (a browse item starts fresh); chapters are inserted
/// separately by the repository so Isar links stay consistent.
db.Manga mangaFromDto(dto.Manga m, {int? existingId}) {
  return db.Manga(
    // id 0 = not persisted (browse DTOs) → null → Isar auto-increments.
    // A literal 0 made every browse-added entry share ONE row.
    id: existingId ?? (m.id > 0 ? m.id : null),
    name: m.title,
    author: m.author ?? '',
    description: m.description ?? '',
    coverUrl: m.thumbnailUrl ?? '',
    filePath: m.itemType == dto.ItemType.book ? m.url : null,
    fileType: null,
    sourceUrl: m.itemType == dto.ItemType.book ? null : m.url,
    sourceId: m.sourceId == 0 ? null : m.sourceId,
    itemType: _itemTypeFromDto(m.itemType),
    status: _statusFromDto(m.status),
    artist: m.artist,
    tags: m.genre,
    rating: m.rating,
    chapterCount: m.totalChapters,
    isFavorite: m.favorite,
    lastReadAt: m.lastReadAt,
    addedAt: m.dateAdded ?? DateTime.now(),
    totalPages: 0,
    currentPage: 0,
    progress: 0.0,
    isFinished: false,
    readCount: 0,
  );
}

// ---------------------------------------------------------------------------
// Chapter
// ---------------------------------------------------------------------------

dto.Chapter chapterToDto(db.Chapter c) {
  return dto.Chapter(
    id: c.id ?? 0,
    url: c.url,
    name: c.name,
    number: c.chapterNumber.toDouble(),
    scanlator: c.scanlator,
    dateUploaded: c.dateUpload,
    isRead: c.isRead,
    isDownloaded: c.isDownloaded,
    isBookmarked: c.isBookmarked,
    lastPageRead: c.lastPageRead,
    totalPages: c.pageCount,
    progress: c.pageCount > 0
        ? (c.lastPageRead / c.pageCount).clamp(0.0, 1.0)
        : 0.0,
  );
}

db.Chapter chapterFromDto(dto.Chapter c, {int? existingId}) {
  return db.Chapter(
    // id 0 on a DTO means "not persisted yet" — it must map to NULL so
    // Isar auto-increments. Mapping it to a literal 0 made every fresh
    // chapter share one row (each put overwrote the previous).
    id: existingId ?? (c.id > 0 ? c.id : null),
    name: c.name,
    url: c.url,
    chapterNumber: c.number.round(),
    dateUpload: c.dateUploaded,
    scanlator: c.scanlator,
    isRead: c.isRead,
    isDownloaded: c.isDownloaded,
    isBookmarked: c.isBookmarked,
    lastPageRead: c.lastPageRead,
    pageCount: c.totalPages,
  );
}

// ---------------------------------------------------------------------------
// Note
// ---------------------------------------------------------------------------

dto.Note noteToDto(db.Note n, {String? mangaTitle, int? mangaId}) {
  return dto.Note(
    id: n.id ?? 0,
    content: n.text,
    mangaId: mangaId ?? n.manga.value?.id ?? 0,
    mangaTitle: mangaTitle ?? n.manga.value?.name ?? '',
    type: n.noteType == db.NoteType.highlight
        ? dto.NoteType.highlight
        : dto.NoteType.thought,
    createdAt: n.createdAt,
    color: dto.NoteColor.values[n.color.clamp(0, dto.NoteColor.values.length - 1)],
    chapterId: n.chapterId,
    page: n.pageNumber,
    tags: n.tags,
  );
}

db.Note noteFromDto(dto.Note n, {int? existingId}) {
  return db.Note(
    id: existingId ?? (n.id == 0 ? null : n.id),
    pageNumber: n.page,
    text: n.content,
    noteType: n.type == dto.NoteType.highlight
        ? db.NoteType.highlight
        : db.NoteType.thought,
    color: n.color.index,
    tags: n.tags,
    createdAt: n.createdAt,
    updatedAt: DateTime.now(),
    chapterId: n.chapterId,
  );
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

dto.HistoryEntry historyToDto(db.History h) {
  return dto.HistoryEntry(
    id: h.id,
    mangaId: h.mangaId ?? 0,
    mangaTitle: h.mangaTitle ?? '',
    thumbnailUrl: h.mangaCover,
    chapterName: h.chapterName ?? '',
    chapterNumber: double.tryParse(h.chapterNumber ?? '') ?? 0,
    readAt: DateTime.fromMillisecondsSinceEpoch(
        h.lastReadAt ?? DateTime.now().millisecondsSinceEpoch),
    progress: h.progress ?? 0,
    isAnime: h.isAnime ?? h.mediaType == db.HistoryMediaType.anime,
    chapterId: h.chapterId,
    page: h.lastReadPage ?? 0,
    totalPages: h.totalPages ?? 0,
  );
}

db.History historyFromDto(dto.HistoryEntry e, {int? existingId}) {
  return db.History(
    id: existingId ?? (e.id == 0 ? Isar.autoIncrement : e.id),
    mangaId: e.mangaId,
    chapterId: e.chapterId,
    chapterName: e.chapterName,
    chapterNumber: e.chapterNumber.toString(),
    totalPages: e.totalPages,
    lastReadPage: e.page,
    progress: e.progress,
    isAnime: e.isAnime,
    isManga: !e.isAnime,
    mangaTitle: e.mangaTitle,
    mangaCover: e.thumbnailUrl,
    mediaType: e.isAnime
        ? db.HistoryMediaType.anime
        : db.HistoryMediaType.manga,
    lastReadAt: e.readAt.millisecondsSinceEpoch,
  );
}

// ---------------------------------------------------------------------------
// Update (new-chapter feed)
// ---------------------------------------------------------------------------

dto.UpdateItem updateToDto(db.Update u) {
  return dto.UpdateItem(
    id: u.id,
    mangaId: u.mangaId ?? 0,
    mangaTitle: u.mangaTitle ?? '',
    thumbnailUrl: u.mangaCover,
    chapterName: u.chapterName ?? '',
    date: DateTime.fromMillisecondsSinceEpoch(
        u.date ?? u.discoveredAt ?? DateTime.now().millisecondsSinceEpoch),
    isRead: u.isRead ?? u.state == db.UpdateState.read,
    isDownloaded: u.isDownloaded ?? u.state == db.UpdateState.downloaded,
    isAnime: u.isAnime ?? u.mediaType == db.UpdateMediaType.anime,
    chapterNumber: u.chapterNumberValue,
    scanlator: u.scanlator,
  );
}

db.Update updateFromDto(dto.UpdateItem u, {int? existingId}) {
  return db.Update(
    id: existingId ?? (u.id == 0 ? Isar.autoIncrement : u.id),
    mangaId: u.mangaId,
    chapterName: u.chapterName,
    chapterNumber: u.chapterNumber?.toString(),
    isAnime: u.isAnime,
    isManga: !u.isAnime,
    mangaTitle: u.mangaTitle,
    mangaCover: u.thumbnailUrl,
    isRead: u.isRead,
    isDownloaded: u.isDownloaded,
    state: u.isDownloaded
        ? db.UpdateState.downloaded
        : (u.isRead ? db.UpdateState.read : db.UpdateState.unread),
    date: u.date.millisecondsSinceEpoch,
    discoveredAt: DateTime.now().millisecondsSinceEpoch,
  );
}

// ---------------------------------------------------------------------------
// Source (extension)
// ---------------------------------------------------------------------------

dto.Source sourceToDto(db.Source s) {
  return dto.Source(
    id: s.id,
    idString: s.idString,
    name: s.displayName,
    lang: s.lang ?? '',
    baseUrl: s.displayBaseUrl,
    iconUrl: s.iconUrl,
    isInstalled: s.isEnabled ?? true,
    isNsfw: s.isNsfw ?? false,
    supportsLatest: s.supportsLatest ?? true,
    version: s.version ?? '1.0.0',
    typeSource: s.typeSource,
    dateFormat: s.dateFormat,
    dateFormatLocale: s.dateFormatLocale,
    additionalParams: s.additionalParams,
    sourceCodeUrl: s.sourceCodeUrl,
    versionLast: s.versionLast,
  );
}

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

dto.Category categoryToDto(db.Category c) {
  return dto.Category(
    id: c.id,
    name: c.name,
    order: c.position ?? 0,
    color: _parseColorHex(c.color) ?? 0xFF6750A4,
  );
}

int? _parseColorHex(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.replaceFirst('#', '');
  if (cleaned.length == 6 || cleaned.length == 8) {
    return int.tryParse(cleaned, radix: 16);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Download
// ---------------------------------------------------------------------------

dto.DownloadState _downloadStateToDto(db.DownloadState? s) {
  switch (s) {
    case db.DownloadState.queued:
      return dto.DownloadState.queued;
    case db.DownloadState.downloading:
      return dto.DownloadState.downloading;
    case db.DownloadState.paused:
      return dto.DownloadState.paused;
    case db.DownloadState.stopped:
      return dto.DownloadState.cancelled;
    case db.DownloadState.completed:
      return dto.DownloadState.completed;
    case db.DownloadState.failed:
      return dto.DownloadState.failed;
    case db.DownloadState.cancelled:
      return dto.DownloadState.cancelled;
    case db.DownloadState.preparing:
      return dto.DownloadState.queued;
    case null:
      return dto.DownloadState.queued;
  }
}

dto.DownloadTask downloadToDto(db.Download d) {
  return dto.DownloadTask(
    id: d.id,
    title: d.mangaTitle ?? '',
    chapterName: d.chapterName ?? '',
    mangaId: d.mangaId ?? 0,
    progress: d.progress,
    state: _downloadStateToDto(d.state),
    speedBytesPerSec: 0,
    downloadedBytes: d.downloadedBytes ?? 0,
    totalBytes: d.fileSize ?? 0,
    errorMessage: d.lastError,
    isAnime: d.isAnime ?? false,
  );
}

// ---------------------------------------------------------------------------
// Settings (presentation SettingsState <-> Isar Settings)
// ---------------------------------------------------------------------------

/// Copies persisted settings over a freshly built defaults row so only the
/// fields the user actually changed differ from defaults. `override` (the
/// older/persisted row) only wins when its field is non-null — this replaces
/// the dangerous `mergeWith` stub that silently wiped every field.
db.Settings mergeSettings(db.Settings base, db.Settings? o) {
  if (o == null) return base;
  final b = base;
  return db.Settings(
    id: b.id,
    // Appearance
    themeMode: o.themeMode ?? b.themeMode,
    dynamicTheme: o.dynamicTheme ?? b.dynamicTheme,
    pureBlackDark: o.pureBlackDark ?? b.pureBlackDark,
    einkMode: o.einkMode ?? b.einkMode,
    uiFontSize: o.uiFontSize ?? b.uiFontSize,
    accentColor: o.accentColor ?? b.accentColor,
    customThemeFontFamily: o.customThemeFontFamily ?? b.customThemeFontFamily,
    // Reader
    readerDefaultMode: o.readerDefaultMode ?? b.readerDefaultMode,
    readerDirection: o.readerDirection ?? b.readerDirection,
    readerBackgroundColor: o.readerBackgroundColor ?? b.readerBackgroundColor,
    readerTapToTurnPage: o.readerTapToTurnPage ?? b.readerTapToTurnPage,
    readerShowPageNumber: o.readerShowPageNumber ?? b.readerShowPageNumber,
    readerKeepScreenOn: o.readerKeepScreenOn ?? b.readerKeepScreenOn,
    // Player
    playerDefaultQuality: o.playerDefaultQuality ?? b.playerDefaultQuality,
    playerSubtitleLanguage:
        o.playerSubtitleLanguage ?? b.playerSubtitleLanguage,
    playerAutoSkipOpening: o.playerAutoSkipOpening ?? b.playerAutoSkipOpening,
    playerEnablePip: o.playerEnablePip ?? b.playerEnablePip,
    // Library / downloads
    downloadAutoNew: o.downloadAutoNew ?? b.downloadAutoNew,
    downloadAutoCategories:
        o.downloadAutoCategories ?? b.downloadAutoCategories,
    downloadOnlyOverWifi: o.downloadOnlyOverWifi ?? b.downloadOnlyOverWifi,
    downloadConcurrent: o.downloadConcurrent ?? b.downloadConcurrent,
    libraryAutoUpdate: o.libraryAutoUpdate ?? b.libraryAutoUpdate,
    libraryDownloadOnlyOverWifi:
        o.libraryDownloadOnlyOverWifi ?? b.libraryDownloadOnlyOverWifi,
    // Security
    appLockEnabled: o.appLockEnabled ?? b.appLockEnabled,
    lockOnLaunch: o.lockOnLaunch ?? b.lockOnLaunch,
    lockOnResume: o.lockOnResume ?? b.lockOnResume,
    // Cloud sync
    cloudSyncEnabled: o.cloudSyncEnabled ?? b.cloudSyncEnabled,
    cloudSyncLastSyncAt: o.cloudSyncLastSyncAt ?? b.cloudSyncLastSyncAt,
    // Trackers
    syncAutoToTracker: o.syncAutoToTracker ?? b.syncAutoToTracker,
    // Backup
    backupInterval: o.backupInterval ?? b.backupInterval,
    backupLastBackupAt: o.backupLastBackupAt ?? b.backupLastBackupAt,
  );
}
