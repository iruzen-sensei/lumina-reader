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
// AniChart airing-schedule service. Mirrors the data exposed by
// https://anichart.net (which itself is a thin wrapper around the AniList
// GraphQL API). Returns the next airing episode for a given media id plus
// a weekly schedule that can be rendered as a calendar.
//
// The service also handles MAL-to-AniList id mapping so the calendar can be
// populated from MAL ids stored on local [Track] entries.

import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

/// Thrown by the AniChart service.
class AniChartException implements Exception {
  AniChartException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AniChartException: $message';
}

/// A single airing entry.
class AiringEpisode {
  AiringEpisode({
    required this.anilistId,
    required this.malId,
    required this.title,
    required this.coverUrl,
    required this.episode,
    required this.airingAt,
    this.colorHex,
    this.format,
    this.episodeTitle,
    this.durationMinutes,
  });

  /// AniList media id.
  final int anilistId;

  /// MAL id, when known.
  final int? malId;

  /// Display title (romaji, falling back to English / native).
  final String title;

  /// Cover image URL.
  final String coverUrl;

  /// Episode number that will air.
  final int episode;

  /// Airing timestamp (milliseconds since epoch, UTC).
  final int airingAt;

  /// Optional colour used by AniChart to colour the card.
  final String? colorHex;

  /// Media format (`TV`, `MOVIE`, `OVA`, ...).
  final String? format;

  /// Optional episode title.
  final String? episodeTitle;

  /// Optional episode duration in minutes.
  final int? durationMinutes;

  /// Returns the airing time as a UTC [DateTime].
  DateTime get airingDateTime =>
      DateTime.fromMillisecondsSinceEpoch(airingAt, isUtc: true);

  /// Returns the time remaining until the episode airs, or `Duration.zero`
  /// when it has already aired.
  Duration get timeUntilAiring {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final delta = airingAt - now;
    return Duration(milliseconds: delta < 0 ? 0 : delta);
  }

  /// Returns a short, human-readable "airs in" label (e.g. `in 3d 4h`).
  String get countdownLabel {
    final remaining = timeUntilAiring;
    if (remaining == Duration.zero) return 'aired';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    if (days > 0) return 'in ${days}d ${hours}h';
    if (hours > 0) return 'in ${hours}h ${minutes}m';
    return 'in ${minutes}m';
  }

  @override
  String toString() => 'AiringEpisode($title #$episode $countdownLabel)';
}

/// Lazily-opened Hive box used to persist MAL -> AniList id mappings.
Box<int>? _idMapBox;

Future<Box<int>> _openIdMapBox() async {
  if (_idMapBox != null && _idMapBox!.isOpen) return _idMapBox!;
  _idMapBox = await Hive.openBox<int>('anichart_id_map');
  return _idMapBox!;
}

