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
// Shikimori tracker integration (simplified). Shikimori exposes a REST API
// at https://shikimori.one/api that is largely compatible with MAL. OAuth2
// authorisation-code flow with a client secret is used for login.

import 'dart:convert';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'package:lumina_reader/models/track.dart';
import 'package:lumina_reader/services/trackers/base_tracker.dart';

/// Lazily-opened Hive box used to persist Shikimori credentials.
Box<String>? _shikiCredsBox;

Future<Box<String>> _openCredsBox() async {
  if (_shikiCredsBox != null && _shikiCredsBox!.isOpen) return _shikiCredsBox!;
  _shikiCredsBox = await Hive.openBox<String>('tracker_shikimori_credentials');
  return _shikiCredsBox!;
}

/// Shikimori tracker (simplified).
///
/// Shikimori's API is a near-clone of MAL's REST surface. The OAuth2 flow
/// requires a client id and secret registered at
/// https://shikimori.one/oauth/applications. This implementation covers the
/// operations Lumina Reader needs: login, search, fetch user entry, and
/// update progress / status / score.
///
/// Note: Shikimori enforces a strict 1 RPS rate limit (5 RPS for paid
/// patrons) — callers should throttle accordingly.
class ShikimoriTracker extends Tracker {
  ShikimoriTracker({
    required this.clientIdValue,
    required this.clientSecretValue,
    this.redirectUriValue = 'lumina-reader://shikimori-callback',
    this.userAgent = 'LuminaReader/1.0',
  }) : super(
          id: TrackerSyncId.shikimori,
          name: 'Shikimori',
          supportsScore: true,
          supportsProgress: true,
          supportsStatus: true,
          supportsStartDate: true,
          supportsFinishDate: true,
          supportsRewatching: true,
          scoreMax: 10,
        );

  final String clientIdValue;
  final String clientSecretValue;
  final String redirectUriValue;
  final String userAgent;

  static const String _kAuthEndpoint =
      'https://shikimori.one/oauth/authorize';
  static const String _kTokenEndpoint =
      'https://shikimori.one/oauth/token';
  static const String _kApiBase = 'https://shikimori.one/api';

  static const String _kPrefsKey = 'tracker.shikimori.credentials';
  static const String _kStateKey = 'tracker.shikimori.oauthState';

  @override
  String get authorizationEndpoint => _kAuthEndpoint;

  @override
  String get tokenEndpoint => _kTokenEndpoint;

  @override
  String get clientId => clientIdValue;

