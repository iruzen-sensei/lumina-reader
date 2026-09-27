// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// STATS REPOSITORY — reading sessions, goals, streaks and heatmap queries.
// All numbers are derived from ReadingSession rows; nothing is faked.

import 'dart:async';

import 'package:isar/isar.dart';

import '../models/chapter.dart' as db;
import '../models/manga.dart' as db;
import '../models/models.dart' as dto;
import '../models/reading_session.dart' as db;
import '../providers/storage_provider.dart';

class StatsRepository {
  StatsRepository(StorageProvider storage) : _isar = storage.isar;
  final Isar _isar;

  // -----------------------------------------------------------------------
  // Summary cards
  // -----------------------------------------------------------------------

  Future<Map<String, int>> summary() async {
    final yearStart = DateTime(DateTime.now().year, 1, 1);
    final sessions = await _isar.readingSessions
        .filter()
        .dateGreaterThan(yearStart)
        .findAll();
    final finishedManga = await _isar.mangas
        .filter()
        .isFinishedEqualTo(true)
        .count();
    final chaptersRead =
        await _isar.chapters.filter().isReadEqualTo(true).count();

    // Episodes watched — previously hardcoded 0 ("wired when the anime
    // player records sessions" — it records duration-only sessions, so the
    // count must come from read episodes on anime library rows instead).
    var episodesWatched = 0;
    final animeRows = await _isar.mangas
        .filter()
        .itemTypeEqualTo(db.ItemType.anime)
        .findAll();
    for (final m in animeRows) {
      await m.chapters.load();
      episodesWatched += m.chapters.where((c) => c.isRead).length;
    }

    final minutes = sessions.fold<int>(0, (a, s) => a + s.durationSeconds) ~/
        60;
    final pages = sessions.fold<int>(0, (a, s) => a + s.pagesRead);

    return {
      'mangaRead': finishedManga,
      'minutesRead': minutes,
      'pagesRead': pages,
      'chaptersRead': chaptersRead,
      'episodesWatched': episodesWatched,
    };
  }

  // -----------------------------------------------------------------------
  // Heatmap
  // -----------------------------------------------------------------------

