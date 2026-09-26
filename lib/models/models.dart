// Copyright 2024 Lumina Reader Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// PRESENTATION LAYER (DTOs)
//
// These classes are the shapes the UI screens consume. They are deliberately
// decoupled from persistence: the Isar collections in lib/models/*.dart are
// the single source of truth on disk, and `lib/models/mappers.dart` converts
// between the two worlds. Screens must never touch Isar directly.
//
// Several fields on these DTOs are mutable (favorite, isRead, progress…)
// because screens update them optimistically; the matching repository call
// is what actually persists the change.
// ---------------------------------------------------------------------------

/// The kind of media a given record represents. Mirrors the unified Isar
/// `ItemType` 1:1 (manga / anime / novel / book) so mappers are trivial.
enum ItemType { manga, anime, novel, book }

/// Publication / airing status of a series.
enum ItemStatus {
  ongoing,
  completed,
  licensed,
  publishingFinished,
  onHiatus,
  cancelled,
  unknown,
}

extension ItemStatusX on ItemStatus {
  String get label {
    switch (this) {
      case ItemStatus.ongoing:
        return 'Ongoing';
      case ItemStatus.completed:
        return 'Completed';
      case ItemStatus.licensed:
        return 'Licensed';
      case ItemStatus.publishingFinished:
        return 'Publishing Finished';
      case ItemStatus.onHiatus:
        return 'On Hiatus';
      case ItemStatus.cancelled:
        return 'Cancelled';
      case ItemStatus.unknown:
        return 'Unknown';
    }
  }
}

/// A single chapter (manga) or episode (anime). The [isAnime] flag flips the
/// wording used throughout the UI without requiring two separate classes.
class Chapter {
  Chapter({
    required this.id,
    required this.url,
    required this.name,
    required this.number,
    this.scanlator,
    this.dateUploaded,
    this.isRead = false,
    this.isDownloaded = false,
    this.isBookmarked = false,
    this.lastPageRead = 0,
    this.totalPages = 0,
    this.progress = 0,
  });

  final int id;
  final String url;
  final String name;
  final double number;
  final String? scanlator;
  final DateTime? dateUploaded;
  bool isRead;
  bool isDownloaded;
  bool isBookmarked;
  int lastPageRead;
  int totalPages;
  double progress;

  bool get isAnime => false;

  Chapter copyWith({
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    int? lastPageRead,
    int? totalPages,
    double? progress,
  }) {
    return Chapter(
      id: id,
      url: url,
      name: name,
      number: number,
      scanlator: scanlator,
      dateUploaded: dateUploaded,
      isRead: isRead ?? this.isRead,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      lastPageRead: lastPageRead ?? this.lastPageRead,
      totalPages: totalPages ?? this.totalPages,
      progress: progress ?? this.progress,
    );
  }
}

/// A manga or anime entry. Holding both metadata and the list of
/// chapters/episodes lets the detail / library screens share a single model.
class Manga {
  Manga({
    required this.id,
    required this.title,
    required this.sourceId,
    required this.url,
    required this.itemType,
    this.author,
    this.artist,
    this.description,
    this.genre = const [],
    this.status = ItemStatus.unknown,
    this.thumbnailUrl,
    this.favorite = false,
    this.categoryIds = const [],
    this.chapters = const [],
    this.lastReadAt,
    this.dateAdded,
    this.rating = 0,
    this.unreadCount = 0,
    this.totalChapters = 0,
    this.lastChapterRead = 0,
    this.sourceError,
  });

  final int id;
  final String title;
  final int sourceId;
  final String url;
  final ItemType itemType;
  final String? author;
  final String? artist;
  final String? description;
  final List<String> genre;
  final ItemStatus status;
  final String? thumbnailUrl;
  bool favorite;
  List<int> categoryIds;
  List<Chapter> chapters;
  DateTime? lastReadAt;
  DateTime? dateAdded;
  double rating;
  int unreadCount;
  int totalChapters;
  double lastChapterRead;

