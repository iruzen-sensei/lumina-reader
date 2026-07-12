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

import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

// ---------------------------------------------------------------------------
// Library providers
// ---------------------------------------------------------------------------

/// Sort order used by the library screen.
enum LibrarySort { title, author, lastRead, dateAdded, unread, progress }

extension LibrarySortX on LibrarySort {
  String get label {
    switch (this) {
      case LibrarySort.title:
        return 'Title';
      case LibrarySort.author:
        return 'Author';
      case LibrarySort.lastRead:
        return 'Last read';
      case LibrarySort.dateAdded:
        return 'Date added';
      case LibrarySort.unread:
        return 'Unread count';
      case LibrarySort.progress:
        return 'Progress';
    }
  }
}

/// Library media type filter. Distinguishes manga, anime, novel and book
/// entries; "all" leaves the list untouched.
enum LibraryMediaType { all, manga, anime, novel, book }

extension LibraryMediaTypeX on LibraryMediaType {
  String get label {
    switch (this) {
      case LibraryMediaType.all:
        return 'All';
      case LibraryMediaType.manga:
        return 'Manga';
      case LibraryMediaType.anime:
        return 'Anime';
      case LibraryMediaType.novel:
        return 'Novel';
      case LibraryMediaType.book:
        return 'Book';
    }
  }

  IconData get icon {
    switch (this) {
      case LibraryMediaType.all:
        return Icons.all_inclusive;
      case LibraryMediaType.manga:
        return Icons.menu_book_rounded;
      case LibraryMediaType.anime:
        return Icons.live_tv_rounded;
      case LibraryMediaType.novel:
        return Icons.auto_stories_rounded;
      case LibraryMediaType.book:
        return Icons.book_rounded;
    }
  }
}

/// Library filter chips.
enum LibraryFilter { all, reading, finished, unread }

extension LibraryFilterX on LibraryFilter {
  String get label {
    switch (this) {
      case LibraryFilter.all:
        return 'All';
      case LibraryFilter.reading:
        return 'Reading';
      case LibraryFilter.finished:
        return 'Finished';
      case LibraryFilter.unread:
        return 'Unread';
    }
  }
}

/// Whether the library renders as a grid or list.
enum LibraryView { grid, list }

class LibraryOptions {
  LibraryOptions({
    this.view = LibraryView.grid,
    this.sort = LibrarySort.title,
    this.filter = LibraryFilter.all,
    this.mediaType = LibraryMediaType.all,
    this.sortDescending = false,
    this.activeCategoryId = 0,
    this.query = '',
  });

  final LibraryView view;
  final LibrarySort sort;
  final LibraryFilter filter;
  final LibraryMediaType mediaType;
  final bool sortDescending;
  final int activeCategoryId;
  final String query;

  LibraryOptions copyWith({
    LibraryView? view,
    LibrarySort? sort,
    LibraryFilter? filter,
    LibraryMediaType? mediaType,
    bool? sortDescending,
    int? activeCategoryId,
    String? query,
  }) {
    return LibraryOptions(
      view: view ?? this.view,
      sort: sort ?? this.sort,
      filter: filter ?? this.filter,
      mediaType: mediaType ?? this.mediaType,
      sortDescending: sortDescending ?? this.sortDescending,
      activeCategoryId: activeCategoryId ?? this.activeCategoryId,
      query: query ?? this.query,
    );
  }
}

class LibraryOptionsNotifier extends StateNotifier<LibraryOptions> {
  LibraryOptionsNotifier() : super(LibraryOptions());

  void setView(LibraryView v) => state = state.copyWith(view: v);
  void setSort(LibrarySort s) => state = state.copyWith(sort: s);
  void toggleSortDirection() =>
      state = state.copyWith(sortDescending: !state.sortDescending);
  void setFilter(LibraryFilter f) => state = state.copyWith(filter: f);
  void setMediaType(LibraryMediaType m) => state = state.copyWith(mediaType: m);
  void setCategory(int id) => state = state.copyWith(activeCategoryId: id);
  void setQuery(String q) => state = state.copyWith(query: q);
}

final libraryOptionsProvider =
    StateNotifierProvider<LibraryOptionsNotifier, LibraryOptions>(
  (ref) => LibraryOptionsNotifier(),
);

/// The set of manga ids currently selected in selection mode.
class SelectionNotifier extends StateNotifier<Set<int>> {
  SelectionNotifier() : super(<int>{});

  bool get isActive => state.isNotEmpty;

  void toggle(int id) {
    final next = Set<int>.from(state);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
  }

  void addAll(Iterable<int> ids) => state = {...state, ...ids};
  void clear() => state = <int>{};
}

final librarySelectionProvider =
    StateNotifierProvider<SelectionNotifier, Set<int>>(
  (ref) => SelectionNotifier(),
);

final animeLibrarySelectionProvider =
    StateNotifierProvider<SelectionNotifier, Set<int>>(
  (ref) => SelectionNotifier(),
);

// ---------------------------------------------------------------------------
// Mock data providers. In a real build these would be backed by Isar / Drift,
// but the screens only depend on the provider contracts.
// ---------------------------------------------------------------------------

final categoriesProvider = Provider<List<Category>>((ref) {
  return [
    Category(id: 0, name: 'All'),
    Category(id: 1, name: 'Reading', order: 1),
    Category(id: 2, name: 'Watch list', order: 2),
    Category(id: 3, name: 'Plan to read', order: 3),
    Category(id: 4, name: 'Completed', order: 4),
  ];
});

final mangaLibraryProvider = Provider<List<Manga>>((ref) {
  return _seedManga();
});

final animeLibraryProvider = Provider<List<Manga>>((ref) {
  return _seedAnime();
});

