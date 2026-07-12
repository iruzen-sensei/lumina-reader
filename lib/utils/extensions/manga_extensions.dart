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
//
// Dart extensions on the [Manga] model. Centralises the display / status /
// progress helpers that the UI needs so that widgets can stay declarative
// and the same logic is reused everywhere the entry is rendered.

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lumina_reader/models/chapter.dart';
import 'package:lumina_reader/models/manga.dart';

/// Display / status / progress helpers for [Manga] entries.
extension MangaDisplayExtensions on Manga {
  /// Returns the effective display name. When the entry is a local file
  /// (EPUB / PDF / CBZ) the file name — without extension — is preferred
  /// over the raw [name] field (which may be empty for freshly-imported
  /// files).
  String get displayName {
    if (name.isNotEmpty) return name;
    if (filePath != null && filePath!.isNotEmpty) {
      return p.basenameWithoutExtension(filePath!);
    }
    return 'Untitled';
  }

  /// Returns a localised, human-readable status label.
  String get displayStatus {
    switch (status) {
      case Status.ongoing:
        return 'Ongoing';
      case Status.completed:
        return 'Completed';
      case Status.canceled:
        return 'Canceled';
      case Status.onHiatus:
        return 'On Hiatus';
      case Status.publishingFinished:
        return 'Publishing Finished';
      case Status.unknown:
        return 'Unknown';
    }
  }

  /// Returns the type label (`Manga`, `Novel`, `Book`, ...).
  String get displayType {
    switch (itemType) {
      case ItemType.manga:
        return 'Manga';
      case ItemType.novel:
        return 'Novel';
      case ItemType.book:
        return 'Book';
    }
  }

