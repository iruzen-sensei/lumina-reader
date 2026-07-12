// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/manga.dart';
import '../models/chapter.dart';
import '../models/episode.dart';
import '../models/note.dart';
import '../models/reading_session.dart';
import '../models/video.dart';

class StorageProvider {
  static final StorageProvider _instance = StorageProvider._internal();
  factory StorageProvider() => _instance;
  StorageProvider._internal();

  late Isar isar;

  Future<Isar> initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open(
      [
        MangaSchema,
        ChapterSchema,
        EpisodeSchema,
        NoteSchema,
        ReadingSessionSchema,
        ReadingGoalSchema,
        VideoSchema,
      ],
      directory: dir.path,
      name: "luminaReaderDb",
      inspector: false,
    );
    return isar;
  }

  Future<String> getDownloadsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadsDir = '${dir.path}/downloads';
    await Directory(downloadsDir).create(recursive: true);
    return downloadsDir;
  }

  Future<String> getCacheDir() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }
}