  /// When the metadata loaded but the chapter/episode list failed (e.g.
  /// provider unreachable), the partial error text — the detail screen
  /// shows an inline retry block instead of dying with a blank screen.
  String? sourceError;

  bool get isAnime => itemType == ItemType.anime;

  /// Field-preserving copy (used by the source-detail preview merge so a
  /// blank fetched field falls back to the browse seed instead of wiping).
  Manga copyWith({
    String? title,
    String? thumbnailUrl,
    String? author,
    String? artist,
    String? description,
    List<Chapter>? chapters,
  }) =>
      Manga(
        id: id,
        title: title ?? this.title,
        sourceId: sourceId,
        url: url,
        itemType: itemType,
        author: author ?? this.author,
        artist: artist ?? this.artist,
        description: description ?? this.description,
        genre: genre,
        status: status,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        favorite: favorite,
        categoryIds: categoryIds,
        chapters: chapters ?? this.chapters,
        lastReadAt: lastReadAt,
        dateAdded: dateAdded,
        rating: rating,
        unreadCount: unreadCount,
        totalChapters: totalChapters,
        lastChapterRead: lastChapterRead,
        sourceError: sourceError,
      );

  int get readCount => totalChapters - unreadCount;

  double get progress {
    if (totalChapters == 0) return 0;
    return (readCount / totalChapters).clamp(0.0, 1.0);
  }
}

/// An installed content source / extension.
class Source {
  Source({
    required this.id,
    required this.name,
    this.idString,
    required this.lang,
    required this.baseUrl,
    this.iconUrl,
    this.isInstalled = true,
    this.isNsfw = false,
    this.supportsLatest = true,
    this.version = '1.0.0',
    this.typeSource,
    this.dateFormat,
    this.dateFormatLocale,
    this.additionalParams,
    this.sourceCodeUrl,
    this.versionLast,
  });

  final int id;

  /// Stable identifier (repo rows: `repo-<name>-<indexId>`; builtins:
  /// `builtin.<key>`). Used for install / uninstall actions.
  final String? idString;
  final String name;
  final String lang;
  final String baseUrl;
  final String? iconUrl;
  final bool isInstalled;
  final bool isNsfw;
  final bool supportsLatest;
  final String version;

  /// Template identifier (`madara`, `mangareader`, …) — decides which native
  /// implementation powers this source (see eval/lib.dart).
  final String? typeSource;

  /// Site-specific chapter date format (Madara-family templates).
  final String? dateFormat;

  /// Locale for [dateFormat] parsing.
  final String? dateFormatLocale;

  /// Opaque per-site configuration blob for the template.
  final String? additionalParams;

  /// Remote template source URL (multisrc extensions share one file).
  final String? sourceCodeUrl;

  /// Latest version in the repo (update available when > [version]).
  final String? versionLast;
}

/// A user created shelf such as "Reading" or "Watch list".
class Category {
  Category({
    required this.id,
    required this.name,
    this.order = 0,
    this.color = 0xFF6750A4,
  });

  final int id;
  final String name;
  final int order;
  final int color;
}

/// Current lifecycle state of a download task.
enum DownloadState { queued, downloading, paused, completed, failed, cancelled }

extension DownloadStateX on DownloadState {
  String get label {
    switch (this) {
      case DownloadState.queued:
        return 'Queued';
      case DownloadState.downloading:
        return 'Downloading';
      case DownloadState.paused:
        return 'Paused';
      case DownloadState.completed:
        return 'Completed';
      case DownloadState.failed:
        return 'Failed';
      case DownloadState.cancelled:
        return 'Cancelled';
    }
  }
}

/// A unit of download work — typically a chapter or episode.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.title,
    required this.chapterName,
    required this.mangaId,
    this.progress = 0,
    this.state = DownloadState.queued,
    this.speedBytesPerSec = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.isAnime = false,
  });

  final int id;
  final String title;
  final String chapterName;
  final int mangaId;
  double progress;
  DownloadState state;
  double speedBytesPerSec;
  int downloadedBytes;
  int totalBytes;
  String? errorMessage;
  final bool isAnime;

  bool get isActive => state == DownloadState.downloading;
}

