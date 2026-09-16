// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:convert';

import 'package:isar/isar.dart';

part 'video.g.dart';

@collection
@Name('Video')
class Video {
    Id? id;

  String url;
  String? videoTitle;
  int? resolution; // e.g., 720, 1080
  int? bitrate;
  bool preferred;

  // HTTP headers for the video request
  String? headersJson;

  // Subtitle / audio tracks (embedded MediaTrack DTOs)
  List<MediaTrack> subtitleTracks;
  List<MediaTrack> audioTracks;

  // MPV-specific args. Isar 3 has no Map property type, so the map is
  // stored JSON-encoded in [mpvArgsJson]; [mpvArgs] remains the public API.
  String? mpvArgsJson;

  /// MPV player arguments. Not persisted directly — see [mpvArgsJson].
  @ignore
  Map<String, String> get mpvArgs {
    final raw = mpvArgsJson;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v is String ? v : v.toString()));
      }
      return const {};
    } catch (_) {
      // Corrupt payload — treat as empty rather than crashing the player.
      return const {};
    }
  }

  set mpvArgs(Map<String, String> value) {
    mpvArgsJson = value.isEmpty ? null : jsonEncode(value);
  }

  Video({
    this.id,
    required this.url,
    this.videoTitle,
    this.resolution,
    this.bitrate,
    this.preferred = false,
    this.headersJson,
    this.subtitleTracks = const [],
    this.audioTracks = const [],
    Map<String, String> mpvArgs = const {},
  }) : mpvArgsJson = mpvArgs.isEmpty ? null : jsonEncode(mpvArgs);
}

/// A subtitle or audio track attached to a [Video].
///
/// Named [MediaTrack] (not `Track`) to avoid colliding with the tracker-sync
/// `Track` collection in `models/track.dart` — the two are unrelated concepts
/// that previously shared a name.
@embedded
class MediaTrack {
  String url;
  String lang;
  String? title;

  MediaTrack({this.url = '', this.lang = '', this.title});
}
