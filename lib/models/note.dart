// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NEW collection — not in Mangayomi

import 'package:isar/isar.dart';
import 'manga.dart';

part 'note.g.dart';

@collection
@Name('Note')
class Note {
  @Id()
  int? id;

  @Index()
  final manga = IsarLink<Manga>();

  int? chapterId;
  String? chapterName;
  int pageNumber;

  String text;
  @enumeration
  NoteType noteType;

  /// 0=Important(purple), 1=Insight(teal), 2=Quote(gold),
  /// 3=Disagree(red-orange), 4=Reference(blue),
  /// 5=Agree(green), 6=Question(indigo)
  int color;

  DateTime createdAt;
  DateTime updatedAt;

  Note({
    this.id,
    required this.pageNumber,
    required this.text,
    this.noteType = NoteType.highlight,
    this.color = 0,
    required this.createdAt,
    required this.updatedAt,
    this.chapterId,
    this.chapterName,
  });
}

enum NoteType {
  highlight,
  thought,
}

/// Semantic highlight colors
const List<int> noteColors = [
  0xFF9B6FDB, // Purple - Important
  0xFF4BC7B8, // Teal - Insight
  0xFFC7A84B, // Gold - Quote
  0xFFC7644B, // Red-orange - Disagree
  0xFF5B8AC7, // Blue - Reference
  0xFF6DC77D, // Green - Agree
  0xFF7B6FC7, // Indigo - Question
];

const List<String> noteColorNames = [
  'Important',
  'Insight',
  'Quote',
  'Disagree',
  'Reference',
  'Agree',
  'Question',
];
