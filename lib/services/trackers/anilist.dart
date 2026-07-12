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
// AniList tracker integration. Implements the OAuth2 implicit-authorisation
// flow used by AniList and exposes the GraphQL mutations / queries needed
// for progress, score and status sync, plus the airing-schedule feed that
// powers the AniChart-style calendar.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'package:lumina_reader/models/track.dart';
import 'package:lumina_reader/services/trackers/base_tracker.dart';

/// Lazily-opened Hive box used to persist AniList credentials.
Box<String>? _anilistCredsBox;

Future<Box<String>> _openCredsBox() async {
  if (_anilistCredsBox != null && _anilistCredsBox!.isOpen) {
    return _anilistCredsBox!;
  }
  _anilistCredsBox = await Hive.openBox<String>('tracker_anilist_credentials');
  return _anilistCredsBox!;
}

/// A single entry in the AniChart airing schedule.
class AniChartEntry {
  AniChartEntry({
    required this.mediaId,
    required this.title,
    required this.coverImage,
    required this.episode,
    required this.airingAt,
    this.episodeTitle,
    this.colorHex,
    this.format,
    this.malId,
  });

  /// AniList media id.
  final int mediaId;

  /// Display title (romaji).
  final String title;

  /// Cover image URL.
  final String coverImage;

  /// Episode number.
  final int episode;

  /// Airing timestamp (milliseconds since epoch, UTC).
  final int airingAt;

  /// Optional episode title.
  final String? episodeTitle;

  /// Optional colour used by AniChart to colour the card.
  final String? colorHex;

  /// Media format (`TV`, `MOVIE`, `OVA`, ...).
  final String? format;

  /// Optional MAL id, when available.
  final int? malId;

  @override
  String toString() =>
      'AniChartEntry($title #$episode @ ${DateTime.fromMillisecondsSinceEpoch(airingAt, isUtc: true)})';
}

/// AniList tracker.
///
/// AniList uses an OAuth2 flow that returns the access token directly in the
/// redirect fragment (implicit grant). The token is valid for ~1 year. We
/// store it locally and, because there is no refresh token, we prompt the
/// user to re-authorise when it expires.
///
/// The GraphQL endpoint is `https://graphql.anilist.co`. All write
/// operations go through a single `SaveMediaListEntry` mutation; reads use
/// `Media` / `Page` queries.
class AniListTracker extends Tracker {
  AniListTracker({
    required this.clientIdValue,
    this.redirectUriValue = 'lumina-reader://anilist-callback',
    this.userAgent = 'LuminaReader/1.0 (https://github.com/lumina-reader)',
  }) : super(
          id: TrackerSyncId.anilist,
          name: 'AniList',
          supportsScore: true,
          supportsProgress: true,
          supportsStatus: true,
          supportsStartDate: true,
          supportsFinishDate: true,
          supportsRewatching: true,
          scoreMax: 10,
        );

  /// AniList OAuth client id.
  final String clientIdValue;

  /// Custom-scheme redirect URI.
  final String redirectUriValue;

  /// User-Agent header.
  final String userAgent;

  static const String _kAuthEndpoint = 'https://anilist.co/api/v2/oauth/authorize';
  static const String _kTokenEndpoint = 'https://anilist.co/api/v2/oauth/token';
  static const String _kGraphqlEndpoint = 'https://graphql.anilist.co';

  static const String _kPrefsKey = 'tracker.anilist.credentials';
  static const String _kStateKey = 'tracker.anilist.oauthState';

  // -- Endpoint configuration ----------------------------------------------

  @override
  String get authorizationEndpoint => _kAuthEndpoint;

  @override
  String get tokenEndpoint => _kTokenEndpoint;

  @override
  String get clientId => clientIdValue;

  @override
  String get redirectUrl => redirectUriValue;

  @override
  String get scopes => '';

  @override
  bool get usesPkce => false;

