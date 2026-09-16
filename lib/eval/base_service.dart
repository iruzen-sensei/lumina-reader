// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Base class for [ExtensionService] implementations with sensible defaults.
//
// Native sources (see eval/native/*) extend this class and override only the
// operations they actually support; everything else degrades gracefully to
// "empty / unsupported" instead of throwing.

import 'dart:async';

import 'package:lumina_reader/eval/interface.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/models/source.dart';

abstract class BaseExtensionService implements ExtensionService {
  BaseExtensionService(this._source);

  final Source _source;

  @override
  Source get source => _source;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<MSource> getSource() async => MSource(
        name: _source.displayName,
        baseUrl: _source.displayBaseUrl,
        lang: _source.lang,
      );

  @override
  Future<Map<String, String>> getHeaders() async => const {};

  @override
  Future<List<MManga>> getPopular(int page) async => const [];

  @override
  Future<List<MManga>> getLatestUpdates(int page) async => const [];

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async =>
      const [];

  @override
  Future<MManga> getMangaDetail(String url) async =>
      MManga(name: url, link: url);

  @override
  Future<List<MChapter>> getChapterList(String url) async => const [];

  @override
  Future<List<String>> getPageList(String url) async => const [];

  @override
  Future<List<MVideo>> getVideoList(String url) async => const [];

  @override
  Future<List<Filter>> getFilterList() async => const [];

  @override
  Future<List<SourcePreference>> getSourcePreferences() async => const [];

  @override
  Future<dynamic> getSourcePreferenceValue(String key) async => null;

  @override
  void clearClient() {}

  @override
  Future<void> refreshClient() async {}

  @override
  Future<String?> useSauceNao(String imageUrl) async => null;

  @override
  bool get needsCloudflareBypass => false;

  @override
  Future<bool> solveCloudflare(String url) async => false;

  @override
  Stream<ExtensionProgress> get progressStream => const Stream.empty();

  @override
  Object? get lastError => null;
}
