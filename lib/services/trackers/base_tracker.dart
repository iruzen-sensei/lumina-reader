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
// Abstract base class shared by every tracker integration (MyAnimeList,
// AniList, Kitsu, Shikimori, ...). Provides the OAuth authentication flow,
// the high-level sync primitives (score / status / progress), media search,
// token refresh logic and AES-GCM token encryption/decryption.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'package:lumina_reader/models/track.dart';

/// Thrown when a tracker operation fails for any reason (network error,
/// authentication failure, API error, ...).
class TrackerException implements Exception {
  TrackerException(this.message, {this.statusCode, this.cause});

  /// Human-readable description of the failure.
  final String message;

  /// HTTP status code returned by the tracker, if applicable.
  final int? statusCode;

  /// Optional underlying cause.
  final Object? cause;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (HTTP $statusCode)';
    return 'TrackerException$code: $message';
  }
}

/// Lightweight result of a media search on a tracker.
class TrackerSearchResult {
  TrackerSearchResult({
    required this.mediaId,
    required this.title,
    required this.coverUrl,
    required this.trackingUrl,
    this.totalChapters,
    this.summary,
    this.publishingStatus,
    this.mediaType,
    this.score,
    this.startDate,
    this.extra,
  });

  /// Identifier of the entry on the tracker service.
  final String mediaId;

  /// Display title.
  final String title;

  /// Cover art URL.
  final String coverUrl;

  /// Direct URL to the entry on the tracker service.
  final String trackingUrl;

  /// Total number of chapters / episodes the entry has. `-1` means unknown.
  final int? totalChapters;

  /// Short synopsis / description.
  final String? summary;

  /// Publishing / airing status string returned by the tracker.
  final String? publishingStatus;

  /// Type of media the entry refers to.
  final TrackMediaType? mediaType;

  /// Aggregate score on the tracker (0..10 on most trackers).
  final double? score;

  /// Start date of the entry, as an ISO-8601 string.
  final String? startDate;

  /// Tracker-specific extra metadata (JSON-decodable map).
  final Map<String, dynamic>? extra;

  @override
  String toString() =>
      'TrackerSearchResult(mediaId: $mediaId, title: $title, type: $mediaType)';
}

/// Snapshot of the currently authenticated user on a tracker.
class TrackerUser {
  TrackerUser({
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.profileUrl,
    this.extra,
  });

  final String userId;
  final String username;
  final String? avatarUrl;
  final String? profileUrl;
  final Map<String, dynamic>? extra;

  @override
  String toString() => 'TrackerUser($username)';
}

/// Credentials returned by the OAuth exchange step.
class OAuthCredentials {
  OAuthCredentials({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.tokenType = 'Bearer',
    this.scope,
    this.userId,
    this.username,
  });

  /// OAuth2 access token.
  final String accessToken;

  /// OAuth2 refresh token (optional — some flows return a long-lived access
  /// token without a refresh token).
  final String? refreshToken;

  /// Timestamp (milliseconds since epoch) at which [accessToken] expires.
  final int expiresAt;

  /// Token type (almost always `Bearer`).
  final String tokenType;

  /// OAuth2 scopes granted by the user.
  final String? scope;

  /// Identifier of the authenticated user, if returned by the token endpoint.
  final String? userId;

  /// Username of the authenticated user, if returned by the token endpoint.
  final String? username;

  /// Returns `true` when the access token has expired (with a 60s safety
  /// margin).
  bool get isExpired =>
      expiresAt <= DateTime.now().millisecondsSinceEpoch + 60000;

  /// Serialises the credentials into a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt,
        'tokenType': tokenType,
        'scope': scope,
        'userId': userId,
        'username': username,
      };

  /// Deserialises credentials from a JSON map.
  factory OAuthCredentials.fromJson(Map<String, dynamic> json) =>
      OAuthCredentials(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String?,
        expiresAt: (json['expiresAt'] as num).toInt(),
        tokenType: (json['tokenType'] as String?) ?? 'Bearer',
        scope: json['scope'] as String?,
        userId: json['userId'] as String?,
        username: json['username'] as String?,
      );
}

