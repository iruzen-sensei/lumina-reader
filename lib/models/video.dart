// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:isar/isar.dart';

part 'video.g.dart';

@collection
@Name('Video')
class Video {
  @Id()
  int? id;

  String url;
  String? videoTitle;
  int? resolution; // e.g., 720, 1080
  int? bitrate;
  bool preferred;

  // HTTP headers for the video request
  String? headersJson;

  // Subtitle tracks
  List<Track> subtitleTracks;
  List<Track> audioTracks;

  // MPV-specific args
  Map<String, String> mpvArgs;

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
    this.mpvArgs = const {},
  });
}

@embedded
class Track {
  String url;
  String lang;

  Track({this.url = '', this.lang = ''});
}