/// A user highlight / thought attached to a book or page.
class Note {
  Note({
    required this.id,
    required this.content,
    required this.mangaId,
    required this.mangaTitle,
    required this.type,
    required this.createdAt,
    required this.color,
    this.chapterId,
    this.page = 0,
    this.tags = const [],
  });

  final int id;
  String content;
  final int mangaId;
  String mangaTitle;
  final NoteType type;
  final DateTime createdAt;
  NoteColor color;
  final int? chapterId;
  final int page;
  final List<String> tags;
}

enum NoteType { highlight, thought }

extension NoteTypeX on NoteType {
  String get label => this == NoteType.highlight ? 'Highlight' : 'Thought';
}

/// Spec-aligned 7-color semantic highlight system (see feature guide):
/// purple=Important, teal=Insight, gold=Quote, redOrange=Disagree,
/// blue=Reference, green=Agree, indigo=Question.
/// The ordinal order MUST match `noteColors` in `models/note.dart` (Isar
/// stores the color as an int index into that list).
enum NoteColor { purple, teal, gold, redOrange, blue, green, indigo }

extension NoteColorX on NoteColor {
  Color get color {
    switch (this) {
      case NoteColor.purple:
        return const Color(0xFF9B6FDB);
      case NoteColor.teal:
        return const Color(0xFF4BC7B8);
      case NoteColor.gold:
        return const Color(0xFFC7A84B);
      case NoteColor.redOrange:
        return const Color(0xFFC7644B);
      case NoteColor.blue:
        return const Color(0xFF5B8AC7);
      case NoteColor.green:
        return const Color(0xFF6DC77D);
      case NoteColor.indigo:
        return const Color(0xFF7B6FC7);
    }
  }

  /// Semantic meaning attached to each colour, surfaced as tooltip / aria
  /// label and used by the note editor picker.
  String get meaning {
    switch (this) {
      case NoteColor.purple:
        return 'Important';
      case NoteColor.teal:
        return 'Insight';
      case NoteColor.gold:
        return 'Quote';
      case NoteColor.redOrange:
        return 'Disagree';
      case NoteColor.blue:
        return 'Reference';
      case NoteColor.green:
        return 'Agree';
      case NoteColor.indigo:
        return 'Question';
    }
  }
}

/// A single entry in the continue-reading history timeline.
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.mangaId,
    required this.mangaTitle,
    required this.thumbnailUrl,
    required this.chapterName,
    required this.chapterNumber,
    required this.readAt,
    required this.progress,
    required this.isAnime,
    this.chapterId,
    this.page = 0,
    this.totalPages = 0,
  });

  final int id;
  final int mangaId;
  final String mangaTitle;
  final String? thumbnailUrl;
  final String chapterName;
  final double chapterNumber;
  final DateTime readAt;
  final double progress;
  final bool isAnime;

  /// Chapter/episode id for deep-linking (resume into the reader).
  final int? chapterId;
  final int page;
  final int totalPages;
}

/// A new chapter/episode update surfaced in the updates feed.
class UpdateItem {
  UpdateItem({
    required this.id,
    required this.mangaId,
    required this.mangaTitle,
    required this.thumbnailUrl,
    required this.chapterName,
    required this.date,
    required this.isRead,
    required this.isDownloaded,
    required this.isAnime,
    this.chapterNumber,
    this.scanlator,
    this.chapterId,
  });

  final int id;
  final int mangaId;

  /// Chapter/episode row id — lets the download action enqueue the real
  /// chapter (previously the tile faked a 700 ms "download" animation).
  final int? chapterId;

  final String mangaTitle;
  final String? thumbnailUrl;
  final String chapterName;