/// Helper that encrypts / decrypts OAuth tokens with AES-GCM.
///
/// The class derives a 256-bit AES key from a user-supplied passphrase using
/// PBKDF2-HMAC-SHA256 (100k iterations) over a per-installation random salt.
/// Tokens are encrypted with a fresh 96-bit nonce per call; the resulting
/// ciphertext and 128-bit auth tag are stored alongside the nonce and salt.
///
/// On-disk format (all big-endian):
///
///     version(1) | salt(16) | nonce(12) | ciphertext(N) | tag(16)
///
/// `package:encrypt` exposes AES-GCM via PointyCastle. The auth tag is
/// appended to the ciphertext by the library; we slice it off manually to
/// keep the layout explicit and version-stable.
class TokenCipher {
  TokenCipher._(this._passphrase);

  /// Magic byte that identifies the v1 ciphertext format.
  static const int _kVersion = 1;

  /// Number of PBKDF2 iterations used to derive the AES key.
  static const int _kPbkdf2Iterations = 100000;

  /// Length (in bytes) of the per-installation salt.
  static const int _kSaltLength = 16;

  /// Length (in bytes) of the AES-GCM nonce.
  static const int _kNonceLength = 12;

  /// Length (in bytes) of the AES-GCM auth tag.
  static const int _kTagLength = 16;

  final String _passphrase;

  /// Creates a [TokenCipher] for the given passphrase.
  factory TokenCipher.fromPassphrase(String passphrase) =>
      TokenCipher._(passphrase);

  /// Encrypts [plaintext] and returns a base64-encoded payload.
  String encryptToken(String plaintext) {
    final rng = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(_kNonceLength, (_) => rng.nextInt(256)),
    );
    final salt = Uint8List.fromList(
      List<int>.generate(_kSaltLength, (_) => rng.nextInt(256)),
    );
    final keyBytes = _pbkdf2(_passphrase, salt, _kPbkdf2Iterations, 32);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.gcm),
    );
    final encrypted = encrypter.encrypt(plaintext, iv: encrypt.IV(nonce));

    // `encrypted.bytes` is ciphertext || tag for GCM in package:encrypt.
    final buffer = <int>[
      _kVersion,
      ...salt,
      ...nonce,
      ...encrypted.bytes,
    ];
    return base64.encode(buffer);
  }

  /// Decrypts a base64-encoded payload produced by [encryptToken].
  String decryptToken(String payload) {
    final bytes = base64.decode(payload);
    if (bytes.isEmpty || bytes[0] != _kVersion) {
      throw TrackerException('Unsupported token ciphertext version');
    }
    final salt = Uint8List.fromList(
      bytes.sublist(1, 1 + _kSaltLength),
    );
    final nonce = Uint8List.fromList(
      bytes.sublist(1 + _kSaltLength, 1 + _kSaltLength + _kNonceLength),
    );
    final ctWithTag = Uint8List.fromList(
      bytes.sublist(1 + _kSaltLength + _kNonceLength),
    );
    final keyBytes = _pbkdf2(_passphrase, salt, _kPbkdf2Iterations, 32);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.gcm),
    );
    final decrypted = encrypter.decrypt(
      encrypt.Encrypted(ctWithTag),
      iv: encrypt.IV(nonce),
    );
    return decrypted;
  }

  /// Synchronous PBKDF2-HMAC-SHA256 key derivation.
  ///
  /// Implemented on top of `package:crypto`'s [crypto.Hmac] because the
  /// upstream PBKDF2 helper is async-only and we want the cipher to stay
  /// synchronous (it is called from tight storage paths).
  static Uint8List _pbkdf2(
    String passphrase,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final passphraseBytes = utf8.encode(passphrase);
    final hmac = crypto.Hmac(crypto.sha256, passphraseBytes);
    final blocks = (keyLength + 31) ~/ 32;
    final output = <int>[];

    for (var blockIndex = 1; blockIndex <= blocks; blockIndex++) {
      final blockBytes = <int>[
        ...salt,
        (blockIndex >> 24) & 0xFF,
        (blockIndex >> 16) & 0xFF,
        (blockIndex >> 8) & 0xFF,
        blockIndex & 0xFF,
      ];
      var u = Uint8List.fromList(hmac.convert(blockBytes).bytes);
      final result = Uint8List(32)..setRange(0, 32, u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < 32; j++) {
          result[j] ^= u[j];
        }
      }
      output.addAll(result);
    }

    return Uint8List.fromList(output.sublist(0, keyLength));
  }
}