  @override
  String get clientSecret => clientSecretValue;

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
        'redirect_uri': redirectUriValue,
        'response_type': 'code',
        'state': state,
      },
    );

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _extractScheme(redirectUriValue),
    );
    final callback = Uri.parse(resultUrl);
    if (callback.queryParameters['state'] != state) {
      throw TrackerException('OAuth state mismatch — possible CSRF attack');
    }
    final code = callback.queryParameters['code'];
    if (code == null) {
      throw TrackerException('No authorisation code returned by Shikimori');
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
        'User-Agent': userAgent,
      },
      body: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientIdValue,
        'client_secret': clientSecretValue,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'Shikimori token refresh failed: ${response.body}',
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
      Uri.parse('$_kApiBase/users/whoami'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return TrackerUser(
      userId: json['id']?.toString() ?? '',
      username: json['nickname'] as String? ?? json['name'] as String? ?? '',
      avatarUrl: json['image']?['x160'] as String? ?? '',
      profileUrl: json['url'] != null
          ? 'https://shikimori.one${json['url']}'
          : null,
      extra: json,
    );
  }

  // -- Search ---------------------------------------------------------------

  @override
  Future<List<TrackerSearchResult>> search(
    String query, {
    int limit = 20,
    TrackMediaType mediaType = TrackMediaType.manga,
  }) async {
    final kind = mediaType == TrackMediaType.anime ? 'animes' : 'mangas';
    final url = Uri.parse('$_kApiBase/$kind').replace(
      queryParameters: <String, String>{
        'search': query,
        'limit': limit.clamp(1, 50).toString(),
      },
    );
    final response = await authenticatedRequest(
      url.toString(),
      headers: <String, String>{'User-Agent': userAgent},
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Shikimori search failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final list = jsonDecode(response.body) as List;
    return list.cast<Map<String, dynamic>>().map((m) {
      return TrackerSearchResult(
        mediaId: m['id'].toString(),
        title: (m['russian'] ?? m['name'] ?? '') as String,
        coverUrl: m['image']?['original'] != null
            ? 'https://shikimori.one${m['image']['original']}'
            : '',
        trackingUrl: m['url'] != null
            ? 'https://shikimori.one${m['url']}'
            : '',
        totalChapters: (m['chapters'] ?? m['episodes']) == null
            ? null
            : ((m['chapters'] ?? m['episodes']) as num).toInt(),
        summary: m['description'] as String?,
        publishingStatus: m['status'] as String?,
        mediaType: mediaType,
        score: (m['score'] as String?) != null
            ? double.tryParse(m['score'] as String)
            : null,
        startDate: m['aired_on'] as String?,
        extra: m,
      );
    }).toList();
  }

  // -- Sync -----------------------------------------------------------------

  @override
  Future<Track> updateTrack(Track track) async {
    if (track.mediaId == null) {
      throw TrackerException('Cannot update a track without a media id');
    }
    final userRateId = await _findUserRateId(track.mediaId!);
    final body = <String, dynamic>{
      'user_rate': <String, dynamic>{
        'target_id': int.parse(track.mediaId!),
        'target_type':
            track.mediaType == TrackMediaType.anime ? 'Anime' : 'Manga',
        if (track.status != null) 'status': _statusToShiki(track.status!),
        if (track.lastReadChapter != null)
          'episodes': track.lastReadChapter,
        if (track.lastReadChapter != null)
          'chapters': track.lastReadChapter,
        if (track.score != null) 'score': track.score,
        if (track.startReadAt != null)
          'started_on': _shikiDate(track.startReadAt!),
        if (track.finishReadAt != null)
          'finished_on': _shikiDate(track.finishReadAt!),
        if (track.rewatchCount != null) 'rewatches': track.rewatchCount,
      },
    };
    final method = userRateId == null ? 'POST' : 'PUT';
    final url = userRateId == null
        ? '$_kApiBase/v2/user_rates'
        : '$_kApiBase/v2/user_rates/$userRateId';
    final response = await authenticatedRequest(
      url,
      method: method,
      headers: <String, String>{
        'User-Agent': userAgent,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'Shikimori update failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('id')) track.metadataJson = jsonEncode(json);
    track.hasPendingChanges = false;
    track.lastSyncedAt = DateTime.now().millisecondsSinceEpoch;
    track.isSynced = true;
    track.lastSyncFailed = false;
    track.lastError = null;
    return track;
  }

  @override
  Future<Track?> getTrack(String mediaId) async {
    final userRateId = await _findUserRateId(mediaId);
    if (userRateId == null) return null;
    final response = await authenticatedRequest(
      '$_kApiBase/v2/user_rates/$userRateId',
      headers: <String, String>{'User-Agent': userAgent},
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final track = Track(
      syncId: id,
      mediaId: mediaId,
      mediaType: TrackMediaType.manga,
    );
    _mergeRate(track, json);
    return track;
  }

  Future<String?> _findUserRateId(String mediaId) async {
    final url = Uri.parse('$_kApiBase/v2/user_rates').replace(
      queryParameters: <String, String>{
        'target_id': mediaId,
        'user_id': _credentials?.userId ?? '',
      },
    );
    final response = await authenticatedRequest(
      url.toString(),
      headers: <String, String>{'User-Agent': userAgent},
    );
    if (response.statusCode != 200) return null;
    final list = jsonDecode(response.body) as List;
    if (list.isEmpty) return null;
    return (list.first as Map<String, dynamic>)['id']?.toString();
  }

  void _mergeRate(Track track, Map<String, dynamic> json) {
    final status = json['status'] as String?;
    if (status != null) track.status = _statusFromShiki(status);
    final eps = json['episodes'] ?? json['chapters'];
    if (eps != null) track.lastReadChapter = (eps as num).toInt();
    if (json['score'] != null) track.score = (json['score'] as num).toInt();
    if (json['rewatches'] != null) {
      track.rewatchCount = (json['rewatches'] as num).toInt();
    }
    if (json['started_on'] != null) {
      track.startReadAt = _parseDate(json['started_on'] as String);
    }
    if (json['finished_on'] != null) {
      track.finishReadAt = _parseDate(json['finished_on'] as String);
    }
  }

  // -- Helpers --------------------------------------------------------------

  Map<String, String> _authHeaders(String token) {
    return <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'User-Agent': userAgent,
    };
  }

  static String _statusToShiki(TrackStatus status) {
    switch (status) {
      case TrackStatus.reading:
        return 'watching';
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

  static TrackStatus _statusFromShiki(String status) {
    switch (status) {
      case 'watching':
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

  static String _shikiDate(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static int? _parseDate(String value) {
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
