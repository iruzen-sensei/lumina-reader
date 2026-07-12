/*
 * Lumina Reader - A Mangayomi fork
 * Copyright (C) 2024 Lumina Reader Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Original Mangayomi source: Copyright (c) 2023-2024 kodjode33
 * SPDX-License-Identifier: Apache-2.0
 */

import 'package:isar/isar.dart';

import 'package:lumina_reader/models/source.dart';

part 'history.g.dart';

/// Type of media a [History] entry refers to.
@enumeration
enum HistoryMediaType {
  /// Manga / manhua / manhwa chapter.
  manga,

  /// Anime episode.
  anime,

  /// EPUB book chapter.
  epub,

  /// PDF document page range.
  pdf,

  /// Web novel chapter.
  novel,
}

/// Isar collection for reading / watching history.
///
/// A [History] entry is created or updated every time the user opens a
/// chapter, episode or document. The collection powers the "Continue
/// reading" carousel on the home screen and the history list in the
/// history tab.
@collection
@Name("History")
class History {
  /// Primary key. Auto-incremented by Isar.
  Id id = Isar.autoIncrement;

  /// Identifier of the parent manga / anime / book entry. Resolved by the
  /// data layer to a [Manga] (or equivalent) record.
  int? mangaId;

  /// Stable string identifier of the parent entry (for cross-source
  /// identification).
  String? mangaIdString;

  /// Identifier of the chapter / episode being consumed.
  int? chapterId;

  /// Stable string identifier of the chapter / episode.
  String? chapterIdString;

  /// Display name of the chapter / episode.
  String? chapterName;

  /// Chapter / episode number (as string for JS interop compatibility).
  String? chapterNumber;

  /// Direct URL to the chapter / episode.
  String? url;

  /// Total number of pages / frames / minutes in the chapter / episode.
  int? totalPages;

  /// Number of pages / frames already consumed.
  int? readPages;

  /// Index (0-based) of the last page / frame the user was on.
  int? lastReadPage;

  /// Position (in milliseconds) within the media. Used for video / audio.
  int? position;

  /// Total duration (in milliseconds) of the media. Used for video / audio.
  int? duration;

  /// Progress fraction in the range `0..1` (inclusive).
  double? progress;

  /// Type of media this history entry refers to.
  @enumeration
  HistoryMediaType? mediaType;

  /// Whether the entry is a manga chapter.
  bool? isManga;

  /// Whether the entry is an anime episode.
  bool? isAnime;

  /// Whether the entry is a book chapter (EPUB / PDF).
  bool? isBook;

  /// Display title of the parent entry.
  String? mangaTitle;

  /// Cover URL of the parent entry.
  String? mangaCover;

  /// Identifier of the source that produced the entry.
  String? sourceId;

  /// Identifier of the category the parent entry belongs to (if any).
  int? categoryId;

  /// Whether the chapter / episode has been marked as fully read.
  bool? isCompleted;

  /// Whether the user is re-reading / re-watching the entry.
  bool? isRereading;

  /// Number of times the user has re-read / re-watched the entry.
  int? rereadCount;

  /// Timestamp (milliseconds since epoch) when the user last interacted
  /// with the entry.
  int? lastReadAt;

  /// Timestamp (milliseconds since epoch) when the user first opened the
  /// entry.
  int? startedAt;

  /// Timestamp (milliseconds since epoch) when the user finished the entry.
  int? finishedAt;

  /// Total time (in milliseconds) the user has spent on this entry.
  int? totalTimeSpent;

  /// Optional note left by the user on this entry.
  String? note;

  /// Optional list of bookmarked page indices (0-based).
  List<int>? bookmarks;

  /// Optional rating (0..10) given by the user to this entry.
  int? rating;

  /// Optional device identifier that produced this history entry. Used to
  /// resolve conflicts when syncing across devices.
  String? deviceId;

  /// Optional revision number used for cloud sync conflict resolution.
  int? revision;

  /// Whether this history entry has been pushed to the cloud sync backend.
  bool? isSynced;

  /// Timestamp (milliseconds since epoch) of the last cloud sync.
  int? lastSyncedAt;

  /// Whether this history entry should be excluded from statistics.
  bool? excludeFromStats;

  /// Optional language code (BCP 47) of the consumed entry.
  String? language;

  /// Optional scanlator / release group.
  String? scanlator;