/// Filters + sorts the manga library according to [libraryOptionsProvider].
final filteredMangaProvider = Provider<List<Manga>>((ref) {
  final all = ref.watch(mangaLibraryProvider);
  final options = ref.watch(libraryOptionsProvider);
  return _applyLibraryOptions(all, options, isAnime: false);
});

/// Filters + sorts the anime library according to [libraryOptionsProvider].
final filteredAnimeProvider = Provider<List<Manga>>((ref) {
  final all = ref.watch(animeLibraryProvider);
  final options = ref.watch(libraryOptionsProvider);
  return _applyLibraryOptions(all, options, isAnime: true);
});

List<Manga> _applyLibraryOptions(
  List<Manga> input,
  LibraryOptions options, {
  required bool isAnime,
}) {
  var items = List<Manga>.from(input);

  if (options.activeCategoryId != 0) {
    items = items
        .where((m) => m.categoryIds.contains(options.activeCategoryId))
        .toList();
  }

  // Media type filter — manga and anime map directly to ItemType; novel
  // and book are detected via genre tags so the existing Manga model can
  // represent all four media kinds without a schema change.
  switch (options.mediaType) {
    case LibraryMediaType.all:
      break;
    case LibraryMediaType.manga:
      items = items.where((m) => m.itemType == ItemType.manga).toList();
      break;
    case LibraryMediaType.anime:
      items = items.where((m) => m.itemType == ItemType.anime).toList();
      break;
    case LibraryMediaType.novel:
      items = items
          .where((m) =>
              m.genre.any((g) =>
                  g.toLowerCase().contains('novel') ||
                  g.toLowerCase().contains('light novel')))
          .toList();
      break;
    case LibraryMediaType.book:
      items = items
          .where((m) =>
              m.genre.any((g) => g.toLowerCase() == 'book') ||
              m.url.endsWith('.epub') ||
              m.url.endsWith('.pdf'))
          .toList();
      break;
  }

  switch (options.filter) {
    case LibraryFilter.reading:
      items = items
          .where((m) =>
              m.unreadCount > 0 && m.unreadCount < m.totalChapters)
          .toList();
      break;
    case LibraryFilter.finished:
      items = items
          .where((m) =>
              m.unreadCount == 0 && m.totalChapters > 0)
          .toList();
      break;
    case LibraryFilter.unread:
      items = items.where((m) => m.unreadCount > 0).toList();
      break;
    case LibraryFilter.all:
      break;
  }

  if (options.query.isNotEmpty) {
    final q = options.query.toLowerCase();
    items = items
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            (m.author ?? '').toLowerCase().contains(q))
        .toList();
  }

  int compare(Manga a, Manga b) {
    switch (options.sort) {
      case LibrarySort.title:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySort.author:
        return (a.author ?? '').toLowerCase().compareTo(
              (b.author ?? '').toLowerCase(),
            );
      case LibrarySort.lastRead:
        final aa = a.lastReadAt ?? DateTime(2000);
        final bb = b.lastReadAt ?? DateTime(2000);
        return aa.compareTo(bb);
      case LibrarySort.dateAdded:
        final aa = a.dateAdded ?? DateTime(2000);
        final bb = b.dateAdded ?? DateTime(2000);
        return aa.compareTo(bb);
      case LibrarySort.unread:
        return a.unreadCount.compareTo(b.unreadCount);
      case LibrarySort.progress:
        return a.progress.compareTo(b.progress);
    }
  }

  items.sort(compare);
  if (options.sortDescending) {
    items = items.reversed.toList();
  }
  return items;
}

// ---------------------------------------------------------------------------
// Browse providers
// ---------------------------------------------------------------------------

enum BrowseTab { popular, latest, search }

final browseTabProvider = StateProvider<BrowseTab>((ref) => BrowseTab.popular);

final sourcesProvider = Provider<List<Source>>((ref) {
  return [
    Source(id: 1, name: 'MangaDex', lang: 'EN', baseUrl: 'https://mangadex.org'),
    Source(id: 2, name: 'MangaPlus', lang: 'EN', baseUrl: 'https://mangaplus.shueisha.co.jp'),
    Source(id: 3, name: 'AniList', lang: 'EN', baseUrl: 'https://anilist.co', supportsLatest: false),
    Source(id: 4, name: 'Crunchyroll', lang: 'EN', baseUrl: 'https://crunchyroll.com'),
    Source(id: 5, name: 'ManhuaPlus', lang: 'ZH', baseUrl: 'https://manhuaplus.com'),
    Source(id: 6, name: 'RawManga', lang: 'JA', baseUrl: 'https://raw-manga.online'),
  ];
});

final browseGridProvider =
    StateProvider.family<List<Manga>, int>((ref, sourceId) {
  return _seedManga().take(18).toList();
});

final globalSearchProvider =
    FutureProvider.family<List<Manga>, String>((ref, query) async {
  await Future.delayed(const Duration(milliseconds: 350));
  if (query.isEmpty) return [];
  final q = query.toLowerCase();
  return _seedManga().where((m) => m.title.toLowerCase().contains(q)).toList();
});

// ---------------------------------------------------------------------------
// Downloads providers
// ---------------------------------------------------------------------------

enum DownloadsTab { all, downloading, completed, queued, failed }

extension DownloadsTabX on DownloadsTab {
  String get label {
    switch (this) {
      case DownloadsTab.all:
        return 'All';
      case DownloadsTab.downloading:
        return 'Downloading';
      case DownloadsTab.completed:
        return 'Completed';
      case DownloadsTab.queued:
        return 'Queued';
      case DownloadsTab.failed:
        return 'Failed';
    }
  }
}

class DownloadsNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadsNotifier() : super(_seedDownloads());

  void pause(int id) => _update(id, DownloadState.paused);
  void resume(int id) => _update(id, DownloadState.queued);
  void cancel(int id) => _update(id, DownloadState.cancelled);
  void retry(int id) => _update(id, DownloadState.queued);

  void pauseAll() {
    state = [
      for (final t in state)
        if (t.state == DownloadState.downloading || t.state == DownloadState.queued)
          t..state = DownloadState.paused
        else
          t,
    ];
  }

  void resumeAll() {
    state = [
      for (final t in state)
        if (t.state == DownloadState.paused || t.state == DownloadState.queued)
          t..state = DownloadState.queued
        else
          t,
    ];
  }

  void clearCompleted() {
    state = state.where((t) => t.state != DownloadState.completed).toList();
  }

  void remove(int id) => state = state.where((t) => t.id != id).toList();

  void _update(int id, DownloadState s) {
    state = [
      for (final t in state)
        if (t.id == id) t..state = s else t,
    ];
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadTask>>(
  (ref) => DownloadsNotifier(),
);

final downloadsTabProvider =
    StateProvider<DownloadsTab>((ref) => DownloadsTab.all);

// ---------------------------------------------------------------------------
// Manga detail providers
// ---------------------------------------------------------------------------

final mangaDetailProvider =
    Provider.family<Manga, int>((ref, id) {
  final all = [..._seedManga(), ..._seedAnime()];
  return all.firstWhere((m) => m.id == id, orElse: () => all.first);
});

final chapterListProvider = Provider.family<List<Chapter>, int>((ref, id) {
  final manga = ref.watch(mangaDetailProvider(id));
  return manga.chapters;
});

// ---------------------------------------------------------------------------
// Reader providers
// ---------------------------------------------------------------------------

enum ReaderMode { paged, continuous, webtoon }

enum ReaderDirection { leftToRight, rightToLeft, vertical }

class ReaderSettings {
  ReaderSettings({
    this.mode = ReaderMode.paged,
    this.direction = ReaderDirection.leftToRight,
    this.fit = ReaderFit.contain,
    this.tapToNavigate = true,
    this.showPageNumber = true,
    this.keepScreenOn = true,
    this.backgroundColor = const Color(0xFF000000),
  });

  final ReaderMode mode;
  final ReaderDirection direction;
  final ReaderFit fit;
  final bool tapToNavigate;
  final bool showPageNumber;
  final bool keepScreenOn;
  final Color backgroundColor;

  ReaderSettings copyWith({
    ReaderMode? mode,
    ReaderDirection? direction,
    ReaderFit? fit,
    bool? tapToNavigate,
    bool? showPageNumber,
    bool? keepScreenOn,
    Color? backgroundColor,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      direction: direction ?? this.direction,
      fit: fit ?? this.fit,
      tapToNavigate: tapToNavigate ?? this.tapToNavigate,
      showPageNumber: showPageNumber ?? this.showPageNumber,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }
}

enum ReaderFit { contain, cover, fill, original }

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  ReaderSettingsNotifier() : super(ReaderSettings());

  void setMode(ReaderMode m) => state = state.copyWith(mode: m);
  void setDirection(ReaderDirection d) => state = state.copyWith(direction: d);
  void setFit(ReaderFit f) => state = state.copyWith(fit: f);
  void togglePageNumber() =>
      state = state.copyWith(showPageNumber: !state.showPageNumber);
  void toggleKeepScreenOn() =>
      state = state.copyWith(keepScreenOn: !state.keepScreenOn);
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  (ref) => ReaderSettingsNotifier(),
);

final readerPagesProvider =
    Provider.family<List<String>, int>((ref, chapterId) {
  return List.generate(
    14 + (chapterId % 6),
    (i) => 'https://picsum.photos/seed/lumina-$chapterId-$i/900/1300',
  );
});

// ---------------------------------------------------------------------------
// Anime player providers
// ---------------------------------------------------------------------------

class VideoQuality {
  VideoQuality(this.label, this.url, this.height);
  final String label;
  final String url;
  final int height;
}

class SubtitleTrack {
  SubtitleTrack(this.label, this.url, {this.isDefault = false});
  final String label;
  final String url;
  final bool isDefault;
}

final videoSourcesProvider = Provider.family<List<VideoQuality>, int>(
  (ref, episodeId) => [
    VideoQuality('1080p', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', 1080),
    VideoQuality('720p', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', 720),
    VideoQuality('480p', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', 480),
  ],
);

final subtitleTracksProvider = Provider.family<List<SubtitleTrack>, int>(
  (ref, episodeId) => [
    SubtitleTrack('Off', '', isDefault: true),
    SubtitleTrack('English', 'https://example.com/subs/en.vtt'),
    SubtitleTrack('Español', 'https://example.com/subs/es.vtt'),
    SubtitleTrack('日本語', 'https://example.com/subs/ja.vtt'),
  ],
);

/// AniSkip skip-range data returned by the skip-intro/ending service.
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

final aniSkipProvider = Provider.family<List<SkipRange>, int>((ref, id) {
  return [
    SkipRange(type: 'op', start: const Duration(seconds: 5), end: const Duration(seconds: 95)),
    SkipRange(type: 'ed', start: const Duration(minutes: 21), end: const Duration(minutes: 23, seconds: 30)),
  ];
});

// ---------------------------------------------------------------------------
// Stats providers
// ---------------------------------------------------------------------------

final statsHeatmapProvider = Provider<List<StatDay>>((ref) {
  final today = DateTime.now();
  final days = <StatDay>[];
  for (var i = 364; i >= 0; i--) {
    final date = today.subtract(Duration(days: i));
    days.add(StatDay(
      date: date,
      count: _pseudoCount(date),
    ));
  }
  return days;
});

int _pseudoCount(DateTime date) {
  final seed = date.day + date.month * 31 + date.year;
  return (seed * 7) % 11;
}

final statsGoalsProvider = Provider<List<Goal>>((ref) {
  return [
    Goal(id: 1, label: 'Chapters read', target: 50, current: 34, unit: 'ch', period: GoalPeriod.weekly),
    Goal(id: 2, label: 'Episodes watched', target: 20, current: 18, unit: 'ep', period: GoalPeriod.weekly),
    Goal(id: 3, label: 'Pages read', target: 1500, current: 980, unit: 'pg', period: GoalPeriod.monthly),
    Goal(id: 4, label: 'Reading minutes', target: 600, current: 412, unit: 'min', period: GoalPeriod.weekly),
  ];
});

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

final streakProvider = Provider<StreakState>((ref) {
  return StreakState(
    currentStreak: 12,
    longestStreak: 28,
    freezeTokens: 3,
    lastActiveDay: DateTime.now(),
  );
});

final statsSummaryProvider = Provider<Map<String, int>>((ref) {
  return {
    'mangaRead': 1842,
    'animeWatched': 412,
    'pagesRead': 38521,
    'minutesRead': 9420,
    'chaptersRead': 1842,
    'episodesWatched': 412,
  };
});

// ---------------------------------------------------------------------------
// Notes providers
// ---------------------------------------------------------------------------

enum NotesFilter { all, highlights, thoughts }

final notesFilterProvider = StateProvider<NotesFilter>((ref) => NotesFilter.all);
final notesSearchProvider = StateProvider<String>((ref) => '');
final notesBookFilterProvider = StateProvider<int?>((ref) => null);

final notesProvider = Provider<List<Note>>((ref) {
  return _seedNotes();
});

final filteredNotesProvider = Provider<List<Note>>((ref) {
  final all = ref.watch(notesProvider);
  final filter = ref.watch(notesFilterProvider);
  final search = ref.watch(notesSearchProvider);
  final book = ref.watch(notesBookFilterProvider);

  return all.where((n) {
    if (book != null && n.mangaId != book) return false;
    if (filter == NotesFilter.highlights && n.type != NoteType.highlight) {
      return false;
    }
    if (filter == NotesFilter.thoughts && n.type != NoteType.thought) {
      return false;
    }
    if (search.isNotEmpty &&
        !n.content.toLowerCase().contains(search.toLowerCase())) {
      return false;
    }
    return true;
  }).toList();
});

// ---------------------------------------------------------------------------
// Calendar providers
// ---------------------------------------------------------------------------

final calendarFocusedDayProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

final calendarSelectedDayProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

final airingScheduleProvider =
    Provider.family<List<AiringEpisode>, DateTime>((ref, day) {
  final seed = day.day + day.month;
  final episodes = <AiringEpisode>[];
  final animeTitles = [
    'Frieren: Beyond Journey\'s End',
    'Solo Leveling',
    'Jujutsu Kaisen',
    'One Piece',
    'Demon Slayer',
    'Spy x Family',
  ];
  for (var i = 0; i < (seed % 4) + 1; i++) {
    final title = animeTitles[(seed + i) % animeTitles.length];
    final airingAt = DateTime(
      day.year,
      day.month,
      day.day,
      12 + i * 3,
      30,
    );
    episodes.add(AiringEpisode(
      id: day.millisecondsSinceEpoch + i,
      animeId: i + 1,
      title: title,
      thumbnailUrl: 'https://picsum.photos/seed/air-$i/200/300',
      episodeNumber: (seed % 12) + i + 1,
      airingAt: airingAt,
      countdownSeconds: airingAt.difference(DateTime.now()).inSeconds,
    ));
  }
  return episodes;
});

// ---------------------------------------------------------------------------
// History providers
// ---------------------------------------------------------------------------

final historyProvider = Provider<List<HistoryEntry>>((ref) {
  return _seedHistory();
});

// ---------------------------------------------------------------------------
// Updates providers
// ---------------------------------------------------------------------------

final updatesProvider = Provider<List<UpdateItem>>((ref) {
  return _seedUpdates();
});

final updatesFilterProvider = StateProvider<bool?>((ref) => null);

// ---------------------------------------------------------------------------
// Anime detail — AniChart "next airing" provider
// ---------------------------------------------------------------------------

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

final nextAiringProvider =
    Provider.family<NextAiring?, int>((ref, animeId) {
  // Deterministic placeholder for the demo build — a real implementation
  // would hit the AniList GraphQL endpoint.
  final seed = animeId * 13 + DateTime.now().day;
  final inDays = (seed % 8) + 1;
  final airingAt = DateTime.now().add(Duration(days: inDays, hours: 4));
  return NextAiring(
    episode: ((seed % 12) + 1),
    airingAt: airingAt,
    timeUntilAiring: airingAt.difference(DateTime.now()),
  );
});

// ---------------------------------------------------------------------------
// Global app toggles — incognito / downloaded only / Wi-Fi-only downloads
// ---------------------------------------------------------------------------

/// When true, reading & watching activity is not recorded to history or
/// tracker services. Mirrors the incognito mode found in Mangayomi / Tachiyomi.
final incognitoModeProvider = StateProvider<bool>((ref) => false);

/// When true, the app only displays content that has been downloaded for
/// offline use, hiding anything that requires a network request.
final downloadedOnlyProvider = StateProvider<bool>((ref) => false);

/// When true, downloads are paused while the device is on a metered network.
final wifiOnlyDownloadsProvider = StateProvider<bool>((ref) => true);

// ---------------------------------------------------------------------------
// Extension repositories
// ---------------------------------------------------------------------------

class ExtensionRepo {
  ExtensionRepo({
    required this.url,
    required this.name,
    this.installedCount = 0,
    this.lastUpdated,
  });

  final String url;
  final String name;
  final int installedCount;
  final DateTime? lastUpdated;
}

final extensionReposProvider = StateProvider<List<ExtensionRepo>>((ref) {
  return [
    ExtensionRepo(
      url: 'https://raw.githubusercontent.com/lumina/extensions/main',
      name: 'Lumina official',
      installedCount: 6,
      lastUpdated: DateTime.now().subtract(const Duration(days: 2)),
    ),
    ExtensionRepo(
      url: 'https://raw.githubusercontent.com/aniyomi/aniyomi-extensions/main',
      name: 'Aniyomi community',
      installedCount: 4,
      lastUpdated: DateTime.now().subtract(const Duration(days: 9)),
    ),
  ];
});

// ---------------------------------------------------------------------------
// Settings providers
// ---------------------------------------------------------------------------

enum AppThemeMode { system, light, dark, amoled }

extension AppThemeModeX on AppThemeMode {
  String get label {
    switch (this) {
      case AppThemeMode.system:
        return 'System default';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.amoled:
        return 'AMOLED black';
    }
  }
}

enum ReaderBgColor { black, gray, white, sepia }

extension ReaderBgColorX on ReaderBgColor {
  String get label {
    switch (this) {
      case ReaderBgColor.black:
        return 'Black';
      case ReaderBgColor.gray:
        return 'Gray';
      case ReaderBgColor.white:
        return 'White';
      case ReaderBgColor.sepia:
        return 'Sepia';
    }
  }

  Color get color {
    switch (this) {
      case ReaderBgColor.black:
        return const Color(0xFF000000);
      case ReaderBgColor.gray:
        return const Color(0xFF212121);
      case ReaderBgColor.white:
        return const Color(0xFFFFFFFF);
      case ReaderBgColor.sepia:
        return const Color(0xFFF5E6C8);
    }
  }
}

class SettingsState {
  SettingsState({
    this.themeMode = AppThemeMode.system,
    this.einkMode = false,
    this.fontSize = 14.0,
    this.customSeed = const Color(0xFF6750A4),
    this.useDynamicColor = false,
    this.defaultReaderMode = ReaderMode.paged,
    this.defaultReaderDirection = ReaderDirection.leftToRight,
    this.readerBgColor = ReaderBgColor.black,
    this.keepScreenOn = true,
    this.showPageNumber = true,
    this.tapToNavigate = true,
    this.defaultVideoQuality = '1080p',
    this.defaultSubtitle = 'English',
    this.aniSkipEnabled = true,
    this.pipEnabled = true,
    this.autoDownloadNew = false,
    this.autoDownloadCategories = const <int>[],
    this.downloadOnWifiOnly = true,
    this.parallelDownloads = 3,
    this.appLockEnabled = false,
    this.lockOnLaunch = true,
    this.lockOnResume = false,
    this.cloudSyncEnabled = false,
    this.lastSyncAt,
    this.trackerAutoUpdate = true,
    this.backupIntervalDays = 7,
    this.lastBackupAt,
  });

  final AppThemeMode themeMode;
  final bool einkMode;
  final double fontSize;
  final Color customSeed;
  final bool useDynamicColor;

  final ReaderMode defaultReaderMode;
  final ReaderDirection defaultReaderDirection;
  final ReaderBgColor readerBgColor;
  final bool keepScreenOn;
  final bool showPageNumber;
  final bool tapToNavigate;

  final String defaultVideoQuality;
  final String defaultSubtitle;
  final bool aniSkipEnabled;
  final bool pipEnabled;

  final bool autoDownloadNew;
  final List<int> autoDownloadCategories;
  final bool downloadOnWifiOnly;
  final int parallelDownloads;

  final bool appLockEnabled;
  final bool lockOnLaunch;
  final bool lockOnResume;

  final bool cloudSyncEnabled;
  final DateTime? lastSyncAt;
  final bool trackerAutoUpdate;

  final int backupIntervalDays;
  final DateTime? lastBackupAt;
}

class AppSettingsNotifier extends StateNotifier<SettingsState> {
  AppSettingsNotifier() : super(SettingsState());

  void setThemeMode(AppThemeMode m) =>
      _mutate((s) => s..themeMode = m);
  void toggleEinkMode() => _mutate((s) => s..einkMode = !s.einkMode);
  void setFontSize(double v) => _mutate((s) => s..fontSize = v);
  void setCustomSeed(Color c) => _mutate((s) => s..customSeed = c);
  void toggleDynamicColor() =>
      _mutate((s) => s..useDynamicColor = !s.useDynamicColor);
  void setReaderMode(ReaderMode m) =>
      _mutate((s) => s..defaultReaderMode = m);
  void setReaderDirection(ReaderDirection d) =>
      _mutate((s) => s..defaultReaderDirection = d);
  void setReaderBg(ReaderBgColor c) =>
      _mutate((s) => s..readerBgColor = c);
  void toggleKeepScreenOn() => _mutate((s) => s..keepScreenOn = !s.keepScreenOn);
  void togglePageNumber() =>
      _mutate((s) => s..showPageNumber = !s.showPageNumber);
  void toggleTapToNavigate() =>
      _mutate((s) => s..tapToNavigate = !s.tapToNavigate);
  void setVideoQuality(String q) =>
      _mutate((s) => s..defaultVideoQuality = q);
  void setSubtitle(String s) => _mutate((s) => s..defaultSubtitle = s);
  void toggleAniSkip() => _mutate((s) => s..aniSkipEnabled = !s.aniSkipEnabled);
  void togglePip() => _mutate((s) => s..pipEnabled = !s.pipEnabled);
  void toggleAutoDownloadNew() =>
      _mutate((s) => s..autoDownloadNew = !s.autoDownloadNew);
  void setParallelDownloads(int n) =>
      _mutate((s) => s..parallelDownloads = n);
  void toggleDownloadOnWifiOnly() =>
      _mutate((s) => s..downloadOnWifiOnly = !s.downloadOnWifiOnly);
  void toggleAppLock() => _mutate((s) => s..appLockEnabled = !s.appLockEnabled);
  void toggleLockOnLaunch() =>
      _mutate((s) => s..lockOnLaunch = !s.lockOnLaunch);
  void toggleLockOnResume() =>
      _mutate((s) => s..lockOnResume = !s.lockOnResume);
  void toggleCloudSync() =>
      _mutate((s) => s..cloudSyncEnabled = !s.cloudSyncEnabled);
  void markSynced() =>
      _mutate((s) => s..lastSyncAt = DateTime.now());
  void toggleTrackerAutoUpdate() =>
      _mutate((s) => s..trackerAutoUpdate = !s.trackerAutoUpdate);
  void setBackupInterval(int days) =>
      _mutate((s) => s..backupIntervalDays = days);
  void markBackup() =>
      _mutate((s) => s..lastBackupAt = DateTime.now());

  // Internal helper — because SettingsState fields are final we rebuild a
  // fresh instance from the current state with the mutation applied.
  void _mutate(void Function(_SettingsBuilder) mutate) {
    final builder = _SettingsBuilder.fromState(state);
    mutate(builder);
    state = builder.toState();
  }
}

/// Mutable companion of [SettingsState] used internally by the notifier so
/// the public surface can stay immutable.
class _SettingsBuilder {
  _SettingsBuilder.fromState(SettingsState s)
      : themeMode = s.themeMode,
        einkMode = s.einkMode,
        fontSize = s.fontSize,
        customSeed = s.customSeed,
        useDynamicColor = s.useDynamicColor,
        defaultReaderMode = s.defaultReaderMode,
        defaultReaderDirection = s.defaultReaderDirection,
        readerBgColor = s.readerBgColor,
        keepScreenOn = s.keepScreenOn,
        showPageNumber = s.showPageNumber,
        tapToNavigate = s.tapToNavigate,
        defaultVideoQuality = s.defaultVideoQuality,
        defaultSubtitle = s.defaultSubtitle,
        aniSkipEnabled = s.aniSkipEnabled,
        pipEnabled = s.pipEnabled,
        autoDownloadNew = s.autoDownloadNew,
        autoDownloadCategories = List<int>.from(s.autoDownloadCategories),
        downloadOnWifiOnly = s.downloadOnWifiOnly,
        parallelDownloads = s.parallelDownloads,
        appLockEnabled = s.appLockEnabled,
        lockOnLaunch = s.lockOnLaunch,
        lockOnResume = s.lockOnResume,
        cloudSyncEnabled = s.cloudSyncEnabled,
        lastSyncAt = s.lastSyncAt,
        trackerAutoUpdate = s.trackerAutoUpdate,
        backupIntervalDays = s.backupIntervalDays,
        lastBackupAt = s.lastBackupAt;

  AppThemeMode themeMode;
  bool einkMode;
  double fontSize;
  Color customSeed;
  bool useDynamicColor;

  ReaderMode defaultReaderMode;
  ReaderDirection defaultReaderDirection;
  ReaderBgColor readerBgColor;
  bool keepScreenOn;
  bool showPageNumber;
  bool tapToNavigate;

  String defaultVideoQuality;
  String defaultSubtitle;
  bool aniSkipEnabled;
  bool pipEnabled;

  bool autoDownloadNew;
  List<int> autoDownloadCategories;
  bool downloadOnWifiOnly;
  int parallelDownloads;

  bool appLockEnabled;
  bool lockOnLaunch;
  bool lockOnResume;

  bool cloudSyncEnabled;
  DateTime? lastSyncAt;
  bool trackerAutoUpdate;

  int backupIntervalDays;
  DateTime? lastBackupAt;

  SettingsState toState() => SettingsState(
        themeMode: themeMode,
        einkMode: einkMode,
        fontSize: fontSize,
        customSeed: customSeed,
        useDynamicColor: useDynamicColor,
        defaultReaderMode: defaultReaderMode,
        defaultReaderDirection: defaultReaderDirection,
        readerBgColor: readerBgColor,
        keepScreenOn: keepScreenOn,
        showPageNumber: showPageNumber,
        tapToNavigate: tapToNavigate,
        defaultVideoQuality: defaultVideoQuality,
        defaultSubtitle: defaultSubtitle,
        aniSkipEnabled: aniSkipEnabled,
        pipEnabled: pipEnabled,
        autoDownloadNew: autoDownloadNew,
        autoDownloadCategories: List<int>.unmodifiable(autoDownloadCategories),
        downloadOnWifiOnly: downloadOnWifiOnly,
        parallelDownloads: parallelDownloads,
        appLockEnabled: appLockEnabled,
        lockOnLaunch: lockOnLaunch,
        lockOnResume: lockOnResume,
        cloudSyncEnabled: cloudSyncEnabled,
        lastSyncAt: lastSyncAt,
        trackerAutoUpdate: trackerAutoUpdate,
        backupIntervalDays: backupIntervalDays,
        lastBackupAt: lastBackupAt,
      );
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, SettingsState>(
  (ref) => AppSettingsNotifier(),
);

// ===========================================================================
// Seed data
// ===========================================================================

List<Chapter> _chaptersFor(int mangaId, int count) {
  return List.generate(count, (i) {
    final number = count - i.toDouble();
    return Chapter(
      id: mangaId * 1000 + i,
      url: '/chapter/$number',
      name: 'Chapter $number',
      number: number,
      scanlator: i % 3 == 0 ? 'Lumina Scans' : 'Fan Group',
      dateUploaded: DateTime.now().subtract(Duration(days: i * 3)),
      isRead: i < (count * 0.6).floor(),
      isDownloaded: i < 4,
      lastPageRead: i < (count * 0.6).floor() ? 0 : 7,
      totalPages: 18 + (i % 6),
      progress: i < (count * 0.6).floor()
          ? 1
          : 0.4 + (i % 5) * 0.1,
    );
  });
}

List<Manga> _seedManga() {
  final titles = [
    'One Piece', 'Berserk', 'Vinland Saga', 'Vagabond', 'Kingdom',
    'Berserk of Gluttony', 'Frieren', 'Solo Leveling', 'Tower of God',
    'The Beginning After The End', 'Omniscient Reader', 'Eleceed',
    'Nano Machine', 'Return of the Mount Hua Sect', 'The Greatest Estate Developer',
  ];
  final statuses = [
    ItemStatus.ongoing, ItemStatus.ongoing, ItemStatus.ongoing,
    ItemStatus.publishingFinished, ItemStatus.ongoing,
  ];
  return List.generate(titles.length, (i) {
    final total = 30 + (i * 7) % 50;
    final unread = (total * (0.1 + (i % 5) * 0.15)).round();
    return Manga(
      id: i + 1,
      title: titles[i],
      sourceId: 1,
      url: '/manga/${i + 1}',
      itemType: ItemType.manga,
      author: 'Author ${i + 1}',
      artist: 'Artist ${i + 1}',
      description:
          'A sweeping epic that follows the journey of ${titles[i]} through '
          'a richly imagined world. As alliances shift and ancient powers '
          'stir, our heroes must confront the darkness within and without.\n\n'
          'Volume after volume the stakes rise, weaving together themes of '
          'friendship, sacrifice and the relentless pursuit of a dream that '
          'refuses to die.',
      genre: ['Action', 'Adventure', 'Fantasy', 'Drama']..shuffle(),
      status: statuses[i % statuses.length],
      thumbnailUrl: 'https://picsum.photos/seed/manga-${i + 1}/300/450',
      favorite: i % 3 != 0,
      categoryIds: [1, if (i % 2 == 0) 3, if (i % 4 == 0) 4],
      chapters: _chaptersFor(i + 1, total.clamp(8, 20)),
      lastReadAt: DateTime.now().subtract(Duration(hours: i * 5)),
      dateAdded: DateTime.now().subtract(Duration(days: i * 10 + 3)),
      rating: 4.0 + (i % 10) / 10,
      unreadCount: unread,
      totalChapters: total,
      lastChapterRead: (total - unread).toDouble(),
    );
  });
}

List<Manga> _seedAnime() {
  final titles = [
    'Frieren: Beyond Journey\'s End', 'Solo Leveling', 'Jujutsu Kaisen',
    'Demon Slayer', 'Attack on Titan', 'Spy x Family', 'Chainsaw Man',
    'Mushoku Tensei', 'Re:Zero', 'That Time I Got Reincarnated as a Slime',
  ];
  return List.generate(titles.length, (i) {
    final total = 12 + (i * 3) % 24;
    final unread = (total * 0.2).round() + (i % 4);
    return Manga(
      id: 100 + i,
      title: titles[i],
      sourceId: 3,
      url: '/anime/${100 + i}',
      itemType: ItemType.anime,
      author: 'Studio ${i + 1}',
      description:
          '${titles[i]} is an acclaimed anime adaptation that has captivated '
          'audiences worldwide. With stunning animation and a powerful score, '
          'each episode raises the emotional stakes.',
      genre: ['Action', 'Fantasy', 'Adventure'],
      status: ItemStatus.ongoing,
      thumbnailUrl: 'https://picsum.photos/seed/anime-${i + 1}/300/450',
      favorite: true,
      categoryIds: [2, if (i % 3 == 0) 4],
      chapters: _chaptersFor(100 + i, total.clamp(6, 16)),
      lastReadAt: DateTime.now().subtract(Duration(hours: i * 7 + 2)),
      dateAdded: DateTime.now().subtract(Duration(days: i * 9 + 1)),
      rating: 4.2 + (i % 8) / 10,
      unreadCount: unread,
      totalChapters: total,
      lastChapterRead: (total - unread).toDouble(),
    );
  });
}

List<DownloadTask> _seedDownloads() {
  return [
    DownloadTask(
      id: 1,
      title: 'One Piece',
      chapterName: 'Chapter 1102',
      mangaId: 1,
      progress: 0.62,
      state: DownloadState.downloading,
      speedBytesPerSec: 2.4 * 1024 * 1024,
      downloadedBytes: 18 * 1024 * 1024,
      totalBytes: 29 * 1024 * 1024,
    ),
    DownloadTask(
      id: 2,
      title: 'Solo Leveling',
      chapterName: 'Chapter 179',
      mangaId: 8,
      progress: 0.28,
      state: DownloadState.downloading,
      speedBytesPerSec: 1.1 * 1024 * 1024,
      downloadedBytes: 8 * 1024 * 1024,
      totalBytes: 28 * 1024 * 1024,
    ),
    DownloadTask(
      id: 3,
      title: 'Jujutsu Kaisen',
      chapterName: 'Episode 24',
      mangaId: 102,
      progress: 0,
      state: DownloadState.queued,
      isAnime: true,
    ),
    DownloadTask(
      id: 4,
      title: 'Berserk',
      chapterName: 'Chapter 374',
      mangaId: 2,
      progress: 1,
      state: DownloadState.completed,
      downloadedBytes: 32 * 1024 * 1024,
      totalBytes: 32 * 1024 * 1024,
    ),
    DownloadTask(
      id: 5,
      title: 'Kingdom',
      chapterName: 'Chapter 801',
      mangaId: 5,
      progress: 1,
      state: DownloadState.completed,
      downloadedBytes: 21 * 1024 * 1024,
      totalBytes: 21 * 1024 * 1024,
    ),
    DownloadTask(
      id: 6,
      title: 'Demon Slayer',
      chapterName: 'Episode 12',
      mangaId: 103,
      progress: 0.45,
      state: DownloadState.failed,
      errorMessage: 'Network timeout (504)',
      isAnime: true,
    ),
    DownloadTask(
      id: 7,
      title: 'Frieren',
      chapterName: 'Episode 18',
      mangaId: 100,
      progress: 0.8,
      state: DownloadState.paused,
      isAnime: true,
    ),
  ];
}

List<Note> _seedNotes() {
  return [
    Note(
      id: 1,
      content: 'The mentor arc recontextualises the entire journey — brilliant foreshadowing here.',
      mangaId: 7,
      mangaTitle: 'Frieren',
      type: NoteType.thought,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      color: NoteColor.purple,
      chapterId: 7012,
      page: 9,
      tags: ['mentor', 'foreshadowing'],
    ),
    Note(
      id: 2,
      content: '“A journey is not about the destination, it is about who walks beside you.”',
      mangaId: 7,
      mangaTitle: 'Frieren',
      type: NoteType.highlight,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      color: NoteColor.yellow,
      chapterId: 7012,
      page: 12,
    ),
    Note(
      id: 3,
      content: 'Power scaling finally pays off — the dwarf fight is peak fiction.',
      mangaId: 8,
      mangaTitle: 'Solo Leveling',
      type: NoteType.thought,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      color: NoteColor.orange,
      chapterId: 8012,
      page: 4,
    ),
    Note(
      id: 4,
      content: 'Guts vs Griffith parallels — the hawk imagery returns.',
      mangaId: 2,
      mangaTitle: 'Berserk',
      type: NoteType.highlight,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
      color: NoteColor.pink,
      chapterId: 2012,
      page: 2,
    ),
    Note(
      id: 5,
      content: 'Reminder to revisit the prologue once volume 14 lands.',
      mangaId: 4,
      mangaTitle: 'Vagabond',
      type: NoteType.thought,
      createdAt: DateTime.now().subtract(const Duration(days: 6)),
      color: NoteColor.green,
    ),
    Note(
      id: 6,
      content: 'The kingdom’s tactical formations are surprisingly well researched.',
      mangaId: 5,
      mangaTitle: 'Kingdom',
      type: NoteType.highlight,
      createdAt: DateTime.now().subtract(const Duration(days: 9)),
      color: NoteColor.blue,
      chapterId: 5012,
      page: 6,
    ),
  ];
}

List<HistoryEntry> _seedHistory() {
  final items = [
    (1, 'One Piece', 'Chapter 1101', 1101, 0.7, false),
    (100, 'Frieren', 'Episode 17', 17, 1.0, true),
    (8, 'Solo Leveling', 'Chapter 178', 178, 0.4, false),
    (102, 'Jujutsu Kaisen', 'Episode 23', 23, 0.5, true),
    (2, 'Berserk', 'Chapter 373', 373, 0.9, false),
    (103, 'Demon Slayer', 'Episode 11', 11, 1.0, true),
    (3, 'Vinland Saga', 'Chapter 216', 216, 0.2, false),
  ];
  return items.asMap().entries.map((e) {
    final i = e.key;
    final v = e.value;
    return HistoryEntry(
      id: i + 1,
      mangaId: v.$1,
      mangaTitle: v.$2,
      thumbnailUrl: 'https://picsum.photos/seed/hist-${v.$1}/200/300',
      chapterName: v.$3,
      chapterNumber: v.$4.toDouble(),
      readAt: DateTime.now().subtract(Duration(hours: i * 6 + 1)),
      progress: v.$5,
      isAnime: v.$6,
      page: (v.$5 * 18).round(),
      totalPages: 18,
    );
  }).toList();
}

List<UpdateItem> _seedUpdates() {
  final items = [
    (1, 'One Piece', 'Chapter 1103', false, false, false, 'Lumina Scans'),
    (2, 'Berserk', 'Chapter 375', false, false, false, 'Dark Horse'),
    (7, 'Frieren', 'Chapter 138', true, false, false, 'Fan Group'),
    (8, 'Solo Leveling', 'Chapter 201', false, true, false, 'Lumina Scans'),
    (100, 'Frieren', 'Episode 19', false, false, true, null),
    (102, 'Jujutsu Kaisen', 'Episode 25', false, false, true, null),
    (5, 'Kingdom', 'Chapter 802', true, true, false, 'Fan Group'),
    (103, 'Demon Slayer', 'Episode 13', false, false, true, null),
    (3, 'Vinland Saga', 'Chapter 217', false, false, false, 'Kodansha'),
  ];
  return items.asMap().entries.map((e) {
    final i = e.key;
    final v = e.value;
    return UpdateItem(
      id: i + 1,
      mangaId: v.$1,
      mangaTitle: v.$2,
      thumbnailUrl: 'https://picsum.photos/seed/upd-${v.$1}/200/300',
      chapterName: v.$3,
      date: DateTime.now().subtract(Duration(hours: i * 3 + 1)),
      isRead: v.$4,
      isDownloaded: v.$5,
      isAnime: v.$6,
      scanlator: v.$7,
    );
  }).toList();
}