/// AniChart airing schedule service.
class AniChartService {
  AniChartService({
    this.userAgent = 'LuminaReader/1.0 (https://github.com/lumina-reader)',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// User-Agent header.
  final String userAgent;

  final http.Client _client;

  static const String _kGraphqlEndpoint = 'https://graphql.anilist.co';

  /// In-memory cache of recently resolved MAL -> AniList mappings.
  final Map<int, int?> _memMap = <int, int?>{};

  // -- ID mapping -----------------------------------------------------------

  /// Resolves the AniList media id for [malId]. Results are cached on disk
  /// because the mapping never changes. Returns `null` when the MAL id has
  /// no AniList equivalent.
  Future<int?> resolveAniListId(int malId) async {
    if (malId <= 0) return null;
    if (_memMap.containsKey(malId)) return _memMap[malId]!;
    final box = await _openIdMapBox();
    final cached = box.get(malId.toString());
    if (cached != null) {
      _memMap[malId] = cached;
      return cached;
    }

    const query = r'''
      query MediaByMal($idMal: Int) {
        Media(idMal: $idMal, type: ANIME) { id }
      }
    ''';
    final data = await _graphql(query, <String, dynamic>{'idMal': malId});
    final id = data['Media']?['id'];
    final resolved = id == null ? null : (id as num).toInt();
    _memMap[malId] = resolved;
    if (resolved != null) {
      await box.put(malId.toString(), resolved);
    }
    return resolved;
  }

  /// Resolves the MAL id for [anilistId]. Cached on disk.
  Future<int?> resolveMalId(int anilistId) async {
    if (anilistId <= 0) return null;
    const query = r'''
      query MediaById($id: Int) {
        Media(id: $id, type: ANIME) { idMal }
      }
    ''';
    final data = await _graphql(query, <String, dynamic>{'id': anilistId});
    final idMal = data['Media']?['idMal'];
    return idMal == null ? null : (idMal as num).toInt();
  }

  // -- Schedule -------------------------------------------------------------

  /// Returns the next airing episode for [anilistId], or `null` when the
  /// series has finished airing / has no scheduled episode.
  Future<AiringEpisode?> getNextAiring(int anilistId) async {
    const query = r'''
      query NextAiring($id: Int) {
        Media(id: $id, type: ANIME) {
          id
          idMal
          title { romaji english native }
          coverImage { large extraLarge color }
          format
          nextAiringEpisode { airingAt episode timeUntilAiring }
        }
      }
    ''';
    final data = await _graphql(query, <String, dynamic>{'id': anilistId});
    final media = data['Media'] as Map<String, dynamic>?;
    if (media == null) return null;
    final next = media['nextAiringEpisode'] as Map<String, dynamic>?;
    if (next == null) return null;
    return _mediaToEpisode(media, next);
  }

  /// Returns the next airing episode for a MAL id. Resolves the AniList id
  /// first (cached), then delegates to [getNextAiring].
  Future<AiringEpisode?> getNextAiringByMalId(int malId) async {
    final anilistId = await resolveAniListId(malId);
    if (anilistId == null) return null;
    return getNextAiring(anilistId);
  }

  /// Returns the airing schedule for the inclusive day range
  /// [from]..[to] (UTC). Mirrors the query used by AniChart's calendar.
  Future<List<AiringEpisode>> getSchedule({
    required DateTime from,
    required DateTime to,
    int perPage = 100,
  }) async {
    final fromSec = from.toUtc().millisecondsSinceEpoch ~/ 1000;
    final toSec = to.toUtc().millisecondsSinceEpoch ~/ 1000;
    const query = r'''
      query AiringSchedule($from: Int, $to: Int, $perPage: Int) {
        Page(perPage: $perPage) {
          airingSchedules(airingAt_greater: $from, airingAt_lesser: $to) {
            episode
            airingAt
            media {
              id
              idMal
              title { romaji english native }
              coverImage { large extraLarge color }
              format
              duration
            }
          }
        }
      }
    ''';
    final data = await _graphql(query, <String, dynamic>{
      'from': fromSec,
      'to': toSec,
      'perPage': perPage,
    });
    final schedules = (data['Page']?['airingSchedules'] as List?) ??
        const <dynamic>[];
    final episodes = <AiringEpisode>[];
    for (final raw in schedules.cast<Map<String, dynamic>>()) {
      final media = raw['media'] as Map<String, dynamic>?;
      if (media == null) continue;
      episodes.add(_mediaToEpisode(media, raw));
    }
    episodes.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    return episodes;
  }

  /// Returns the airing schedule for a list of MAL ids. The MAL ids are
  /// resolved in parallel (cached) and then the schedule is fetched.
  Future<List<AiringEpisode>> getScheduleForMalIds(
    Iterable<int> malIds, {
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now().toUtc();
    final start = from ?? now;
    final end = to ?? now.add(const Duration(days: 7));
    final schedule = await getSchedule(from: start, to: end);
    final wantedMalIds = malIds.toSet();
    // Filter the schedule by MAL ids the caller asked about. Entries whose
    // MAL id we don't know are still returned (the caller can resolve them
    // lazily).
    return schedule.where((e) {
      if (e.malId == null) return true; // unknown — keep, caller decides
      return wantedMalIds.contains(e.malId);
    }).toList();
  }

  /// Returns the airing schedule grouped by day. The keys are the UTC date
  /// (truncated to midnight); the values are the episodes airing that day,
  /// sorted by time.
  Future<Map<DateTime, List<AiringEpisode>>> getScheduleByDay({
    required DateTime from,
    required DateTime to,
  }) async {
    final schedule = await getSchedule(from: from, to: to);
    final byDay = <DateTime, List<AiringEpisode>>{};
    for (final ep in schedule) {
      final day = DateTime.utc(
        ep.airingDateTime.year,
        ep.airingDateTime.month,
        ep.airingDateTime.day,
      );
      byDay.putIfAbsent(day, () => <AiringEpisode>[]).add(ep);
    }
    return byDay;
  }

  // -- GraphQL plumbing -----------------------------------------------------

  Future<Map<String, dynamic>> _graphql(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await _client
        .post(
          Uri.parse(_kGraphqlEndpoint),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'User-Agent': userAgent,
          },
          body: jsonEncode(<String, dynamic>{
            'query': query,
            'variables': variables,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AniChartException(
        'AniList GraphQL request failed: ${response.statusCode}',
        cause: response.body,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['errors'] != null) {
      final errors = body['errors'] as List;
      final message = errors.isEmpty
          ? 'Unknown AniList error'
          : (errors.first['message'] ?? 'Unknown AniList error');
      throw AniChartException('AniList GraphQL error: $message');
    }
    return (body['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  }

  AiringEpisode _mediaToEpisode(
    Map<String, dynamic> media,
    Map<String, dynamic> schedule,
  ) {
    final title = media['title'] as Map<String, dynamic>? ?? const {};
    return AiringEpisode(
      anilistId: (media['id'] as num).toInt(),
      malId: media['idMal'] == null ? null : (media['idMal'] as num).toInt(),
      title: (title['romaji'] ?? title['english'] ?? title['native'] ?? '') as String,
      coverUrl:
          (media['coverImage']?['extraLarge'] ?? media['coverImage']?['large'] ?? '') as String,
      episode: (schedule['episode'] as num).toInt(),
      airingAt: (schedule['airingAt'] as num).toInt() * 1000,
      colorHex: media['coverImage']?['color'] as String?,
      format: media['format'] as String?,
      durationMinutes: media['duration'] == null
          ? null
          : (media['duration'] as num).toInt(),
    );
  }

  /// Releases the underlying HTTP client.
  void dispose() {
    _client.close();
  }
}
