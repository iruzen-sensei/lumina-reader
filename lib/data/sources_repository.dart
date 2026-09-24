// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// SOURCES REPOSITORY — installed extension sources + first-run seeding of
// built-in sources (currently: native MangaDex).

import 'package:isar/isar.dart';

import '../models/mappers.dart' as map;
import '../models/models.dart' as dto;
import '../models/source.dart' as db;
import '../providers/storage_provider.dart';

class SourcesRepository {
  SourcesRepository(StorageProvider storage) : _isar = storage.isar;
  final Isar _isar;

  /// Stable id for the built-in native MangaDex source.
  static const String mangadexIdString = 'builtin.mangadex';

  /// Verified-alive template sources seeded alongside MangaDex so a fresh
  /// install has REAL working content on day one (the default extension
  /// repo is ~60% dead domains — a bare install left Browse with a single
  /// source and, for users whose ISP blocks MangaDex, literally nothing).
  ///
  /// All were live-verified end-to-end (popular → detail → chapters →
  /// pages) before being added. They run through the same native
  /// madara/mangareader templates as repo-installed extensions.
  static const List<({String id, String name, String baseUrl,
      String template})> _seedSources = [
    (
      id: 'builtin.mangasushi',
      name: 'Mangasushi',
      baseUrl: 'https://mangasushi.org',
      template: 'madara',
    ),
    (
      id: 'builtin.lhtranslation',
      name: 'LHTranslation',
      baseUrl: 'https://lhtranslation.net',
      template: 'madara',
    ),
    (
      id: 'builtin.ravenscans',
      name: 'Raven Scans',
      baseUrl: 'https://ravenscans.com',
      template: 'mangareader',
    ),
  ];

  Future<List<dto.Source>> getSources() async {
    final sources = await _isar.sources.where().findAll();
    sources.sort((a, b) => a.displayName.compareTo(b.displayName));
    return sources.map(map.sourceToDto).toList();
  }

  Future<db.Source?> getSource(int id) => _isar.sources.get(id);

  Future<db.Source?> getSourceByIdString(String idString) async {
    return _isar.sources.filter().idStringEqualTo(idString).findFirst();
  }

  /// Installs a source (upsert by idString).
  Future<int> putSource(db.Source source) async {
    final existing = source.idString == null
        ? null
        : await getSourceByIdString(source.idString!);
    source.id = existing?.id ?? Isar.autoIncrement;
    return _isar.writeTxn(() async => _isar.sources.put(source));
  }

  Future<void> toggleEnabled(int sourceId) async {
    await _isar.writeTxn(() async {
      final s = await _isar.sources.get(sourceId);
      if (s == null) return;
      s.isEnabled = !(s.isEnabled ?? true);
      await _isar.sources.put(s);
    });
  }

  Future<void> remove(int sourceId) async {
    await _isar.writeTxn(() async {
      await _isar.sources.delete(sourceId);
    });
  }

  /// First-run seed: registers the built-in native sources. Idempotent —
  /// safe to call on every boot.
  Future<void> ensureBuiltinSources() async {
    final existing = await getSourceByIdString(mangadexIdString);
    if (existing == null) {
      final mangadex = db.Source(
        idString: mangadexIdString,
        name: 'MangaDex',
        lang: 'en',
        baseUrl: 'https://api.mangadex.org',
        version: '1.0.0',
        isManga: true,
        isAnime: false,
        isEnabled: true,
        isFullData: true,
        supportsLatest: true,
        supportsFilter: true,
        // Native Dart implementation — see eval/native/mangadex_source.dart.
        // `sourceCode` uses the reserved `builtin:` scheme which
        // getExtensionService() dispatches to native implementations.
        sourceCodeLanguage: db.SourceCodeLanguage.dart,
        sourceCode: 'builtin:mangadex',
      );
      await putSource(mangadex);
    }

    // Verified-alive template sources (see [_seedSources]).
    for (final s in _seedSources) {
      final row = await getSourceByIdString(s.id);
      if (row != null) continue;
      await putSource(db.Source(
        idString: s.id,
        name: s.name,
        lang: 'en',
        baseUrl: s.baseUrl,
        version: '1.0.0',
        typeSource: s.template,
        isManga: true,
        isAnime: false,
        isEnabled: true,
        supportsLatest: true,
        sourceCodeLanguage: db.SourceCodeLanguage.dart,
        sourceCode: 'builtin:${s.template}',
      ));
    }
  }

  Stream<void> watchSources() {
    return _isar.sources.watchLazy(fireImmediately: true);
  }
}
