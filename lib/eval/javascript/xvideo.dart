// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Wire DTOs shared by the JS extension host and the Mihon APK bridge.
// Upstream Mangayomi calls these `Video` / `Track`; our `Video` model is an
// Isar collection, so the ported extractor code speaks [XVideo]/[XTrack]
// and the coordinator-facing adapter converts them into [MVideo] with the
// `parameters['subtitles'] / ['audios']` convention.

import 'dart:convert';

/// One video stream as reported by an extension.
class XVideo {
  XVideo(
    this.url,
    this.quality,
    this.originalUrl, {
    Map<String, String>? headers,
    List<XTrack>? subtitles,
    List<XTrack>? audios,
  })  : headers = headers,
        subtitles = subtitles ?? [],
        audios = audios ?? [];

  String url;
  String quality;
  String originalUrl;
  Map<String, String>? headers;
  List<XTrack> subtitles;
  List<XTrack> audios;

  factory XVideo.fromJson(Map<String, dynamic> json) => XVideo(
        (json['url'] ?? '').toString().trim(),
        (json['quality'] ?? '').toString().trim(),
        (json['originalUrl'] ?? json['url'] ?? '').toString().trim(),
        headers: (json['headers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
        subtitles: json['subtitles'] != null
            ? (json['subtitles'] as List)
                .map((e) => XTrack.fromJson(e as Map))
                .toList()
            : [],
        audios: json['audios'] != null
            ? (json['audios'] as List)
                .map((e) => XTrack.fromJson(e as Map))
                .toList()
            : [],
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'quality': quality,
        'originalUrl': originalUrl,
        'headers': headers,
        'subtitles': subtitles.map((e) => e.toJson()).toList(),
        'audios': audios.map((e) => e.toJson()).toList(),
      };
}

/// One subtitle / audio track as reported by an extension.
class XTrack {
  XTrack({this.file, this.label, this.url, this.lang});

  final String? file;
  final String? label;
  final String? url;
  final String? lang;

  factory XTrack.fromJson(Map json) => XTrack(
        file: json['file']?.toString().trim(),
        label: json['label']?.toString().trim(),
        url: json['url']?.toString().trim(),
        lang: json['lang']?.toString().trim(),
      );

  Map<String, dynamic> toJson() =>
      {'file': file, 'label': label, if (url != null) 'url': url};
}

/// Response.toJson() for the JS `Client` bridge — mirrors the http package
/// shape the extensions expect: body, statusCode, headers, request, ...
Map<String, dynamic> httpResponseToJson({
  required String body,
  required int statusCode,
  required Map<String, String> headers,
  String? reasonPhrase,
  bool isRedirect = false,
  String? requestUrl,
  String? requestMethod,
}) =>
    {
      'body': body,
      'statusCode': statusCode,
      'headers': headers,
      'reasonPhrase': reasonPhrase ?? '',
      'isRedirect': isRedirect,
      'persistentConnection': true,
      'contentLength': body.length,
      'request': {
        'url': requestUrl ?? '',
        'method': requestMethod ?? 'GET',
        'headers': <String, String>{},
        'followRedirects': true,
        'maxRedirects': 5,
      },
    };

/// `jsonDecode` + cast helper used all over the glue.
Map<String, String>? mapStringString(dynamic v) => v is Map
    ? v.map((k, e) => MapEntry(k.toString(), e?.toString() ?? ''))
    : null;

/// Encodes [json] with the JS-friendly escaping jsonEncode already emits.
String jsJsonEncode(Object? json) => jsonEncode(json);
