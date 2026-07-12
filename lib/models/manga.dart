// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:isar/isar.dart';
import 'chapter.dart';

part 'manga.g.dart';

@collection
@Name('Manga')
class Manga {
  @Id()
  int? id;

  @Index(unique: false)
  String name;

  String author;
  String description;
  String coverUrl;

  // For local file imports (EPUB, PDF, CBZ, CBR)
  String? filePath;
  String? fileType; // epub, pdf, cbz, cbr, html, extension

  // For extension-sourced content
  String? sourceUrl;
  int? sourceId;
  String? sourceName;

  @enumeration
  ItemType itemType;

  @enumeration
  Status status;

  List<String> tags;
  double rating;
  int chapterCount;

  bool isFavorite;
  DateTime? lastReadAt;
  DateTime addedAt;

  // Progress tracking
  int totalPages;
  int currentPage;
  double progress;
  bool isFinished;
  int readCount;

  // Library category/shelf
  String? category;

  // Link to chapters
  @Backlink(to: 'manga')
  final chapters = IsarLinks<Chapter>();

  Manga({
    this.id,
    required this.name,
    this.author = '',
    this.description = '',
    this.coverUrl = '',
    this.filePath,
    this.fileType,
    this.sourceUrl,
    this.sourceId,
    this.sourceName,
    this.itemType = ItemType.manga,
    this.status = Status.unknown,
    this.tags = const [],
    this.rating = 0.0,
    this.chapterCount = 0,
    this.isFavorite = false,
    this.lastReadAt,
    required this.addedAt,
    this.totalPages = 0,
    this.currentPage = 0,
    this.progress = 0.0,
    this.isFinished = false,
    this.readCount = 0,
    this.category,
  });
}

enum ItemType {
  manga,
  novel,
  book,
}

enum Status {
  ongoing,
  completed,
  canceled,
  unknown,
  onHiatus,
  publishingFinished,
}
