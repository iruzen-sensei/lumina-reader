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
// AniSkip integration. Queries api.aniskip.com for intro / outro skip
// segments and exposes three skip modes: manual, auto-skip and
// Netflix-style countdown. MAL ids are resolved via AniList's GraphQL
// endpoint when only an AniList id is available. Skip segments are cached
// in memory and persisted to a Hive box so they survive across launches.

import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// Thrown by the AniSkip service.
class AniSkipException implements Exception {
  AniSkipException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AniSkipException: $message';
}

/// Type of skip segment returned by AniSkip.
enum SkipType {
  opening('op'),
  ending('ed'),
  mixedOpening('mixed-op'),
  mixedEnding('mixed-ed'),
  recap('recap');

  const SkipType(this.apiKey);

  /// Key used by the AniSkip API.
  final String apiKey;

  static SkipType? fromApiKey(String? key) {
    if (key == null) return null;
    for (final v in SkipType.values) {
      if (v.apiKey == key) return v;
    }
    return null;
  }

  /// Whether this segment is an opening (intro) skip.
  bool get isOpening =>
      this == SkipType.opening || this == SkipType.mixedOpening;

  /// Whether this segment is an ending (outro) skip.
  bool get isEnding =>
      this == SkipType.ending || this == SkipType.mixedEnding;
}

/// Behaviour used when a skip segment becomes active.
enum SkipMode {
  /// Show a small skip button that the user must tap.
  manual,

  /// Skip the segment automatically as soon as it starts.
  autoSkip,

  /// Show a Netflix-style 5s countdown overlay; the segment is skipped
  /// when the countdown reaches zero (or the user taps "Skip").
  netflixCountdown,
}

/// A single skip segment for an episode.
class SkipSegment {
  SkipSegment({
    required this.type,
    required this.start,
    required this.end,
    this.episodeLength,
    this.serverName,
    this.uuid,
    this.userCount,
  });

  /// Kind of skip segment (opening / ending / recap / ...).
  final SkipType type;

  /// Start time of the segment, in seconds.
  final double start;

  /// End time of the segment, in seconds.
  final double end;

  /// Total length of the episode the segment belongs to, in seconds.
  final double? episodeLength;

  /// Name of the AniSkip server that produced the segment.
  final String? serverName;

  /// Stable UUID of the segment on the AniSkip side.
  final String? uuid;

  /// Number of users who have upvoted the segment.
  final int? userCount;

  /// Duration of the segment, in seconds.
  double get duration => end - start;

  /// Returns `true` when [position] (seconds) is inside the segment.
  bool contains(double position) => position >= start && position < end;

  /// Returns `true` when [position] is within [tolerance] seconds of the
  /// segment start. Used to trigger the Netflix countdown a moment before
  /// the segment actually starts.
  bool isApproaching(double position, {double tolerance = 2.0}) =>
      position >= start - tolerance && position < start;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.apiKey,
        'start': start,
        'end': end,
        'episodeLength': episodeLength,
        'serverName': serverName,
        'uuid': uuid,
        'userCount': userCount,
      };

  factory SkipSegment.fromJson(Map<String, dynamic> json) {
    final interval = (json['interval'] as List?) ?? const <dynamic>[];
    final start = interval.length >= 1 ? (interval[0] as num).toDouble() : 0.0;
    final end = interval.length >= 2 ? (interval[1] as num).toDouble() : 0.0;
    return SkipSegment(
      type: SkipType.fromApiKey(json['skipType'] as String?) ??
          SkipType.opening,
      start: start,
      end: end,
      episodeLength: (json['episodeLength'] as num?)?.toDouble(),
      serverName: json['skipId'] as String?,
      uuid: json['skipId'] as String?,
      userCount: (json['userCount'] as num?)?.toInt(),
    );
  }

  @override
  String toString() =>
      'SkipSegment(${type.apiKey} ${start.toStringAsFixed(1)}->${end.toStringAsFixed(1)})';
}

/// Lazily-opened Hive box used to persist skip segments.
Box<String>? _aniskipCacheBox;

Future<Box<String>> _openCacheBox() async {
  if (_aniskipCacheBox != null && _aniskipCacheBox!.isOpen) {
    return _aniskipCacheBox!;
  }
  _aniskipCacheBox = await Hive.openBox<String>('aniskip_cache');
  return _aniskipCacheBox!;
}

