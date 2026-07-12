// Copyright 2025 Lumina Reader Contributors
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

import 'dart:async';

/// LibraryUpdater — Background library updater.
///
/// Periodically iterates over every enabled source/extension and fetches the
/// latest chapter/episode list for every manga/anime the user has added to
/// their library. New entries are persisted as `Update` records in Isar and
/// surfaced through a notification badge counter.
///
/// Configuration:
/// * [interval] — polling interval (default 30 minutes).
/// * [onlyOnWifi] — skip updates when not on Wi-Fi (default true).
/// * [maxConcurrentSources] — number of sources to query in parallel.
///
/// The updater is transport-agnostic — it calls into extension sources via
/// the abstract [Source] interface. Concrete source implementations live in
/// the extensions package and are registered into [SourceRegistry].
library library_updater;

// ---------------------------------------------------------------------------
// Data model (Isar-shaped)
// ---------------------------------------------------------------------------

/// One entry in the user's library.
class Manga {
  const Manga({
    required this.id,
    required this.sourceId,
    required this.url,
    required this.title,
    this.coverUrl,
    this.lastChapterUrl,
    this.lastChapterName,
    this.lastUpdateCheck,
  });

  final int id;
  final String sourceId;
  final String url;
  final String title;
  final String? coverUrl;
  final String? lastChapterUrl;
  final String? lastChapterName;
  final DateTime? lastUpdateCheck;

  Manga copyWith({
    String? lastChapterUrl,
    String? lastChapterName,
    DateTime? lastUpdateCheck,
  }) =>
      Manga(
        id: id,
        sourceId: sourceId,
        url: url,
        title: title,
        coverUrl: coverUrl,
        lastChapterUrl: lastChapterUrl ?? this.lastChapterUrl,
        lastChapterName: lastChapterName ?? this.lastChapterName,
        lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
      );
}

/// A discovered chapter/episode from a source.
class Chapter {
  const Chapter({
    required this.url,
    required this.name,
    this.dateUploaded,
    this.chapterNumber,
    this.scanlator,
  });

  final String url;
  final String name;
  final DateTime? dateUploaded;
  final double? chapterNumber;
  final String? scanlator;
}

/// A pending update notification record persisted to Isar.
class Update {
  const Update({
    this.id,
    required this.mangaId,
    required this.sourceId,
    required this.chapterUrl,
    required this.chapterName,
    required this.discoveredAt,
    this.read = false,
  });

  final int? id;
  final int mangaId;
  final String sourceId;
  final String chapterUrl;
  final String chapterName;
  final DateTime discoveredAt;
  final bool read;

  Update copyWith({int? id, bool? read}) => Update(
        id: id ?? this.id,
        mangaId: mangaId,
        sourceId: sourceId,
        chapterUrl: chapterUrl,
        chapterName: chapterName,
        discoveredAt: discoveredAt,
        read: read ?? this.read,
      );
}

// ---------------------------------------------------------------------------
// Source abstraction
// ---------------------------------------------------------------------------

/// Implemented by every extension source (Mangadex, MangaSee, Gogoanime, ...).
abstract class Source {
  String get id;
  String get name;
  bool get isEnabled;

  /// Returns the latest chapters for [manga] in newest-first order.
  Future<List<Chapter>> fetchChapters(Manga manga);
}

/// Registry of available sources.
class SourceRegistry {
  SourceRegistry._();
  static final SourceRegistry instance = SourceRegistry._();

  final Map<String, Source> _sources = <String, Source>{};

  void register(Source s) => _sources[s.id] = s;
  void unregister(String id) => _sources.remove(id);

  Source? byId(String id) => _sources[id];
  List<Source> get all => _sources.values.toList();
  List<Source> get enabled =>
      _sources.values.where((Source s) => s.isEnabled).toList();
}

// ---------------------------------------------------------------------------
// Storage abstraction (Isar-shaped)
// ---------------------------------------------------------------------------

