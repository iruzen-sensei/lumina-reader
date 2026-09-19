// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/category.dart';
import '../models/chapter.dart';
import '../models/download.dart';
import '../models/episode.dart';
import '../models/history.dart';
import '../models/manga.dart';
import '../models/note.dart';
import '../models/reading_session.dart';
import '../models/settings.dart';
import '../models/source.dart';
import '../models/track.dart';
import '../models/update.dart';
import '../models/video.dart';

/// Central database bootstrap.
///
/// Registers ALL 14 Isar schemas (the original skeleton registered only 7,
/// which crashed every service that touched History / Category / Track /
/// Settings / Source / Update / Download).
///
/// Error-proofing: if the primary database cannot be opened (corrupted file,
/// full disk, ROM quirks), we transparently fall back to a temporary
/// directory instead of crashing to a black screen — the HyperOS lesson.
class StorageProvider {
  static final StorageProvider _instance = StorageProvider._internal();
  factory StorageProvider() => _instance;
  StorageProvider._internal();

  Isar? _isar;
  bool _usingFallback = false;

  /// All schemas in one place. Adding a new @collection? Register it here
  /// or the audit gate (scripts/audit.py, check A5) will fail the build.
  static final List<CollectionSchema<dynamic>> _schemas = [
    MangaSchema,
    ChapterSchema,
    EpisodeSchema,
    VideoSchema,
    NoteSchema,
    ReadingSessionSchema,
    ReadingGoalSchema,
    SettingsSchema,
    SourceSchema,
    CategorySchema,
    HistorySchema,
    DownloadSchema,
    UpdateSchema,
    TrackSchema,
  ];

  Isar get isar {
    final db = _isar;
    if (db == null) {
      throw StateError(
          'Database not initialized — call StorageProvider().initDB() first.');
    }
    return db;
  }

  /// True when the app is running on the fallback (non-persistent) database.
  bool get isFallback => _usingFallback;

  /// True when a database handle has been opened successfully (main or
  /// fallback). Callers use this to skip persistence work when storage is
  /// unavailable instead of catching [StateError]s.
  bool get isAvailable => _isar != null && _isar!.isOpen;

  /// Test-only injection point: run the whole provider graph against an
  /// externally created Isar instance (golden screenshots, widget tests).
  /// Production code must go through [initDB].
  @visibleForTesting
  void initForTesting(Isar isar) {
    _isar = isar;
    _usingFallback = false;
  }

  /// Test-only reset (isolates golden/widget tests from each other).
  @visibleForTesting
  void resetForTesting() {
    _isar = null;
    _usingFallback = false;
  }

  Future<Isar> initDB() async {
    if (_isar != null && _isar!.isOpen) return _isar!;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _isar = await Isar.open(
        _schemas,
        directory: dir.path,
        name: 'luminaReaderDb',
        inspector: false,
      );
      _usingFallback = false;
    } catch (e) {
      debugPrint('StorageProvider: primary DB open failed ($e); '
          'falling back to temporary directory.');
      try {
        final tmp = await getTemporaryDirectory();
        _isar = await Isar.open(
          _schemas,
          directory: tmp.path,
          name: 'luminaReaderDbFallback',
          inspector: false,
        );
        _usingFallback = true;
      } catch (e2) {
        // Total failure: rethrow — main.dart's error boundary renders an
        // error screen instead of a black screen.
        throw StateError('Database unavailable: $e / $e2');
      }
    }
    return _isar!;
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