  /// One [dto.StatDay] per day for the last [weeks] weeks (oldest first),
  /// `count` = pages read that day.
  Future<List<dto.StatDay>> heatmap({int weeks = 20}) async {
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 1));
    final start = end.subtract(Duration(days: weeks * 7));
    final sessions = await _isar.readingSessions
        .filter()
        .dateGreaterThan(start, include: false)
        .and()
        .dateLessThan(end)
        .findAll();

    final pagesByDay = <DateTime, int>{};
    for (final s in sessions) {
      final day = DateTime(s.date.year, s.date.month, s.date.day);
      // Pages-only counting made ANIME and short text sessions invisible on
      // the heatmap (0 pages = no cell painted) — to a user checking the
      // heatmap after watching anime, stats looked frozen. A session with
      // time but no pages paints intensity 1 (reading happened, just not
      // image pages).
      final contribution = s.pagesRead > 0 ? s.pagesRead : 1;
      pagesByDay[day] = (pagesByDay[day] ?? 0) + contribution;
    }

    final days = <dto.StatDay>[];
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      days.add(dto.StatDay(date: d, count: pagesByDay[d] ?? 0));
    }
    return days;
  }

  // -----------------------------------------------------------------------
  // Goals
  // -----------------------------------------------------------------------

  /// Ensures the four default goals exist (matching the four streak types
  /// in the feature guide) and returns them with live progress.
  Future<List<dto.Goal>> goals() async {
    final existing = await _isar.readingGoals.where().findAll();
    if (existing.isEmpty) {
      final now = DateTime.now();
      await _isar.writeTxn(() async {
        await _isar.readingGoals.putAll([
          db.ReadingGoal(
              type: db.GoalType.dailyReading,
              target: 30,
              date: now), // minutes
          db.ReadingGoal(
              type: db.GoalType.dailyPages,
              target: 20,
              date: now), // pages
          db.ReadingGoal(
              type: db.GoalType.weeklyBooks, target: 1, date: now),
          db.ReadingGoal(
              type: db.GoalType.monthlyGoal, target: 4, date: now),
        ]);
      });
    }
    final goals = await _isar.readingGoals.where().findAll();
    final results = <dto.Goal>[];
    for (final g in goals) {
      final (label, unit, period, current) = await _goalProgress(g);
      results.add(dto.Goal(
        id: g.id ?? 0,
        label: label,
        target: g.target,
        current: current,
        unit: unit,
        period: period,
      ));
    }
    results.sort((a, b) => a.period.index.compareTo(b.period.index));
    return results;
  }

  /// Updates a goal's target (wired to the Stats screen's "Set goal"
  /// dialog — previously the button was a snackbar-only stub and the
  /// seeded defaults were permanently read-only).
  Future<void> setGoalTarget(int goalId, int target) async {
    if (target <= 0) return;
    await _isar.writeTxn(() async {
      final g = await _isar.readingGoals.get(goalId);
      if (g == null) return;
      g.target = target;
      await _isar.readingGoals.put(g);
    });
  }

  Future<(String, String, dto.GoalPeriod, int)> _goalProgress(
      db.ReadingGoal g) async {
    final now = DateTime.now();
    switch (g.type) {
      case db.GoalType.dailyReading:
        final start = DateTime(now.year, now.month, now.day);
        final sessions = await _isar.readingSessions
            .filter()
            .dateGreaterThan(start, include: true)
            .findAll();
        final minutes =
            sessions.fold<int>(0, (a, s) => a + s.durationSeconds) ~/ 60;
        return ('Read daily', 'min', dto.GoalPeriod.daily, minutes);
      case db.GoalType.dailyPages:
        final start = DateTime(now.year, now.month, now.day);
        final sessions = await _isar.readingSessions
            .filter()
            .dateGreaterThan(start, include: true)
            .findAll();
        final pages = sessions.fold<int>(0, (a, s) => a + s.pagesRead);
        return ('Pages per day', 'pages', dto.GoalPeriod.daily, pages);
      case db.GoalType.weeklyBooks:
        final finished = await _finishedCountSince(
            now.subtract(Duration(days: now.weekday - 1)));
        return ('Books per week', 'books', dto.GoalPeriod.weekly, finished);
      case db.GoalType.monthlyGoal:
        final finished =
            await _finishedCountSince(DateTime(now.year, now.month, 1));
        return ('Books this month', 'books', dto.GoalPeriod.monthly, finished);
    }
  }

  Future<int> _finishedCountSince(DateTime since) async {
    return _isar.mangas
        .filter()
        .isFinishedEqualTo(true)
        .and()
        .lastReadAtGreaterThan(since)
        .count();
  }

  // -----------------------------------------------------------------------
  // Streaks
  // -----------------------------------------------------------------------

  /// Current reading streak: consecutive days (ending today or yesterday)
  /// with at least one session. Freeze tokens are reported as 0 until the
  /// freeze mechanic is wired to a persisted counter.
  /// Per-media-type breakdown for the unified stats hub. One entry per
  /// item type with minutes / sessions / pages / chapters-or-episodes /
  /// finished items, computed by joining sessions to their parent rows.
  Future<List<dto.MediaTypeStats>> byType() async {
    final sessions = await _isar.readingSessions.where().findAll();
    final byManga = <int, List<db.ReadingSession>>{};
    // IsarLink.load() REQUIRES an active transaction in Isar 3 — without
    // one the await never settles (the golden stuck-skeleton bug).
    await _isar.txn(() async {
      for (final s in sessions) {
        await s.manga.load();
        final owner = s.manga.value?.id;
        if (owner == null) continue;
        byManga.putIfAbsent(owner, () => []).add(s);
      }
    });
    final ids = byManga.keys.toList();
    final mangas = await _isar.mangas.getAll(ids);
    final typeOf = <int, db.ItemType>{};
    for (var i = 0; i < ids.length; i++) {
      typeOf[ids[i]] = mangas[i]?.itemType ?? db.ItemType.manga;
    }

    dto.MediaTypeStats statsFor(db.ItemType t) {
      final sids = [
        for (final e in byManga.entries)
          if (typeOf[e.key] == t) ...e.value
      ];
      final minutes =
          sids.fold<int>(0, (a, s) => a + s.durationSeconds) ~/ 60;
      return dto.MediaTypeStats(
        type: _itemTypeToDto(t),
        minutes: minutes,
        sessions: sids.length,
        pagesRead: sids.fold<int>(0, (a, s) => a + s.pagesRead),
        itemsFinished: 0,
        chaptersOrEpisodes: 0,
      );
    }

    final out = <dto.MediaTypeStats>[
      statsFor(db.ItemType.anime),
      statsFor(db.ItemType.manga),
      statsFor(db.ItemType.novel),
      statsFor(db.ItemType.book),
    ];

    // Finished items + chapters/episodes per type (from the library rows).
    final allMangas = await _isar.mangas.where().findAll();
    for (final m in allMangas) {
      final dtoType = _itemTypeToDto(m.itemType);
      for (var i = 0; i < out.length; i++) {
        if (out[i].type != dtoType) continue;
        if (m.isFinished) {
          out[i] = out[i].copyWith(itemsFinished: out[i].itemsFinished + 1);
        }
      }
    }
    final chapters = await _isar.chapters.filter().isReadEqualTo(true).findAll();
    await _isar.txn(() async {
      for (final c in chapters) {
        await c.manga.load();
        final owner = c.manga.value?.id;
        final t = owner == null ? null : typeOf[owner];
        if (t == null) continue;
        final dtoT = _itemTypeToDto(t);
        for (var i = 0; i < out.length; i++) {
          if (out[i].type == dtoT) {
            out[i] = out[i].copyWith(
                chaptersOrEpisodes: out[i].chaptersOrEpisodes + 1);
          }
        }
      }
    });
    return out;
  }

  /// Top series by total minutes within one media type.
  Future<List<dto.SeriesStat>> topSeries(db.ItemType type,
      {int limit = 5}) async {
    final sessions = await _isar.readingSessions.where().findAll();
    final byManga = <int, int>{};
    await _isar.txn(() async {
      for (final s in sessions) {
        await s.manga.load();
        final owner = s.manga.value?.id;
        if (owner == null) continue;
        byManga[owner] = (byManga[owner] ?? 0) + s.durationSeconds;
      }
    });
    final ids = byManga.keys.toList();
    final mangas = await _isar.mangas.getAll(ids);
    final out = <dto.SeriesStat>[];
    for (var i = 0; i < ids.length; i++) {
      final m = mangas[i];
      if (m == null || m.itemType != type) continue;
      out.add(dto.SeriesStat(
        title: m.name,
        thumbnailUrl: m.coverUrl,
        minutes: (byManga[ids[i]] ?? 0) ~/ 60,
      ));
    }
    out.sort((a, b) => b.minutes.compareTo(a.minutes));
    return out.take(limit).toList();
  }

  Future<StreakInfo> streak() async {
    final sessions = await _isar.readingSessions.where().findAll();
    if (sessions.isEmpty) {
      return const StreakInfo(current: 0, longest: 0, lastActiveDay: null);
    }
    final days = sessions
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet();

    DateTime? lastActive;
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    if (days.contains(today0)) {
      lastActive = today0;
    } else if (days.contains(today0.subtract(const Duration(days: 1)))) {
      lastActive = today0.subtract(const Duration(days: 1));
    }

    var current = 0;
    if (lastActive != null) {
      var d = lastActive;
      while (days.contains(d)) {
        current++;
        d = d.subtract(const Duration(days: 1));
      }
    }

    var longest = 0;
    var run = 0;
    DateTime? prevDay;
    final sorted = days.toList()..sort();
    for (final d in sorted) {
      if (prevDay != null && d.difference(prevDay).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
      prevDay = d;
    }

    return StreakInfo(
        current: current, longest: longest, lastActiveDay: lastActive);
  }

  // -----------------------------------------------------------------------
  // Session recording
  // -----------------------------------------------------------------------

  /// Records a completed reading/watching session (called by the tracker
  /// when a reader/player closes or a chapter completes).
  Future<void> recordSession({
    required int mangaId,
    int? chapterId,
    required int pagesRead,
    required int durationSeconds,
  }) async {
    final manga = await _isar.mangas.get(mangaId);
    if (manga == null) return;
    final now = DateTime.now();
    final session = db.ReadingSession(
      startTime: now.subtract(Duration(seconds: durationSeconds)),
      endTime: now,
      durationSeconds: durationSeconds,
      pagesRead: pagesRead,
      date: now,
      chapterId: chapterId,
    );
    session.manga.value = manga;
    await _isar.writeTxn(() async {
      await _isar.readingSessions.put(session);
    });
  }

  /// Marks a manga finished when all chapters are read (called from the
  /// library repository's progress path via providers).
  Future<void> maybeMarkFinished(int mangaId) async {
    final m = await _isar.mangas.get(mangaId);
    if (m == null) return;
    await m.chapters.load();
    final chapters = m.chapters.toList();
    if (chapters.isNotEmpty && chapters.every((c) => c.isRead)) {
      m.isFinished = true;
      await _isar.writeTxn(() async {
        await _isar.mangas.put(m);
      });
    }
  }

  /// Fires whenever any input to the summary changes. Reading sessions
  /// alone are NOT enough: `chaptersRead` / `episodesWatched` are derived
  /// from chapter `isRead` flags and `mangaRead` from manga rows — a
  /// chapter marked read (without a session) or an anime finished left the
  /// More-screen card and the stats page stale until the next session.
  Stream<void> watch() {
    return _mergeStreams([
      _isar.readingSessions.watchLazy(fireImmediately: true),
      _isar.chapters.watchLazy(fireImmediately: false),
      _isar.mangas.watchLazy(fireImmediately: false),
    ]);
  }

  static Stream<void> _mergeStreams(List<Stream<void>> streams) {
    // The controller is handed to the consumer; cancelling the returned
    // stream subscription drives onCancel below.
    // ignore: close_sinks
    final controller = StreamController<void>();
    final subs = <StreamSubscription<void>>[];
    controller.onListen = () {
      for (final s in streams) {
        subs.add(s.listen((_) {
          if (!controller.isClosed) controller.add(null);
        }));
      }
    };
    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }
}

/// Plain streak result (mapped to the UI's StreakState by providers).
dto.ItemType _itemTypeToDto(db.ItemType type) =>
    dto.ItemType.values[type.index];

class StreakInfo {
  const StreakInfo({
    required this.current,
    required this.longest,
    this.lastActiveDay,
  });

  final int current;
  final int longest;
  final DateTime? lastActiveDay;
}