/// Minimal DAO surface for the updater. The real implementation wraps Isar.
abstract class LibraryStore {
  List<Manga> get library;
  Future<void> upsertManga(Manga manga);
  Future<int> insertUpdate(Update u);
  Future<List<Update>> unreadUpdates();
  Future<void> markUpdateRead(int id);
  Future<void> clearUpdates();
}

/// In-memory default implementation. Swap with the Isar-backed one in main().
class InMemoryLibraryStore implements LibraryStore {
  final Map<int, Manga> _library = <int, Manga>{};
  final List<Update> _updates = <Update>[];
  int _nextId = 1;

  @override
  List<Manga> get library => _library.values.toList();

  @override
  Future<void> upsertManga(Manga manga) async {
    _library[manga.id] = manga;
  }

  @override
  Future<int> insertUpdate(Update u) async {
    final int id = _nextId++;
    _updates.add(u.copyWith(id: id));
    return id;
  }

  @override
  Future<List<Update>> unreadUpdates() async =>
      _updates.where((Update u) => !u.read).toList();

  @override
  Future<void> markUpdateRead(int id) async {
    for (int i = 0; i < _updates.length; i++) {
      if (_updates[i].id == id) {
        _updates[i] = _updates[i].copyWith(read: true);
      }
    }
  }

  @override
  Future<void> clearUpdates() async {
    _updates.clear();
  }

  void addManga(Manga m) => _library[m.id] = m;
}

// ---------------------------------------------------------------------------
// Notification abstraction
// ---------------------------------------------------------------------------

/// Sends a notification badge count to the platform notification tray.
typedef BadgeNotifier = void Function(int count);

void _noopBadge(int _) {}

// ---------------------------------------------------------------------------
// LibraryUpdater
// ---------------------------------------------------------------------------

/// Background library updater.
class LibraryUpdater {
  LibraryUpdater({
    required LibraryStore store,
    Duration? interval,
    bool onlyOnWifi = true,
    int maxConcurrentSources = 3,
    Future<bool> Function()? hasWifi,
    BadgeNotifier onBadgeUpdate = _noopBadge,
  })  : _store = store,
        _interval = interval ?? const Duration(minutes: 30),
        _onlyOnWifi = onlyOnWifi,
        _maxConcurrentSources = maxConcurrentSources,
        _hasWifi = hasWifi ?? _defaultHasWifi,
        _onBadgeUpdate = onBadgeUpdate;

  final LibraryStore _store;
  Duration _interval;
  bool _onlyOnWifi;
  int _maxConcurrentSources;
  Future<bool> Function() _hasWifi;
  BadgeNotifier _onBadgeUpdate;

  Timer? _timer;
  bool _running = false;
  DateTime? _lastRun;
  int _lastUnreadCount = 0;

  /// Polling interval (default 30 minutes).
  Duration get interval => _interval;
  set interval(Duration d) {
    _interval = d;
    if (_timer != null) {
      _stopTimer();
      _startTimer();
    }
  }

  bool get onlyOnWifi => _onlyOnWifi;
  set onlyOnWifi(bool v) => _onlyOnWifi = v;

  int get maxConcurrentSources => _maxConcurrentSources;
  set maxConcurrentSources(int v) =>
      _maxConcurrentSources = v < 1 ? 1 : v;

  bool get isRunning => _running;
  DateTime? get lastRun => _lastRun;
  int get unreadCount => _lastUnreadCount;

  /// Begin the periodic update cycle.
  void start() {
    if (_timer != null) return;
    _startTimer();
    // Kick off immediately on start.
    unawaited(runOnce());
  }

  /// Stop the periodic update cycle. In-flight runs are NOT interrupted.
  void stop() {
    _stopTimer();
  }