  /// Chapter number as a double (`.0` for whole chapters), when known.
  final double? chapterNumber;
  final DateTime date;
  bool isRead;
  bool isDownloaded;
  final bool isAnime;
  final String? scanlator;
}

/// A day in the activity heat-map.
class StatDay {
  StatDay({required this.date, this.count = 0});

  final DateTime date;
  final int count;

  int get level {
    if (count <= 0) return 0;
    if (count < 2) return 1;
    if (count < 5) return 2;
    if (count < 9) return 3;
    return 4;
  }
}

// ---------------------------------------------------------------------------
// Media playback DTOs (moved here from providers.dart so the extension
// coordinator can produce them without import cycles).
// ---------------------------------------------------------------------------

/// One selectable video stream quality for an anime episode.
class VideoQuality {
  VideoQuality(this.label, this.url, this.height,
      {this.subtitles = const [], this.headers});

  final String label;
  final String url;
  final int height;

  /// HTTP headers (User-Agent, Referer, …) the stream CDN requires.
  /// Video CDNs (AniZone's vid-cdn edge, Cloudflare-fronted hosts) commonly
  /// 403 hotlinked .m3u8/.ts requests that lack a browser UA — the player
  /// and downloader MUST forward these.
  final Map<String, String>? headers;

  /// External subtitle tracks bundled with this stream (AniZone and other
  /// anime providers attach ASS/VTT tracks to their HLS entries).
  final List<SubtitleTrack> subtitles;
}

/// An external subtitle track for an anime episode.
class SubtitleTrack {
  const SubtitleTrack(this.label, this.url, {this.isDefault = false});

  final String label;
  final String url;
  final bool isDefault;
}

/// AniSkip skip-range data for intro/outro skipping.
class SkipRange {
  SkipRange({required this.type, required this.start, required this.end});

  final String type; // 'op', 'ed', 'recap', 'mixed-ed', 'mixed-op'
  final Duration start;
  final Duration end;

  String get label {
    switch (type) {
      case 'op':
        return 'Skip Opening';
      case 'ed':
        return 'Skip Ending';
      case 'recap':
        return 'Skip Recap';
      default:
        return 'Skip';
    }
  }
}

/// Next-airing episode info for an anime, as surfaced by AniChart / AniList.
class NextAiring {
  NextAiring({
    required this.episode,
    required this.airingAt,
    required this.timeUntilAiring,
  });

  final int episode;
  final DateTime airingAt;
  final Duration timeUntilAiring;
}

/// Streak snapshot for the stats screen.
class StreakState {
  StreakState({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.freezeTokens = 0,
    this.lastActiveDay,
  });

  final int currentStreak;
  final int longestStreak;
  final int freezeTokens;
  final DateTime? lastActiveDay;
}

/// A daily reading/watching goal the user can configure.
class Goal {
  Goal({
    required this.id,
    required this.label,
    required this.target,
    required this.current,
    required this.unit,
    required this.period,
  });

  final int id;
  final String label;
  final int target;
  final int current;
  final String unit;
  final GoalPeriod period;

  double get progress =>
      target == 0 ? 0 : (current / target).clamp(0.0, 1.0);
}

enum GoalPeriod { daily, weekly, monthly, yearly }

extension GoalPeriodX on GoalPeriod {
  String get label {
    switch (this) {
      case GoalPeriod.daily:
        return 'Daily';
      case GoalPeriod.weekly:
        return 'Weekly';
      case GoalPeriod.monthly:
        return 'Monthly';
      case GoalPeriod.yearly:
        return 'Yearly';
    }
  }
}

/// A calendar entry describing an airing episode on a given day.
class AiringEpisode {
  AiringEpisode({
    required this.id,
    required this.animeId,
    required this.title,
    required this.thumbnailUrl,
    required this.episodeNumber,
    required this.airingAt,
    required this.countdownSeconds,
  });

  final int id;
  final int animeId;
  final String title;
  final String? thumbnailUrl;
  final int episodeNumber;
  final DateTime airingAt;
  final int countdownSeconds;
}