  @override
  List<TrackStatus> get supportedStatuses => const <TrackStatus>[
        TrackStatus.reading,
        TrackStatus.completed,
        TrackStatus.onHold,
        TrackStatus.dropped,
        TrackStatus.planToRead,
      ];

  // -- OAuth flow -----------------------------------------------------------

  @override
  Future<OAuthCredentials> login() async {
    final state = Tracker.generateState();
    final box = await _openCredsBox();
    await box.put(_kStateKey, state);

    final authUrl = Uri.parse(_kAuthEndpoint).replace(
      queryParameters: <String, String>{
        'client_id': clientIdValue,
        'response_type': 'token', // implicit grant
        'redirect_uri': redirectUriValue,
        'state': state,
      },
    );

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _extractScheme(redirectUriValue),
    );

    // AniList returns the token in the URL *fragment* (after `#`).
    final fragment = Uri.splitQueryString(
      Uri.parse(resultUrl.replace('#', '?')).query,
    );
    final returnedState = fragment['state'];
    if (returnedState != state) {
      throw TrackerException('OAuth state mismatch — possible CSRF attack');
    }
    final accessToken = fragment['access_token'];
    if (accessToken == null) {
      throw TrackerException('No access token returned by AniList');
    }
    final expiresIn = int.tryParse(fragment['expires_in'] ?? '') ?? 31536000;

    final creds = OAuthCredentials(
      accessToken: accessToken,
      refreshToken: null, // AniList implicit grant has no refresh token
      expiresAt: DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
      tokenType: fragment['token_type'] ?? 'Bearer',
    );

