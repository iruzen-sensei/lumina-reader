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
// Reading session tracker. Records the duration, pages read and seconds
// watched for every reading / viewing session, updates the user's daily
// streak, advances reading goals and manages "freeze tokens" that protect
// the streak when the user misses a day (Duolingo-style).

import 'dart:async';

import 'package:hive/hive.dart';
import 'package:isar/isar.dart';

import 'package:lumina_reader/models/manga.dart';
import 'package:lumina_reader/models/reading_session.dart';

/// Thrown by the reading tracker.
class ReadingTrackerException implements Exception {
  ReadingTrackerException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ReadingTrackerException: $message';
}

/// Type of session being tracked. Determines whether the unit is pages or
/// seconds.
enum SessionType {
  reading,
  watching,
  listening,
}

/// Snapshot of the user's current streak state.
class StreakSnapshot {
  StreakSnapshot({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastReadDate,
    required this.freezeTokens,
    required this.totalSessions,
    required this.totalDurationSeconds,
    required this.totalPagesRead,
  });

  /// Number of consecutive days the user has read / watched.
  final int currentStreak;

  /// Longest streak ever achieved.
  final int longestStreak;

  /// Last date (UTC) the user read / watched.
  final DateTime? lastReadDate;

  /// Number of freeze tokens available.
  final int freezeTokens;

  /// Total number of sessions ever recorded.
  final int totalSessions;

  /// Total time spent reading / watching, in seconds.
  final int totalDurationSeconds;

  /// Total pages read across all sessions.
  final int totalPagesRead;

  /// Returns `true` when the streak is at risk of being broken today
  /// (i.e. the user hasn't read yet today and the last read date is
  /// yesterday).
  bool get atRiskToday {
    final today = _todayUtc();
    if (lastReadDate == null) return false;
    final last = DateTime.utc(
      lastReadDate!.year,
      lastReadDate!.month,
      lastReadDate!.day,
    );
    return last.isBefore(today);
  }

  @override
  String toString() =>
      'StreakSnapshot(current=$currentStreak, longest=$longestStreak, '
      'freezeTokens=$freezeTokens, total=$totalSessions)';
}

/// Result returned by [ReadingTracker.endSession].
class SessionResult {
  SessionResult({
    required this.session,
    required this.streakBefore,
    required this.streakAfter,
    required this.goalsUpdated,
    required this.freezeTokensEarned,
  });

  final ReadingSession session;
  final StreakSnapshot streakBefore;
  final StreakSnapshot streakAfter;
  final List<ReadingGoal> goalsUpdated;
  final int freezeTokensEarned;
}

/// Pluggable persistence layer. The default implementation wires to Isar;
/// tests can swap it out for an in-memory variant.
abstract class ReadingTrackerStore {
  Future<List<ReadingSession>> fetchSessions({DateTime? from, DateTime? to});
  Future<void> saveSession(ReadingSession session);
  Future<void> deleteSession(int id);

  Future<List<ReadingGoal>> fetchActiveGoals();
  Future<void> saveGoal(ReadingGoal goal);

  /// Returns the persisted streak state.
  Future<StreakSnapshot> fetchStreak();

  /// Persists the streak state.
  Future<void> saveStreak(StreakSnapshot snapshot);

  /// Returns the number of freeze tokens purchased / earned but not yet
  /// used. The store is responsible for persisting this count.
  Future<int> fetchFreezeTokens();
  Future<void> setFreezeTokens(int count);
}

/// Hive-backed default implementation of [ReadingTrackerStore].
///
/// Streak / freeze state lives in Hive because it is a single record and
/// changes frequently (every session). Session and goal records live in
/// Isar so they can be queried by date / manga.
class IsarReadingTrackerStore implements ReadingTrackerStore {
  IsarReadingTrackerStore(this._isar);

  final Isar _isar;

