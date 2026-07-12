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
// Kitsu tracker integration (simplified). Implements the OAuth2 password /
// authorisation-code flow against Kitsu's JSON:API and exposes the minimal
// sync + search surface used by the Lumina library.

import 'dart:convert';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'package:lumina_reader/models/track.dart';
import 'package:lumina_reader/services/trackers/base_tracker.dart';

/// Lazily-opened Hive box used to persist Kitsu credentials.
Box<String>? _kitsuCredsBox;

Future<Box<String>> _openCredsBox() async {
  if (_kitsuCredsBox != null && _kitsuCredsBox!.isOpen) return _kitsuCredsBox!;
  _kitsuCredsBox = await Hive.openBox<String>('tracker_kitsu_credentials');
  return _kitsuCredsBox!;
}

/// Kitsu tracker.
///
/// Kitsu exposes a JSON:API at `https://kitsu.app/api/edge`. Authentication
/// uses OAuth2 password grant (or the implicit authorisation-code flow with
/// a redirect). The integration here covers the operations Lumina Reader
/// needs: login, search, fetch user entry, and update progress / status /
/// score. Library fetching and rich category support are intentionally
/// omitted to keep the surface small.
class KitsuTracker extends Tracker {
  KitsuTracker({
    required this.clientIdValue,
    this.clientSecretValue,
    this.redirectUriValue = 'lumina-reader://kitsu-callback',
    this.userAgent = 'LuminaReader/1.0 (https://github.com/lumina-reader)',
  }) : super(
          id: TrackerSyncId.kitsu,
          name: 'Kitsu',
          supportsScore: true,
          supportsProgress: true,
          supportsStatus: true,
          supportsStartDate: true,
          supportsFinishDate: true,
          supportsRewatching: false,
          scoreMax: 5, // Kitsu uses a 0..5 scale (with halves)
        );

  final String clientIdValue;
  final String? clientSecretValue;
  final String redirectUriValue;
  final String userAgent;

  static const String _kAuthEndpoint = 'https://kitsu.app/api/oauth/authorize';
  static const String _kTokenEndpoint = 'https://kitsu.app/api/oauth/token';
  static const String _kApiBase = 'https://kitsu.app/api/edge';

  static const String _kPrefsKey = 'tracker.kitsu.credentials';
  static const String _kStateKey = 'tracker.kitsu.oauthState';

  @override
  String get authorizationEndpoint => _kAuthEndpoint;

  @override
  String get tokenEndpoint => _kTokenEndpoint;

  @override
  String get clientId => clientIdValue;

  @override
  String get clientSecret => clientSecretValue ?? '';