/// Abstract base class every tracker integration extends.
///
/// Concrete trackers implement the platform-specific network calls; the base
/// class provides:
///   * the OAuth state machine (`login`, `logout`, `refreshIfNeeded`),
///   * high-level sync primitives (`updateProgress`, `updateScore`,
///     `updateStatus`) that delegate to `updateTrack`,
///   * media search,
///   * AES-GCM-backed persistent storage of OAuth tokens.
abstract class Tracker {
  Tracker({
    required this.id,
    required this.name,
    this.supportsScore = true,
    this.supportsProgress = true,
    this.supportsStatus = true,
    this.supportsStartDate = true,
    this.supportsFinishDate = true,
    this.supportsRewatching = false,
    this.scoreMax = 10,
  });

  /// Stable identifier of this tracker (mirrors [TrackerSyncId]).
  final TrackerSyncId id;

  /// Human-readable name (e.g. `MyAnimeList`).
  final String name;

  /// Whether the tracker accepts score updates.
  final bool supportsScore;

  /// Whether the tracker accepts progress updates.
  final bool supportsProgress;

  /// Whether the tracker accepts status updates.
  final bool supportsStatus;

  /// Whether the tracker records a start date.
  final bool supportsStartDate;

  /// Whether the tracker records a finish date.
  final bool supportsFinishDate;

  /// Whether the tracker supports rewatch / reread counters.
  final bool supportsRewatching;

  /// Maximum score accepted by the tracker.
  final int scoreMax;

  /// In-memory cache of the current credentials. Persisted through
  /// [persistCredentials] whenever they change.
  OAuthCredentials? _credentials;

  /// Optional cipher used to encrypt tokens at rest. When `null` tokens are
  /// stored in plain text (only recommended for debug builds).
  TokenCipher? _cipher;

  /// Sets the [TokenCipher] used to protect OAuth tokens at rest. Must be
  /// called before [login] for the cipher to take effect.
  void setTokenCipher(TokenCipher cipher) => _cipher = cipher;

  /// Returns the current credentials, or `null` when the user is not logged
  /// in.
  OAuthCredentials? get credentials => _credentials;

  /// Returns `true` when the user is logged in (i.e. we have an access
  /// token that has not expired).
  bool get isLoggedIn =>
      _credentials != null && !_credentials!.isExpired;

  /// Returns the list of [TrackStatus] values the tracker supports.
  List<TrackStatus> get supportedStatuses => const <TrackStatus>[
        TrackStatus.reading,
        TrackStatus.completed,
        TrackStatus.onHold,
        TrackStatus.dropped,
        TrackStatus.planToRead,
      ];

  // -- OAuth authentication flow -------------------------------------------

  /// Authorisation endpoint URL the user is redirected to.
  String get authorizationEndpoint;

  /// Token endpoint URL where the authorisation code is exchanged for an
  /// access token.
  String get tokenEndpoint;

  /// OAuth2 client id.
  String get clientId;

  /// OAuth2 client secret (empty for PKCE / public clients).
  String get clientSecret => '';

  /// Redirect URL the tracker calls back after the user authorises the app.
  String get redirectUrl;

  /// OAuth2 scopes requested by the tracker.
  String get scopes => '';

  /// Returns `true` when the tracker uses the PKCE extension.
  bool get usesPkce => false;

  /// Opens the OAuth authorisation URL in the platform browser / WebView and
  /// waits for the redirect. Returns the credentials obtained from the token
  /// endpoint.
  ///
  /// Implementations must call [exchangeAuthorizationCode] with the code
  /// returned by the redirect and persist the result via
  /// [persistCredentials].
  Future<OAuthCredentials> login();

  /// Logs the user out, clearing any cached credentials.
  Future<void> logout() async {
    _credentials = null;
    await clearPersistedCredentials();
  }

  /// Refreshes the access token using the refresh token. Throws
  /// [TrackerException] if the tracker does not support refresh or the
  /// refresh failed.
  Future<OAuthCredentials> refreshToken() async {
    if (_credentials?.refreshToken == null) {
      throw TrackerException('No refresh token available for $name');
    }
    final creds = await doRefreshToken(_credentials!.refreshToken!);
    _credentials = creds;
    await persistCredentials(creds, cipher: _cipher);
    return creds;
  }

