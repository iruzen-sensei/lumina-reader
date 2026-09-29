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

// EXTENSION REPO SERVICE — repository registration, sync and install for
// EVERY index format in the Tachiyomi / Aniyomi / Mihon / Mangayomi
// ecosystem (see repo_index_parser.dart):
//
//   * Mangayomi JSON array      (index.json)
//   * Tachiyomi/Aniyomi legacy  (index.min.json — pkg/apk/sources[])
//   * v2 JSON store             ({"name":…, "extensions":[…]})
//   * repo.json redirect        ({"index_v2": <url>})
//   * index.pb protobuf         (gzip'd, manga AND anime schema variants)
//
// Installing:
//   * multisrc template rows (madara / mangareader / …) — flag flip; the
//     native template in eval/native/ runs them;
//   * JS extensions — the .js from sourceCodeUrl is fetched into
//     Source.sourceCode and executed by the QuickJS host (eval/javascript/);
//   * APK extensions (Aniyomi/Mihon) — the APK is downloaded, base64-stored
//     in Source.sourceCode and executed by the on-device Dex bridge
//     (eval/mihon/ + services/extension_server.dart).
//
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';

import '../models/settings.dart' as db;
import '../models/source.dart' as db;
import '../services/http/m_client.dart';
import 'repo_index_parser.dart';

/// A repository the user added (or one of the default seeds), persisted in
/// the Settings row as JSON.
class ExtensionRepo {
  ExtensionRepo({
    required this.url,
    required this.name,
    this.addedAt,
    this.lastSyncAt,
    this.extensionCount = 0,
    this.lastError,
  });

  /// Index URL (normalized to point at a real index file).
  final String url;

  /// Display name (inferred from the URL or the store's own name).
  final String name;

