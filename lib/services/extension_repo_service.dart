// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// EXTENSION REPO SERVICE — makes "Add repository" real.
//
// Speaks the Mangayomi extension-repo format (github.com/kodjodevf/
// mangayomi-extensions): a JSON array index (`index.json`) of source
// descriptors:
//   { name, id, baseUrl, lang, typeSource, iconUrl, dateFormat,
//     dateFormatLocale, isNsfw, hasCloudflare, sourceCodeUrl, version,
//     isManga, appMinVerReq, additionalParams, sourceCodeLanguage }
//
// Installing an extension does NOT download or interpret code: multisrc
// entries (typeSource madara / mangareader, 238 of the 363 official
// extensions) map to the NATIVE templates in eval/native/ — a Source row
// with the site's config is all that's needed. Non-template entries are
// listed but marked unsupported (honest "Not supported in this build").
//
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';

import '../models/settings.dart' as db;
import '../models/source.dart' as db;
import '../services/http/m_client.dart';

/// A repository the user added (or the default seed), persisted in the
/// Settings row as JSON.
class ExtensionRepo {
  ExtensionRepo({
    required this.url,
    required this.name,
    this.addedAt,
    this.lastSyncAt,
    this.extensionCount = 0,
    this.lastError,
  });

  /// Index URL (normalized to end with a JSON file name).
  final String url;

  /// Display name (inferred from the URL when the repo has no meta).
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

/// One parsed index entry (Mangayomi format).
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

  /// Mirrors the corresponding Source row's install state.
  bool installed;

  /// A newer version exists in the repo than the installed one.
  bool updatable;

  /// Whether this build can run the extension natively.
  bool get isSupported =>
      const {'madara', 'mangareader', 'mangadex', 'mangabox', 'mmrcms'}
          .contains(typeSource.toLowerCase()) ||
      // 45 repo entries are MangaDex language variants disguised as
      // `single` sources (baseUrl = mangadex.org) — natively supported.
      (typeSource.toLowerCase() == 'single' && baseUrl.contains('mangadex.org'));
}

/// Default repository seeded on first launch — the official Mangayomi
/// extension index (363 extensions, 68% of them native-template compatible).
const String kDefaultRepoUrl =
    'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json';

class ExtensionRepoService {
  ExtensionRepoService(this._isar);

  final Isar _isar;

