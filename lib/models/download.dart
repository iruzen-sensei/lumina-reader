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

part 'download.g.dart';

/// State of a [Download] task in the download queue.
@enumeration
enum DownloadState {
  /// The download is queued and waiting to be started.
  queued,

  /// The download is currently in progress.
  downloading,

  /// The download has been paused by the user.
  paused,

  /// The download has been stopped by the user.
  stopped,

  /// The download has completed successfully.
  completed,

  /// The download has failed and will be retried.
  failed,

  /// The download has been cancelled.
  cancelled,

  /// The download is being prepared (e.g. fetching page list).
  preparing,
}

/// Type of media being downloaded.
@enumeration
enum DownloadMediaType {
  /// Manga / manhua / manhwa chapter (image set).
  manga,

  /// Anime episode (video file).
  anime,

  /// EPUB book.
  epub,

  /// PDF document.
  pdf,

  /// Audio file (e.g. for audio books / drama CDs).
  audio,
}

/// Priority of a [Download] task in the queue.
@enumeration
enum DownloadPriority {
  /// Low priority — only downloaded when the queue is otherwise idle.
  low,

  /// Normal priority (default).
  normal,

  /// High priority — jumps to the front of the queue.
  high,

  /// Urgent priority — downloaded immediately, bypassing the queue.
  urgent,
}

/// Isar collection for the download queue.
///
/// A [Download] entry tracks the state of a single chapter / episode
/// download. The download manager reads from this collection to decide
/// which tasks to start, pause or cancel.
@collection
@Name("Download")
class Download {
  /// Primary key. Auto-incremented by Isar.
  Id id = Isar.autoIncrement;

  /// Identifier of the parent manga / anime / book entry.
  int? mangaId;

  /// Stable string identifier of the parent entry.
  String? mangaIdString;

  /// Identifier of the chapter / episode being downloaded.
  int? chapterId;

  /// Stable string identifier of the chapter / episode.
  String? chapterIdString;

  /// Display name of the chapter / episode.
  String? chapterName;

  /// Chapter / episode number (as string for JS interop compatibility).
  String? chapterNumber;

  /// Direct URL of the chapter / episode page (used for re-fetching).
  String? url;

  /// Type of media being downloaded.
  @enumeration
  DownloadMediaType? mediaType;

  /// Whether the entry is a manga chapter.
  bool? isManga;

  /// Whether the entry is an anime episode.
  bool? isAnime;

  /// Whether the entry is a book (EPUB / PDF).
  bool? isBook;

  /// Identifier of the source that produces the entry.
  String? sourceId;

  /// Identifier of the category the parent entry belongs to.
  int? categoryId;

  /// Display title of the parent entry.
  String? mangaTitle;

  /// Cover URL of the parent entry.
  String? mangaCover;

  /// Current state of the download task.
  @enumeration
  DownloadState? state;

  /// Priority of the download task.
  @enumeration
  DownloadPriority? priority;

  /// Whether the download has fully completed.
  bool? isDownloaded;

  /// Whether the download has been started at least once.
  bool? isStartDownload;

  /// Whether the download has been paused by the user.
  bool? isPauseDownload;

  /// Whether the download has been stopped by the user.
  bool? isStopDownload;

  /// Number of pages / segments successfully downloaded.
  int? success;

  /// Number of pages / segments that failed to download.
  int? failed;

  /// Total number of pages / segments to download.
  int? total;

  /// Index of the current task in the queue (0 = front). Maintained by the
  /// download manager.
  int? taskIndex;

  /// Optional identifier used by the platform download manager (e.g.
  /// Android's `DownloadManager`).
  String? taskId;

  /// MIME type of the downloaded content.
  String? mimeType;

  /// File extension of the downloaded content (e.g. `cbz`, `mp4`, `epub`).
  String? fileExtension;

  /// Filesystem path where the download is being saved.
  String? downloadPath;

  /// Filesystem directory containing the download (parent of [downloadPath]).
  String? downloadDir;

  /// File size (in bytes) of the fully downloaded content.
  int? fileSize;

  /// Number of bytes downloaded so far.
  int? downloadedBytes;

  /// Timestamp (milliseconds since epoch) when the download was requested.
  int? requestedAt;

  /// Timestamp (milliseconds since epoch) when the download was started.
  int? startedAt;

  /// Timestamp (milliseconds since epoch) when the download was last
  /// updated (progress, pause, resume, ...).
  int? updatedAt;

  /// Timestamp (milliseconds since epoch) when the download completed
  /// (successfully or not).
  int? completedAt;

  /// Number of times the download has been retried.
  int? retryCount;

  /// Maximum number of retries allowed before giving up.
  int? maxRetries;

  /// Optional error message captured the last time the download failed.
  String? lastError;

  /// Optional stack trace captured the last time the download failed.
  String? lastStackTrace;

  /// List of image / segment URLs that make up the download. Populated by
  /// the extension service before the download starts.
  List<String>? urls;

  /// List of successfully saved file paths (one per page / segment).
  List<String>? savedFiles;

  /// List of HTTP headers to use for each request.
  List<String>? headersJson;

  /// Optional referer URL to use for each request.
  String? referer;

  /// Optional username for HTTP basic auth.
  String? username;

  /// Optional password for HTTP basic auth.
  String? password;

  /// Whether the download should only proceed over Wi-Fi.
  bool? wifiOnly;

  /// Whether the download should only proceed when the device is charging.
  bool? chargingOnly;

  /// Whether the download should be deleted after being read.
  bool? deleteAfterRead;

  /// Whether the download should be encrypted at rest.
  bool? encrypt;

