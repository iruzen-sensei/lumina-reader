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

part 'track.g.dart';

/// Identifier of a tracker service. Stored as a stable string so that new
/// trackers can be added without bumping the Isar schema.
@enumeration
enum TrackerSyncId {
  /// MyAnimeList (https://myanimelist.net).
  myanimelist,

  /// AniList (https://anilist.co).
  anilist,

  /// MangaDex (https://mangadex.org).
  mangadex,

  /// Shikimori (https://shikimori.one).
  shikimori,

  /// Kitsu (https://kitsu.io).
  kitsu,

  /// Bangumi (https://bgm.tv).
  bangumi,

  /// Simkl (https://simkl.com).
  simkl,

  /// Anime-Planet (https://www.anime-planet.com).
  animePlanet,

  /// Novel Updates (https://www.novelupdates.com).
  novelUpdates,

  /// Goodreads (https://www.goodreads.com).
  goodreads,

  /// Local tracker — used to keep progress data without syncing to a
  /// remote service.
  local,

  /// Komga (https://komga.org).
  komga,

  /// Kavita (https://www.kavitareader.com).
  kavita,
}

/// Status of an entry on a tracker.
@enumeration
enum TrackStatus {
  /// The user is currently reading / watching the entry.
  reading,

  /// The user has finished the entry.
  completed,

  /// The user has put the entry on hold.
  onHold,

  /// The user has dropped the entry.
  dropped,

  /// The user plans to read / watch the entry.
  planToRead,
}

/// Isar collection for tracker sync state.
///
/// A [Track] entry represents the user's progress on a single manga / anime
/// / book entry as known by a remote tracker (MyAnimeList, AniList, ...).
/// The collection is the source of truth for the local view of the tracker
/// state — the remote view is fetched lazily by the tracker integration.
@collection
@Name("Track")
class Track {
  /// Primary key. Auto-incremented by Isar.
  Id id = Isar.autoIncrement;

  /// Identifier of the parent manga / anime / book entry.
  int? mangaId;

  /// Stable string identifier of the parent entry.
  String? mangaIdString;

  /// Identifier of the tracker service this entry belongs to.
  @enumeration
  TrackerSyncId? syncId;

  /// Optional raw string identifier of the tracker (for legacy / custom
  /// trackers that do not have a [TrackerSyncId] enum value).
  String? syncIdString;

  /// Identifier of the entry on the tracker service.
  String? mediaId;

  /// Display title of the entry on the tracker service.
  String? title;

  /// Cover URL of the entry on the tracker service.
  String? cover;

  /// Direct URL to the entry on the tracker service.
  String? trackingUrl;

  /// Total number of chapters / episodes the entry has on the tracker
  /// service. `-1` means unknown.
  int? totalChapters;

  /// Number of chapters / episodes the user has read / watched.
  int? lastReadChapter;

  /// Number of unread chapters / episodes.
  int? unreadChapters;

  /// Score given by the user (0..10 on most trackers).
  int? score;

  /// Optional raw score string (some trackers use non-numeric scales).
  String? scoreString;

  /// Status of the entry on the tracker.
  @enumeration
  TrackStatus? status;

  /// Timestamp (milliseconds since epoch) when the user started the entry.
  int? startReadAt;

  /// Timestamp (milliseconds since epoch) when the user finished the entry.
  int? finishReadAt;

  /// Timestamp (milliseconds since epoch) of the last read / watched
  /// chapter / episode.
  int? lastReadAt;

  /// Timestamp (milliseconds since epoch) when the entry was last synced
  /// with the tracker.
  int? lastSyncedAt;

  /// Optional OAuth access token used to authenticate with the tracker.
  String? token;

  /// Optional OAuth refresh token.
  String? refreshToken;

  /// Timestamp (milliseconds since epoch) when the access token expires.
  int? tokenExpiresAt;

  /// Optional username on the tracker service.
  String? username;

  /// Optional user identifier on the tracker service.
  String? userId;

  /// Optional user avatar URL on the tracker service.
  String? userAvatar;

  /// Whether the entry should be auto-synced with the tracker.
  bool? autoSync;

  /// Whether the entry has been marked as favourite on the tracker.
  bool? isFavourite;

  /// Whether the entry has been marked as NSFW on the tracker.
  bool? isNsfw;

  /// Whether the entry has been marked as private on the tracker.
  bool? isPrivate;

  /// Number of times the entry has been re-read / re-watched.
  int? rewatchCount;

  /// Optional priority for the entry (0..10 on most trackers).
  int? priority;

  /// Optional notes left by the user on the tracker.
  String? notes;

  /// Optional list of tags applied to the entry on the tracker.
  List<String>? tags;

  /// Optional list of custom lists the entry belongs to on the tracker.
  List<String>? customLists;

