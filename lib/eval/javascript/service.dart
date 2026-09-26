// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// JS EXTENSION SERVICE — runs a Mangayomi-ecososystem JavaScript extension
// (kodjodevf/mangayomi-extensions, entityJY/mangayomi-extensions-eJ) inside
// the QuickJS engine (kodjodevf/flutter_qjs fork).
//
// Ported from upstream Mangayomi's eval/javascript/service.dart and adapted
// to Lumina's [ExtensionService] interface:
//   * upstream returns MPages (list + hasNextPage) — our interface returns a
//     plain List, so `hasNextPage=false` pages surface as EMPTY lists and
//     the browse grid's "stop when a page comes back empty" rule applies;
//   * upstream's Video/PageUrl DTOs are converted into our MVideo /
//     List<String> with the parameters['subtitles'] convention the player's
//     subtitle pipeline already understands;
//   * genre may arrive as a JSON list OR a comma string — mapped tolerantly.

import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/javascript/dom_selector.dart';
import 'package:lumina_reader/eval/javascript/extractors.dart';
import 'package:lumina_reader/eval/javascript/http.dart';
import 'package:lumina_reader/eval/javascript/js_errors.dart';
import 'package:lumina_reader/eval/javascript/preferences.dart';
import 'package:lumina_reader/eval/javascript/utils.dart';
import 'package:lumina_reader/eval/javascript/xvideo.dart';
import 'package:lumina_reader/eval/lib.dart' show sourceToMSource;
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/models/source.dart';

class JsExtensionService extends BaseExtensionService {
  JsExtensionService(super.source);

  JavascriptRuntime? _runtime;
  JsDomSelector? _jsDomSelector;
  bool _initialized = false;

  JavascriptRuntime get runtime => _runtime!;