  /// Optional encryption key (base64-encoded). Only present when [encrypt]
  /// is `true`.
  String? encryptionKey;

  /// Optional device identifier that initiated the download. Used for
  /// cross-device download syncing.
  String? deviceId;

  /// Optional revision number used for cloud sync conflict resolution.
  int? revision;

  /// Whether this download entry has been pushed to the cloud sync backend.
  bool? isSynced;

  /// Timestamp (milliseconds since epoch) of the last cloud sync.
  int? lastSyncedAt;

  /// Optional user-supplied note attached to the download.
  String? note;

  /// Optional list of tags for the download.
  List<String>? tags;

  /// For anime downloads: the video quality label (e.g. `1080p`).
  String? videoQuality;

  /// For anime downloads: the video codec (e.g. `H.264`, `H.265`).
  String? videoCodec;

  /// For anime downloads: the audio codec (e.g. `AAC`, `Opus`).
  String? audioCodec;

  /// For anime downloads: the container format (e.g. `mp4`, `mkv`).
  String? containerFormat;

  /// For anime downloads: the duration in milliseconds.
  int? videoDuration;

  /// For anime downloads: the bitrate in bits per second.
  int? videoBitrate;

  // -- Indexes -------------------------------------------------------------

  /// Index on [mangaId] for fast retrieval of all downloads for an entry.
  @Index()
  int? get mangaIdIndex => mangaId;

  /// Index on [chapterId] for fast retrieval of a single chapter's download.
  @Index()
  int? get chapterIdIndex => chapterId;

  /// Index on [state] for the download manager's main loop.
  @Index()
  DownloadState? get stateIndex => state;

  /// Index on [priority] for queue ordering.
  @Index()
  DownloadPriority? get priorityIndex => priority;

  /// Index on [taskIndex] for stable queue ordering.
  @Index()
  int? get taskIndexIndex => taskIndex;

  /// Index on [isDownloaded] for filtering completed downloads.
  @Index()
  bool get isDownloadedIndex => isDownloaded ?? false;

  /// Index on [sourceId] for filtering downloads by source.
  @Index()
  String? get sourceIdIndex => sourceId;

  /// Index on [mediaType] for filtering downloads by media type.
  @Index()
  DownloadMediaType? get mediaTypeIndex => mediaType;

  /// Index on [requestedAt] for chronological ordering.
  @Index()
  int? get requestedAtIndex => requestedAt;

  /// Composite index on (state, priority, taskIndex) for the queue scan.
  @Index(composite: [
    CompositeIndex('priority'),
    CompositeIndex('taskIndex'),
  ])
  DownloadState? get queueScanIndex => state;

  /// Composite unique-ish index on (mangaId, chapterId) for deduplication.
  @Index(composite: [CompositeIndex('chapterId')])
  int? get mangaChapterIndex => mangaId;

  // -- Constructors --------------------------------------------------------

  Download({
    this.id = Isar.autoIncrement,
    this.mangaId,
    this.mangaIdString,
    this.chapterId,
    this.chapterIdString,
    this.chapterName,
    this.chapterNumber,
    this.url,
    this.mediaType,
    this.isManga,
    this.isAnime,
    this.isBook,
    this.sourceId,
    this.categoryId,
    this.mangaTitle,
    this.mangaCover,
    this.state,
    this.priority,
    this.isDownloaded,
    this.isStartDownload,
    this.isPauseDownload,
    this.isStopDownload,
    this.success,
    this.failed,
    this.total,
    this.taskIndex,
    this.taskId,
    this.mimeType,
    this.fileExtension,
    this.downloadPath,
    this.downloadDir,
    this.fileSize,
    this.downloadedBytes,
    this.requestedAt,
    this.startedAt,
    this.updatedAt,
    this.completedAt,
    this.retryCount,
    this.maxRetries,
    this.lastError,
    this.lastStackTrace,
    this.urls,
    this.savedFiles,
    this.headersJson,
    this.referer,
    this.username,
    this.password,
    this.wifiOnly,
    this.chargingOnly,
    this.deleteAfterRead,
    this.encrypt,
    this.encryptionKey,
    this.deviceId,
    this.revision,
    this.isSynced,
    this.lastSyncedAt,
    this.note,
    this.tags,
    this.videoQuality,
    this.videoCodec,
    this.audioCodec,
    this.containerFormat,
    this.videoDuration,
    this.videoBitrate,
  });

  /// Returns the progress fraction in `0..1`.
  double get progress {
    final t = total ?? 0;
    if (t <= 0) return 0.0;
    final s = success ?? 0;
    return (s / t).clamp(0.0, 1.0);
  }

  /// Returns `true` when the download is currently active.
  bool get isActive =>
      state == DownloadState.downloading || state == DownloadState.preparing;

  /// Returns `true` when the download is in a terminal state.
  bool get isTerminal =>
      state == DownloadState.completed ||
      state == DownloadState.cancelled ||
      state == DownloadState.failed;

  /// Returns the human-readable status of the download.
  String get statusLabel {
    switch (state) {
      case DownloadState.queued:
        return 'Queued';
      case DownloadState.downloading:
        return 'Downloading';
      case DownloadState.paused:
        return 'Paused';
      case DownloadState.stopped:
        return 'Stopped';
      case DownloadState.completed:
        return 'Completed';
      case DownloadState.failed:
        return 'Failed';
      case DownloadState.cancelled:
        return 'Cancelled';
      case DownloadState.preparing:
        return 'Preparing';
      case null:
        return 'Unknown';
    }
  }

  @override
  String toString() =>
      'Download(id: $id, mangaId: $mangaId, chapterId: $chapterId, '
      'state: $state, progress: $progress)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Download && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