/// AniSkip intro / outro skip service.
class AniSkipService {
  AniSkipService({
    this.mode = SkipMode.netflixCountdown,
    this.userAgent = 'LuminaReader/1.0 (https://github.com/lumina-reader)',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Default skip mode applied to new episodes.
  SkipMode mode;

  /// User-Agent sent with every request.
  final String userAgent;

  final http.Client _client;

  /// In-memory cache of recently fetched segments, keyed by
  /// `malId:episode`.
  final Map<String, List<SkipSegment>> _memCache = <String, List<SkipSegment>>{};

  static const String _kApiBase = 'https://api.aniskip.com/v2';
  static const String _kAnilistGraphql = 'https://graphql.anilist.co';

  /// Returns the skip segments for [malId] + [episodeNumber]. Results are
  /// cached in memory and on disk for 24 hours.
  Future<List<SkipSegment>> getSkipSegments({
    required int malId,
    required int episodeNumber,
    bool forceRefresh = false,
  }) async {
    final key = '$malId:$episodeNumber';
    if (!forceRefresh && _memCache.containsKey(key)) {
      return _memCache[key]!;
    }
    if (!forceRefresh) {
      final cached = await _loadFromDisk(key);
      if (cached != null) {
        _memCache[key] = cached;
        return cached;
      }
    }

    final url = Uri.parse('$_kApiBase/skip-times/$malId/$episodeNumber')
        .replace(queryParameters: <String, String>{
      'types': 'op,ed,mixed-op,mixed-ed,recap',
    });
    final response = await _client.get(url, headers: <String, String>{
      'Accept': 'application/json',
      'User-Agent': userAgent,
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw AniSkipException(
        'AniSkip API returned HTTP ${response.statusCode}',
        cause: response.body,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final found = (body['found'] as bool?) ?? false;
    if (!found) {
      _memCache[key] = const <SkipSegment>[];
      await _saveToDisk(key, const <SkipSegment>[]);
      return const <SkipSegment>[];
    }
    final raw = (body['results'] as List?) ?? const <dynamic>[];
    final segments = raw
        .cast<Map<String, dynamic>>()
        .map(SkipSegment.fromJson)
        .toList();
    // Prefer segments with more upvotes; keep the best per type.
    segments.sort((a, b) => (b.userCount ?? 0).compareTo(a.userCount ?? 0));
    final deduped = <SkipType, SkipSegment>{};
    for (final s in segments) {
      deduped.putIfAbsent(s.type, () => s);
    }
    final result = deduped.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    _memCache[key] = result;
    await _saveToDisk(key, result);
    return result;
  }

  /// Resolves the MAL id for an entry when only the AniList id is known.
  /// Returns `null` when the entry has no MAL mapping.
  Future<int?> resolveMalIdFromAniList(int anilistId) async {
    const query = r'''
      query MediaIdMal($id: Int) {
        Media(id: $id) { idMal }
      }
    ''';
    final response = await http.post(
      Uri.parse(_kAnilistGraphql),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': userAgent,
      },
      body: jsonEncode(<String, dynamic>{
        'query': query,
        'variables': <String, dynamic>{'id': anilistId},
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final idMal = body['data']?['Media']?['idMal'];
    return idMal == null ? null : (idMal as num).toInt();
  }

  /// Returns the skip segment that should currently be active at
  /// [position] (seconds), or `null` when none is active.
  SkipSegment? activeSegment(
    List<SkipSegment> segments,
    double position,
  ) {
    for (final s in segments) {
      if (s.contains(position)) return s;
    }
    return null;
  }

  /// Returns the next segment that will start after [position], or `null`
  /// when there are no more segments.
  SkipSegment? upcomingSegment(
    List<SkipSegment> segments,
    double position, {
    double tolerance = 5.0,
  }) {
    SkipSegment? best;
    for (final s in segments) {
      if (s.start <= position) continue;
      if (best == null || s.start < best.start) best = s;
    }
    if (best == null) return null;
    return best.start - position <= tolerance ? best : null;
  }

  /// Clears the in-memory and on-disk caches for the given episode.
  Future<void> clearCache({int? malId, int? episodeNumber}) async {
    if (malId == null && episodeNumber == null) {
      _memCache.clear();
      final box = await _openCacheBox();
      await box.clear();
      return;
    }
    final key = '$malId:$episodeNumber';
    _memCache.remove(key);
    final box = await _openCacheBox();
    await box.delete(key);
  }

  // -- Disk cache -----------------------------------------------------------

  Future<List<SkipSegment>?> _loadFromDisk(String key) async {
    final box = await _openCacheBox();
    final raw = box.get(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = (map['cachedAt'] as num).toInt();
      // Invalidate entries older than 24 hours so updated segments are
      // picked up eventually.
      if (DateTime.now().millisecondsSinceEpoch - cachedAt >
          const Duration(hours: 24).inMilliseconds) {
        await box.delete(key);
        return null;
      }
      final list = (map['segments'] as List?) ?? const <dynamic>[];
      return list
          .cast<Map<String, dynamic>>()
          .map(SkipSegment.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToDisk(String key, List<SkipSegment> segments) async {
    final box = await _openCacheBox();
    final payload = jsonEncode(<String, dynamic>{
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
      'segments': segments.map((s) => s.toJson()).toList(),
    });
    await box.put(key, payload);
  }

  /// Releases the underlying HTTP client.
  void dispose() {
    _client.close();
  }
}

/// State machine that drives the Netflix-style countdown overlay.
class SkipCountdownController {
  SkipCountdownController({
    required this.service,
    this.defaultMode = SkipMode.netflixCountdown,
    this.countdownSeconds = 5,
  });

  final AniSkipService service;
  final SkipMode defaultMode;
  final int countdownSeconds;

  /// Currently active mode (overridable per episode).
  SkipMode mode = SkipMode.netflixCountdown;

  /// The episode's skip segments. Populated by [load].
  List<SkipSegment> _segments = const <SkipSegment>[];
  List<SkipSegment> get segments => _segments;

  /// The segment for which a countdown is currently running.
  SkipSegment? _pendingSegment;
  SkipSegment? get pendingSegment => _pendingSegment;

  /// Remaining seconds on the countdown.
  int _remaining = 0;
  int get remaining => _remaining;

  /// Stream that emits countdown updates.
  final _controller = StreamController<SkipCountdownEvent>.broadcast();
  Stream<SkipCountdownEvent> get events => _controller.stream;

  Timer? _ticker;

  /// Loads the skip segments for the given episode.
  Future<void> load({
    required int malId,
    required int episodeNumber,
    SkipMode? modeOverride,
  }) async {
    if (modeOverride != null) mode = modeOverride;
    _segments = await service.getSkipSegments(
      malId: malId,
      episodeNumber: episodeNumber,
    );
    _controller.add(SkipCountdownEvent.segmentsLoaded(_segments));
  }

  /// Called by the player on every position update (in seconds).
  void onPositionChanged(double position) {
    if (mode == SkipMode.manual) {
      // In manual mode we only emit "show skip button" events.
      final active = service.activeSegment(_segments, position);
      _controller.add(SkipCountdownEvent.buttonVisible(active));
      return;
    }

    final active = service.activeSegment(_segments, position);
    if (active != null) {
      if (mode == SkipMode.autoSkip) {
        _controller.add(SkipCountdownEvent.skipNow(active));
        return;
      }
      // Netflix-style: if we are inside a segment but haven't started a
      // countdown yet, jump straight to skipping (the countdown is only
      // shown before the segment starts).
      _controller.add(SkipCountdownEvent.skipNow(active));
      return;
    }

    final upcoming =
        service.upcomingSegment(_segments, position, tolerance: 5.0);
    if (upcoming != null && upcoming != _pendingSegment) {
      _startCountdown(upcoming);
    }
  }

  void _startCountdown(SkipSegment segment) {
    _pendingSegment = segment;
    _remaining = countdownSeconds;
    _controller.add(SkipCountdownEvent.countdownStarted(segment, _remaining));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      _remaining--;
      if (_remaining <= 0) {
        t.cancel();
        _controller.add(SkipCountdownEvent.skipNow(segment));
        _pendingSegment = null;
      } else {
        _controller.add(SkipCountdownEvent.countdownTick(_remaining));
      }
    });
  }

  /// Cancels the current countdown (e.g. when the user dismisses it).
  void cancelCountdown() {
    _ticker?.cancel();
    _pendingSegment = null;
    _remaining = 0;
    _controller.add(const SkipCountdownEvent.countdownCancelled());
  }

  /// Skips the pending segment immediately (e.g. when the user taps
  /// "Skip intro" early).
  void skipNow() {
    if (_pendingSegment != null) {
      _controller.add(SkipCountdownEvent.skipNow(_pendingSegment!));
    }
    _ticker?.cancel();
    _pendingSegment = null;
    _remaining = 0;
  }

  void dispose() {
    _ticker?.cancel();
    _controller.close();
  }
}

/// Events emitted by [SkipCountdownController].
class SkipCountdownEvent {
  const SkipCountdownEvent._({
    required this.kind,
    this.segment,
    this.remaining,
    this.segments,
  });

  final SkipCountdownKind kind;
  final SkipSegment? segment;
  final int? remaining;
  final List<SkipSegment>? segments;

  factory SkipCountdownEvent.segmentsLoaded(List<SkipSegment> segments) =>
      SkipCountdownEvent._(
        kind: SkipCountdownKind.segmentsLoaded,
        segments: segments,
      );
  factory SkipCountdownEvent.countdownStarted(
          SkipSegment segment, int remaining) =>
      SkipCountdownEvent._(
        kind: SkipCountdownKind.countdownStarted,
        segment: segment,
        remaining: remaining,
      );
  factory SkipCountdownEvent.countdownTick(int remaining) =>
      SkipCountdownEvent._(
        kind: SkipCountdownKind.countdownTick,
        remaining: remaining,
      );
  factory SkipCountdownEvent.countdownCancelled() =>
      const SkipCountdownEvent._(kind: SkipCountdownKind.countdownCancelled);
  factory SkipCountdownEvent.skipNow(SkipSegment segment) =>
      SkipCountdownEvent._(
        kind: SkipCountdownKind.skipNow,
        segment: segment,
      );
  factory SkipCountdownEvent.buttonVisible(SkipSegment? segment) =>
      SkipCountdownEvent._(
        kind: SkipCountdownKind.buttonVisibility,
        segment: segment,
      );
}

enum SkipCountdownKind {
  segmentsLoaded,
  countdownStarted,
  countdownTick,
  countdownCancelled,
  skipNow,
  buttonVisibility,
}