  void _init() {
    if (_initialized) return;
    _runtime = getJavascriptRuntime();
    final r = _runtime!;
    JsHttpClient(r).init();
    _jsDomSelector = JsDomSelector(r)..init();
    JsUtils(r).init();
    JsVideosExtractors(r).init();
    JsPreferences(r, source).init();

    final sourceJson = jsonEncode(sourceToMSource(source).toJson());
    _throwIfError(
      r.evaluate('''
class MProvider {
    get source() {
        return $sourceJson;
    }
    get supportsLatest() {
        throw new Error("supportsLatest not implemented");
    }
    getHeaders(url) {
        throw new Error("getHeaders not implemented");
    }
    async getPopular(page) {
        throw new Error("getPopular not implemented");
    }
    async getLatestUpdates(page) {
        throw new Error("getLatestUpdates not implemented");
    }
    async search(query, page, filters) {
        throw new Error("search not implemented");
    }
    async getDetail(url) {
        throw new Error("getDetail not implemented");
    }
    async getPageList() {
        throw new Error("getPageList not implemented");
    }
    async getVideoList(url) {
        throw new Error("getVideoList not implemented");
    }
    async getHtmlContent(name, url) {
        throw new Error("getHtmlContent not implemented");
    }
    async cleanHtmlContent(html) {
        throw new Error("cleanHtmlContent not implemented");
    }
    getFilterList() {
        throw new Error("getFilterList not implemented");
    }
    getSourcePreferences() {
        throw new Error("getSourcePreferences not implemented");
    }
}
async function jsonStringify(fn) {
    return JSON.stringify(await fn());
}
'''),
      'installing the MProvider base class',
    );

    // evaluate() reports failures via isError, it does NOT throw — a source
    // that failed to load must not be marked initialized (upstream #873).
    _throwIfError(
      r.evaluate('''
${source.displaySourceCode ?? ''}
var extention = new DefaultExtension();
'''),
      'loading the source',
    );
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      _jsDomSelector?.dispose();
    } catch (_) {}
    try {
      _runtime?.dispose();
    } catch (_) {}
    _runtime = null;
    _initialized = false;
  }

  // ------------------------------------------------------------------ calls

  T _extensionCall<T>(String call, T def) {
    _init();
    final res = runtime.evaluate('JSON.stringify(extention.$call)');
    if (res.isError) {
      if (_isNotImplemented(res) && def != null) return def;
      _throwIfError(res, call);
    }
    try {
      return jsonDecode(res.stringResult) as T;
    } catch (_) {
      if (def != null) return def;
      rethrow;
    }
  }

  Future<dynamic> _extensionCallAsync(String call) async {
    _init();
    final evaluated = await runtime
        .evaluateAsync('jsonStringify(() => extention.$call)');
    _throwIfError(evaluated, call);
    final promised = await runtime.handlePromise(evaluated);
    _throwIfError(promised, call);
    return jsonDecode(promised.stringResult);
  }

  void _throwIfError(JsEvalResult result, String what) {
    if (!result.isError) return;
    throw Exception(jsExtensionErrorMessage(
      sourceName: source.displayName.isNotEmpty
          ? source.displayName
          : 'unknown',
      whileDoing: what,
      reported: result.stringResult,
    ));
  }

  bool _isNotImplemented(JsEvalResult result) =>
      isNotImplementedError(result.stringResult);

  // ------------------------------------------------------- interface surface

  @override
  Future<MSource> getSource() async {
    _init();
    return sourceToMSource(source);
  }

  @override
  Future<Map<String, String>> getHeaders() async {
    try {
      final map = _extensionCall<Map>(
        'getHeaders(${jsonEncode(source.displayBaseUrl)})',
        const <String, dynamic>{},
      );
      return map.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    } catch (_) {
      return const {};
    }
  }

  List<MManga> _listFromPageJson(dynamic json) {
    if (json is! Map) return const [];
    final list = json['list'];
    if (list is! List) return const [];
    return [for (final e in list) if (e is Map) _mangaFromJson(e)];
  }

  MManga _mangaFromJson(Map e) {
    final genre = e['genre'];
    List<String>? categories;
    if (genre is List) {
      categories = [for (final g in genre) g.toString()];
    } else if (genre is String && genre.isNotEmpty) {
      categories =
          genre.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
    }
    return MManga(
      name: e['name']?.toString(),
      link: e['link']?.toString(),
      imageUrl: e['imageUrl']?.toString(),
      description: e['description']?.toString(),
      author: e['author']?.toString(),
      artist: e['artist']?.toString(),
      status: e['status']?.toString(),
      genre: categories?.join(', '),
      categories: categories,
    );
  }

  @override
  Future<List<MManga>> getPopular(int page) async =>
      _listFromPageJson(await _extensionCallAsync('getPopular($page)'));

  @override
  Future<List<MManga>> getLatestUpdates(int page) async =>
      _listFromPageJson(await _extensionCallAsync('getLatestUpdates($page)'));

  @override
  Future<List<MManga>> searchManga({
    required String query,
    required int page,
    required FilterList filterList,
  }) async =>
      _listFromPageJson(await _extensionCallAsync(
          'search(${jsonEncode(query)},$page,${jsonEncode(filterList.filters.map(_filterToJson).toList())})'));

  Map<String, dynamic> _filterToJson(Filter f) => f.toJson();

  @override
  Future<MManga> getMangaDetail(String url) async {
    final json = await _extensionCallAsync('getDetail(${jsonEncode(url)})');
    if (json is! Map) return MManga(name: url, link: url);
    final m = _mangaFromJson(json);
    // JS extensions return `episodes` for anime and `chapters` for manga —
    // accept both (upstream MManga.fromJson does the same).
    final chapters = json['chapters'] ?? json['episodes'];
    if (chapters is List) {
      m.chapters = [
        for (final c in chapters)
          if (c is Map)
            MChapter(
              name: c['name']?.toString(),
              url: c['url']?.toString(),
              dateUpload: c['dateUpload']?.toString(),
              scanlator: c['scanlator']?.toString(),
            )
      ];
    }
    return m;
  }

  @override
  Future<List<MChapter>> getChapterList(String url) async {
    final detail = await getMangaDetail(url);
    return detail.chapters ?? const [];
  }

  @override
  Future<List<String>> getPageList(String url) async {
    final pages = await _extensionCallAsync('getPageList(${jsonEncode(url)})');
    if (pages is! List) return const [];
    return [
      for (final e in pages)
        if (e is String)
          e.trim()
        else if (e is Map)
          (e['url'] ?? e.toString()).toString().trim()
    ];
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final list = await _extensionCallAsync('getVideoList(${jsonEncode(url)})');
    if (list is! List) return const [];
    final out = <MVideo>[];
    for (final e in list) {
      if (e is! Map) continue;
      final v = XVideo.fromJson(Map<String, dynamic>.from(e));
      if (v.url.isEmpty) continue;
      out.add(MVideo(
        url: v.url,
        originalUrl: v.originalUrl.isEmpty ? v.url : v.originalUrl,
        quality: v.quality.isEmpty ? null : v.quality,
        headers: v.headers,
        parameters: {
          if (v.subtitles.isNotEmpty)
            'subtitles': [
              for (final s in v.subtitles)
                {
                  'url': s.file ?? s.url ?? '',
                  'label': s.label ?? s.lang ?? 'Subtitle',
                  'language': s.lang ?? '',
                }
            ],
          if (v.audios.isNotEmpty)
            'audios': [
              for (final a in v.audios)
                {'url': a.file ?? a.url ?? '', 'label': a.label ?? a.lang ?? ''}
            ],
        },
      ));
    }
    return out;
  }

  @override
  Future<String?> getChapterContent(String url) async {
    _init();
    try {
      final html = (await runtime.handlePromise(await runtime.evaluateAsync(
              'jsonStringify(() => extention.getHtmlContent(${jsonEncode(source.displayName)}, ${jsonEncode(url)}))')))
          .stringResult;
      if (html.isEmpty || html == 'null') return null;
      final cleaned = (await runtime.handlePromise(await runtime.evaluateAsync(
              'jsonStringify(() => extention.cleanHtmlContent(${jsonEncode(html)}))')))
          .stringResult;
      return cleaned.isEmpty || cleaned == 'null' ? html : cleaned;
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<Filter>> getFilterList() async {
    try {
      final list = _extensionCall<dynamic>('getFilterList()', const []);
      if (list is! List) return const [];
      // Filter subclasses (TextFilter/CheckBoxFilter/...) carry typed
      // state; Filter.fromJson dispatches on the `type` field.
      return [
        for (final f in list)
          if (f is Map)
            Filter.fromJson(Map<String, dynamic>.from(f))
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<SourcePreference>> getSourcePreferences() async {
    try {
      final list = _extensionCall<dynamic>('getSourcePreferences()', const []);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map) SourcePreference.fromJson(Map<String, dynamic>.from(e))
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  void clearClient() {}

  @override
  Future<void> refreshClient() async {}
}
