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

part 'update.g.dart';

/// State of an [Update] entry in the new-chapter feed.
@enumeration
enum UpdateState {
  /// The update is new and has not been seen by the user.
  unread,

  /// The update has been read by the user.
  read,

  /// The update has been downloaded by the user.
  downloaded,

  /// The update has been dismissed by the user.
  dismissed,

  /// The update has been bookmarked by the user.
  bookmarked,

  /// The update has been marked as ignored.
  ignored,
}

/// Type of media an [Update] entry refers to.
@enumeration
enum UpdateMediaType {
  /// New manga chapter.
  manga,

  /// New anime episode.
  anime,

  /// New EPUB chapter.
  epub,

  /// New PDF document.
  pdf,
}

/// Isar collection for the new chapter / episode feed.
///
/// An [Update] entry is created whenever the library refresh detects a new
/// chapter / episode for an entry the user is following. The collection
/// powers the "Updates" tab in the library screen.
@collection
@Name("Update")
class Update {
  /// Primary key. Auto-incremented by Isar.
  Id id = Isar.autoIncrement;

  /// Identifier of the parent manga / anime / book entry.
  int? mangaId;

  /// Stable string identifier of the parent entry.
  String? mangaIdString;

  /// Identifier of the chapter / episode that is new.
  int? chapterId;

  /// Stable string identifier of the chapter / episode.
  String? chapterIdString;

  /// Display name of the chapter / episode.
  String? chapterName;

  /// Chapter / episode number (as string for JS interop compatibility).
  String? chapterNumber;

  /// Chapter / episode number as a `double` for sorting.
  double? chapterNumberValue;

  /// Direct URL of the chapter / episode.
  String? url;

  /// Type of media the update refers to.
  @enumeration
  UpdateMediaType? mediaType;

  /// Whether the entry is a manga chapter.
  bool? isManga;

  /// Whether the entry is an anime episode.
  bool? isAnime;

  /// Whether the entry is a book chapter.
  bool? isBook;

  /// Identifier of the source that produces the entry.
  String? sourceId;

  /// Identifier of the category the parent entry belongs to.
  int? categoryId;

  /// Display title of the parent entry.
  String? mangaTitle;

  /// Cover URL of the parent entry.
  String? mangaCover;

  /// ISO language code of the chapter / episode.
  String? language;

  /// Optional scanlator / release group.
  String? scanlator;

  /// Current state of the update.
  @enumeration
  UpdateState? state;

  /// Whether the chapter / episode has been read by the user.
  bool? isRead;

  /// Whether the chapter / episode has been downloaded.
  bool? isDownloaded;

  /// Whether the chapter / episode has been bookmarked.
  bool? isBookmarked;

  /// Whether the chapter / episode has been dismissed.
  bool? isDismissed;

  /// Whether the update has been seen by the user (i.e. the user has
  /// opened the Updates tab since the update was created).
  bool? isSeen;

  /// Timestamp (milliseconds since epoch) when the chapter / episode was
  /// published, as reported by the source.
  int? date;

  /// Timestamp (milliseconds since epoch) when the update was discovered
  /// by the library refresh.
  int? discoveredAt;

  /// Timestamp (milliseconds since epoch) when the user last interacted
  /// with the update (read, downloaded, dismissed, ...).
  int? updatedAt;

  /// Optional number of pages in the chapter / episode.
  int? pageCount;

  /// Optional file size (in bytes) of the chapter / episode.
  int? fileSize;

  /// Optional summary / preview text for the chapter / episode.
  String? summary;

  /// Optional list of image / video URLs (for previewing without opening).
  List<String>? previewUrls;

  /// Optional list of tags associated with the chapter / episode.
  List<String>? tags;

  /// Optional note left by the user on this update.
  String? note;

  /// Optional device identifier that discovered the update.
  String? deviceId;

  /// Optional revision number used for cloud sync conflict resolution.
  int? revision;

  /// Whether this update entry has been pushed to the cloud sync backend.
  bool? isSynced;

  /// Timestamp (milliseconds since epoch) of the last cloud sync.
  int? lastSyncedAt;

  /// Optional source-specific metadata (JSON-encoded).
  String? metadataJson;

  /// Whether this update should be excluded from notifications.
  bool? silent;

