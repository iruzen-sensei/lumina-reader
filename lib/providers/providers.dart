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

// ---------------------------------------------------------------------------
// APP-LEVEL PROVIDERS — every screen's data source.
//
// ARCHITECTURE (post-remediation):
//   screens → these providers → repositories (lib/data/) → Isar
//                                      ↘ ExtensionCoordinator → sources
//
// All seed/mock data has been REMOVED. Providers are either:
//   * Isar-watch-backed (library, notes, history, downloads, updates,
//     categories, sources) — they rebuild automatically when the DB changes,
//     or
//   * auto-loading notifiers (reader pages, video sources, aniSkip, stats,
//     calendar) — they fetch through the coordinator / services on creation
//     and expose the SAME synchronous contract the screens always consumed,
//     so screens did not need rewrites for these paths.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../data/providers.dart' as data;
import '../models/settings.dart' as db_s;
import '../models/update.dart' as db_update;
import '../models/models.dart';
import '../services/anichart.dart' as anichart;
import '../services/aniskip.dart' as aniskip;
import '../services/extension_coordinator.dart';
import '../services/extension_repo_service.dart';
import '../models/mappers.dart' as map;
import '../services/library_updater.dart';

export '../services/extension_repo_service.dart'
    show ExtensionRepo, RepoExtension, kDefaultRepoUrl;

// Media DTOs moved to models.dart — re-exported here so existing screen
// imports (`import '../providers/providers.dart'`) keep resolving.
export '../models/models.dart'
    show
        VideoQuality,
        SubtitleTrack,
        SkipRange,
        NextAiring,
        StreakState;

/// Minimal stream debouncer (Isar's watchLazy fires once per transaction;
/// bursts of writes — e.g. per-page progress saves — must collapse into one
/// reload).
extension _DebounceStream<T> on Stream<T> {
  Stream<T> debounceTime(Duration duration) {
    Timer? timer;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        final sub = listen((event) {
          timer?.cancel();
          timer = Timer(duration, () => controller.add(event));
        }, onDone: controller.close);
        controller.onCancel = () {
          timer?.cancel();
          return sub.cancel();
        };
      },
    );
    return controller.stream;
  }
}

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
// Library data (Isar-backed)
// ---------------------------------------------------------------------------

/// Watches the whole library and maps it to presentation DTOs. Any Isar
/// write (progress, favorite, add/remove) re-emits automatically.
class LibraryListNotifier extends StateNotifier<List<Manga>> {
  LibraryListNotifier(this._type, this._repo) : super(const []) {
    _sub = _repo.watchLibrary()
        .debounceTime(const Duration(milliseconds: 80))
        .listen((_) => _reload());
    _reload();
  }