  /// Ensures a non-expired access token is available, refreshing it if
  /// necessary. Returns the access token.
  Future<String> ensureValidToken() async {
    final creds = _credentials;
    if (creds == null) {
      throw TrackerException('Not logged in to $name');
    }
    if (!creds.isExpired) return creds.accessToken;
    final refreshed = await refreshToken();
    return refreshed.accessToken;
  }

  /// Tracker-specific refresh implementation. Must return the new
  /// credentials.
  @protected
  Future<OAuthCredentials> doRefreshToken(String refreshToken);

  /// Exchanges an authorisation code (obtained from the redirect) for a set
  /// of credentials. Subclasses may override to add tracker-specific
  /// parameters (e.g. MAL's PKCE verifier).
  Future<OAuthCredentials> exchangeAuthorizationCode(
    String code, {
    String? codeVerifier,
  }) async {
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': clientId,
      'redirect_uri': redirectUrl,
    };
    if (clientSecret.isNotEmpty) body['client_secret'] = clientSecret;
    if (codeVerifier != null) body['code_verifier'] = codeVerifier;
    return _postToken(body);
  }

  /// Low-level helper that POSTs a token request and parses the response.
  Future<OAuthCredentials> _postToken(Map<String, String> body) async {
    final response = await http.post(
      Uri.parse(tokenEndpoint),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TrackerException(
        'Token request failed: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseTokenResponse(json);
  }

  /// Parses a token endpoint response into [OAuthCredentials].
  ///
  /// Subclasses can override to extract tracker-specific fields such as the
  /// user id.
  OAuthCredentials parseTokenResponse(Map<String, dynamic> json) {
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return OAuthCredentials(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
      tokenType: (json['token_type'] as String?) ?? 'Bearer',
      scope: json['scope'] as String?,
    );
  }

  // -- Sync primitives ------------------------------------------------------

  /// Pushes the local state of [track] to the tracker. Returns the updated
  /// [Track] (with refreshed remote state merged in).
  Future<Track> updateTrack(Track track);

  /// Fetches the remote state of an entry identified by [mediaId]. Returns
  /// `null` when the entry is not in the user's list.
  Future<Track?> getTrack(String mediaId);

  /// Updates the reading / watching progress on the tracker.
  Future<Track> updateProgress(Track track, int progress) async {
    track.lastReadChapter = progress;
    track.hasPendingChanges = true;
    return updateTrack(track);
  }

  /// Updates the score on the tracker.
  Future<Track> updateScore(Track track, int score) async {
    if (!supportsScore) {
      throw TrackerException('$name does not support score updates');
    }
    track.score = score.clamp(0, scoreMax);
    track.hasPendingChanges = true;
    return updateTrack(track);
  }

  /// Updates the status on the tracker.
  Future<Track> updateStatus(Track track, TrackStatus status) async {
    if (!supportsStatus) {
      throw TrackerException('$name does not support status updates');
    }
    track.status = status;
    track.hasPendingChanges = true;
    return updateTrack(track);
  }

  /// Convenience wrapper that updates score, status and progress in a single
  /// round-trip.
  Future<Track> updateAll({
    required Track track,
    int? progress,
    int? score,
    TrackStatus? status,
    int? startReadAt,
    int? finishReadAt,
    int? rewatchCount,
    bool? isPrivate,
    List<String>? tags,
    String? notes,
  }) async {
    if (progress != null && supportsProgress) track.lastReadChapter = progress;
    if (score != null && supportsScore) track.score = score.clamp(0, scoreMax);
    if (status != null && supportsStatus) track.status = status;
    if (startReadAt != null && supportsStartDate) track.startReadAt = startReadAt;
    if (finishReadAt != null && supportsFinishDate) track.finishReadAt = finishReadAt;
    if (rewatchCount != null && supportsRewatching) track.rewatchCount = rewatchCount;
    if (isPrivate != null) track.isPrivate = isPrivate;
    if (tags != null) track.tags = tags;
    if (notes != null) track.notes = notes;
    track.hasPendingChanges = true;
    return updateTrack(track);
  }

  // -- Search ---------------------------------------------------------------

  /// Searches the tracker for entries matching [query]. Returns up to
  /// [limit] results.
  Future<List<TrackerSearchResult>> search(String query, {int limit = 20});

  /// Resolves the tracker media id for a [Manga] / anime entry. Subclasses
  /// can override to use cached mappings (e.g. AniList -> MAL id table).
  Future<String?> resolveMediaId({
    String? title,
    String? anilistId,
    String? malId,
    TrackMediaType? mediaType,
  }) async {
    if (malId != null) return malId;
    if (anilistId != null) return anilistId;
    if (title == null || title.isEmpty) return null;
    final results = await search(title, limit: 1);
    return results.isEmpty ? null : results.first.mediaId;
  }

  // -- User -----------------------------------------------------------------

  /// Returns the currently authenticated user, or `null` when not logged in.
  Future<TrackerUser?> getCurrentUser();

  // -- Persistence ----------------------------------------------------------

  /// Persists [creds] to disk. The default implementation encrypts the
  /// credentials with [cipher] (when provided) and delegates to
  /// [persistCredentialsImpl] which subclasses must implement.
  Future<void> persistCredentials(
    OAuthCredentials creds, {
    TokenCipher? cipher,
  }) async {
    final payload = jsonEncode(creds.toJson());
    final stored = cipher == null ? payload : cipher.encryptToken(payload);
    await persistCredentialsImpl(stored, encrypted: cipher != null);
  }

  /// Loads persisted credentials from disk.
  Future<OAuthCredentials?> loadCredentials({TokenCipher? cipher}) async {
    final stored = await loadCredentialsImpl();
    if (stored == null) return null;
    final plaintext = cipher == null ? stored : cipher.decryptToken(stored);
    final json = jsonDecode(plaintext) as Map<String, dynamic>;
    return OAuthCredentials.fromJson(json);
  }

  /// Subclass hook for persisting the (optionally encrypted) credential
  /// blob.
  @protected
  Future<void> persistCredentialsImpl(String blob, {required bool encrypted});

  /// Subclass hook for loading the persisted credential blob.
  @protected
  Future<String?> loadCredentialsImpl();

  /// Subclass hook for clearing persisted credentials.
  @protected
  Future<void> clearPersistedCredentials();

  /// Loads the persisted credentials into [_credentials]. Called by the app
  /// at startup to restore a previous session.
  Future<bool> restoreSession() async {
    final creds = await loadCredentials(cipher: _cipher);
    if (creds == null) return false;
    _credentials = creds;
    if (creds.isExpired && creds.refreshToken != null) {
      try {
        await refreshToken();
      } catch (_) {
        // Refresh failures are non-fatal — the user will be asked to log in
        // again on the next protected operation.
        return false;
      }
    }
    return true;
  }

  // -- Helpers --------------------------------------------------------------

  /// Generates a cryptographically secure PKCE code verifier (43..128 chars
  /// from the unreserved set).
  static String generateCodeVerifier({int length = 64}) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = Random.secure();
    return List<String>.generate(
      length,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
  }

  /// Derives the PKCE code challenge (S256) from [verifier].
  static String generateCodeChallenge(String verifier) {
    final digest = crypto.sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Generates a random state parameter for the OAuth flow.
  static String generateState({int length = 32}) {
    final rng = Random.secure();
    return base64Url
        .encode(List<int>.generate(length, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
  }

  /// Encodes a [Map] as a `application/x-www-form-urlencoded` body.
  static String encodeFormBody(Map<String, String> body) =>
      body.entries.map((e) {
        final k = Uri.encodeQueryComponent(e.key);
        final v = Uri.encodeQueryComponent(e.value);
        return '$k=$v';
      }).join('&');

  /// Sends an authenticated JSON request to [url]. The access token is
  /// injected automatically and refreshed when needed.
  Future<http.Response> authenticatedRequest(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    Object? body,
  }) async {
    final token = await ensureValidToken();
    final mergedHeaders = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      ...?headers,
    };
    final request = http.Request(method, Uri.parse(url));
    request.headers.addAll(mergedHeaders);
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is Map) {
        request.body = jsonEncode(body);
      }
    }
    final streamed = await request.send();
    return http.Response.fromStream(streamed);
  }
}