  Box? _box;
  Future<Box> _openBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox('reading_tracker_state');
    return _box!;
  }

  static const String _kStreakKey = 'streak_snapshot';
  static const String _kFreezeTokensKey = 'freeze_tokens';

  @override
  Future<List<ReadingSession>> fetchSessions({DateTime? from, DateTime? to}) async {
    final query = _isar.readingSessions.where();
    if (from != null && to != null) {
      return query
          .dateBetween(from, to)
          .sortByDateDesc()
          .findAll();
    }
    return query.sortByDateDesc().findAll();
  }

  @override
  Future<void> saveSession(ReadingSession session) async {
    await _isar.writeTxn(() async {
      await _isar.readingSessions.put(session);
    });
  }

  @override
  Future<void> deleteSession(int id) async {
    await _isar.writeTxn(() async {
      await _isar.readingSessions.delete(id);
    });
  }

  @override
  Future<List<ReadingGoal>> fetchActiveGoals() async {
    return _isar.readingGoals
        .filter()
        .isCompletedEqualTo(false)
        .findAll();
  }

  @override
  Future<void> saveGoal(ReadingGoal goal) async {
    await _isar.writeTxn(() async {
      await _isar.readingGoals.put(goal);
    });
  }

  @override
  Future<StreakSnapshot> fetchStreak() async {
    final box = await _openBox();
    final raw = box.get(_kStreakKey) as Map?;
    if (raw == null) {
      return StreakSnapshot(
        currentStreak: 0,
        longestStreak: 0,
        lastReadDate: null,
        freezeTokens: 1, // every user starts with 1 freeze token
        totalSessions: 0,
        totalDurationSeconds: 0,
        totalPagesRead: 0,
      );
    }
    return StreakSnapshot(
      currentStreak: (raw['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (raw['longestStreak'] as num?)?.toInt() ?? 0,
      lastReadDate: raw['lastReadDate'] == null
          ? null
          : DateTime.parse(raw['lastReadDate'] as String),
      freezeTokens: (raw['freezeTokens'] as num?)?.toInt() ?? 0,
      totalSessions: (raw['totalSessions'] as num?)?.toInt() ?? 0,
      totalDurationSeconds:
          (raw['totalDurationSeconds'] as num?)?.toInt() ?? 0,
      totalPagesRead: (raw['totalPagesRead'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> saveStreak(StreakSnapshot snapshot) async {
    final box = await _openBox();
    await box.put(_kStreakKey, <String, dynamic>{
      'currentStreak': snapshot.currentStreak,
      'longestStreak': snapshot.longestStreak,
      'lastReadDate': snapshot.lastReadDate?.toIso8601String(),
      'freezeTokens': snapshot.freezeTokens,
      'totalSessions': snapshot.totalSessions,
      'totalDurationSeconds': snapshot.totalDurationSeconds,
      'totalPagesRead': snapshot.totalPagesRead,
    });
  }

  @override
  Future<int> fetchFreezeTokens() async {
    final box = await _openBox();
    return (box.get(_kFreezeTokensKey) as num?)?.toInt() ?? 1;
  }

  @override
  Future<void> setFreezeTokens(int count) async {
    final box = await _openBox();
    await box.put(_kFreezeTokensKey, count);
  }
}

/// The reading session tracker.
class ReadingTracker {
  ReadingTracker(this._store);

  final ReadingTrackerStore _store;

  /// Currently active session, or `null` when no session is running.
  ReadingSession? _activeSession;
  ReadingSession? get activeSession => _activeSession;

  /// Elapsed timer for the active session.
  Timer? _ticker;
  DateTime? _tickStart;
  int _accumulatedSeconds = 0;

  /// Periodic stream that emits the running elapsed time (in seconds)
  /// while a session is active.
  final _elapsedController = StreamController<int>.broadcast();
  Stream<int> get elapsedStream => _elapsedController.stream;

  /// Number of freeze tokens granted per N minutes of reading. Default is
  /// 1 token per 30 minutes of reading (capped at 5 tokens).
  static const int _kFreezeGrantIntervalMinutes = 30;
  static const int _kFreezeTokenCap = 5;

  // -- Lifecycle ------------------------------------------------------------

  /// Starts a new session for [manga] of [type]. Throws if a session is
  /// already running.
  ReadingSession startSession({
    required Manga manga,
    required SessionType type,
    int? chapterId,
  }) {
    if (_activeSession != null) {
      throw ReadingTrackerException(
        'A session is already running — stop it before starting a new one',
      );
    }
    final now = DateTime.now();
    final session = ReadingSession(
      startTime: now,
      date: now,
      durationSeconds: 0,
      pagesRead: 0,
      chapterId: chapterId,
    );
    _activeSession = session;
    _accumulatedSeconds = 0;
    _tickStart = now;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = _accumulatedSeconds +
          DateTime.now().difference(_tickStart!).inSeconds;
      _elapsedController.add(elapsed);
    });
    return session;
  }

  /// Pauses the active session. The session stays open; call [resume] to
  /// continue.
  void pause() {
    if (_activeSession == null || _tickStart == null) return;
    _accumulatedSeconds +=
        DateTime.now().difference(_tickStart!).inSeconds;
    _tickStart = null;
    _ticker?.cancel();
    _ticker = null;
  }

  /// Resumes a paused session.
  void resume() {
    if (_activeSession == null || _tickStart != null) return;
    _tickStart = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = _accumulatedSeconds +
          DateTime.now().difference(_tickStart!).inSeconds;
      _elapsedController.add(elapsed);
    });
  }

  /// Records [pagesRead] (or seconds watched) on the active session.
  void recordProgress({int? pagesRead, int? secondsWatched}) {
    final s = _activeSession;
    if (s == null) {
      throw ReadingTrackerException('No active session to record progress on');
    }
    if (pagesRead != null) {
      s.pagesRead += pagesRead;
    }
    if (secondsWatched != null) {
      // For watching sessions we treat secondsWatched as the canonical
      // measure of progress; the session duration is updated on stop().
      _accumulatedSeconds += secondsWatched;
    }
  }

  /// Ends the active session, persists it, and updates streaks / goals.
  Future<SessionResult> endSession() async {
    final session = _activeSession;
    if (session == null) {
      throw ReadingTrackerException('No active session to end');
    }
    _ticker?.cancel();
    _ticker = null;
    final now = DateTime.now();
    if (_tickStart != null) {
      _accumulatedSeconds += now.difference(_tickStart!).inSeconds;
      _tickStart = null;
    }
    session.endTime = now;
    session.durationSeconds = _accumulatedSeconds;
    _activeSession = null;

    final streakBefore = await _store.fetchStreak();
    await _store.saveSession(session);
    final streakAfter = await _updateStreak(session, streakBefore);
    final goals = await _updateGoals(session);

    return SessionResult(
      session: session,
      streakBefore: streakBefore,
      streakAfter: streakAfter,
      goalsUpdated: goals,
      freezeTokensEarned: streakAfter.freezeTokens - streakBefore.freezeTokens,
    );
  }

  /// Abandons the active session without recording it. Useful when the
  /// user closes the reader by mistake.
  Future<void> discardSession() async {
    _ticker?.cancel();
    _ticker = null;
    _tickStart = null;
    _accumulatedSeconds = 0;
    _activeSession = null;
  }

  // -- Streaks --------------------------------------------------------------

  /// Returns the current streak snapshot.
  Future<StreakSnapshot> currentStreak() => _store.fetchStreak();

  /// Updates the streak after a session was recorded. Implements the
  /// following rules:
  ///   * If the session was today and the last read was today: no change.
  ///   * If the session was today and the last read was yesterday: streak
  ///     +1.
  ///   * If the session was today and the last read was >1 day ago: try to
  ///     spend a freeze token to bridge a single missed day; otherwise
  ///     reset the streak to 1.
  ///   * The longest streak is updated when the new streak exceeds it.
  ///   * Freeze tokens are granted every 30 minutes of reading, capped at
  ///     5 tokens total.
  Future<StreakSnapshot> _updateStreak(
    ReadingSession session,
    StreakSnapshot before,
  ) async {
    final today = _todayUtc();
    final sessionDay = DateTime.utc(
      session.date.year,
      session.date.month,
      session.date.day,
    );
    if (sessionDay.isAfter(today)) {
      // Future-dated session — ignore for streak purposes.
      return before;
    }

    var newStreak = before.currentStreak;
    final lastRead = before.lastReadDate == null
        ? null
        : DateTime.utc(
            before.lastReadDate!.year,
            before.lastReadDate!.month,
            before.lastReadDate!.day,
          );

    if (lastRead == null) {
      newStreak = 1;
    } else if (lastRead == sessionDay) {
      // Same day — no change.
    } else if (lastRead.isBefore(sessionDay)) {
      final gap = sessionDay.difference(lastRead).inDays;
      if (gap == 1) {
        newStreak += 1;
      } else if (gap == 2 && before.freezeTokens > 0) {
        // Spend a freeze token to bridge the single missed day.
        newStreak += 1;
        await _spendFreezeToken(before.freezeTokens);
      } else {
        newStreak = 1;
      }
    }

    // Grant freeze tokens every 30 minutes of reading.
    final newTotalDuration =
        before.totalDurationSeconds + session.durationSeconds;
    final tokensBeforeSession =
        (before.totalDurationSeconds ~/ 60) ~/ _kFreezeGrantIntervalMinutes;
    final tokensAfterSession =
        (newTotalDuration ~/ 60) ~/ _kFreezeGrantIntervalMinutes;
    final tokensEarned = tokensAfterSession - tokensBeforeSession;
    final freezeTokens = (before.freezeTokens + tokensEarned)
        .clamp(0, _kFreezeTokenCap);

    final snapshot = StreakSnapshot(
      currentStreak: newStreak,
      longestStreak:
          newStreak > before.longestStreak ? newStreak : before.longestStreak,
      lastReadDate: sessionDay,
      freezeTokens: freezeTokens,
      totalSessions: before.totalSessions + 1,
      totalDurationSeconds: newTotalDuration,
      totalPagesRead: before.totalPagesRead + session.pagesRead,
    );
    await _store.saveStreak(snapshot);
    return snapshot;
  }

  Future<void> _spendFreezeToken(int currentCount) async {
    await _store.setFreezeTokens((currentCount - 1).clamp(0, _kFreezeTokenCap));
  }

  // -- Goals ----------------------------------------------------------------

  Future<List<ReadingGoal>> _updateGoals(ReadingSession session) async {
    final goals = await _store.fetchActiveGoals();
    final updated = <ReadingGoal>[];
    final sessionDate = DateTime.utc(
      session.date.year,
      session.date.month,
      session.date.day,
    );
    for (final goal in goals) {
      final goalDate = DateTime.utc(
        goal.date.year,
        goal.date.month,
        goal.date.day,
      );
      final matches = _goalMatchesDate(goal.type, goalDate, sessionDate);
      if (!matches) continue;

      switch (goal.type) {
        case GoalType.dailyReading:
          goal.current += session.durationSeconds ~/ 60;
          break;
        case GoalType.dailyPages:
          goal.current += session.pagesRead;
          break;
        case GoalType.weeklyBooks:
          // Counted at chapter / book completion — increment via
          // [recordGoalProgress] instead.
          break;
        case GoalType.monthlyGoal:
          goal.current += session.durationSeconds ~/ 60;
          break;
      }
      if (goal.current >= goal.target) {
        goal.isCompleted = true;
      }
      await _store.saveGoal(goal);
      updated.add(goal);
    }
    return updated;
  }

  /// Returns `true` when [goalType] should be advanced by a session that
  /// happened on [sessionDate] for a goal anchored on [goalDate].
  bool _goalMatchesDate(
      GoalType goalType, DateTime goalDate, DateTime sessionDate) {
    switch (goalType) {
      case GoalType.dailyReading:
      case GoalType.dailyPages:
        return goalDate == sessionDate;
      case GoalType.weeklyBooks:
        // Week starts on Monday. The goal is "active" for the 7-day window
        // that contains [goalDate].
        final weekStart = goalDate.subtract(Duration(days: goalDate.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 7));
        return !sessionDate.isBefore(weekStart) && sessionDate.isBefore(weekEnd);
      case GoalType.monthlyGoal:
        return goalDate.year == sessionDate.year &&
            goalDate.month == sessionDate.month;
    }
  }

  /// Manually advances a [GoalType.weeklyBooks] goal by [count] books.
  /// Called by the reader / player when a chapter / book is finished.
  Future<void> recordGoalProgress({
    required GoalType type,
    required int count,
    DateTime? when,
  }) async {
    final date = when ?? DateTime.now();
    final goals = await _store.fetchActiveGoals();
    final goalDate = DateTime.utc(date.year, date.month, date.day);
    for (final goal in goals) {
      if (goal.type != type) continue;
      final anchor = DateTime.utc(goal.date.year, goal.date.month, goal.date.day);
      if (!_goalMatchesDate(type, anchor, goalDate)) continue;
      goal.current += count;
      if (goal.current >= goal.target) goal.isCompleted = true;
      await _store.saveGoal(goal);
    }
  }

  // -- Freeze tokens --------------------------------------------------------

  /// Returns the number of freeze tokens currently available.
  Future<int> availableFreezeTokens() => _store.fetchFreezeTokens();

  /// Returns `true` when the user has at least one freeze token, i.e. the
  /// streak can survive a single missed day.
  Future<bool> canUseFreezeToken() async => (await _store.fetchFreezeTokens()) > 0;

  /// Manually purchases [count] freeze tokens (e.g. via an in-app reward).
  Future<void> grantFreezeTokens(int count) async {
    final current = await _store.fetchFreezeTokens();
    final updated = (current + count).clamp(0, _kFreezeTokenCap);
    await _store.setFreezeTokens(updated);
  }

  /// Returns the historical sessions for the given day range (inclusive),
  /// sorted by start time descending.
  Future<List<ReadingSession>> sessionsForRange({
    DateTime? from,
    DateTime? to,
  }) {
    return _store.fetchSessions(from: from, to: to);
  }

  /// Returns the total reading time (in seconds) for [day] (UTC).
  Future<int> totalDurationForDay(DateTime day) async {
    final start = DateTime.utc(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final sessions = await _store.fetchSessions(from: start, to: end);
    return sessions.fold<int>(
        0, (sum, s) => sum + s.durationSeconds);
  }

  /// Returns the total pages read for [day] (UTC).
  Future<int> totalPagesForDay(DateTime day) async {
    final start = DateTime.utc(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final sessions = await _store.fetchSessions(from: start, to: end);
    return sessions.fold<int>(0, (sum, s) => sum + s.pagesRead);
  }

  void dispose() {
    _ticker?.cancel();
    _elapsedController.close();
  }

  static DateTime _todayUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }
}
