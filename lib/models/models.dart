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

/// The kind of media a given record represents. Mirrors the dual nature of
/// Mangayomi which supports both manga and anime in a single library.
enum ItemType { manga, anime }

/// Publication / airing status of a series.
enum ItemStatus { ongoing, completed, licensed, publishingFinished, cancelled, unknown }

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

  bool get isAnime => itemType == ItemType.anime;

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
    required this.lang,
    required this.baseUrl,
    this.iconUrl,
    this.isInstalled = true,
    this.isNsfw = false,
    this.supportsLatest = true,
    this.version = '1.0.0',
  });

  final int id;
  final String name;
  final String lang;
  final String baseUrl;
  final String? iconUrl;
  final bool isInstalled;
  final bool isNsfw;
  final bool supportsLatest;
  final String version;
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

enum NoteColor { yellow, green, blue, pink, purple, orange, red }

extension NoteColorX on NoteColor {
  Color get color {
    switch (this) {
      case NoteColor.yellow:
        return const Color(0xFFFFF59D);
      case NoteColor.green:
        return const Color(0xFFA5D6A7);
      case NoteColor.blue:
        return const Color(0xFF90CAF9);
      case NoteColor.pink:
        return const Color(0xFFF48FB1);
      case NoteColor.purple:
        return const Color(0xFFCE93D8);
      case NoteColor.orange:
        return const Color(0xFFFFAB91);
      case NoteColor.red:
        return const Color(0xFFEF9A9A);
    }
  }

  /// Semantic meaning attached to each colour, surfaced as tooltip / aria
  /// label and used by the note editor picker.
  String get meaning {
    switch (this) {
      case NoteColor.yellow:
        return 'Important';
      case NoteColor.green:
        return 'Insight';
      case NoteColor.blue:
        return 'Reference';
      case NoteColor.pink:
        return 'Favourite';
      case NoteColor.purple:
        return 'Question';
      case NoteColor.orange:
        return 'Warning';
      case NoteColor.red:
        return 'Critical';
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
    this.scanlator,
  });

  final int id;
  final int mangaId;
  final String mangaTitle;
  final String? thumbnailUrl;
  final String chapterName;
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
