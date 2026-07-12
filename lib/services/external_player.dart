// Copyright 2024 Lumina Reader Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// External player support. Launches VLC, MX Player, mpv or NextPlayer with
// a video URL, HTTP headers, subtitle tracks and a resume position. When
// the player exits, the resulting position and duration are read back via
// a platform channel so the caller can update the local history record.
//
// NOTE: This service depends on `android_intent_plus` for sending explicit
// intents and on a small native plugin (registered as
// `lumina_reader/external_player`) to receive the player's result. Add the
// dependency to pubspec.yaml before enabling the feature:
//
//   dependencies:
//     android_intent_plus: ^5.0.2

import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/services.dart';

/// Thrown when an external player launch fails.
class ExternalPlayerException implements Exception {
  ExternalPlayerException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ExternalPlayerException: $message';
}

/// Supported external players.
enum ExternalPlayer {
  vlc,
  mxPlayer,
  mxPlayerFree,
  mpv,
  nextPlayer,
  system,
}

extension ExternalPlayerMetadata on ExternalPlayer {
  /// Android package name of the player.
  String get packageName {
    switch (this) {
      case ExternalPlayer.vlc:
        return 'org.videolan.vlc';
      case ExternalPlayer.mxPlayer:
        return 'com.mxtech.videoplayer.pro';
      case ExternalPlayer.mxPlayerFree:
        return 'com.mxtech.videoplayer.ad';
      case ExternalPlayer.mpv:
        return 'is.xyz.mpv';
      case ExternalPlayer.nextPlayer:
        return 'dev.anilbeesetti.nextplayer';
      case ExternalPlayer.system:
        return '';
    }
  }

  /// Human-readable display name.
  String get displayName {
    switch (this) {
      case ExternalPlayer.vlc:
        return 'VLC';
      case ExternalPlayer.mxPlayer:
        return 'MX Player';
      case ExternalPlayer.mxPlayerFree:
        return 'MX Player (Free)';
      case ExternalPlayer.mpv:
        return 'mpv';
      case ExternalPlayer.nextPlayer:
        return 'NextPlayer';
      case ExternalPlayer.system:
        return 'System player';
    }
  }