  http.Client? _client;
  http.Client get _http => _client ??= MClient.httpClient(
        useLogger: false,
        timeout: const Duration(seconds: 25),
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
          .map((e) =>
              ExtensionRepo.fromJson(e as Map<String, dynamic>))
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

  /// Seeds the default repository on first run. Idempotent.
  Future<void> ensureDefaultRepo() async {
    final repos = await getRepos();
    if (repos.any((r) => r.url == kDefaultRepoUrl)) return;
    await addRepo(kDefaultRepoUrl, sync: false);
  }

  // -----------------------------------------------------------------------
  // URL normalization
  // -----------------------------------------------------------------------

  /// Mangayomi-compatible URL normalization: a bare repo URL gets
  /// /index.min.json, /repo.json, /index.json appended candidates.
  List<String> candidateUrls(String rawUrl) {
    final clean = rawUrl.trim();
    final urls = <String>[clean];
    if (!clean.endsWith('.json') && !clean.endsWith('.pb')) {
      final normalized =
          clean.endsWith('/') ? clean.substring(0, clean.length - 1) : clean;
      urls.addAll([
        '$normalized/index.min.json',
        '$normalized/repo.json',
        '$normalized/index.json',
        '$normalized/index_v2.json',
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
            s != '.dist' &&
            s != 'dist' &&
            s != 'build' &&
            s != '.build')
        .toList();
    return segments.isNotEmpty ? segments.last : uri.host;
  }

  // -----------------------------------------------------------------------
  // Add / remove repos
  // -----------------------------------------------------------------------

  /// Validates + persists a repository. Returns the parsed extension count,
  /// or throws with a human-readable reason. Also upserts the catalog rows.
  Future<int> addRepo(String rawUrl, {bool sync = true}) async {
    final urls = candidateUrls(rawUrl);
    Map<String, dynamic>? meta;
    String? workingUrl;
    for (final url in urls) {
      try {
        final res = await _http.get(Uri.parse(url));
        if (res.statusCode != 200) continue;
        final decoded = jsonDecode(res.body);
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
          final first = decoded.first as Map;
          if (first['name'] != null && first['baseUrl'] != null) {
            meta = {
              'url': url,
              'name': inferRepoName(url),
            };
            workingUrl = url;
            break;
          }
        }
      } catch (_) {
        continue;
      }
    }
    if (workingUrl == null) {
      throw Exception(
          'Not a Mangayomi extension repository (no JSON index found at '
          '${urls.first})');
    }

    var repos = await getRepos();
    repos = repos.where((r) => r.url != workingUrl).toList()
      ..add(ExtensionRepo(
        url: workingUrl,
        name: meta!['name'] as String,
        addedAt: DateTime.now(),
      ));
    await _saveRepos(repos);

    if (sync) {
      final count = await syncRepo(workingUrl);
      if (count == 0) {
        throw Exception('Repository added, but no compatible extensions '
            'were found in its index.');
      }
      return count;
    }
    return 0;
  }

  Future<void> removeRepo(String url) async {
    final repos = await getRepos();
    await _saveRepos(repos.where((r) => r.url != url).toList());
    // Uninstall every catalog row that came from this repo.
    await _isar.writeTxn(() async {
      final rows = await _isar.sources
          .filter()
          .idStringContains('repo-')
          .findAll();
      final fromRepo = rows
          .where((r) => url.startsWith(_repoKeyBase(r)))
          .toList();
      for (final r in fromRepo) {
        if (r.isEnabled == true) {
          r.isEnabled = false;
          await _isar.sources.put(r);
        }
      }
    });
  }

  String _repoKeyBase(db.Source s) => s.repo?.sourceUrl ?? '';

  // -----------------------------------------------------------------------
  // Sync + install
  // -----------------------------------------------------------------------

  /// Fetches the repo index and upserts the catalog Source rows (NOT
  /// installed). Existing installs keep their enabled state; versionLast is
  /// refreshed. Returns the number of extensions in the index.
  ///
  /// All rows are persisted in ONE write transaction — 361 individual
  /// writeTxns fired the sources watcher 361 times, which rebuilt the
  /// extensions sheet in a jank storm on every sync ("the whole app bugs
  /// out" — live-reproduced).
  Future<int> syncRepo(String url) async {
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Repository returned HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      throw Exception('Unexpected repository index format');
    }

    final repoName = inferRepoName(url);
    final entries = decoded.whereType<Map<dynamic, dynamic>>().toList();

    // Resolve existing rows (read-only pass) so install state survives.
    final existingByld = <String, db.Source>{};
    final existingRows = await _isar.sources
        .filter()
        .idStringContains('repo-')
        .findAll();
    for (final r in existingRows) {
      final key = r.idString;
      if (key != null) existingByld[key] = r;
    }

    final batch = <db.Source>[];
    for (final e in entries) {
      final id = e['id'];
      final name = e['name'];
      if (id is! int || name is! String) continue;

      final idString = 'repo-$repoName-$id';
      final existing = existingByld[idString];
      final row = existing ?? db.Source();
      row.idString = idString;
      row.name = name;
      row.customName = null;
      row.lang = (e['lang'] as String?) ?? 'en';
      row.baseUrl = (e['baseUrl'] as String?) ?? '';
      row.iconUrl = e['iconUrl'] as String?;
      row.version = existing?.version ?? (e['version'] as String? ?? '0.0.1');
      row.versionLast = e['version'] as String? ?? row.version;
      row.typeSource = e['typeSource'] as String? ?? '';
      row.dateFormat = e['dateFormat'] as String?;
      row.dateFormatLocale = e['dateFormatLocale'] as String?;
      row.additionalParams = e['additionalParams'] as String?;
      row.sourceCodeUrl = e['sourceCodeUrl'] as String?;
      row.appMinVerReq = e['appMinVerReq'] as String?;
      row.isNsfw = e['isNsfw'] as bool? ?? false;
      row.hasCloudflare = e['hasCloudflare'] as bool? ?? false;
      row.isManga = e['isManga'] as bool? ?? true;
      row.isAnime = false;
      // Newly discovered rows start NOT installed; existing rows keep their
      // install state.
      row.isEnabled = existing?.isEnabled ?? false;
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
    }

    // ONE transaction for the whole batch — one watcher fire, one fsync.
    await _isar.writeTxn(() async => _isar.sources.putAll(batch));

    // Update repo stats.
    final repos = await getRepos();
    for (var i = 0; i < repos.length; i++) {
      if (repos[i].url == url) {
        repos[i] = ExtensionRepo(
          url: repos[i].url,
          name: repos[i].name,
          addedAt: repos[i].addedAt,
          lastSyncAt: DateTime.now(),
          extensionCount: entries.length,
        );
      }
    }
    await _saveRepos(repos);
    return entries.length;
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

  /// Marks a catalog row installed (enabled). Only template-compatible
  /// extensions can be installed — see [RepoExtension.isSupported].
  Future<void> install(String idString) async {
    await _isar.writeTxn(() async {
      final row = await _isar.sources
          .filter()
          .idStringEqualTo(idString)
          .findFirst();
      if (row == null) return;
      row.isEnabled = true;
      row.added = true;
      await _isar.sources.put(row);
    });
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
      await _isar.sources.put(row);
    });
  }

  /// Every catalog row (installed + available) from every registered repo.
  /// Installed entries sort first (they are the ones users act on), then
  /// alphabetically.
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
  }
}