  /// Whether the local copy is ahead of the remote (i.e. local changes
  /// that have not been pushed yet).
  bool? hasPendingChanges;

  /// Whether the last sync attempt failed.
  bool? lastSyncFailed;

  /// Optional error message captured the last time the sync failed.
  String? lastError;

  /// Number of times the sync has been retried.
  int? retryCount;

  /// Optional device identifier that last synced the entry.
  String? deviceId;

  /// Optional revision number used for cross-device conflict resolution.
  int? revision;

  /// Whether this track entry has been fully synced with the remote.
  bool? isSynced;

  /// Optional source-specific metadata (JSON-encoded).
  String? metadataJson;

  /// Type of media the entry refers to (mirror of the parent entry's
  /// media type, cached for fast filtering).
  @enumeration
  TrackMediaType? mediaType;

  /// Identifier of the source that produces the entry.
  String? sourceId;

  // -- Indexes -------------------------------------------------------------

  /// Index on [mangaId] for fast retrieval of all trackers for an entry.
  @Index()
  int? get mangaIdIndex => mangaId;

  /// Index on [syncId] for filtering by tracker.
  @Index()
  TrackerSyncId? get syncIdIndex => syncId;

  /// Index on [mediaId] for fast lookup by tracker media id.
  @Index()
  String? get mediaIdIndex => mediaId;

  /// Index on [status] for filtering by status.
  @Index()
  TrackStatus? get statusIndex => status;

  /// Index on [isSynced] for finding entries that need to be pushed.
  @Index()
  bool get isSyncedIndex => isSynced ?? false;

  /// Index on [hasPendingChanges] for finding entries that need to be
  /// pushed.
  @Index()
  bool get hasPendingChangesIndex => hasPendingChanges ?? false;

  /// Index on [lastSyncedAt] for finding stale entries.
  @Index()
  int? get lastSyncedAtIndex => lastSyncedAt;

  /// Index on [autoSync] for finding entries that should be auto-synced.
  @Index()
  bool get autoSyncIndex => autoSync ?? false;

  /// Composite unique index on (syncId, mediaId) — a tracker can only have
  /// one entry per media id.
  @Index(unique: true, replace: true, composite: [CompositeIndex('mediaId')])
  TrackerSyncId? get syncMediaIndex => syncId;

  /// Composite index on (mangaId, syncId) for fast per-entry per-tracker
  /// lookup.
  @Index(composite: [CompositeIndex('syncId')])
  int? get mangaSyncIndex => mangaId;

  // -- Constructors --------------------------------------------------------

  Track({
    this.id = Isar.autoIncrement,
    this.mangaId,
    this.mangaIdString,
    this.syncId,
    this.syncIdString,
    this.mediaId,
    this.title,
    this.cover,
    this.trackingUrl,
    this.totalChapters,
    this.lastReadChapter,
    this.unreadChapters,
    this.score,
    this.scoreString,
    this.status,
    this.startReadAt,
    this.finishReadAt,
    this.lastReadAt,
    this.lastSyncedAt,
    this.token,
    this.refreshToken,
    this.tokenExpiresAt,
    this.username,
    this.userId,
    this.userAvatar,
    this.autoSync,
    this.isFavourite,
    this.isNsfw,
    this.isPrivate,
    this.rewatchCount,
    this.priority,
    this.notes,
    this.tags,
    this.customLists,
    this.hasPendingChanges,
    this.lastSyncFailed,
    this.lastError,
    this.retryCount,
    this.deviceId,
    this.revision,
    this.isSynced,
    this.metadataJson,
    this.mediaType,
    this.sourceId,
  });

  /// Returns `true` when the access token is expired or about to expire.
  bool get tokenIsExpired =>
      tokenExpiresAt != null &&
      tokenExpiresAt! <= DateTime.now().millisecondsSinceEpoch + 60000;

  /// Returns `true` when the entry is fully synced.
  bool get isFullySynced =>
      isSynced == true && !(hasPendingChanges == true) && !(lastSyncFailed == true);

  /// Returns the progress fraction in `0..1` based on the last read
  /// chapter and the total chapter count.
  double get progressFraction {
    final total = totalChapters ?? 0;
    if (total <= 0) return 0.0;
    final read = lastReadChapter ?? 0;
    return (read / total).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'Track(id: $id, mangaId: $mangaId, syncId: $syncId, mediaId: $mediaId, '
      'status: $status, score: $score)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Type of media a [Track] entry refers to (mirror of the parent entry's
/// media type).
@enumeration
enum TrackMediaType {
  /// Manga / manhua / manhwa.
  manga,

  /// Anime.
  anime,

  /// Light novel / web novel.
  novel,

  /// EPUB book.
  epub,

  /// PDF document.
  pdf,
}