  /// Whether this player is installed on the device. Always returns `true`
  /// for [ExternalPlayer.system].
  Future<bool> isInstalled() async {
    if (this == ExternalPlayer.system) return true;
    if (!Platform.isAndroid) return false;
    try {
      final intent = AndroidIntent(
        action: 'action.MAIN',
        package: packageName,
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// A subtitle track to pass to the external player.
class SubtitleTrack {
  SubtitleTrack({
    required this.url,
    required this.language,
    this.title,
    this.isExternal = true,
  });

  /// URL or file path of the subtitle file.
  final String url;

  /// ISO 639-1 language code (e.g. `en`, `ja`).
  final String language;

  /// Optional human-readable title.
  final String? title;

  /// Whether the track is external (vs. embedded in the media).
  final bool isExternal;

  Map<String, String> toIntentExtras() => <String, String>{
        'sub': url,
        if (title != null) 'sub_name': title!,
        if (language.isNotEmpty) 'sub_language': language,
      };
}

/// Parameters for an external player launch.
class ExternalPlayerRequest {
  ExternalPlayerRequest({
    required this.url,
    required this.player,
    this.title,
    this.headers = const <String, String>{},
    this.subtitles = const <SubtitleTrack>[],
    this.resumePositionMs = 0,
    this.durationMs,
    this.enableHardwareAcceleration = true,
    this.returnResult = true,
  });

  /// Video URL (http, https, file or content URI).
  final String url;

  /// Target player.
  final ExternalPlayer player;

  /// Optional display title.
  final String? title;

  /// HTTP headers to send with the request.
  final Map<String, String> headers;

  /// Subtitle tracks to pass.
  final List<SubtitleTrack> subtitles;

  /// Resume position in milliseconds. When > 0 the player seeks to this
  /// position on startup.
  final int resumePositionMs;

  /// Total duration in milliseconds, when known. Helps some players
  /// initialise their scrubber correctly.
  final int? durationMs;

  /// Whether to enable hardware acceleration (where supported).
  final bool enableHardwareAcceleration;

  /// Whether the player should return its final position / duration via
  /// the platform channel. Disable for fire-and-forget launches.
  final bool returnResult;
}

/// Result returned by the player after it exits.
class ExternalPlayerResult {
  ExternalPlayerResult({
    this.player,
    this.positionMs,
    this.durationMs,
    this.completed = false,
    this.error,
  });

  /// Which player produced this result, when known.
  final ExternalPlayer? player;

  /// Last playback position in milliseconds. `null` when the player did
  /// not report a position.
  final int? positionMs;

  /// Total duration in milliseconds. `null` when the player did not
  /// report a duration.
  final int? durationMs;

  /// Whether the player reached the end of the media.
  final bool completed;

  /// Optional error message produced by the player.
  final String? error;

  /// Progress fraction in `0..1` based on [positionMs] and [durationMs].
  double get progress {
    final p = positionMs;
    final d = durationMs;
    if (p == null || d == null || d <= 0) return 0.0;
    return (p / d).clamp(0.0, 1.0);
  }

  bool get isError => error != null;
}

/// Platform channel used to receive results from external players.
const MethodChannel _kChannel =
    MethodChannel('lumina_reader/external_player');

/// External player launcher.
class ExternalPlayerService {
  ExternalPlayerService();

  /// Returns the list of players installed on the device.
  Future<List<ExternalPlayer>> installedPlayers() async {
    if (!Platform.isAndroid) return const <ExternalPlayer>[];
    final results = <ExternalPlayer>[];
    for (final p in ExternalPlayer.values) {
      if (p == ExternalPlayer.system) {
        results.add(p);
        continue;
      }
      if (await p.isInstalled()) {
        results.add(p);
      }
    }
    return results;
  }

  /// Launches the external player described by [request]. When
  /// [request.returnResult] is `true`, this future completes with the
  /// player's exit result; otherwise it completes as soon as the player
  /// has been launched.
  Future<ExternalPlayerResult> launch(ExternalPlayerRequest request) async {
    if (!Platform.isAndroid) {
      throw ExternalPlayerException(
        'External players are only supported on Android',
      );
    }

    final intent = _buildIntent(request);
    try {
      await intent.launch();
    } catch (e) {
      throw ExternalPlayerException(
        'Failed to launch ${request.player.displayName}: $e',
        cause: e,
      );
    }

    if (!request.returnResult) {
      return ExternalPlayerResult(player: request.player);
    }
    return _awaitResult(request.player);
  }

  /// Builds the [AndroidIntent] for the given request, honouring the
  /// per-player extras conventions.
  AndroidIntent _buildIntent(ExternalPlayerRequest request) {
    final action = 'android.intent.action.VIEW';
    final extras = <String, dynamic>{};
    var data = Uri.parse(request.url);
    if (request.headers.isNotEmpty) {
      extras['headers'] = <String>[for (final e in request.headers.entries) '${e.key}: ${e.value}'];
    }
    if (request.title != null) {
      extras['title'] = request.title!;
    }
    if (request.resumePositionMs > 0) {
      extras['position'] = request.resumePositionMs;
      extras['resume'] = request.resumePositionMs;
    }
    if (request.durationMs != null) {
      extras['duration'] = request.durationMs!;
    }
    if (request.subtitles.isNotEmpty) {
      extras['subs'] = request.subtitles.map((s) => s.url).toList();
      if (request.subtitles.any((s) => s.title != null)) {
        extras['subs.name'] =
            request.subtitles.map((s) => s.title ?? '').toList();
      }
      if (request.subtitles.any((s) => s.language.isNotEmpty)) {
        extras['subs.language'] =
            request.subtitles.map((s) => s.language).toList();
      }
    }

    switch (request.player) {
      case ExternalPlayer.vlc:
        return AndroidIntent(
          action: action,
          data: data.toString(),
          package: ExternalPlayer.vlc.packageName,
          arguments: extras,
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
      case ExternalPlayer.mxPlayer:
      case ExternalPlayer.mxPlayerFree:
        return _buildMxPlayerIntent(request, action, extras);
      case ExternalPlayer.mpv:
        // mpv accepts a single subtitle via the "sub" extra.
        if (request.subtitles.isNotEmpty) {
          extras['sub'] = request.subtitles.first.url;
        }
        return AndroidIntent(
          action: action,
          data: data.toString(),
          package: ExternalPlayer.mpv.packageName,
          arguments: extras,
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
      case ExternalPlayer.nextPlayer:
        // NextPlayer uses a simpler extras layout — title + position.
        final nextExtras = <String, dynamic>{
          if (request.title != null) 'title': request.title,
          if (request.resumePositionMs > 0)
            'position': request.resumePositionMs,
        };
        return AndroidIntent(
          action: action,
          data: data.toString(),
          package: ExternalPlayer.nextPlayer.packageName,
          arguments: nextExtras,
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
      case ExternalPlayer.system:
        return AndroidIntent(
          action: action,
          data: data.toString(),
          arguments: extras,
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
    }
  }

  /// MX Player uses a set of custom extras documented at
  /// https://mx.junkyard.net/developer.html
  AndroidIntent _buildMxPlayerIntent(
    ExternalPlayerRequest request,
    String action,
    Map<String, dynamic> extras,
  ) {
    final mxExtras = Map<String, dynamic>.from(extras);
    if (request.headers.isNotEmpty) {
      // MX Player expects headers as a String array of "Key: Value" pairs.
      mxExtras['headers'] = <String>[
        for (final e in request.headers.entries) '${e.key}: ${e.value}'
      ];
    }
    if (request.subtitles.isNotEmpty) {
      mxExtras['subs'] = request.subtitles.map((s) => s.url).toList();
      mxExtras['subs.name'] =
          request.subtitles.map((s) => s.title ?? s.language).toList();
      mxExtras['subs.language'] =
          request.subtitles.map((s) => s.language).toList();
      mxExtras['subs.enable'] = request.subtitles.map((_) => 1).toList();
    }
    if (request.resumePositionMs > 0) {
      mxExtras['position'] = request.resumePositionMs;
    }
    if (request.enableHardwareAcceleration) {
      mxExtras['decode_mode'] = 1; // HW+ decoding
    }
    if (request.returnResult) {
      mxExtras['return_result'] = true;
      mxExtras['end_by'] = 'user';
    }
    return AndroidIntent(
      action: action,
      data: request.url,
      package: request.player.packageName,
      arguments: mxExtras,
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
  }

  /// Waits for the external player to report its result via the platform
  /// channel. Times out after 8 hours (long movies) and returns whatever
  /// was reported last.
  Future<ExternalPlayerResult> _awaitResult(ExternalPlayer player) async {
    final completer = Completer<ExternalPlayerResult>();

    Future<dynamic> previousHandler = _kChannel.setMethodCallHandler(
      (MethodCall call) async {
        if (call.method != 'onPlayerResult') return null;
        final args =
            (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        final result = ExternalPlayerResult(
          player: player,
          positionMs: (args['position'] as num?)?.toInt(),
          durationMs: (args['duration'] as num?)?.toInt(),
          completed: (args['completed'] as bool?) ?? false,
          error: args['error'] as String?,
        );
        if (!completer.isCompleted) completer.complete(result);
        return null;
      },
    );
    // Restore the previous handler once we are done with it.
    // ignore: unawaited_futures
    previousHandler;

    // Fallback timeout — if the player never reports back, resolve with an
    // empty result so the caller's future doesn't hang forever.
    Future.delayed(const Duration(hours: 8), () {
      if (!completer.isCompleted) {
        completer.complete(ExternalPlayerResult(player: player));
      }
    });

    final result = await completer.future;
    await _kChannel.setMethodCallHandler(null);
    return result;
  }

  /// Forwards a result received out-of-band (e.g. from a native
  /// `onActivityResult` handler that was registered separately) to any
  /// pending [launch] caller.
  void handleNativeResult(Map<String, dynamic> args) {
    final result = ExternalPlayerResult(
      positionMs: (args['position'] as num?)?.toInt(),
      durationMs: (args['duration'] as num?)?.toInt(),
      completed: (args['completed'] as bool?) ?? false,
      error: args['error'] as String?,
    );
    _resultController.add(result);
  }

  final StreamController<ExternalPlayerResult> _resultController =
      StreamController<ExternalPlayerResult>.broadcast();

  /// Stream of results received out-of-band (when [launch] was called with
  /// `returnResult: false` but the app still wants to observe results).
  Stream<ExternalPlayerResult> get results => _resultController.stream;

  void dispose() {
    _resultController.close();
  }
}
