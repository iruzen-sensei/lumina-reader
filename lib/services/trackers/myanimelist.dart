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
// MyAnimeList tracker integration. Implements the OAuth2 PKCE flow required
// by MAL's public API and exposes the REST endpoints used for progress /
// score / status sync and media search.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'package:lumina_reader/models/track.dart';
import 'package:lumina_reader/services/trackers/base_tracker.dart';

/// Lazily-opened Hive box used to persist MAL credentials.
Box<String>? _malCredsBox;

Future<Box<String>> _openCredsBox() async {
  if (_malCredsBox != null && _malCredsBox!.isOpen) return _malCredsBox!;
  _malCredsBox = await Hive.openBox<String>('tracker_mal_credentials');
  return _malCredsBox!;
}

/// MyAnimeList tracker.
///
/// MAL's public API uses OAuth2 with the PKCE extension. There is no client
/// secret — the client id alone authenticates the app. The flow is:
///
///   1. Generate a PKCE verifier + challenge.
///   2. Open the authorisation URL in the browser; the redirect carries the
///      `code` query parameter.
///   3. Exchange the code (and verifier) for an access token at
///      `https://myanimelist.net/v1/oauth2/token`.
///   4. Call the REST API at `https://api.myanimelist.net/v2/`.
///
/// Refresh tokens are supported and never expire (unless revoked by the
/// user). Access tokens are valid for ~31 days but we refresh them eagerly
/// when they are within 60s of expiry.
class MyAnimeListTracker extends Tracker {
  MyAnimeListTracker({
    required this.clientId,
    required this.clientSecretValue,
    this.redirectUri = 'lumina-reader://mal-callback',
    this.userAgent = 'LuminaReader/1.0 (https://github.com/lumina-reader)',
    SharedPreferencesAsync? prefs,
  })  : _prefs = prefs,
        super(
          id: TrackerSyncId.myanimelist,
          name: 'MyAnimeList',
          supportsScore: true,
          supportsProgress: true,
          supportsStatus: true,
          supportsStartDate: true,
          supportsFinishDate: true,
          supportsRewatching: true,
          scoreMax: 10,
        );

  /// MAL OAuth client id (registered at https://myanimelist.net/apiconfig).
  final String clientId;

  /// Optional client secret. MAL's public PKCE flow does not require one,
  /// but we keep the field for confidential clients.
  final String? clientSecretValue;

  /// Custom-scheme redirect URI used by [FlutterWebAuth2].
  final String redirectUri;

  /// User-Agent sent with every API request. MAL blocks requests without a
  /// recognisable UA.
  final String userAgent;

  static const String _kPrefsKey = 'tracker.mal.credentials';
  static const String _kVerifierKey = 'tracker.mal.pkceVerifier';
  static const String _kStateKey = 'tracker.mal.oauthState';

  // -- Endpoint URLs --------------------------------------------------------

  static const String _kAuthEndpoint =
      'https://myanimelist.net/v1/oauth2/authorize';
  static const String _kTokenEndpoint =
      'https://myanimelist.net/v1/oauth2/token';
  static const String _kApiBase = 'https://api.myanimelist.net/v2';

  @override
  String get authorizationEndpoint => _kAuthEndpoint;

  @override
  String get tokenEndpoint => _kTokenEndpoint;

  @override
  String get clientSecret => clientSecretValue ?? '';

  @override
  String get redirectUrl => redirectUri;

  @override
  bool get usesPkce => true;

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
    final verifier = Tracker.generateCodeVerifier();
    final challenge = Tracker.generateCodeChallenge(verifier);
    final state = Tracker.generateState();

    final box = await _openCredsBox();
    await box.put(_kVerifierKey, verifier);
    await box.put(_kStateKey, state);