    final user = await _fetchViewer(creds.accessToken);
    creds.userId = user?.userId;
    creds.username = user?.username;
    _credentials = creds;
    await persistCredentials(creds, cipher: _cipher);
    return creds;
  }

  @override
  @protected
  Future<OAuthCredentials> doRefreshToken(String refreshToken) async {
    // AniList's implicit grant does not issue refresh tokens. When the access
    // token expires the user must re-authorise.
    throw TrackerException(
      'AniList access tokens cannot be refreshed — please log in again',
    );
  }

  // -- User -----------------------------------------------------------------

  @override
  Future<TrackerUser?> getCurrentUser() async {
    final token = await ensureValidToken();
    return _fetchViewer(token);
  }

  Future<TrackerUser?> _fetchViewer(String token) async {
    const query = r'''
      query Viewer {
        Viewer {
          id
          name
          avatar { large }
          siteUrl
        }
      }
    ''';
    final data = await _graphql(query, {}, token: token);
    final viewer = data['Viewer'] as Map<String, dynamic>?;
    if (viewer == null) return null;
    return TrackerUser(
      userId: viewer['id'].toString(),
      username: viewer['name'] as String? ?? '',
      avatarUrl: (viewer['avatar']?['large'] as String?) ?? '',
      profileUrl: viewer['siteUrl'] as String?,
      extra: viewer,
    );
  }

  // -- Search ---------------------------------------------------------------

  @override
  Future<List<TrackerSearchResult>> search(
    String query, {
    int limit = 20,
    TrackMediaType mediaType = TrackMediaType.manga,
  }) async {
    final anilistType = mediaType == TrackMediaType.anime ? 'ANIME' : 'MANGA';
    const gql = r'''
      query Search($type: MediaType!, $search: String!, $perPage: Int!) {
        Page(perPage: $perPage) {
          media(type: $type, search: $search, sort: SEARCH_MATCH) {
            id
            idMal
            title { romaji english native }
            coverImage { large extraLarge color }
            siteUrl
            description(asHtml: false)
            status
            format
            startDate { year month day }
            episodes
            chapters
            volumes
            meanScore
            mediaType: type
          }
        }
      }
    ''';
    final data = await _graphql(gql, <String, dynamic>{
      'type': anilistType,
      'search': query,
      'perPage': limit.clamp(1, 50),
    });
    final media = (data['Page']?['media'] as List?) ?? const <dynamic>[];
    return media.cast<Map<String, dynamic>>().map((m) {
      final title = m['title'] as Map<String, dynamic>? ?? const {};
      return TrackerSearchResult(
        mediaId: m['id'].toString(),
        title: (title['romaji'] ?? title['english'] ?? title['native'] ?? '') as String,
        coverUrl: (m['coverImage']?['extraLarge'] ?? m['coverImage']?['large'] ?? '') as String,
        trackingUrl: m['siteUrl'] as String? ?? '',
        totalChapters: (m['chapters'] ?? m['episodes'] ?? m['volumes']) == null
            ? null
            : ((m['chapters'] ?? m['episodes'] ?? m['volumes']) as num).toInt(),
        summary: m['description'] as String?,
        publishingStatus: m['status'] as String?,
        mediaType: mediaType,
        score: (m['meanScore'] as num?)?.toDouble() != null
            ? (m['meanScore'] as num).toDouble() / 10.0
            : null,
        startDate: _formatStartDate(m['startDate']),
        extra: <String, dynamic>{
          'idMal': m['idMal'],
          'format': m['format'],
          'color': m['coverImage']?['color'],
        },
      );
    }).toList();
  }

  // -- Sync -----------------------------------------------------------------

  @override
  Future<Track> updateTrack(Track track) async {
    if (track.mediaId == null) {
      throw TrackerException('Cannot update a track without a media id');
    }
    const mutation = r'''
      mutation SaveEntry($mediaId: Int, $status: MediaListStatus, $progress: Int,
                         $score: Float, $start: FuzzyDateInput,
                         $complete: FuzzyDateInput, $repeat: Int,
                         $private: Boolean) {
        SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress,
                           score: $score, startedAt: $start, completedAt: $complete,
                           repeat: $repeat, private: $private) {
          id
          status
          progress
          progressVolumes
          score
          repeat
          private
          startedAt { year month day }
          completedAt { year month day }
          updatedAt
          media { id title { romaji } coverImage { large } siteUrl
                  chapters episodes }
        }
      }
    ''';
    final variables = <String, dynamic>{
      'mediaId': int.parse(track.mediaId!),
      if (supportsStatus && track.status != null)
        'status': _statusToAnilist(track.status!),
      if (supportsProgress && track.lastReadChapter != null)
        'progress': track.lastReadChapter,
      if (supportsScore && track.score != null)
        'score': (track.score! * 10).clamp(0, 100).toDouble(),
      if (supportsStartDate && track.startReadAt != null)
        'start': _fuzzyDate(track.startReadAt!),
      if (supportsFinishDate && track.finishReadAt != null)
        'complete': _fuzzyDate(track.finishReadAt!),
      if (supportsRewatching && track.rewatchCount != null)
        'repeat': track.rewatchCount,
      if (track.isPrivate != null) 'private': track.isPrivate,
    };

    final data = await _graphql(mutation, variables);
    final saved = data['SaveMediaListEntry'] as Map<String, dynamic>?;
    if (saved == null) {
      throw TrackerException('AniList returned no saved entry');
    }
    _mergeRemoteEntry(track, saved);
    track.hasPendingChanges = false;
    track.lastSyncedAt = DateTime.now().millisecondsSinceEpoch;
    track.isSynced = true;
    track.lastSyncFailed = false;
    track.lastError = null;
    return track;
  }

  @override
  Future<Track?> getTrack(String mediaId) async {
    final token = await ensureValidToken();
    const query = r'''
      query GetEntry($mediaId: Int) {
        MediaList(mediaId: $mediaId) {
          id status progress progressVolumes score repeat private
          startedAt { year month day }
          completedAt { year month day }
          updatedAt
          media { id title { romaji } coverImage { large } siteUrl
                  chapters episodes }
        }
      }
    ''';
    final data = await _graphql(
      query,
      <String, dynamic>{'mediaId': int.parse(mediaId)},
      token: token,
    );
    final entry = data['MediaList'] as Map<String, dynamic>?;
    if (entry == null) return null;
    final track = Track(
      syncId: id,
      mediaId: mediaId,
      mediaType: TrackMediaType.manga,
    );
    _mergeRemoteEntry(track, entry);
    return track;
  }

  void _mergeRemoteEntry(Track track, Map<String, dynamic> entry) {
    final media = entry['media'] as Map<String, dynamic>? ?? const {};
    final status = entry['status'] as String?;
    if (status != null) track.status = _statusFromAnilist(status);
    final progress = entry['progress'];
    if (progress != null) track.lastReadChapter = (progress as num).toInt();
    final score = entry['score'];
    if (score != null) track.score = ((score as num).toDouble() / 10).round();
    track.title = media['title']?['romaji'] as String?;
    track.cover = media['coverImage']?['large'] as String?;
    track.trackingUrl = media['siteUrl'] as String?;
    track.totalChapters = (media['chapters'] ?? media['episodes']) == null
        ? null
        : ((media['chapters'] ?? media['episodes']) as num).toInt();
    final repeat = entry['repeat'];
    if (repeat != null) track.rewatchCount = (repeat as num).toInt();
    track.isPrivate = entry['private'] as bool?;
    track.startReadAt = _fuzzyDateToMillis(entry['startedAt']);
    track.finishReadAt = _fuzzyDateToMillis(entry['completedAt']);
    final updatedAt = entry['updatedAt'];
    if (updatedAt != null) {
      track.lastSyncedAt = (updatedAt as num).toInt() * 1000;
    }
  }

  // -- AniChart airing schedule --------------------------------------------

  /// Returns the next airing episode for [mediaId] (AniList id).
  Future<AniChartEntry?> getNextAiring(int mediaId) async {
    const query = r'''
      query NextAiring($mediaId: Int) {
        Media(id: $mediaId) {
          id
          idMal
          title { romaji english }
          coverImage { large color }
          format
          nextAiringEpisode { airingAt episode }
        }
      }
    ''';
    final data = await _graphql(query, <String, dynamic>{'mediaId': mediaId});
    final media = data['Media'] as Map<String, dynamic>?;
    if (media == null) return null;
    final next = media['nextAiringEpisode'] as Map<String, dynamic>?;
    if (next == null) return null;
    return AniChartEntry(
      mediaId: mediaId,
      title: (media['title']?['romaji'] ?? media['title']?['english'] ?? '') as String,
      coverImage: (media['coverImage']?['large'] as String?) ?? '',
      episode: (next['episode'] as num).toInt(),
      airingAt: (next['airingAt'] as num).toInt() * 1000,
      colorHex: media['coverImage']?['color'] as String?,
      format: media['format'] as String?,
      malId: media['idMal'] == null ? null : (media['idMal'] as num).toInt(),
    );
  }

  /// Returns the airing schedule for the given day range (UTC).
  ///
  /// Mirrors the AniChart `/api` query that powers the web calendar.
  Future<List<AniChartEntry>> getAiringSchedule({
    required int fromMs,
    required int toMs,
  }) async {
    final fromSec = (fromMs ~/ 1000).clamp(0, 1 << 31);
    final toSec = (toMs ~/ 1000).clamp(0, 1 << 31);
    const query = r'''
      query AiringSchedule($from: Int, $to: Int) {
        Page(perPage: 100) {
          airingSchedules(airingAt_greater: $from, airingAt_lesser: $to) {
            episode
            airingAt
            media {
              id
              idMal
              title { romaji english }
              coverImage { large color }
              format
            }
          }
        }
      }
    ''';
    final data = await _graphql(query, <String, dynamic>{
      'from': fromSec,
      'to': toSec,
    });
    final schedules = (data['Page']?['airingSchedules'] as List?) ??
        const <dynamic>[];
    return schedules.cast<Map<String, dynamic>>().map((s) {
      final media = s['media'] as Map<String, dynamic>? ?? const {};
      return AniChartEntry(
        mediaId: (media['id'] as num).toInt(),
        title: (media['title']?['romaji'] ?? media['title']?['english'] ?? '') as String,
        coverImage: (media['coverImage']?['large'] as String?) ?? '',
        episode: (s['episode'] as num).toInt(),
        airingAt: (s['airingAt'] as num).toInt() * 1000,
        colorHex: media['coverImage']?['color'] as String?,
        format: media['format'] as String?,
        malId: media['idMal'] == null ? null : (media['idMal'] as num).toInt(),
      );
    }).toList();
  }

  // -- GraphQL plumbing -----------------------------------------------------

  Future<Map<String, dynamic>> _graphql(
    String query,
    Map<String, dynamic> variables, {
    String? token,
  }) async {
    final accessToken = token ?? await ensureValidToken();
    final response = await http.post(
      Uri.parse(_kGraphqlEndpoint),
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': userAgent,
      },
      body: jsonEncode(<String, dynamic>{
        'query': query,
        'variables': variables,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'AniList GraphQL request failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['errors'] != null) {
      final errors = body['errors'] as List;
      final message = errors.isEmpty
          ? 'Unknown AniList error'
          : (errors.first['message'] ?? 'Unknown AniList error');
      throw TrackerException('AniList GraphQL error: $message');
    }
    return (body['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  }

  // -- Status mapping -------------------------------------------------------

  static String _statusToAnilist(TrackStatus status) {
    switch (status) {
      case TrackStatus.reading:
        return 'CURRENT';
      case TrackStatus.completed:
        return 'COMPLETED';
      case TrackStatus.onHold:
        return 'PAUSED';
      case TrackStatus.dropped:
        return 'DROPPED';
      case TrackStatus.planToRead:
        return 'PLANNING';
    }
  }

  static TrackStatus _statusFromAnilist(String status) {
    switch (status) {
      case 'CURRENT':
      case 'REPEATING':
        return TrackStatus.reading;
      case 'COMPLETED':
        return TrackStatus.completed;
      case 'PAUSED':
        return TrackStatus.onHold;
      case 'DROPPED':
        return TrackStatus.dropped;
      case 'PLANNING':
      default:
        return TrackStatus.planToRead;
    }
  }

  // -- Date helpers ---------------------------------------------------------

  static Map<String, dynamic> _fuzzyDate(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    return <String, dynamic>{
      'year': dt.year,
      'month': dt.month,
      'day': dt.day,
    };
  }

  static int? _fuzzyDateToMillis(Map<String, dynamic>? fuzzy) {
    if (fuzzy == null) return null;
    final year = fuzzy['year'];
    if (year == null) return null;
    final month = (fuzzy['month'] ?? 1) as int;
    final day = (fuzzy['day'] ?? 1) as int;
    return DateTime.utc(year as int, month, day).millisecondsSinceEpoch;
  }

  static String? _formatStartDate(Map<String, dynamic>? fuzzy) {
    if (fuzzy == null || fuzzy['year'] == null) return null;
    final y = (fuzzy['year'] as int).toString().padLeft(4, '0');
    final m = ((fuzzy['month'] ?? 1) as int).toString().padLeft(2, '0');
    final d = ((fuzzy['day'] ?? 1) as int).toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _extractScheme(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme.isEmpty) {
      throw TrackerException('redirectUri must include a scheme: $uri');
    }
    return parsed.scheme;
  }

  // -- Persistence ----------------------------------------------------------

  @override
  @protected
  Future<void> persistCredentialsImpl(String blob, {required bool encrypted}) async {
    final box = await _openCredsBox();
    await box.put(_kPrefsKey, blob);
  }

  @override
  @protected
  Future<String?> loadCredentialsImpl() async {
    final box = await _openCredsBox();
    return box.get(_kPrefsKey);
  }

  @override
  @protected
  Future<void> clearPersistedCredentials() async {
    final box = await _openCredsBox();
    await box.delete(_kPrefsKey);
    await box.delete(_kStateKey);
  }
}