  /// Run a single update pass right now. Returns the number of new updates.
  Future<int> runOnce() async {
    if (_running) return 0;
    _running = true;
    try {
      if (_onlyOnWifi && !await _hasWifi()) {
        return 0;
      }

      final List<Source> sources = SourceRegistry.instance.enabled;
      if (sources.isEmpty) return 0;

      // Group library by source.
      final Map<String, List<Manga>> bySource = <String, List<Manga>>{};
      for (final Manga m in _store.library) {
        bySource.putIfAbsent(m.sourceId, () => <Manga>[]).add(m);
      }

      int newCount = 0;
      // Bounded concurrency across sources.
      final List<Future<int>> tasks = <Future<int>>[];
      final List<Source> queue = sources
          .where((Source s) => bySource.containsKey(s.id))
          .toList();

      final List<Future<void>> workers = <Future<void>>[];
      int nextSource = 0;

      Future<void> worker() async {
        while (true) {
          final int idx = nextSource++;
          if (idx >= queue.length) return;
          final Source src = queue[idx];
          final List<Manga> mangas = bySource[src.id] ?? const <Manga>[];
          for (final Manga m in mangas) {
            try {
              final List<Chapter> fresh = await src.fetchChapters(m);
              final int added = await _diffAndStore(m, fresh);
              newCount += added;
            } catch (_) {
              // Continue with the next manga on failure.
            }
          }
        }
      }

      for (int i = 0; i < _maxConcurrentSources; i++) {
        workers.add(worker());
      }
      await Future.wait(workers);

      _lastRun = DateTime.now();
      final int unread = (await _store.unreadUpdates()).length;
      _lastUnreadCount = unread;
      _onBadgeUpdate(unread);
      return newCount;
    } finally {
      _running = false;
    }
  }

  /// Diff fresh chapter list against the manga's stored last-chapter pointer
  /// and persist any new entries as [Update]s.
  Future<int> _diffAndStore(Manga manga, List<Chapter> fresh) async {
    if (fresh.isEmpty) return 0;
    // Source returns newest-first; pick the newest as the new "last seen".
    final Chapter newest = fresh.first;
    int added = 0;
    final String? known = manga.lastChapterUrl;
    if (known == null) {
      // First check — record only the newest, no notification spam.
      await _store.upsertManga(manga.copyWith(
        lastChapterUrl: newest.url,
        lastChapterName: newest.name,
        lastUpdateCheck: DateTime.now(),
      ));
      return 0;
    }

    final List<Chapter> newOnes = <Chapter>[];
    for (final Chapter c in fresh) {
      if (c.url == known) break;
      newOnes.add(c);
    }

    for (final Chapter c in newOnes) {
      await _store.insertUpdate(Update(
        mangaId: manga.id,
        sourceId: manga.sourceId,
        chapterUrl: c.url,
        chapterName: c.name,
        discoveredAt: c.dateUploaded ?? DateTime.now(),
      ));
      added++;
    }

    if (newOnes.isNotEmpty) {
      await _store.upsertManga(manga.copyWith(
        lastChapterUrl: newest.url,
        lastChapterName: newest.name,
        lastUpdateCheck: DateTime.now(),
      ));
    }
    return added;
  }

  // ---- Timer plumbing ------------------------------------------------------

  void _startTimer() {
    _timer = Timer.periodic(_interval, (Timer t) {
      unawaited(runOnce());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // ---- Default Wi-Fi check -------------------------------------------------

  static Future<bool> _defaultHasWifi() async {
    try {
      // Defer to connectivity_plus at runtime to keep this file dependency-free.
      // ignore: avoid_dynamic_calls
      final lib = _ConnectivityBridge();
      return lib.hasWifi;
    } catch (_) {
      return true; // Assume connected; let the request fail.
    }
  }
}

/// Lazy bridge to `connectivity_plus`. Wrapped in try/catch so the updater
/// still works in unit tests where the package is absent.
class _ConnectivityBridge {
  Future<bool> get hasWifi async {
    // ignore: avoid_relative_lib_imports
    final result = await _connectivity_plus.Connectivity().checkConnectivity();
    return result == _connectivity_plus.ConnectivityResult.wifi ||
        result == _connectivity_plus.ConnectivityResult.ethernet;
  }
}

// ignore: avoid_relative_lib_imports
import 'package:connectivity_plus/connectivity_plus.dart' as _connectivity_plus;