  final DateTime? addedAt;
  final DateTime? lastSyncAt;
  final int extensionCount;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'addedAt': addedAt?.millisecondsSinceEpoch,
        'lastSyncAt': lastSyncAt?.millisecondsSinceEpoch,
        'extensionCount': extensionCount,
        'lastError': lastError,
      };

  static ExtensionRepo fromJson(Map<String, dynamic> json) => ExtensionRepo(
        url: json['url'] as String,
        name: json['name'] as String? ?? 'Repository',
        addedAt: json['addedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int)
            : null,
        lastSyncAt: json['lastSyncAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['lastSyncAt'] as int)
            : null,
        extensionCount: json['extensionCount'] as int? ?? 0,
        lastError: json['lastError'] as String?,
      );
}

/// One parsed index entry (Mangayomi format — kept for the tile DTO).
class RepoExtension {
  RepoExtension({
    required this.repoId,
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.typeSource,
    required this.version,
    this.iconUrl,
    this.dateFormat,
    this.dateFormatLocale,
    this.isNsfw = false,
    this.hasCloudflare = false,
    this.sourceCodeUrl,
    this.appMinVerReq,
    this.additionalParams,
    this.sourceCodeLanguage = 0,
    this.installed = false,
    this.updatable = false,
  });

  final int repoId;
  final String name;
  final String baseUrl;
  final String lang;
  final String typeSource;
  final String version;
  final String? iconUrl;
  final String? dateFormat;
  final String? dateFormatLocale;
  final bool isNsfw;
  final bool hasCloudflare;
  final String? sourceCodeUrl;
  final String? appMinVerReq;
  final String? additionalParams;
  final int sourceCodeLanguage;

  bool installed;
  bool updatable;

  /// Whether this build can run the extension natively.
  bool get isSupported =>
      const {'madara', 'mangareader', 'mangadex', 'mangabox', 'mmrcms'}
          .contains(typeSource.toLowerCase()) ||
      (typeSource.toLowerCase() == 'single' &&
          (sourceCodeLanguage == 1 || baseUrl.contains('mangadex.org')));
}

/// Default repositories seeded on first launch. Together they cover the
/// whole ecosystem: Mangayomi manga JS + templates, the anime/novel JS
/// corpus (eJ fork), the Mihon manga-APK universe (keiyoushi, 1.3k+
/// extensions via index.pb) and the official Aniyomi anime-APK repo.
const List<String> kDefaultRepoUrls = [
  // Mangayomi official manga index (363 entries; madara/mangareader
  // multisrc + JS singles incl. the 45 MangaDex language variants).
  'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json',
  // Anime JS corpus (61 entries — AllAnime, AnimeWorld, …; 22 are JS).
  'https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/anime_index.json',
  // Novel JS corpus (5 entries).
  'https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/novel_index.json',
  // Mihon/keiyoushi manga APK universe (1.3k+ extensions; index.pb).
  'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb',
  // Official Aniyomi anime APK repo (legacy index.min.json).
  'https://raw.githubusercontent.com/aniyomiorg/aniyomi-extensions/repo/index.min.json',
];

/// Kept for backwards compatibility with existing settings rows.
const String kDefaultRepoUrl =
    'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json';

class ExtensionRepoService {
  ExtensionRepoService(this._isar);

  final Isar _isar;

  http.Client? _client;
  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 30),
      );

  /// Long-haul client for extension DOWNLOADS (APKs run 1-25 MB; the old
  /// shared 15s client aborted mid-download on real mobile networks —
  /// THE "can't install keiyoushi/anime extensions" root cause).
  http.Client? _downloadClient;
  http.Client get _dl => _downloadClient ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(minutes: 3),
      );

  // -----------------------------------------------------------------------
  // Repo list persistence (Settings row)
  // -----------------------------------------------------------------------

  Future<List<ExtensionRepo>> getRepos() async {
    final s = await _isar.settings.get(227);
    final raw = s?.extensionReposJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ExtensionRepo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveRepos(List<ExtensionRepo> repos) async {
    await _isar.writeTxn(() async {
      final s = await _isar.settings.get(227) ?? db.Settings();
      s.extensionReposJson =
          jsonEncode(repos.map((r) => r.toJson()).toList());
      await _isar.settings.put(s);
    });
  }

  /// Seeds the default repositories on first run. Idempotent.
  Future<void> ensureDefaultRepo() async {
    final repos = await getRepos();
    var changed = false;
    for (final url in kDefaultRepoUrls) {
      if (repos.any((r) => r.url == url)) continue;
      await _addRepoRow(url, sync: false);
      changed = true;
    }
    if (changed) debugPrint('ExtensionRepoService: seeded default repos');
  }

  // -----------------------------------------------------------------------
  // URL normalization
  // -----------------------------------------------------------------------

  /// Candidate index URLs for a raw user-supplied URL. Tries the URL as
  /// given (when it already points at an index file) plus the standard
  /// index file names.
  List<String> candidateUrls(String rawUrl) {
    final clean = rawUrl.trim();
    final urls = <String>[clean];
    final lower = clean.toLowerCase();
    if (!lower.endsWith('.json') &&
        !lower.endsWith('.pb') &&
        !lower.endsWith('.pb.gz')) {
      final normalized =
          clean.endsWith('/') ? clean.substring(0, clean.length - 1) : clean;
      urls.addAll([
        '$normalized/index.min.json',
        '$normalized/index.json',
        '$normalized/index.pb',
        '$normalized/repo.json',
      ]);
    }
    return urls.toSet().toList();
  }

  String inferRepoName(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Repository';
    if (uri.host == 'raw.githubusercontent.com' &&
        uri.pathSegments.length >= 2) {
      return uri.pathSegments[1];
    }
    final segments = uri.pathSegments
        .where((s) =>
            s.isNotEmpty &&
            !s.endsWith('.json') &&
            !s.endsWith('.pb') &&
            s != '.dist' &&
            s != 'dist' &&
            s != 'build' &&
            s != '.build')
        .toList();
    return segments.isNotEmpty ? segments.first : uri.host;
  }

  // -----------------------------------------------------------------------
  // Fetch + parse (with redirect following)
  // -----------------------------------------------------------------------

  /// Fetches [url], gunzips/decodes and parses it. Follows repo.json /
  /// extensionListUrl redirects (depth 2) like Aniyomi/Mihon themselves do.
  Future<ParsedRepoIndex> _fetchAndParse(String url, {int depth = 0}) async {
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Repository returned HTTP ${res.statusCode}');
    }
    if (res.bodyBytes.length > 8 * 1024 * 1024) {
      throw Exception('Repository index too large (>8 MB) — refusing.');
    }
    final result = parseRepoIndex(res.bodyBytes, url);
    if (result.isRedirect) {
      if (depth >= 2) {
        throw Exception('Repository redirect chain too deep.');
      }
      return _fetchAndParse(result.redirectUrl!, depth: depth + 1);
    }
    return result.index!;
  }

  // -----------------------------------------------------------------------
  // Add / remove repos
  // -----------------------------------------------------------------------

  /// Validates + persists a repository. Returns the parsed extension count.
  /// ALL candidates are fetched in PARALLEL (a dead repo answers with
  /// timeouts — sequential probing took minutes); the parse with the most
  /// extensions wins, which also defeats keiyoushi's index.min.json stub
  /// ("Outdated App" — 2 entries) whose real catalog lives in index.pb.
  Future<int> addRepo(String rawUrl, {bool sync = true}) async {
    final urls = candidateUrls(rawUrl)
        .where((u) => u.startsWith('https://') || u.startsWith('http://'))
        .toList();
    if (urls.isEmpty) {
      throw Exception('Repository URL must start with http:// or https://');
    }

    // Fetch ALL candidates in parallel; each failure degrades to null and
    // the survivor with the most extensions wins.
    final results = <(String, ParsedRepoIndex)>[];
    await Future.wait(urls.map((u) async {
      try {
        results.add((u, await _fetchAndParse(u)));
      } catch (_) {
        // Candidate failed — other candidates may still work.
      }
    }));

    if (results.isEmpty) {
      throw Exception(
          'No readable index found (tried ${urls.length} candidate URLs '
          'at ${urls.first}). Supported: index.json, index.min.json, '
          'index.pb, repo.json.');
    }

    // Most extensions wins (ties → first in candidate order).
    results.sort((a, b) => b.$2.extensions.length.compareTo(
          a.$2.extensions.length,
        ));
    final (workingUrl, index) = results.first;
    if (index.extensions.isEmpty) {
      throw Exception('Repository index contains no extensions.');
    }

    final name =
        index.storeName?.isNotEmpty == true ? index.storeName! : inferRepoName(workingUrl);

    // SYNC FIRST, PERSIST SECOND: the old order registered the repo even
    // when the sync then failed — the user saw "Could not add repository"
    // but the broken repo appeared (and kept re-syncing) anyway.
    if (sync) {
      final count = await syncRepo(workingUrl);
      var repos = await getRepos();
      repos = repos.where((r) => r.url != workingUrl).toList()
        ..add(ExtensionRepo(
          url: workingUrl,
          name: name,
          addedAt: DateTime.now(),
        ));
      await _saveRepos(repos);
      return count;
    }
    var repos = await getRepos();
    repos = repos.where((r) => r.url != workingUrl).toList()
      ..add(ExtensionRepo(
        url: workingUrl,
        name: name,
        addedAt: DateTime.now(),
      ));
    await _saveRepos(repos);
    return index.extensions.length;
  }

  Future<void> _addRepoRow(String url, {required bool sync}) async {
    var repos = await getRepos();
    repos = repos.where((r) => r.url != url).toList()
      ..add(ExtensionRepo(url: url, name: inferRepoName(url), addedAt: DateTime.now()));
    await _saveRepos(repos);
  }

  Future<void> removeRepo(String url) async {
    final repos = await getRepos();
    await _saveRepos(repos.where((r) => r.url != url).toList());
    // Uninstall every catalog row that came from THIS repo — the old
    // prefix-match also caught sibling repos (…/repo vs …/repo2) and
    // matched EVERYTHING when a row's repo URL was empty.
    await _isar.writeTxn(() async {
      final rows = await _isar.sources
          .filter()
          .idStringContains('repo-')
          .findAll();
      final fromRepo = rows.where((r) => r.repo?.sourceUrl == url).toList();
      for (final r in fromRepo) {
        if (r.isEnabled == true) {
          r.isEnabled = false;
          await _isar.sources.put(r);
        }
      }
    });
  }

  // -----------------------------------------------------------------------
  // Sync + install
  // -----------------------------------------------------------------------

  /// Fetches the repo index and upserts the catalog Source rows (NOT
  /// installed). Existing installs keep their enabled state and downloaded
  /// code; versionLast is refreshed. Returns the number of SOURCE rows
  /// (an APK with 3 sources becomes 3 rows, like Aniyomi itself presents
  /// them).
  ///
  /// All rows are persisted in ONE write transaction — hundreds of
  /// individual writeTxns fired the sources watcher hundreds of times,
  /// which rebuilt the extensions sheet in a jank storm on every sync.
  Future<int> syncRepo(String url) async {
    final index = await _fetchAndParse(url);
    final repoName =
        index.storeName?.isNotEmpty == true ? index.storeName! : inferRepoName(url);

    // Resolve existing rows (read-only pass) so install state survives.
    final existingById = <String, db.Source>{};
    final existingRows = await _isar.sources
        .filter()
        .idStringContains('repo-')
        .findAll();
    for (final r in existingRows) {
      final key = r.idString;
      if (key != null) existingById[key] = r;
    }

    final batch = <db.Source>[];
    var skipped = 0;
    switch (index.format) {
      case RepoFormat.mangayomiJson:
        skipped = _syncMangayomi(index, repoName, url, existingById, batch);
      case RepoFormat.tachiyomiLegacyJson:
      case RepoFormat.protobuf:
      case RepoFormat.v2Json:
        skipped = _syncApkIndex(index, repoName, url, existingById, batch);
    }

    await _isar.writeTxn(() async => _isar.sources.putAll(batch));
    if (skipped > 0) {
      debugPrint('ExtensionRepoService.syncRepo: skipped $skipped malformed '
          'entries in $url');
    }

    // Update repo stats.
    final repos = await getRepos();
    for (var i = 0; i < repos.length; i++) {
      if (repos[i].url == url) {
        repos[i] = ExtensionRepo(
          url: repos[i].url,
          name: repoName,
          addedAt: repos[i].addedAt,
          lastSyncAt: DateTime.now(),
          extensionCount: batch.length,
        );
      }
    }
    await _saveRepos(repos);
    return batch.length;
  }

  /// Mangayomi-format entries: template rows + JS rows (sourceCodeUrl).
  int _syncMangayomi(ParsedRepoIndex index, String repoName, String url,
      Map<String, db.Source> existingById, List<db.Source> batch) {
    var malformed = 0;
    for (final ext in index.extensions) {
      final e = ext.mangayomiEntry;
      if (e == null) {
        malformed++;
        continue;
      }
      try {
        final id = e['id'];
        if (id is! int) {
          malformed++;
          continue;
        }
        final idString = 'repo-$repoName-$id';
        final existing = existingById[idString];
        final row = existing ?? db.Source();
        row.idString = idString;
        row.name = ext.name;
        row.customName = null;
        row.lang = ext.lang;
        row.baseUrl = ext.mangayomiEntry?['baseUrl'] as String? ?? '';
        row.apiUrl = e['apiUrl'] as String?;
        row.iconUrl = ext.iconUrl;
        row.version =
            existing?.version ?? (ext.versionName ?? '0.0.1');
        row.versionLast = ext.versionName ?? row.version;
        row.typeSource = e['typeSource'] as String? ?? '';
        row.dateFormat = e['dateFormat'] as String?;
        row.dateFormatLocale = e['dateFormatLocale'] as String?;
        row.additionalParams = e['additionalParams'] as String?;
        row.sourceCodeUrl = e['sourceCodeUrl'] as String?;
        row.appMinVerReq = e['appMinVerReq'] as String?;
        row.isNsfw = ext.isNsfw;
        row.hasCloudflare = e['hasCloudflare'] as bool? ?? false;
        row.isManga = !ext.isAnime && !ext.isNovel;
        row.isAnime = ext.isAnime;
        // Novels browse through the manga pipeline (text chapters).
        row.sourceCodeLanguage = switch (e['sourceCodeLanguage']) {
          1 => db.SourceCodeLanguage.javascript,
          _ => null,
        };
        // Newly discovered rows start NOT installed; existing rows keep
        // their install state AND downloaded code.
        row.isEnabled = existing?.isEnabled ?? false;
        if (existing?.sourceCode != null) row.sourceCode = existing!.sourceCode;
        row.isLocal = false;
        row.repo = db.Repo(
          name: repoName,
          sourceUrl: url,
          typeSource: row.typeSource,
          iconUrl: row.iconUrl,
          lang: row.lang,
          isManga: row.isManga,
          isNsfw: row.isNsfw,
          hasCloudflare: row.hasCloudflare,
        );
        row.lastUpdateAt = DateTime.now().millisecondsSinceEpoch;
        batch.add(row);
      } catch (_) {
        malformed++;
      }
    }
    return malformed;
  }

  /// APK formats (legacy JSON / protobuf / v2 JSON): one Source row per
  /// SOURCE inside each extension APK (Aniyomi's own presentation), all
  /// sharing the APK URL.
  int _syncApkIndex(ParsedRepoIndex index, String repoName, String url,
      Map<String, db.Source> existingById, List<db.Source> batch) {
    var skipped = 0;
    for (final ext in index.extensions) {
      try {
        final resolvedApkUrl = ext.apkUrl ?? '';
        final resolvedIcon = ext.iconUrl;
        if (resolvedApkUrl.isEmpty) {
          skipped++;
          continue;
        }

        final sources = ext.sources.isNotEmpty
            ? ext.sources
            : [
                ParsedRepoSource(
                    id: 0, name: ext.name, lang: ext.lang, baseUrl: '')
              ];
        for (final src in sources) {
          final idString = 'repo-$repoName-${ext.pkg}#${src.id}';
          final existing = existingById[idString];
          final row = existing ?? db.Source();
          row.idString = idString;
          row.name = src.name.isNotEmpty ? src.name : ext.name;
          row.customName = null;
          row.lang = src.lang.isNotEmpty ? src.lang : ext.lang;
          row.baseUrl = src.baseUrl;
          row.iconUrl = resolvedIcon ?? ext.iconUrl;
          row.version = existing?.version ?? (ext.versionName ?? '0');
          row.versionLast = ext.versionName ?? row.version;
          row.typeSource = ext.isAnime ? 'apk-anime' : 'apk-manga';
          row.isNsfw = ext.isNsfw;
          row.hasCloudflare = false;
          row.isManga = !ext.isAnime;
          row.isAnime = ext.isAnime;
          row.apiUrl = resolvedApkUrl; // APK download URL
          row.sourceCodeLanguage = db.SourceCodeLanguage.mihon;
          row.tags = [
            'apk',
            if (ext.pkg != null) 'pkg:${ext.pkg}',
            if (ext.versionCode != null) 'code:${ext.versionCode}',
            if (ext.isTorrent) 'torrent',
          ];
          row.isEnabled = existing?.isEnabled ?? false;
          if (existing?.sourceCode != null) {
            row.sourceCode = existing!.sourceCode;
          }
          row.isLocal = false;
          row.repo = db.Repo(
            name: repoName,
            sourceUrl: url,
            typeSource: row.typeSource,
            iconUrl: row.iconUrl,
            lang: row.lang,
            isManga: row.isManga,
            isNsfw: row.isNsfw,
            hasCloudflare: false,
          );
          row.lastUpdateAt = DateTime.now().millisecondsSinceEpoch;
          batch.add(row);
        }
      } catch (_) {
        skipped++;
      }
    }
    return skipped;
  }

  /// Syncs every registered repo. Errors per repo are captured on the repo
  /// entry instead of aborting the loop.
  Future<void> syncAll() async {
    final repos = await getRepos();
    for (final repo in repos) {
      try {
        await syncRepo(repo.url);
      } catch (e) {
        try {
          final updated = await getRepos();
          await _saveRepos([
            for (final r in updated)
              if (r.url == repo.url)
                ExtensionRepo(
                  url: r.url,
                  name: r.name,
                  addedAt: r.addedAt,
                  lastSyncAt: r.lastSyncAt,
                  extensionCount: r.extensionCount,
                  lastError: e.toString(),
                )
              else
                r,
          ]);
        } catch (e2) {
          // Even the error-recording path must never propagate — syncAll
          // runs as an unawaited background task from main().
          debugPrint('ExtensionRepoService.syncAll: recording failure for '
              '${repo.url} failed too: $e2');
        }
      }
    }
  }

  // -----------------------------------------------------------------------
  // Install / uninstall (the real deal: APK download + JS fetch)
  // -----------------------------------------------------------------------

  /// Installs an extension. For template rows this is a flag flip; for JS
  /// extensions the source code is fetched; for APK extensions the APK is
  /// downloaded with REAL PROGRESS (base64 into the row, exactly like
  /// upstream Mangayomi).
  ///
  /// [onProgress] receives (bytesDownloaded, totalBytes) during the
  /// download so the UI can show honest progress instead of an eternal
  /// spinner.
  Future<void> install(String idString,
      {void Function(int downloaded, int? total)? onProgress}) async {
    final row = await _isar.sources
        .filter()
        .idStringEqualTo(idString)
        .findFirst();
    // Silent no-ops made the install button LOOK broken (no feedback, no
    // error). A missing row is a real failure — surface it.
    if (row == null) {
      throw StateError('This extension is not in any synced repository. '
          'Refresh the repository list and try again.');
    }

    // JS extension: fetch the source code.
    if (row.sourceCodeLanguage == db.SourceCodeLanguage.javascript) {
      final codeUrl = row.sourceCodeUrl;
      if ((row.sourceCode == null || row.sourceCode!.isEmpty) &&
          codeUrl != null &&
          codeUrl.isNotEmpty) {
        final bytes = await _download(codeUrl,
            maxBytes: 4 * 1024 * 1024, onProgress: onProgress);
        row.sourceCode = utf8.decode(bytes);
      }
    }

    // APK extension: download the APK (stored base64 — the /dalvik bridge
    // receives it per call and caches the loaded Dex by content hash).
    if (row.sourceCodeLanguage == db.SourceCodeLanguage.mihon) {
      final apkUrl = row.apiUrl;
      final hasUpdate =
          row.versionLast != null && row.versionLast != row.version;
      if ((row.sourceCode == null || row.sourceCode!.isEmpty || hasUpdate) &&
          apkUrl != null &&
          apkUrl.isNotEmpty) {
        final bytes = await _download(apkUrl,
            maxBytes: 80 * 1024 * 1024, onProgress: onProgress);
        row.sourceCode = base64Encode(bytes);
        row.version = row.versionLast ?? row.version;
      }
    }

    await _isar.writeTxn(() async {
      row.isEnabled = true;
      row.added = true;
      await _isar.sources.put(row);
    });
  }

  /// Streams a download through the long-haul client with byte progress.
  /// Retries once on transient failure (mobile networks).
  Future<Uint8List> _download(
    String url, {
    required int maxBytes,
    void Function(int downloaded, int? total)? onProgress,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final req = http.Request('GET', Uri.parse(url));
        final res = await _dl.send(req);
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode} for $url');
        }
        final total = res.contentLength;
        if (total != null && total > maxBytes) {
          throw Exception('Download larger than ${maxBytes ~/ (1024 * 1024)} MB'
              ' — refusing.');
        }
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in res.stream) {
          received += chunk.length;
          if (received > maxBytes) {
            throw Exception('Download exceeded ${maxBytes ~/ (1024 * 1024)} MB'
                ' — refusing.');
          }
          builder.add(chunk);
          onProgress?.call(received, total);
        }
        return builder.takeBytes();
      } catch (e) {
        lastError = e;
        // Only retry when nothing meaningful was received yet — a 90%
        // download that dies should restart from zero, not double-fail.
      }
    }
    throw Exception('Could not download extension ($url): $lastError');
  }

  Future<void> uninstall(String idString) async {
    await _isar.writeTxn(() async {
      final row = await _isar.sources
          .filter()
          .idStringEqualTo(idString)
          .findFirst();
      if (row == null) return;
      row.isEnabled = false;
      row.added = false;
      // Drop the downloaded payload (APK base64 can be tens of MB).
      row.sourceCode = null;
      await _isar.sources.put(row);
    });
  }

  /// Every catalog row (installed + available) from every registered repo.
  /// Installed entries sort first, then alphabetically.
  Future<List<db.Source>> catalog() async {
    final rows = await _isar.sources
        .filter()
        .idStringContains('repo-')
        .findAll();
    rows.sort((a, b) {
      final aInstalled = (a.isEnabled ?? false) ? 0 : 1;
      final bInstalled = (b.isEnabled ?? false) ? 0 : 1;
      if (aInstalled != bInstalled) return aInstalled - bInstalled;
      return (a.name ?? '').compareTo(b.name ?? '');
    });
    return rows;
  }

  /// Fires when the repo list changes (Settings row update).
  Stream<void> watchRepos() =>
      _isar.settings.watchLazy(fireImmediately: true);

  /// Fires when the extension catalog changes (Source rows upserted).
  Stream<void> watchCatalog() =>
      _isar.sources.watchLazy(fireImmediately: true);

  void dispose() {
    _client?.close();
    _client = null;
    _downloadClient?.close();
    _downloadClient = null;
  }
}
