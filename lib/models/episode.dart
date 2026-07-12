// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// NEW collection — Dedicated anime episode model (inspired by Aniyomi)
// Separates time-based anime progress from page-based manga progress

import 'package:isar/isar.dart';
import 'manga.dart';

part 'episode.g.dart';

@collection
@Name('Episode')
class Episode {
  @Id()
  int? id;

  @Index()
  final manga = IsarLink<Manga>(); // links to the anime

  @Index()
  String name;
  String url;

  double episodeNumber; // float (e.g., 12.5 for OVA)
  DateTime? dateUpload;
  String? scanlator;
  String? summary; // episode description
  String? previewUrl; // thumbnail URL

  // Watch progress (time-based, not page-based)
  bool seen; // watched (>= 85% of totalSeconds)
  bool bookmark;
  int lastSecondSeen; // resume position in seconds
  int totalSeconds; // episode duration
  bool fillermark; // filler episode flag

  // Download state
  bool isDownloaded;
  bool isDownloading;
  double downloadProgress;

  // Multi-season support (from Aniyomi)
  int? parentId; // parent anime ID for seasons
  int? seasonNumber;

  // Sync
  int version;
  bool isSyncing;
  DateTime? lastModifiedAt;

  // Link to chapters (for backward compat with Mangayomi's Chapter model)
  @Backlink(to: 'manga')
  final chapters = IsarLinks<Chapter>();

  Episode({
    this.id,
    required this.name,
    required this.url,
    this.episodeNumber = 0,
    this.dateUpload,
    this.scanlator,
    this.summary,
    this.previewUrl,
    this.seen = false,
    this.bookmark = false,
    this.lastSecondSeen = 0,
    this.totalSeconds = 0,
    this.fillermark = false,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.parentId,
    this.seasonNumber,
    this.version = 0,
    this.isSyncing = false,
    this.lastModifiedAt,
  });

  /// Check if episode is considered "watched" (>= 85% threshold from Aniyomi)
  bool get isWatched {
    if (totalSeconds == 0) return seen;
    return lastSecondSeen >= (totalSeconds * 0.85);
  }
}
