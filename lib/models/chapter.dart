// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:isar/isar.dart';
import 'manga.dart';

part 'chapter.g.dart';

@collection
@Name('Chapter')
class Chapter {
  @Id()
  int? id;

  @Index()
  final manga = IsarLink<Manga>();

  @Index()
  String name;
  String url;

  int chapterNumber;
  DateTime? dateUpload;
  String? scanlator;

  bool isRead;
  bool isDownloaded;
  bool isDownloading;
  double downloadProgress;

  int pageCount;
  int lastPageRead;

  Chapter({
    this.id,
    required this.name,
    required this.url,
    this.chapterNumber = 0,
    this.dateUpload,
    this.scanlator,
    this.isRead = false,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.pageCount = 0,
    this.lastPageRead = 0,
  });
}