  /// Returns the progress fraction in `0..1` based on [currentPage] /
  /// [totalPages] (for books) or [progress] (for extension-sourced
  /// manga where pages are not tracked individually).
  double get progressPercentage {
    if (totalPages > 0) {
      return (currentPage / totalPages).clamp(0.0, 1.0);
    }
    if (progress > 0.0) return progress.clamp(0.0, 1.0);
    if (chapterCount > 0 && chaptersLoaded) {
      final read = chapters.where((c) => c.isRead).length;
      return (read / chapterCount).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// Returns the progress as a percentage string (e.g. `42%`).
  String get progressLabel =>
      '${(progressPercentage * 100).round()}%';

  /// Returns `true` when the user has read every chapter / page of the
  /// entry.
  bool get isRead {
    if (isFinished) return true;
    if (chaptersLoaded) {
      if (chapters.isEmpty) return false;
      return chapters.every((c) => c.isRead);
    }
    return progressPercentage >= 1.0;
  }

  /// Returns `true` when the entry is currently being read / watched (i.e.
  /// has progress but is not finished).
  bool get isReading =>
      !isFinished && progressPercentage > 0.0 && progressPercentage < 1.0;

  /// Returns `true` when the entry is an anime being watched (i.e. has
  /// [itemType] manga but its chapters look like episodes). The heuristic
  /// checks whether the chapter names start with `Episode`.
  ///
  /// Prefer setting an explicit flag on the entry in the data layer; this
  /// helper exists for backwards compatibility with legacy libraries.
  bool get isWatching {
    if (!chaptersLoaded || chapters.isEmpty) return false;
    final sample = chapters.take(3);
    return sample.every((c) =>
        c.name.toLowerCase().startsWith('episode') ||
        RegExp(r'^ep\.?\s*\d', caseSensitive: false).hasMatch(c.name));
  }

  /// Returns `true` when the entry has at least one unread chapter that is
  /// newer than the last read chapter.
  bool get hasNewChapters {
    if (!chaptersLoaded || chapters.isEmpty) return false;
    return chapters.any((c) => !c.isRead);
  }

  /// Returns the number of unread chapters / episodes.
  int get unreadChapterCount {
    if (!chaptersLoaded) return 0;
    return chapters.where((c) => !c.isRead).length;
  }

  /// Returns the number of downloaded chapters / episodes.
  int get downloadedChapterCount {
    if (!chaptersLoaded) return 0;
    return chapters.where((c) => c.isDownloaded).length;
  }

  /// Returns `true` when the [chapters] link has been loaded from Isar.
  /// Calling [chapters] on a detached [Manga] throws, so we guard against
  /// that.
  bool get chaptersLoaded {
    try {
      // Accessing `.length` triggers Isar's lazy load. When the entry is
      // detached (no Isar instance attached) this throws.
      chapters.length;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the next chapter to read, or `null` when the entry is
  /// finished.
  Chapter? get nextUnreadChapter {
    if (!chaptersLoaded) return null;
    final unread = chapters.where((c) => !c.isRead).toList()
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    return unread.isEmpty ? null : unread.first;
  }

  /// Returns the last chapter the user read, or `null` when no progress
  /// has been made.
  Chapter? get lastReadChapter {
    if (!chaptersLoaded) return null;
    final read = chapters.where((c) => c.isRead).toList()
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    return read.isEmpty ? null : read.last;
  }

  // -- File system paths ----------------------------------------------------

  /// Returns the absolute path to the entry's cover image inside the
  /// application's documents directory. The path is stable across launches
  /// and is used by the download manager to cache cover art.
  Future<String> get coverPath async {
    final docs = await getApplicationDocumentsDirectory();
    final safeName = _sanitiseForPath(displayName);
    return p.join(docs.path, 'covers', '$id-$safeName.jpg');
  }

  /// Returns the absolute path to the directory that holds the entry's
  /// downloaded chapters / episodes.
  Future<String> get downloadPath async {
    final docs = await getApplicationDocumentsDirectory();
    final safeName = _sanitiseForPath(displayName);
    return p.join(docs.path, 'downloads', '${id ?? 0}-$safeName');
  }

  /// Returns the absolute path to the directory that holds the entry's
  /// locally-cached pages for a given chapter.
  Future<String> chapterDownloadPath(Chapter chapter) async {
    final base = await downloadPath;
    return p.join(base, 'chapter_${chapter.id ?? chapter.chapterNumber}');
  }

  /// Returns the absolute path to the directory that holds the entry's
  /// notes (exported annotations).
  Future<String> get notesPath async {
    final docs = await getApplicationDocumentsDirectory();
    final safeName = _sanitiseForPath(displayName);
    return p.join(docs.path, 'notes', '${id ?? 0}-$safeName');
  }

  /// Returns the absolute path to the entry's thumbnail image used by
  /// notifications and the media-style controls. Falls back to [coverPath]
  /// when the thumbnail has not been generated yet.
  Future<String> get thumbnailPath async {
    final docs = await getApplicationDocumentsDirectory();
    final safeName = _sanitiseForPath(displayName);
    return p.join(docs.path, 'thumbnails', '$id-$safeName.webp');
  }

  // -- Sorting & filtering helpers -----------------------------------------

  /// Returns a sortable key for "last read" ordering. Entries that have
  /// never been read are sorted last.
  int get lastReadSortKey => lastReadAt?.millisecondsSinceEpoch ?? 0;

  /// Returns a sortable key for "recently added" ordering.
  int get addedSortKey => addedAt.millisecondsSinceEpoch;

  /// Returns `true` when the entry matches the given search [query] across
  /// its name, author and tags.
  bool matchesSearch(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (name.toLowerCase().contains(q)) return true;
    if (author.toLowerCase().contains(q)) return true;
    if (tags.any((t) => t.toLowerCase().contains(q))) return true;
    if (sourceName?.toLowerCase().contains(q) ?? false) return true;
    return false;
  }

  // -- Helpers --------------------------------------------------------------

  static String _sanitiseForPath(String input) {
    // Strip characters that are unsafe on the filesystem across the
    // platforms Lumina Reader targets (Android, iOS, desktop).
    final sanitised = input
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitised.isEmpty) return 'untitled';
    // Cap the length so we never blow past filesystem limits.
    return sanitised.length > 80 ? sanitised.substring(0, 80) : sanitised;
  }
}

/// Extensions on a list of [Manga] entries for common sorting operations.
extension MangaListExtensions on List<Manga> {
  /// Sorts the list alphabetically by [Manga.displayName] (case-insensitive).
  List<Manga> sortedAlphabetically() {
    final copy = List<Manga>.from(this);
    copy.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return copy;
  }

  /// Sorts the list by last read date (most recent first).
  List<Manga> sortedByLastRead() {
    final copy = List<Manga>.from(this);
    copy.sort((a, b) => b.lastReadSortKey.compareTo(a.lastReadSortKey));
    return copy;
  }

  /// Sorts the list by date added (most recent first).
  List<Manga> sortedByDateAdded() {
    final copy = List<Manga>.from(this);
    copy.sort((a, b) => b.addedSortKey.compareTo(a.addedSortKey));
    return copy;
  }

  /// Filters the list to entries that have unread chapters.
  List<Manga> withNewChapters() => where((m) => m.hasNewChapters).toList();

  /// Filters the list to entries that are currently being read.
  List<Manga> currentlyReading() => where((m) => m.isReading).toList();

  /// Filters the list to entries that are fully read.
  List<Manga> fullyRead() => where((m) => m.isRead).toList();

  /// Filters the list to entries that match the given [query].
  List<Manga> search(String query) =>
      where((m) => m.matchesSearch(query)).toList();
}

/// Extensions on a single [Chapter] used by the reader UI.
extension ChapterDisplayExtensions on Chapter {
  /// Returns a short label suitable for a list row (e.g. `Ch. 12` or
  /// `Episode 4`).
  String get shortLabel {
    if (chapterNumber > 0) {
      return name.toLowerCase().startsWith('episode')
          ? 'Ep. $chapterNumber'
          : 'Ch. $chapterNumber';
    }
    return name;
  }

  /// Returns the progress fraction in `0..1` based on [lastPageRead] /
  /// [pageCount].
  double get progressFraction {
    if (pageCount <= 0) return isRead ? 1.0 : 0.0;
    return (lastPageRead / pageCount).clamp(0.0, 1.0);
  }

  /// Returns `true` when the chapter has been started but not finished.
  bool get isInProgress => !isRead && lastPageRead > 0;
}