  /// For anime updates: the video duration in milliseconds.
  int? videoDuration;

  /// For anime updates: the available video qualities (e.g. `['1080p', '720p']`).
  List<String>? videoQualities;

  // -- Indexes -------------------------------------------------------------

  /// Index on [mangaId] for fast retrieval of all updates for an entry.
  @Index()
  int? get mangaIdIndex => mangaId;

  /// Index on [chapterId] for fast retrieval of a single chapter's update.
  @Index()
  int? get chapterIdIndex => chapterId;

  /// Index on [date] for chronological ordering of the feed.
  @Index()
  int? get dateIndex => date;

  /// Index on [discoveredAt] for ordering updates by discovery time.
  @Index()
  int? get discoveredAtIndex => discoveredAt;

  /// Index on [sourceId] for filtering updates by source.
  @Index()
  String? get sourceIdIndex => sourceId;

  /// Index on [mediaType] for filtering updates by media type.
  @Index()
  UpdateMediaType? get mediaTypeIndex => mediaType;

  /// Index on [state] for filtering updates by state.
  @Index()
  UpdateState? get stateIndex => state;

  /// Index on [isRead] for filtering unread updates.
  @Index()
  bool get isReadIndex => isRead ?? false;

  /// Index on [isDownloaded] for filtering downloaded updates.
  @Index()
  bool get isDownloadedIndex => isDownloaded ?? false;

  /// Index on [isBookmarked] for filtering bookmarked updates.
  @Index()
  bool get isBookmarkedIndex => isBookmarked ?? false;

  /// Index on [isSeen] for filtering unseen updates.
  @Index()
  bool get isSeenIndex => isSeen ?? false;

  /// Index on [isSynced] for finding updates that need to be pushed.
  @Index()
  bool get isSyncedIndex => isSynced ?? false;

  /// Composite index on (mangaId, date) for the per-entry recent feed.
  @Index(composite: [CompositeIndex('date')])
  int? get mangaDateIndex => mangaId;

  /// Composite index on (state, date) for the unread feed.
  @Index(composite: [CompositeIndex('date')])
  UpdateState? get stateDateIndex => state;

  /// Composite unique-ish index on (mangaId, chapterId) for deduplication.
  @Index(composite: [CompositeIndex('chapterId')])
  int? get mangaChapterIndex => mangaId;

  // -- Constructors --------------------------------------------------------

  Update({
    this.id = Isar.autoIncrement,
    this.mangaId,
    this.mangaIdString,
    this.chapterId,
    this.chapterIdString,
    this.chapterName,
    this.chapterNumber,
    this.chapterNumberValue,
    this.url,
    this.mediaType,
    this.isManga,
    this.isAnime,
    this.isBook,
    this.sourceId,
    this.categoryId,
    this.mangaTitle,
    this.mangaCover,
    this.language,
    this.scanlator,
    this.state,
    this.isRead,
    this.isDownloaded,
    this.isBookmarked,
    this.isDismissed,
    this.isSeen,
    this.date,
    this.discoveredAt,
    this.updatedAt,
    this.pageCount,
    this.fileSize,
    this.summary,
    this.previewUrls,
    this.tags,
    this.note,
    this.deviceId,
    this.revision,
    this.isSynced,
    this.lastSyncedAt,
    this.metadataJson,
    this.silent,
    this.videoDuration,
    this.videoQualities,
  });

  /// Returns `true` when the update is fresh (unread and unseen).
  bool get isFresh =>
      !(isRead == true) && !(isSeen == true) && state != UpdateState.dismissed;

  /// Returns `true` when the update is a manga chapter.
  bool get isMangaChapter => isManga == true || mediaType == UpdateMediaType.manga;

  /// Returns `true` when the update is an anime episode.
  bool get isAnimeEpisode => isAnime == true || mediaType == UpdateMediaType.anime;

  /// Returns the chapter number as a `double` for sorting, defaulting to
  /// `0.0` when not set.
  double get effectiveChapterNumber => chapterNumberValue ?? 0.0;

  @override
  String toString() =>
      'Update(id: $id, mangaId: $mangaId, chapterId: $chapterId, '
      'date: $date, state: $state)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Update && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
