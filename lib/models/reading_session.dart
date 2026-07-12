// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NEW collection — not in Mangayomi

import 'package:isar/isar.dart';
import 'manga.dart';

part 'reading_session.g.dart';

@collection
@Name('ReadingSession')
class ReadingSession {
  @Id()
  int? id;

  @Index()
  final manga = IsarLink<Manga>();

  int? chapterId;
  DateTime startTime;
  DateTime? endTime;
  int durationSeconds;
  int pagesRead;

  @Index()
  DateTime date; // For daily aggregation (heatmap)

  ReadingSession({
    this.id,
    required this.startTime,
    this.endTime,
    this.durationSeconds = 0,
    this.pagesRead = 0,
    required this.date,
    this.chapterId,
  });
}

@collection
@Name('ReadingGoal')
class ReadingGoal {
  @Id()
  int? id;

  @enumeration
  GoalType type;
  int target;
  int current;
  DateTime date;
  bool isCompleted;
  bool freezeUsed;

  ReadingGoal({
    this.id,
    required this.type,
    required this.target,
    this.current = 0,
    required this.date,
    this.isCompleted = false,
    this.freezeUsed = false,
  });
}

enum GoalType {
  dailyReading,
  dailyPages,
  weeklyBooks,
  monthlyGoal,
}