  final ItemType _type;
  final data.LibraryRepository _repo;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      final all = await _repo.getLibrary();
      state = all.where((m) => m.itemType == _type).toList();
    } catch (e) {
      debugPrint('LibraryListNotifier($_type) reload failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final mangaLibraryProvider =
    StateNotifierProvider<LibraryListNotifier, List<Manga>>(
  (ref) => LibraryListNotifier(
      ItemType.manga, ref.watch(data.libraryRepositoryProvider)),
);

final animeLibraryProvider =
    StateNotifierProvider<LibraryListNotifier, List<Manga>>(
  (ref) => LibraryListNotifier(
      ItemType.anime, ref.watch(data.libraryRepositoryProvider)),
);

/// Novels + local books share the library tab; combined provider keeps the
/// existing screen contract while ItemType now distinguishes them cleanly.
final bookLibraryProvider =
    StateNotifierProvider<LibraryListNotifier, List<Manga>>(
  (ref) => LibraryListNotifier(
      ItemType.book, ref.watch(data.libraryRepositoryProvider)),
);

final novelLibraryProvider =
    StateNotifierProvider<LibraryListNotifier, List<Manga>>(
  (ref) => LibraryListNotifier(
      ItemType.novel, ref.watch(data.libraryRepositoryProvider)),
);

/// Filters + sorts the anime library according to [libraryOptionsProvider].
/// Applies the global "Downloaded only" toggle (previously the switch only
/// flipped a badge and never filtered any list).
final filteredAnimeProvider = Provider<List<Manga>>((ref) {
  final all = ref.watch(animeLibraryProvider);
  final options = ref.watch(libraryOptionsProvider);
  final downloadedOnly = ref.watch(downloadedOnlyProvider);
  var items = _applyLibraryOptions(all, options);
  if (downloadedOnly) {
    items = items
        .where((m) => m.chapters.any((c) => c.isDownloaded))
        .toList();
  }
  return items;
});

/// Everything the Library tab can show: manga + novels + imported local
/// books. Previously the tab watched ONLY the manga list, so imported
/// EPUB/PDF/CBZ files (ItemType.book) silently vanished after import —
/// the snackbar said "Imported 1 file(s)" and the grid never changed.
final libraryTabProvider = Provider<List<Manga>>((ref) => [
      ...ref.watch(mangaLibraryProvider),
      ...ref.watch(novelLibraryProvider),
      ...ref.watch(bookLibraryProvider),
    ]);

/// Filters + sorts the Library tab. Applies the media-type pills
/// (All / Manga / Novel / Book) on top of [libraryTabProvider] — the pills
/// were previously rendered but never consumed by any filter logic.
/// The anime tab deliberately does NOT apply mediaType (it has its own
/// dedicated screen and always shows ItemType.anime).
final filteredMangaProvider = Provider<List<Manga>>((ref) {
  final all = ref.watch(libraryTabProvider);
  final options = ref.watch(libraryOptionsProvider);
  final downloadedOnly = ref.watch(downloadedOnlyProvider);
  var items = _applyLibraryOptions(all, options);
  final ItemType? mediaFilter = switch (options.mediaType) {
    LibraryMediaType.all => null,
    LibraryMediaType.manga => ItemType.manga,
    LibraryMediaType.anime => ItemType.anime,
    LibraryMediaType.novel => ItemType.novel,
    LibraryMediaType.book => ItemType.book,
  };
  if (mediaFilter != null) {
    items = items.where((m) => m.itemType == mediaFilter).toList();
  }
  if (downloadedOnly) {
    items = items
        .where((m) => m.chapters.any((c) => c.isDownloaded))
        .toList();
  }
  return items;
});

List<Manga> _applyLibraryOptions(
  List<Manga> input,
  LibraryOptions options,
) {
  var items = List<Manga>.from(input);

  if (options.activeCategoryId != 0) {
    items = items
        .where((m) => m.categoryIds.contains(options.activeCategoryId))
        .toList();
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
          .where((m) => m.unreadCount == 0 && m.totalChapters > 0)
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
// Categories (Isar-backed)
// ---------------------------------------------------------------------------

class CategoriesNotifier extends StateNotifier<List<Category>> {
  CategoriesNotifier(this._repo) : super(const []) {
    _sub = _repo.watchCategories().listen((_) => _reload());
    _reload();
  }

  final data.LibraryRepository _repo;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      var cats = await _repo.getCategories();
      if (cats.isEmpty) {
        cats = await _repo.ensureDefaultCategories();
      }
      state = [
        Category(id: 0, name: 'All'),
        ...cats,
      ];
    } catch (e) {
      debugPrint('CategoriesNotifier reload failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, List<Category>>(
  (ref) => CategoriesNotifier(ref.watch(data.libraryRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Downloads providers (Isar-backed queue + engine hookup)
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

/// Queue-state notifier. The transfer engine (download manager service)
/// writes state transitions into the DownloadsRepository; this notifier
/// mirrors them to the UI. Control methods (pause/resume/cancel/…) forward
/// to the repository and additionally notify the engine.
class DownloadsNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadsNotifier(this._repo) : super(const []) {
    _sub = _repo.watch().listen((_) => _reload());
    _reload();
  }

  final data.DownloadsRepository _repo;
  StreamSubscription<void>? _sub;

  // Last snapshot per task id — used to derive a live bytes/sec readout
  // (the Download row stores byte counters, not speeds).
  final Map<int, (int, DateTime)> _lastBytes = {};

  Future<void> _reload() async {
    try {
      final now = DateTime.now();
      final rows = await _repo.getAll();
      final next = <DownloadTask>[];
      for (final t in rows) {
        var speed = 0.0;
        if (t.state == DownloadState.downloading) {
          final last = _lastBytes[t.id];
          if (last != null) {
            final dBytes = t.downloadedBytes - last.$1;
            final dSec = now.difference(last.$2).inMilliseconds / 1000.0;
            if (dSec > 0.2 && dBytes > 0) speed = dBytes / dSec;
          }
          _lastBytes[t.id] = (t.downloadedBytes, now);
        } else {
          _lastBytes.remove(t.id);
        }
        t.speedBytesPerSec = speed;
        next.add(t);
      }
      state = next;
    } catch (e) {
      debugPrint('DownloadsNotifier reload failed: $e');
    }
  }

  Future<void> pause(int id) => _repo.pause(id);
  Future<void> resume(int id) => _repo.resume(id);
  Future<void> cancel(int id) => _repo.cancel(id);
  Future<void> retry(int id) => _repo.resume(id);

  Future<void> pauseAll() async {
    for (final t in state) {
      if (t.state == DownloadState.downloading ||
          t.state == DownloadState.queued) {
        await _repo.pause(t.id);
      }
    }
  }

  Future<void> resumeAll() async {
    for (final t in state) {
      if (t.state == DownloadState.paused ||
          t.state == DownloadState.queued) {
        await _repo.resume(t.id);
      }
    }
  }

  Future<void> clearCompleted() => _repo.clearCompleted();

  Future<void> clearAll() => _repo.clearAll();

  Future<void> remove(int id) => _repo.remove(id);

  /// Remove a task AND its downloaded files (what every "Remove" affordance
  /// in the Downloads screen calls — previously only the queue row vanished
  /// and the files stayed on disk with the chapter checkmark still set).
  Future<void> removeWithFiles(int id) async {
    final chapterId = await _repo.chapterIdFor(id);
    if (chapterId != null) {
      await _repo.removeByChapter(chapterId);
    } else {
      await _repo.remove(id);
    }
  }

  /// Enqueues a chapter download for a library item.
  Future<void> enqueueChapter({
    required Manga manga,
    required Chapter chapter,
  }) =>
      _repo.enqueue(
        mangaId: manga.id,
        chapterId: chapter.id,
        mangaTitle: manga.title,
        chapterName: chapter.name,
        isAnime: false,
        mangaCover: manga.thumbnailUrl,
      );

  /// Enqueues an EPISODE download (the engine resolves the stream through
  /// the coordinator's videoList and pulls the m3u8 segments).
  Future<void> enqueueEpisode({
    required Manga manga,
    required Chapter chapter,
  }) =>
      _repo.enqueue(
        mangaId: manga.id,
        chapterId: chapter.id,
        mangaTitle: manga.title,
        chapterName: chapter.name,
        isAnime: true,
        mangaCover: manga.thumbnailUrl,
      );

  /// Removes a download row AND its files on disk + resets the chapter's
  /// downloaded flag (previously only the queue row vanished and the
  /// "downloaded" checkmark stayed forever). Chapter-row writes re-emit
  /// watchLibrary so every screen refreshes automatically.
  Future<void> deleteChapterFiles(int chapterId) async {
    await _repo.removeByChapter(chapterId);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadTask>>(
  (ref) => DownloadsNotifier(ref.watch(data.downloadsRepositoryProvider)),
);

final downloadsTabProvider =
    StateProvider<DownloadsTab>((ref) => DownloadsTab.all);

// ---------------------------------------------------------------------------
// Manga detail provider (nullable — a missing id renders "not found")
// ---------------------------------------------------------------------------

class MangaDetailNotifier extends StateNotifier<Manga?> {
  MangaDetailNotifier(this._id, this._repo) : super(null) {
    _sub = _repo.watchLibrary()
        .debounceTime(const Duration(milliseconds: 80))
        .listen((_) => _reload());
    _reload();
  }

  final int _id;
  final data.LibraryRepository _repo;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      state = await _repo.getManga(_id);
    } catch (e) {
      debugPrint('MangaDetailNotifier($_id) reload failed: $e');
    }
  }

  /// Updates the in-memory copy optimistically (screens keep mutating DTOs
  /// directly for snappy UI; persistence happens via the repository).
  void patch(Manga manga) => state = manga;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Detail data for a library entry. `null` while loading / when the id does
/// not exist — consuming screens show a "not found" view.
final mangaDetailProvider =
    StateNotifierProvider.family<MangaDetailNotifier, Manga?, int>(
  (ref, id) => MangaDetailNotifier(id, ref.watch(data.libraryRepositoryProvider)),
);

final chapterListProvider = Provider.family<List<Chapter>, int>((ref, id) {
  final manga = ref.watch(mangaDetailProvider(id));
  return manga?.chapters ?? const [];
});

// ---------------------------------------------------------------------------
// Reader providers
// ---------------------------------------------------------------------------

enum ReaderMode { paged, continuous, webtoon }

enum ReaderDirection { leftToRight, rightToLeft, vertical }

enum ReaderFit { contain, cover, fill, original }

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

  // Value equality — syncFromAppSettings compares old vs. mapped state to
  // avoid announcing no-op rebuilds.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderSettings &&
          other.mode == mode &&
          other.direction == direction &&
          other.fit == fit &&
          other.tapToNavigate == tapToNavigate &&
          other.showPageNumber == showPageNumber &&
          other.keepScreenOn == keepScreenOn &&
          other.backgroundColor == backgroundColor;

  @override
  int get hashCode =>
      Object.hash(mode, direction, fit, tapToNavigate, showPageNumber,
          keepScreenOn, backgroundColor);
}

/// Reader session settings.
///
/// Hydrated from the PERSISTED app settings ([appSettingsProvider]) on
/// construction and re-synced whenever those settings change (e.g. edited
/// from the Settings screen). In-reader changes are written THROUGH to the
/// persisted defaults so they survive app restarts — previously this
/// notifier was a bare in-memory StateNotifier, so every reader preference
/// silently reset on relaunch.
class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  ReaderSettingsNotifier(this._ref) : super(ReaderSettings()) {
    syncFromAppSettings(_ref.read(appSettingsProvider), initial: true);
  }

  final Ref _ref;

  /// Updates local state from the persisted app settings WITHOUT writing
  /// back (prevents feedback loops with the write-through setters).
  void syncFromAppSettings(SettingsState s, {bool initial = false}) {
    final mapped = ReaderSettings(
      mode: s.defaultReaderMode,
      direction: s.defaultReaderDirection,
      fit: state.fit,
      tapToNavigate: s.tapToNavigate,
      showPageNumber: s.showPageNumber,
      keepScreenOn: s.keepScreenOn,
      backgroundColor: s.readerBgColor.color,
    );
    // Only announce when something actually changed — avoids useless
    // rebuilds on every unrelated settings mutation.
    if (initial || mapped != state) state = mapped;
  }

  void setMode(ReaderMode m) {
    state = state.copyWith(mode: m);
    _ref.read(appSettingsProvider.notifier).setReaderMode(m);
  }

  void setDirection(ReaderDirection d) {
    state = state.copyWith(direction: d);
    _ref.read(appSettingsProvider.notifier).setReaderDirection(d);
  }

  void setFit(ReaderFit f) => state = state.copyWith(fit: f);

  void setBackgroundColor(Color c) {
    state = state.copyWith(backgroundColor: c);
    final bg = ReaderBgColor.values.firstWhere(
      (b) => b.color == c,
      orElse: () => ReaderBgColor.black,
    );
    _ref.read(appSettingsProvider.notifier).setReaderBg(bg);
  }

  void togglePageNumber() {
    state = state.copyWith(showPageNumber: !state.showPageNumber);
    _ref.read(appSettingsProvider.notifier).togglePageNumber();
  }

  void toggleKeepScreenOn() {
    state = state.copyWith(keepScreenOn: !state.keepScreenOn);
    _ref.read(appSettingsProvider.notifier).toggleKeepScreenOn();
  }

  void toggleTapToNavigate() {
    state = state.copyWith(tapToNavigate: !state.tapToNavigate);
    _ref.read(appSettingsProvider.notifier).toggleTapToNavigate();
  }
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  (ref) {
    final notifier = ReaderSettingsNotifier(ref);
    // Keep the reader defaults aligned with persisted settings (Settings
    // screen edits apply to the next reader session / open sessions).
    ref.listen<SettingsState>(appSettingsProvider, (prev, next) {
      notifier.syncFromAppSettings(next);
    });
    return notifier;
  },
);

/// Auto-loading page cache for a chapter. Created on first access; fetches
/// through the ExtensionCoordinator (downloaded chapters resolve to local
/// files via the download manager once wired) and exposes the synchronous
/// `List<String>` contract the readers always consumed.
class ChapterPagesNotifier extends StateNotifier<List<String>> {
  ChapterPagesNotifier(this._chapterId, this._coordinator)
      : super(const []) {
    _load();
  }

  final int _chapterId;
  final ExtensionCoordinator _coordinator;

  Future<void> _load() async {
    try {
      state = await _coordinator.pageList(_chapterId);
    } catch (e) {
      debugPrint('ChapterPagesNotifier($_chapterId) load failed: $e');
      state = const [];
    }
  }

  /// Re-fetch (pull-to-refresh / retry after a network failure).
  Future<void> reload() => _load();
}

final readerPagesProvider =
    StateNotifierProvider.family<ChapterPagesNotifier, List<String>, int>(
  (ref, chapterId) => ChapterPagesNotifier(
      chapterId, ref.watch(extensionCoordinatorProvider)),
);

// ---------------------------------------------------------------------------
// Anime player providers (auto-loading)
// ---------------------------------------------------------------------------

/// Video streams for an episode. Empty until loaded / when no anime source
/// provides streams — the player shows its empty state instead of a crash.
class EpisodeMediaNotifier extends StateNotifier<List<VideoQuality>> {
  EpisodeMediaNotifier(this._episodeId, this._coordinator)
      : super(const []) {
    _load();
  }

  final int _episodeId;
  final ExtensionCoordinator _coordinator;

  Future<void> _load() async {
    try {
      state = await _coordinator.videoList(_episodeId);
    } catch (e) {
      debugPrint('EpisodeMediaNotifier($_episodeId) load failed: $e');
    }
  }

  Future<void> reload() => _load();
}

final videoSourcesProvider =
    StateNotifierProvider.family<EpisodeMediaNotifier, List<VideoQuality>,
        int>(
  (ref, episodeId) => EpisodeMediaNotifier(
      episodeId, ref.watch(extensionCoordinatorProvider)),
);

/// Subtitle tracks. Sources without subtitle support get the default
/// "Off" entry only.
class SubtitleTracksNotifier extends StateNotifier<List<SubtitleTrack>> {
  SubtitleTracksNotifier() : super(const [SubtitleTrack('Off', '')]);

  void setTracks(List<SubtitleTrack> tracks) {
    state = [
      const SubtitleTrack('Off', ''),
      ...tracks.where((t) => t.url.isNotEmpty),
    ];
  }
}

final subtitleTracksProvider =
    StateNotifierProvider.family<SubtitleTracksNotifier, List<SubtitleTrack>,
        int>((ref, episodeId) => SubtitleTracksNotifier());

/// AniSkip segments for an episode, resolved through the real AniSkip API
/// (MAL id looked up from the anime's tags when the source provides one).
class AniSkipNotifier extends StateNotifier<List<SkipRange>> {
  AniSkipNotifier(this._episodeId, this._repo, this._service)
      : super(const []) {
    _load();
  }

  final int _episodeId;
  final data.LibraryRepository _repo;
  final aniskip.AniSkipService _service;

  Future<void> _load() async {
    try {
      final (manga, episode) = await _repo.resolveChapter(_episodeId);
      if (manga == null || episode == null) return;
      final malId = _extractMalId(manga);
      if (malId == null) return;
      final segments = await _service.getSkipSegments(
        malId: malId,
        episodeNumber: episode.number.round(),
      );
      state = [
        for (final s in segments)
          SkipRange(
            type: s.type.apiKey,
            start: Duration(milliseconds: (s.start * 1000).round()),
            end: Duration(milliseconds: (s.end * 1000).round()),
          ),
      ];
    } catch (e) {
      debugPrint('AniSkipNotifier($_episodeId) load failed: $e');
    }
  }

  int? _extractMalId(Manga manga) {
    for (final tag in manga.genre) {
      final match = RegExp(r'mal:(\d+)').firstMatch(tag);
      if (match != null) return int.parse(match.group(1)!);
    }
    return null;
  }
}

final aniSkipProvider =
    StateNotifierProvider.family<AniSkipNotifier, List<SkipRange>, int>(
  (ref, episodeId) => AniSkipNotifier(
    episodeId,
    ref.watch(data.libraryRepositoryProvider),
    ref.watch(aniSkipServiceProvider),
  ),
);

final aniSkipServiceProvider = Provider<aniskip.AniSkipService>(
  (ref) => aniskip.AniSkipService(),
);

// ---------------------------------------------------------------------------
// Stats providers (auto-loading, Isar-derived)
// ---------------------------------------------------------------------------

class _StatsReloader<T> extends StateNotifier<T> {
  _StatsReloader(
    Future<T> Function() loader,
    Stream<void> changes,
    T initial,
  ) : super(initial) {
    _sub = changes
        .debounceTime(const Duration(milliseconds: 150))
        .listen((_) async {
      try {
        state = await loader();
      } catch (e) {
        debugPrint('Stats reload failed: $e');
      }
    });
    () async {
      try {
        state = await loader();
      } catch (e) {
        debugPrint('Stats initial load failed: $e');
      }
    }();
  }

  StreamSubscription<void>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final statsHeatmapProvider =
    StateNotifierProvider<_StatsReloader<List<StatDay>>, List<StatDay>>(
  (ref) => _StatsReloader<List<StatDay>>(
    () => ref.read(data.statsRepositoryProvider).heatmap(),
    ref.read(data.statsRepositoryProvider).watch(),
    const [],
  ),
);

final statsGoalsProvider =
    StateNotifierProvider<_StatsReloader<List<Goal>>, List<Goal>>(
  (ref) => _StatsReloader<List<Goal>>(
    () => ref.read(data.statsRepositoryProvider).goals(),
    ref.read(data.statsRepositoryProvider).watch(),
    const [],
  ),
);

final streakProvider =
    StateNotifierProvider<_StatsReloader<StreakState>, StreakState>(
  (ref) => _StatsReloader<StreakState>(
    () async {
      final s = await ref.read(data.statsRepositoryProvider).streak();
      return StreakState(
        currentStreak: s.current,
        longestStreak: s.longest,
        freezeTokens: 0,
        lastActiveDay: s.lastActiveDay,
      );
    },
    ref.read(data.statsRepositoryProvider).watch(),
    StreakState(),
  ),
);

final statsSummaryProvider =
    StateNotifierProvider<_StatsReloader<Map<String, int>>, Map<String, int>>(
  (ref) => _StatsReloader<Map<String, int>>(
    () => ref.read(data.statsRepositoryProvider).summary(),
    ref.read(data.statsRepositoryProvider).watch(),
    const {
      'mangaRead': 0,
      'animeWatched': 0,
      'pagesRead': 0,
      'minutesRead': 0,
      'chaptersRead': 0,
      'episodesWatched': 0,
    },
  ),
);

// ---------------------------------------------------------------------------
// Notes providers (Isar-backed)
// ---------------------------------------------------------------------------

enum NotesFilter { all, highlights, thoughts }

final notesFilterProvider = StateProvider<NotesFilter>((ref) => NotesFilter.all);
final notesSearchProvider = StateProvider<String>((ref) => '');
final notesBookFilterProvider = StateProvider<int?>((ref) => null);

class NotesListNotifier extends StateNotifier<List<Note>> {
  NotesListNotifier(this._repo) : super(const []) {
    _sub = _repo.watchNotes().listen((_) => _reload());
    _reload();
  }

  final data.NotesRepository _repo;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      state = await _repo.getNotes();
    } catch (e) {
      debugPrint('NotesListNotifier reload failed: $e');
    }
  }

  Future<void> add({
    required int mangaId,
    required String text,
    required NoteType type,
    required NoteColor color,
    int? chapterId,
    String? chapterName,
    int page = 0,
    List<String> tags = const [],
  }) =>
      _repo.addNote(
        mangaId: mangaId,
        text: text,
        type: type,
        color: color,
        chapterId: chapterId,
        chapterName: chapterName,
        page: page,
        tags: tags,
      );

  Future<void> update(int id, {String? text, NoteColor? color}) =>
      _repo.updateNote(id, text: text, color: color);

  Future<void> delete(int id) => _repo.deleteNote(id);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final notesProvider =
    StateNotifierProvider<NotesListNotifier, List<Note>>(
  (ref) => NotesListNotifier(ref.watch(data.notesRepositoryProvider)),
);

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
// Calendar providers (AniChart-backed)
// ---------------------------------------------------------------------------

final calendarFocusedDayProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

final calendarSelectedDayProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

/// Airing schedule for one day, fetched from the real AniChart (AniList
/// GraphQL) service. Empty list = nothing airing / offline.
class AiringScheduleNotifier extends StateNotifier<List<AiringEpisode>> {
  AiringScheduleNotifier(this._day, this._service) : super(const []) {
    _load();
  }

  final DateTime _day;
  final anichart.AniChartService _service;

  Future<void> _load() async {
    try {
      final from = DateTime(_day.year, _day.month, _day.day);
      final to = from.add(const Duration(days: 1));
      final entries = await _service.getSchedule(from: from, to: to);
      state = [
        for (final e in entries)
          AiringEpisode(
            id: e.anilistId,
            animeId: e.anilistId,
            title: e.title,
            thumbnailUrl: e.coverUrl,
            episodeNumber: e.episode,
            airingAt: e.airingDateTime,
            countdownSeconds:
                e.airingDateTime.difference(DateTime.now()).inSeconds,
          ),
      ]..sort((a, b) => a.airingAt.compareTo(b.airingAt));
    } catch (e) {
      debugPrint('AiringScheduleNotifier($_day) load failed: $e');
    }
  }

  Future<void> reload() => _load();
}

final airingScheduleProvider = StateNotifierProvider.family<
    AiringScheduleNotifier, List<AiringEpisode>, DateTime>(
  (ref, day) => AiringScheduleNotifier(day, ref.watch(aniChartServiceProvider)),
);

final aniChartServiceProvider = Provider<anichart.AniChartService>(
  (ref) => anichart.AniChartService(),
);

// ---------------------------------------------------------------------------
// History providers (Isar-backed)
// ---------------------------------------------------------------------------

class HistoryListNotifier extends StateNotifier<List<HistoryEntry>> {
  HistoryListNotifier(this._repo) : super(const []) {
    _sub = _repo.watchHistory().listen((_) => _reload());
    _reload();
  }

  final data.HistoryRepository _repo;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      state = await _repo.getHistory();
    } catch (e) {
      debugPrint('HistoryListNotifier reload failed: $e');
    }
  }

  Future<void> remove(int id) => _repo.remove(id);
  Future<void> clearAll() => _repo.clearAll();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryListNotifier, List<HistoryEntry>>(
  (ref) => HistoryListNotifier(ref.watch(data.historyRepositoryProvider)),
);

// ---------------------------------------------------------------------------
// Updates providers (Isar-backed)
// ---------------------------------------------------------------------------

class UpdatesListNotifier extends StateNotifier<List<UpdateItem>> {
  UpdatesListNotifier(this._storage) : super(const []) {
    _sub = _storage.isar.updates.watchLazy(fireImmediately: true).listen((_) {
      _reload();
    });
  }

  final data.StorageProvider _storage;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      final rows =
          await _storage.isar.updates.where().sortByDiscoveredAtDesc().findAll();
      state = rows.map(_toDto).toList();
    } catch (e) {
      debugPrint('UpdatesListNotifier reload failed: $e');
    }
  }

  UpdateItem _toDto(db_update.Update u) => UpdateItem(
        id: u.id,
        mangaId: u.mangaId ?? 0,
        mangaTitle: u.mangaTitle ?? '',
        thumbnailUrl: u.mangaCover,
        chapterName: u.chapterName ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
            u.discoveredAt ?? DateTime.now().millisecondsSinceEpoch),
        isRead: u.isRead ?? false,
        isDownloaded: u.isDownloaded ?? false,
        isAnime: u.isAnime ?? false,
        scanlator: u.scanlator,
        chapterId: u.chapterId,
      );

  /// Persists the read/seen flag of a single update row (previously the
  /// tile only flipped a local `setState` copy that reset on rebuild).
  Future<void> setRead(int updateId, {required bool read}) async {
    try {
      await _storage.isar.writeTxn(() async {
        final row = await _storage.isar.updates.get(updateId);
        if (row == null) return;
        row.isRead = read;
        await _storage.isar.updates.put(row);
      });
      // The Isar watch fires and reloads the list.
    } catch (e) {
      debugPrint('UpdatesListNotifier.setRead($updateId) failed: $e');
    }
  }

  /// Marks every update row as read (wired to the "Mark all read" action;
  /// previously a snackbar-only stub).
  Future<void> markAllRead() async {
    try {
      await _storage.isar.writeTxn(() async {
        final rows = await _storage.isar.updates.where().findAll();
        for (final row in rows) {
          if (row.isRead != true) {
            row.isRead = true;
            await _storage.isar.updates.put(row);
          }
        }
      });
    } catch (e) {
      debugPrint('UpdatesListNotifier.markAllRead failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final updatesProvider =
    StateNotifierProvider<UpdatesListNotifier, List<UpdateItem>>(
  (ref) => UpdatesListNotifier(ref.watch(data.storageProvider)),
);

final updatesFilterProvider = StateProvider<bool?>((ref) => null);

// ---------------------------------------------------------------------------
// Next airing (AniChart) — auto-loading
// ---------------------------------------------------------------------------

class NextAiringNotifier extends StateNotifier<NextAiring?> {
  NextAiringNotifier(this._animeId, this._repo, this._service) : super(null) {
    _load();
  }

  final int _animeId;
  final data.LibraryRepository _repo;
  final anichart.AniChartService _service;

  Future<void> _load() async {
    try {
      final manga = await _repo.getManga(_animeId);
      if (manga == null) return;
      int? anilistId;
      for (final tag in manga.genre) {
        final m = RegExp(r'anilist:(\d+)').firstMatch(tag);
        if (m != null) {
          anilistId = int.parse(m.group(1)!);
          break;
        }
      }
      if (anilistId == null) return; // no cross-reference → no airing info
      final next = await _service.getNextAiring(anilistId);
      if (next != null) {
        state = NextAiring(
          episode: next.episode,
          airingAt: next.airingDateTime,
          timeUntilAiring: next.airingDateTime.difference(DateTime.now()),
        );
      }
    } catch (e) {
      debugPrint('NextAiringNotifier($_animeId) load failed: $e');
    }
  }
}

final nextAiringProvider =
    StateNotifierProvider.family<NextAiringNotifier, NextAiring?, int>(
  (ref, animeId) => NextAiringNotifier(
    animeId,
    ref.watch(data.libraryRepositoryProvider),
    ref.watch(aniChartServiceProvider),
  ),
);

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
// Extension repositories (user-added source repositories) — REAL
// ---------------------------------------------------------------------------

/// Isar watch-backed repo list. Repos are persisted as JSON on the Settings
/// row and synced through [data.extensionRepoServiceProvider] (previously
/// this was an in-memory StateProvider that forgot everything on restart —
/// "I added a repository and it didn't display anything").
class ExtensionReposNotifier
    extends StateNotifier<List<ExtensionRepo>> {
  ExtensionReposNotifier(this._service) : super(const []) {
    _sub = _service.watchRepos().listen((_) => _reload());
    _reload();
  }

  final ExtensionRepoService _service;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      state = await _service.getRepos();
    } catch (e) {
      debugPrint('ExtensionReposNotifier reload failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final extensionReposProvider =
    StateNotifierProvider<ExtensionReposNotifier, List<ExtensionRepo>>(
  (ref) => ExtensionReposNotifier(
      ref.watch(data.extensionRepoServiceProvider)),
);

/// Extension catalog (installed + available), Isar watch-backed.
class ExtensionCatalogNotifier extends StateNotifier<List<Source>> {
  ExtensionCatalogNotifier(this._service) : super(const []) {
    _sub = _service.watchCatalog().listen((_) => _reload());
    _reload();
  }

  final ExtensionRepoService _service;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      final rows = await _service.catalog();
      state = rows.map(map.sourceToDto).toList();
    } catch (e) {
      debugPrint('ExtensionCatalogNotifier reload failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final extensionCatalogProvider =
    StateNotifierProvider<ExtensionCatalogNotifier, List<Source>>(
  (ref) => ExtensionCatalogNotifier(
      ref.watch(data.extensionRepoServiceProvider)),
);

// ---------------------------------------------------------------------------
// Extension coordinator provider
// ---------------------------------------------------------------------------

final extensionCoordinatorProvider = Provider<ExtensionCoordinator>(
  (ref) => ExtensionCoordinator(
    sources: ref.watch(data.sourcesRepositoryProvider),
    library: ref.watch(data.libraryRepositoryProvider),
  ),
);

// ---------------------------------------------------------------------------
// Source manga preview (Browse → detail before library add)
// ---------------------------------------------------------------------------

/// Full detail + chapters for a catalog entry that is NOT yet in the
/// library, keyed by `(sourceId, url)` — browse DTOs carry no persistent id
/// (id 0), which is exactly why this provider exists: previously every
/// browse tap pushed /mangaDetail/0 and died on "Not found".
///
/// The screen seeds the UI from the in-memory browse DTO (instant title +
/// cover) while this provider fetches the authoritative detail through the
/// extension coordinator.
final sourceMangaDetailProvider = FutureProvider.autoDispose
    .family<Manga, (int, String)>((ref, key) async {
  final (sourceId, url) = key;
  final coordinator = ref.watch(extensionCoordinatorProvider);
  return await coordinator.detail(sourceId, url);
});

/// The background library-update checker. Not auto-started in this build —
/// pull-to-refresh on the Library screen runs `runOnce()`; a future
/// milestone can call `start()` for the 30-minute periodic check once a
/// foreground service is wired.
final libraryUpdaterProvider = Provider<LibraryUpdater>(
  (ref) => LibraryUpdater(
    storage: ref.watch(data.storageProvider),
    library: ref.watch(data.libraryRepositoryProvider),
    coordinator: ref.watch(extensionCoordinatorProvider),
  ),
);

// ---------------------------------------------------------------------------
// Sources (Isar-backed) + Browse
// ---------------------------------------------------------------------------

class SourcesNotifier extends StateNotifier<List<Source>> {
  SourcesNotifier(this._repo) : super(const []) {
    _sub = _repo.watchSources().listen((_) => _reload());
    _reload();
  }

  final data.SourcesRepository _repo;
  StreamSubscription<void>? _sub;

  Future<void> _reload() async {
    try {
      await _repo.ensureBuiltinSources();
      state = await _repo.getSources();
    } catch (e) {
      debugPrint('SourcesNotifier reload failed: $e');
    }
  }

  Future<void> toggle(int sourceId) => _repo.toggleEnabled(sourceId);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final sourcesProvider =
    StateNotifierProvider<SourcesNotifier, List<Source>>(
  (ref) => SourcesNotifier(ref.watch(data.sourcesRepositoryProvider)),
);

/// Catalog grid for one source, keyed by `(sourceId, latest)`. The Latest
/// tab previously watched the SAME provider instance as Popular (family
/// keyed by sourceId only), so it displayed a duplicate of the popular
/// grid — `load(latest: true)` existed but was unreachable. The record key
/// gives each tab its own notifier.
/// Feed state with EXPLICIT loading + error phases. Previously the feed
/// was a bare `List<Manga>`: an in-flight fetch and a hard failure were
/// both `[]`, so the grid rendered "Nothing here yet" while loading and
/// looked exactly like a broken source.
class BrowseFeedState {
  const BrowseFeedState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<Manga> items;

  /// True while the initial (page-1) fetch is in flight.
  final bool loading;

  /// Human-readable failure reason; non-null means the initial fetch
  /// failed (the grid shows an error card with retry).
  final String? error;

  bool get hasError => error != null;
}

class BrowseGridNotifier extends StateNotifier<BrowseFeedState> {
  BrowseGridNotifier(
    this._sourceId,
    this._coordinator, {
    bool latest = false,
  })  : _latest = latest,
        super(const BrowseFeedState(loading: true)) {
    _load();
  }

  final int _sourceId;
  final bool _latest;
  final ExtensionCoordinator _coordinator;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;

  Future<void> _load() => load();

  Future<void> load({bool latest = false, int page = 1}) async {
    state = BrowseFeedState(items: state.items, loading: true);
    try {
      final useLatest = latest || _latest;
      final items = useLatest
          ? await _coordinator.latest(_sourceId, page: page)
          : await _coordinator.popular(_sourceId, page: page);
      _page = page;
      _hasMore = items.length >= 20; // sources page in twenties
      state = BrowseFeedState(items: items);
    } catch (e) {
      debugPrint('BrowseGridNotifier($_sourceId) load failed: $e');
      state = BrowseFeedState(error: _friendlyError(e));
    }
  }

  /// Appends the next page (infinite scroll). A failure here keeps the
  /// already-loaded items and surfaces the reason as a transient error
  /// the grid can show without wiping content.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final next = _latest
          ? await _coordinator.latest(_sourceId, page: _page + 1)
          : await _coordinator.popular(_sourceId, page: _page + 1);
      _page = _page + 1;
      _hasMore = next.length >= 20;
      if (next.isNotEmpty) {
        state = BrowseFeedState(items: [...state.items, ...next]);
      }
    } catch (e) {
      debugPrint('BrowseGridNotifier($_sourceId) loadMore failed: $e');
      state = BrowseFeedState(
          items: state.items, error: _friendlyError(e));
    } finally {
      _loadingMore = false;
    }
  }

  /// Maps raw exceptions to a one-line reason the grid can display.
  static String _friendlyError(Object e) {
    final msg = e.toString();
    if (e is StateError) return e.message;
    if (msg.contains('SocketException') || msg.contains('Failed host')) {
      return 'Network unreachable - check your connection.';
    }
    if (msg.contains('HandshakeException')) {
      return 'Secure connection failed.';
    }
    if (msg.contains('FormatException')) {
      return 'The source returned an unexpected response.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timeout')) {
      return 'The source took too long to respond.';
    }
    return 'Could not load this source.';
  }
}

final browseFeedProvider = StateNotifierProvider.family<
    BrowseGridNotifier,
    BrowseFeedState,
    (int, bool)>((ref, key) => BrowseGridNotifier(
      key.$1,
      ref.watch(extensionCoordinatorProvider),
      latest: key.$2,
    ));

/// Search ONE source. Keyed by (sourceId, query) — previously the
/// per-source search box watched the merged cross-source provider, so
/// searching inside a source returned a soup of every source's results.
final sourceSearchProvider = FutureProvider.autoDispose
    .family<List<Manga>, (int, String)>((ref, key) async {
  final (sourceId, query) = key;
  if (query.trim().isEmpty) return const [];
  final coordinator = ref.watch(extensionCoordinatorProvider);
  return await coordinator.search(sourceId, query);
});

/// Global search across every INSTALLED source. Runs one search per source
/// concurrently and merges the results.
final globalSearchProvider =
    FutureProvider.autoDispose.family<List<Manga>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  final sources = ref.watch(sourcesProvider).where((s) => s.isInstalled).toList();
  final coordinator = ref.watch(extensionCoordinatorProvider);
  final results = await Future.wait(
    sources.map((s) => coordinator.search(s.id, query).catchError((_) => <Manga>[])),
  );
  return results.expand((list) => list).toList();
});

// ---------------------------------------------------------------------------
// Settings providers (persisted to Isar)
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
    // Noir-first: the app is designed primarily for the black theme
    // (OpenAI/ElevenLabs/Grok dialect) — dark is the default for new
    // installs; users can still switch to system/light/amoled.
    this.themeMode = AppThemeMode.dark,
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
  AppSettingsNotifier(this._repo) : super(SettingsState()) {
    _load();
  }

  final data.SettingsRepository _repo;
  bool _hydrated = false;

  Future<void> _load() async {
    try {
      final s = await _repo.load();
      state = _fromDb(s);
      _hydrated = true;
    } catch (e) {
      debugPrint('AppSettingsNotifier load failed: $e');
    }
  }

  Future<void> _persist() async {
    if (!_hydrated) return;
    try {
      final db = _toDb(state);
      await _repo.save(db);
    } catch (e) {
      debugPrint('AppSettingsNotifier persist failed: $e');
    }
  }

  SettingsState _fromDb(db_s.Settings s) {
    AppThemeMode theme(AppThemeMode fallback) {
      switch (s.themeMode) {
        case 'system':
          return AppThemeMode.system;
        case 'light':
          return AppThemeMode.light;
        case 'dark':
          return AppThemeMode.dark;
        case 'amoled':
          return AppThemeMode.amoled;
        default:
          return fallback;
      }
    }

    ReaderBgColor bg(ReaderBgColor fallback) {
      switch (s.readerBackgroundColor) {
        case 0xFF212121:
          return ReaderBgColor.gray;
        case 0xFFFFFFFF:
          return ReaderBgColor.white;
        case 0xFFF5E6C8:
          return ReaderBgColor.sepia;
        case 0xFF000000:
          return ReaderBgColor.black;
        default:
          return fallback;
      }
    }

    return SettingsState(
      themeMode: theme(AppThemeMode.dark),
      einkMode: s.einkMode ?? false,
      fontSize: (s.uiFontSize ?? 14).toDouble(),
      customSeed: Color(s.accentColor ?? 0xFF6750A4),
      useDynamicColor: s.dynamicTheme ?? false,
      defaultReaderMode: ReaderMode.values[(s.readerDefaultMode ?? 0)
          .clamp(0, ReaderMode.values.length - 1)],
      defaultReaderDirection: ReaderDirection
          .values[(s.readerDirection ?? 0)
              .clamp(0, ReaderDirection.values.length - 1)],
      readerBgColor: bg(ReaderBgColor.black),
      keepScreenOn: s.readerKeepScreenOn ?? true,
      showPageNumber: s.readerShowPageNumber ?? true,
      tapToNavigate: s.readerTapToTurnPage ?? true,
      defaultVideoQuality: _qualityLabel(s.playerDefaultQuality ?? 1080),
      defaultSubtitle: s.playerSubtitleLanguage ?? 'English',
      aniSkipEnabled: s.playerAutoSkipOpening ?? true,
      pipEnabled: s.playerEnablePip ?? true,
      autoDownloadNew: s.downloadAutoNew ?? false,
      autoDownloadCategories: s.downloadAutoCategories ?? const <int>[],
      downloadOnWifiOnly: s.downloadOnlyOverWifi ?? true,
      parallelDownloads: s.downloadConcurrent ?? 3,
      appLockEnabled: s.appLockEnabled ?? false,
      lockOnLaunch: s.lockOnLaunch ?? true,
      lockOnResume: s.lockOnResume ?? false,
      cloudSyncEnabled: s.cloudSyncEnabled ?? false,
      lastSyncAt: s.cloudSyncLastSyncAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(s.cloudSyncLastSyncAt!),
      trackerAutoUpdate: s.syncAutoToTracker ?? true,
      backupIntervalDays: ((s.backupInterval ?? 168) / 24).round().clamp(1, 90),
      lastBackupAt: s.backupLastBackupAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(s.backupLastBackupAt!),
    );
  }

  String _qualityLabel(int height) {
    if (height >= 2160) return '4K';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 480) return '480p';
    return 'Auto';
  }

  int _qualityHeight(String label) {
    switch (label) {
      case '4K':
        return 2160;
      case '1440p':
        return 1440;
      case '1080p':
        return 1080;
      case '720p':
        return 720;
      case '480p':
        return 480;
      default:
        return 0;
    }
  }

  db_s.Settings _toDb(SettingsState s) {
    final theme = switch (s.themeMode) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
      AppThemeMode.amoled => 'amoled',
    };
    return db_s.Settings(
      id: 227,
      themeMode: theme,
      dynamicTheme: s.useDynamicColor,
      einkMode: s.einkMode,
      uiFontSize: s.fontSize.round(),
      accentColor: s.customSeed.toARGB32(),
      customThemeFontFamily: null,
      readerDefaultMode: s.defaultReaderMode.index,
      readerDirection: s.defaultReaderDirection.index,
      readerBackgroundColor: s.readerBgColor.color.toARGB32(),
      readerTapToTurnPage: s.tapToNavigate,
      readerShowPageNumber: s.showPageNumber,
      readerKeepScreenOn: s.keepScreenOn,
      playerDefaultQuality: _qualityHeight(s.defaultVideoQuality),
      playerSubtitleLanguage: s.defaultSubtitle,
      playerAutoSkipOpening: s.aniSkipEnabled,
      playerEnablePip: s.pipEnabled,
      downloadAutoNew: s.autoDownloadNew,
      downloadAutoCategories: s.autoDownloadCategories,
      downloadOnlyOverWifi: s.downloadOnWifiOnly,
      downloadConcurrent: s.parallelDownloads,
      libraryAutoUpdate: true,
      appLockEnabled: s.appLockEnabled,
      lockOnLaunch: s.lockOnLaunch,
      lockOnResume: s.lockOnResume,
      cloudSyncEnabled: s.cloudSyncEnabled,
      cloudSyncLastSyncAt: s.lastSyncAt?.millisecondsSinceEpoch,
      syncAutoToTracker: s.trackerAutoUpdate,
      backupInterval: s.backupIntervalDays * 24,
      backupLastBackupAt: s.lastBackupAt?.millisecondsSinceEpoch,
    );
  }

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
  void setSubtitle(String value) =>
      _mutate((s) => s..defaultSubtitle = value);
  void toggleAniSkip() => _mutate((s) => s..aniSkipEnabled = !s.aniSkipEnabled);
  void togglePip() => _mutate((s) => s..pipEnabled = !s.pipEnabled);
  void toggleAutoDownloadNew() =>
      _mutate((s) => s..autoDownloadNew = !s.autoDownloadNew);
  void setAutoDownloadCategories(List<int> ids) =>
      _mutate((s) => s..autoDownloadCategories = List<int>.from(ids));
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
  // fresh instance from the current state with the mutation applied, then
  // persist to Isar.
  void _mutate(void Function(_SettingsBuilder) mutate) {
    final builder = _SettingsBuilder.fromState(state);
    mutate(builder);
    state = builder.toState();
    _persist();
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
  (ref) => AppSettingsNotifier(ref.watch(data.settingsRepositoryProvider)),
);
