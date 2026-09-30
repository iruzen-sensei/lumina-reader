// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:isar/isar.dart';
import 'chapter.dart';

part 'manga.g.dart';

@collection
@Name('Manga')
class Manga {
    Id? id;

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

  @Enumerated(EnumType.name)
  ItemType itemType;

  @Enumerated(EnumType.name)
  Status status;

  String? artist;

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

  /// Explicit user-set status (0=Reading/Watching, 1=Finished, 2=Plan).
  /// NULL = derive from isFinished/readCount (legacy rows). This column
  /// exists because the derived value could never represent "Watching"
  /// for an entry with 0 read episodes — setting Watching snapped back to
  /// "Plan to watch" on the next build.
  int? userStatusOverride;

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
    this.artist,
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
    this.userStatusOverride,
    this.category,
  });
}

/// Unified content type. Persisted by name (`@Enumerated(EnumType.name)`), so
/// the declaration order is free to change without touching stored data.
/// `anime` was missing in the original skeleton — added per the architecture
/// document (unified Manga model covering manga / anime / novel / book).
enum ItemType {
  manga,
  anime,
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