  @override
  String get redirectUrl => redirectUriValue;

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
        'response_type': 'code',
        'redirect_uri': redirectUriValue,
        'state': state,
      },
    );

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _extractScheme(redirectUriValue),
    );
    final callback = Uri.parse(resultUrl);
    final returnedState = callback.queryParameters['state'];
    if (returnedState != state) {
      throw TrackerException('OAuth state mismatch — possible CSRF attack');
    }
    final code = callback.queryParameters['code'];
    if (code == null) {
      throw TrackerException('No authorisation code returned by Kitsu');
    }
    final creds = await exchangeAuthorizationCode(code);
    final user = await _fetchCurrentUser(creds.accessToken);
    creds.userId = user?.userId;
    creds.username = user?.username;
    _credentials = creds;
    await persistCredentials(creds, cipher: _cipher);
    return creds;
  }

  @override
  @protected
  Future<OAuthCredentials> doRefreshToken(String refreshToken) async {
    final response = await http.post(
      Uri.parse(_kTokenEndpoint),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientIdValue,
        if (clientSecretValue != null) 'client_secret': clientSecretValue!,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'Kitsu token refresh failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    return parseTokenResponse(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // -- User -----------------------------------------------------------------

  @override
  Future<TrackerUser?> getCurrentUser() async {
    final token = await ensureValidToken();
    return _fetchCurrentUser(token);
  }

  Future<TrackerUser?> _fetchCurrentUser(String token) async {
    final response = await http.get(
      Uri.parse('$_kApiBase/users?filter[self]=true'),
      headers: _jsonHeaders(token),
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final users = (body['data'] as List?) ?? const <dynamic>[];
    if (users.isEmpty) return null;
    final user = users.first as Map<String, dynamic>;
    final attrs = user['attributes'] as Map<String, dynamic>? ?? const {};
    return TrackerUser(
      userId: user['id'].toString(),
      username: attrs['name'] as String? ?? '',
      avatarUrl: (attrs['avatar']?['large'] as String?) ?? '',
      profileUrl: 'https://kitsu.io/users/${attrs['slug'] ?? attrs['name']}',
      extra: user,
    );
  }

  // -- Search ---------------------------------------------------------------

  @override
  Future<List<TrackerSearchResult>> search(
    String query, {
    int limit = 20,
    TrackMediaType mediaType = TrackMediaType.manga,
  }) async {
    final endpoint = mediaType == TrackMediaType.anime ? 'anime' : 'manga';
    final url = Uri.parse('$_kApiBase/$endpoint').replace(
      queryParameters: <String, String>{
        'filter[text]': query,
        'page[limit]': limit.clamp(1, 20).toString(),
        'include': '',
      },
    );
    final response = await authenticatedRequest(
      url.toString(),
      headers: <String, String>{'User-Agent': userAgent, ..._jsonHeaders('')},
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Kitsu search failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = (body['data'] as List?) ?? const <dynamic>[];
    return data.cast<Map<String, dynamic>>().map((entry) {
      final attrs = entry['attributes'] as Map<String, dynamic>? ?? const {};
      return TrackerSearchResult(
        mediaId: entry['id'].toString(),
        title: (attrs['canonicalTitle'] ?? attrs['titles']?['en'] ?? '') as String,
        coverUrl: (attrs['posterImage']?['large'] as String?) ?? '',
        trackingUrl:
            'https://kitsu.io/$endpoint/${attrs['slug'] ?? entry['id']}',
        totalChapters: (attrs['chapterCount'] ?? attrs['episodeCount']) == null
            ? null
            : ((attrs['chapterCount'] ?? attrs['episodeCount']) as num).toInt(),
        summary: attrs['synopsis'] as String?,
        publishingStatus: attrs['status'] as String?,
        mediaType: mediaType,
        score: (attrs['averageRating'] as num?)?.toDouble() != null
            ? ((attrs['averageRating'] as num).toDouble() / 20.0)
            : null,
        startDate: attrs['startDate'] as String?,
        extra: entry,
      );
    }).toList();
  }

  // -- Sync -----------------------------------------------------------------

  @override
  Future<Track> updateTrack(Track track) async {
    if (track.mediaId == null) {
      throw TrackerException('Cannot update a track without a media id');
    }
    // Kitsu stores library entries under /library-entries. We need to know
    // the entry id (not the media id) to PATCH. We fetch it first.
    final endpoint = track.mediaType == TrackMediaType.anime ? 'anime' : 'manga';
    final listUrl = Uri.parse('$_kApiBase/library-entries').replace(
      queryParameters: <String, String>{
        'filter[$endpoint_id]': track.mediaId!,
        'filter[user_id]': _credentials?.userId ?? '@me',
        'include': '$endpoint',
      },
    );
    final listResp = await authenticatedRequest(
      listUrl.toString(),
      headers: <String, String>{'User-Agent': userAgent, ..._jsonHeaders('')},
    );
    Map<String, dynamic>? existing;
    if (listResp.statusCode == 200) {
      final body = jsonDecode(listResp.body) as Map<String, dynamic>;
      final items = (body['data'] as List?) ?? const <dynamic>[];
      if (items.isNotEmpty) {
        existing = items.first as Map<String, dynamic>;
      }
    }

    final entryId = existing?['id'] as String?;
    final attrs = <String, dynamic>{
      'progress': track.lastReadChapter ?? 0,
      if (track.status != null) 'status': _statusToKitsu(track.status!),
      if (track.score != null)
        'ratingTwenty': ((track.score! / scoreMax) * 20).round().clamp(0, 20),
      if (track.isPrivate != null) 'private': track.isPrivate,
      if (track.startReadAt != null)
        'startedAt': _isoDate(track.startReadAt!),
      if (track.finishReadAt != null)
        'finishedAt': _isoDate(track.finishReadAt!),
    };
    final payload = <String, dynamic>{
      'data': <String, dynamic>{
        'type': 'libraryEntries',
        if (entryId != null) 'id': entryId,
        'attributes': attrs,
        'relationships': <String, dynamic>{
          endpoint: <String, dynamic>{
            'data': <String, dynamic>{
              'type': endpoint,
              'id': track.mediaId,
            },
          },
          'user': <String, dynamic>{
            'data': <String, dynamic>{
              'type': 'users',
              'id': _credentials?.userId ?? '@me',
            },
          },
        },
      },
    };

    final method = entryId == null ? 'POST' : 'PATCH';
    final targetUrl = entryId == null
        ? '$_kApiBase/library-entries'
        : '$_kApiBase/library-entries/$entryId';
    final response = await authenticatedRequest(
      targetUrl,
      method: method,
      headers: <String, String>{
        'User-Agent': userAgent,
        'Content-Type': 'application/vnd.api+json',
        'Accept': 'application/vnd.api+json',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'Kitsu update failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final saved = (body['data'] as Map<String, dynamic>?)?['attributes']
        as Map<String, dynamic>?;
    if (saved != null) _mergeAttributes(track, saved);
    track.hasPendingChanges = false;
    track.lastSyncedAt = DateTime.now().millisecondsSinceEpoch;
    track.isSynced = true;
    track.lastSyncFailed = false;
    track.lastError = null;
    return track;
  }

  @override
  Future<Track?> getTrack(String mediaId) async {
    final url = Uri.parse('$_kApiBase/library-entries').replace(
      queryParameters: <String, String>{
        'filter[manga_id]': mediaId,
        'filter[user_id]': _credentials?.userId ?? '@me',
      },
    );
    final response = await authenticatedRequest(
      url.toString(),
      headers: <String, String>{'User-Agent': userAgent, ..._jsonHeaders('')},
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['data'] as List?) ?? const <dynamic>[];
    if (items.isEmpty) return null;
    final entry = items.first as Map<String, dynamic>;
    final attrs = entry['attributes'] as Map<String, dynamic>? ?? const {};
    final track = Track(
      syncId: id,
      mediaId: mediaId,
      mediaType: TrackMediaType.manga,
    );
    _mergeAttributes(track, attrs);
    return track;
  }

  void _mergeAttributes(Track track, Map<String, dynamic> attrs) {
    final status = attrs['status'] as String?;
    if (status != null) track.status = _statusFromKitsu(status);
    if (attrs['progress'] != null) {
      track.lastReadChapter = (attrs['progress'] as num).toInt();
    }
    if (attrs['ratingTwenty'] != null) {
      final r = (attrs['ratingTwenty'] as num).toInt();
      track.score = ((r / 20) * scoreMax).round().clamp(0, scoreMax);
    }
    if (attrs['private'] != null) track.isPrivate = attrs['private'] as bool;
    if (attrs['startedAt'] != null) {
      track.startReadAt = _parseIso(attrs['startedAt'] as String);
    }
    if (attrs['finishedAt'] != null) {
      track.finishReadAt = _parseIso(attrs['finishedAt'] as String);
    }
  }

  // -- Helpers --------------------------------------------------------------

  Map<String, String> _jsonHeaders(String token) {
    final headers = <String, String>{
      'Accept': 'application/vnd.api+json',
      'Content-Type': 'application/vnd.api+json',
      'User-Agent': userAgent,
    };
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static String _statusToKitsu(TrackStatus status) {
    switch (status) {
      case TrackStatus.reading:
        return 'current';
      case TrackStatus.completed:
        return 'completed';
      case TrackStatus.onHold:
        return 'on_hold';
      case TrackStatus.dropped:
        return 'dropped';
      case TrackStatus.planToRead:
        return 'planned';
    }
  }

  static TrackStatus _statusFromKitsu(String status) {
    switch (status) {
      case 'current':
        return TrackStatus.reading;
      case 'completed':
        return TrackStatus.completed;
      case 'on_hold':
        return TrackStatus.onHold;
      case 'dropped':
        return TrackStatus.dropped;
      case 'planned':
      default:
        return TrackStatus.planToRead;
    }
  }

  static String _isoDate(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toIso8601String();

  static int? _parseIso(String value) {
    try {
      return DateTime.parse(value).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
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