    final authUrl = Uri.parse(_kAuthEndpoint).replace(queryParameters: <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
    });

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: _extractScheme(redirectUri),
    );

    final callback = Uri.parse(resultUrl);
    final returnedState = callback.queryParameters['state'];
    if (returnedState != state) {
      throw TrackerException('OAuth state mismatch — possible CSRF attack');
    }
    final code = callback.queryParameters['code'];
    if (code == null) {
      throw TrackerException('No authorisation code returned by MAL');
    }

    final creds = await exchangeAuthorizationCode(code, codeVerifier: verifier);
    final user = await _fetchCurrentUser(creds.accessToken);
    creds.userId = user?.userId;
    creds.username = user?.username;
    await persistCredentials(creds, cipher: _cipher);
    return creds;
  }

  @override
  @protected
  Future<OAuthCredentials> doRefreshToken(String refreshToken) async {
    final body = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
    };
    if (clientSecret.isNotEmpty) body['client_secret'] = clientSecret;

    final response = await http.post(
      Uri.parse(_kTokenEndpoint),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'MAL token refresh failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseTokenResponse(json);
  }

  // -- REST API -------------------------------------------------------------

  /// Fetches the currently authenticated user.
  @override
  Future<TrackerUser?> getCurrentUser() async {
    final token = await ensureValidToken();
    return _fetchCurrentUser(token);
  }

  Future<TrackerUser?> _fetchCurrentUser(String token) async {
    final response = await http.get(
      Uri.parse('$_kApiBase/users/@me'),
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'User-Agent': userAgent,
      },
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return TrackerUser(
      userId: json['id']?.toString() ?? '',
      username: json['name'] as String? ?? '',
      avatarUrl: (json['picture'] as String?)?.replaceAll('https://', 'https://'),
      profileUrl: json['name'] != null
          ? 'https://myanimelist.net/profile/${json['name']}'
          : null,
      extra: json,
    );
  }

  /// Searches the MAL catalogue for entries matching [query].
  ///
  /// [mediaType] selects between `manga` and `anime`. When omitted the
  /// tracker defaults to `manga`.
  @override
  Future<List<TrackerSearchResult>> search(
    String query, {
    int limit = 20,
    TrackMediaType mediaType = TrackMediaType.manga,
  }) async {
    final endpoint = mediaType == TrackMediaType.anime ? 'anime' : 'manga';
    final url = Uri.parse('$_kApiBase/$endpoint').replace(
      queryParameters: <String, String>{
        'q': query,
        'limit': limit.clamp(1, 100).toString(),
        'fields':
            'id,title,main_picture,synopsis,media_type,status,start_date,num_chapters,num_episodes,mean',
        'nsfw': 'true',
      },
    );
    final response = await authenticatedRequest(
      url.toString(),
      headers: <String, String>{'User-Agent': userAgent},
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'MAL search failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final nodes = (json['data'] as List?) ?? const <dynamic>[];
    return nodes.cast<Map<String, dynamic>>().map((node) {
      final entry = node['node'] as Map<String, dynamic>? ?? node;
      return TrackerSearchResult(
        mediaId: entry['id'].toString(),
        title: entry['title'] as String? ?? '',
        coverUrl: (entry['main_picture']?['large'] as String?) ??
            (entry['main_picture']?['medium'] as String?) ??
            '',
        trackingUrl:
            'https://myanimelist.net/$endpoint/${entry['id']}/${entry['title']}'
                .replaceAll(RegExp(r'\s+'), '_'),
        totalChapters: (entry['num_chapters'] as num?)?.toInt() ??
            (entry['num_episodes'] as num?)?.toInt(),
        summary: entry['synopsis'] as String?,
        publishingStatus: entry['status'] as String?,
        mediaType: mediaType,
        score: (entry['mean'] as num?)?.toDouble(),
        startDate: entry['start_date'] as String?,
        extra: entry,
      );
    }).toList();
  }

  /// Pushes the local state of [track] to MAL.
  @override
  Future<Track> updateTrack(Track track) async {
    if (track.mediaId == null) {
      throw TrackerException('Cannot update a track without a media id');
    }
    final endpoint = (track.mediaType == TrackMediaType.anime) ? 'anime' : 'manga';
    final url = '$_kApiBase/$endpoint/${track.mediaId}/my_list_status';

    final body = <String, String>{};
    if (supportsStatus && track.status != null) {
      body['status'] = _statusToMal(track.status!);
    }
    if (supportsProgress && track.lastReadChapter != null) {
      body[track.mediaType == TrackMediaType.anime ? 'num_watched_episodes' : 'num_chapters'] =
          track.lastReadChapter.toString();
    }
    if (supportsScore && track.score != null) {
      body['score'] = track.score.toString();
    }
    if (supportsStartDate && track.startReadAt != null) {
      body['start_date'] = _formatDate(track.startReadAt!);
    }
    if (supportsFinishDate && track.finishReadAt != null) {
      body['finish_date'] = _formatDate(track.finishReadAt!);
    }
    if (supportsRewatching && track.rewatchCount != null) {
      body[track.mediaType == TrackMediaType.anime
          ? 'num_times_rewatched'
          : 'num_times_reread'] = track.rewatchCount.toString();
    }
    if (track.isPrivate == true) body['is_private'] = 'true';

    final response = await authenticatedRequest(
      url,
      method: 'PUT',
      headers: <String, String>{
        'User-Agent': userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: Tracker.encodeFormBody(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'MAL update failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _mergeRemoteStatus(track, json);
    track.hasPendingChanges = false;
    track.lastSyncedAt = DateTime.now().millisecondsSinceEpoch;
    track.isSynced = true;
    track.lastSyncFailed = false;
    track.lastError = null;
    return track;
  }

  /// Fetches the remote state of an entry. MAL does not expose a per-entry
  /// lookup, so we hit the user list endpoint and filter.
  @override
  Future<Track?> getTrack(String mediaId) async {
    final response = await authenticatedRequest(
      '$_kApiBase/manga/$mediaId?fields=my_list_status',
      headers: <String, String>{'User-Agent': userAgent},
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final status = json['my_list_status'] as Map<String, dynamic>?;
    if (status == null) return null;
    final track = Track(syncId: id, mediaId: mediaId, mediaType: TrackMediaType.manga);
    _mergeRemoteStatus(track, status);
    return track;
  }

  void _mergeRemoteStatus(Track track, Map<String, dynamic> status) {
    final malStatus = status['status'] as String?;
    if (malStatus != null) track.status = _statusFromMal(malStatus);
    final chapters = status['num_chapters_read'] ??
        status['num_episodes_watched'] ??
        status['num_chapters'];
    if (chapters != null) track.lastReadChapter = (chapters as num).toInt();
    if (status['score'] != null) {
      track.score = (status['score'] as num).toInt();
    }
    if (status['is_rewatching'] == true || status['is_rereading'] == true) {
      track.isFavourite = false;
    }
    if (status['start_date'] != null) {
      track.startReadAt = _parseDate(status['start_date'] as String);
    }
    if (status['finish_date'] != null) {
      track.finishReadAt = _parseDate(status['finish_date'] as String);
    }
    if (status['num_times_rewatched'] != null ||
        status['num_times_reread'] != null) {
      track.rewatchCount =
          (status['num_times_rewatched'] ?? status['num_times_reread']) as int;
    }
  }

  // -- Status mapping -------------------------------------------------------

  static String _statusToMal(TrackStatus status) {
    switch (status) {
      case TrackStatus.reading:
        return 'reading';
      case TrackStatus.completed:
        return 'completed';
      case TrackStatus.onHold:
        return 'on_hold';
      case TrackStatus.dropped:
        return 'dropped';
      case TrackStatus.planToRead:
        return 'plan_to_read';
    }
  }

  static TrackStatus _statusFromMal(String status) {
    switch (status) {
      case 'reading':
        return TrackStatus.reading;
      case 'completed':
        return TrackStatus.completed;
      case 'on_hold':
        return TrackStatus.onHold;
      case 'dropped':
        return TrackStatus.dropped;
      case 'plan_to_read':
      default:
        return TrackStatus.planToRead;
    }
  }

  static String _formatDate(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static int? _parseDate(String value) {
    try {
      final dt = DateTime.parse(value);
      return dt.millisecondsSinceEpoch;
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
    await box.delete(_kVerifierKey);
    await box.delete(_kStateKey);
  }
}