  /// Optional source-specific metadata (JSON-encoded).
  String? metadataJson;

  /// For PDF history: the page number the user was on (1-indexed).
  int? pdfPageNumber;

  /// For PDF history: the zoom level (1.0 = 100%).
  double? pdfZoomLevel;

  /// For EPUB history: the locator (CFI) of the last position.
  String? epubCfi;

  /// For EPUB history: the chapter index the user was on.
  int? epubChapterIndex;

  /// For EPUB history: the percentage progress (0..1).
  double? epubProgress;

  // -- Indexes -------------------------------------------------------------

  /// Index on [mangaId] for fast retrieval of all history entries for an
  /// entry.
  @Index()
  int? get mangaIdIndex => mangaId;

  /// Index on [chapterId] for fast retrieval of a single chapter's history.
  @Index()
  int? get chapterIdIndex => chapterId;

  /// Index on [lastReadAt] for the "Continue reading" carousel (sorted by
  /// most recent first).
  @Index()
  int? get lastReadAtIndex => lastReadAt;

  /// Index on [sourceId] for filtering history by source.
  @Index()
  String? get sourceIdIndex => sourceId;

  /// Index on [mediaType] for filtering history by media type.
  @Index()
  HistoryMediaType? get mediaTypeIndex => mediaType;

  /// Index on [isCompleted] for filtering completed entries.
  @Index()
  bool get isCompletedIndex => isCompleted ?? false;

  /// Index on [isSynced] for finding entries that need to be pushed.
  @Index()
  bool get isSyncedIndex => isSynced ?? false;

  /// Composite index on (mangaId, chapterId) for unique-ish lookups.
  @Index(composite: [CompositeIndex('chapterId')])
  int? get mangaChapterIndex => mangaId;

  // -- Constructors --------------------------------------------------------

  History({
    this.id = Isar.autoIncrement,
    this.mangaId,
    this.mangaIdString,
    this.chapterId,
    this.chapterIdString,
    this.chapterName,
    this.chapterNumber,
    this.url,
    this.totalPages,
    this.readPages,
    this.lastReadPage,
    this.position,
    this.duration,
    this.progress,
    this.mediaType,
    this.isManga,
    this.isAnime,
    this.isBook,
    this.mangaTitle,
    this.mangaCover,
    this.sourceId,
    this.categoryId,
    this.isCompleted,
    this.isRereading,
    this.rereadCount,
    this.lastReadAt,
    this.startedAt,
    this.finishedAt,
    this.totalTimeSpent,
    this.note,
    this.bookmarks,
    this.rating,
    this.deviceId,
    this.revision,
    this.isSynced,
    this.lastSyncedAt,
    this.excludeFromStats,
    this.language,
    this.scanlator,
    this.metadataJson,
    this.pdfPageNumber,
    this.pdfZoomLevel,
    this.epubCfi,
    this.epubChapterIndex,
    this.epubProgress,
  });

  /// Returns `true` when the entry is a manga chapter.
  bool get isMangaChapter => isManga == true || mediaType == HistoryMediaType.manga;

  /// Returns `true` when the entry is an anime episode.
  bool get isAnimeEpisode => isAnime == true || mediaType == HistoryMediaType.anime;

  /// Returns `true` when the entry is a book chapter.
  bool get isBookChapter =>
      isBook == true ||
      mediaType == HistoryMediaType.epub ||
      mediaType == HistoryMediaType.pdf ||
      mediaType == HistoryMediaType.novel;

  /// Returns the effective progress as a fraction in `0..1`.
  double get effectiveProgress {
    if (progress != null) return progress!.clamp(0.0, 1.0);
    if (totalPages != null && totalPages! > 0 && readPages != null) {
      return (readPages! / totalPages!).clamp(0.0, 1.0);
    }
    if (duration != null && duration! > 0 && position != null) {
      return (position! / duration!).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// Returns `true` when the user has finished this entry.
  bool get isFinished =>
      isCompleted == true ||
      effectiveProgress >= 1.0 ||
      (totalPages != null &&
          totalPages! > 0 &&
          readPages != null &&
          readPages! >= totalPages!);

  @override
  String toString() =>
      'History(id: $id, mangaId: $mangaId, chapterId: $chapterId, '
      'lastReadAt: $lastReadAt, progress: $progress)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is History && (id == other.id);

  @override
  int get hashCode => id.hashCode;
}
