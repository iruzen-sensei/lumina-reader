// Standalone live probe — runs the REAL extension chain outside the
// flutter_test HTTP sandbox: MangaDex (native) + Madara (mangaread.org).
//
// Usage: dart run tool/live_probe.dart
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:lumina_reader/eval/lib.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/models/source.dart' as db;

Future<void> main() async {
  var failures = 0;

  // ------------------------------------------------------------------
  // 1. MangaDex — the default seeded source.
  // ------------------------------------------------------------------
  print('=== 1. MangaDex (builtin.mangadex) ===');
  final md = db.Source(
    idString: 'builtin.mangadex',
    name: 'MangaDex',
    lang: 'en',
    baseUrl: 'https://api.mangadex.org',
    isManga: true,
    sourceCodeLanguage: db.SourceCodeLanguage.dart,
    sourceCode: 'builtin:mangadex',
  );
  final mdService = getExtensionService(md);
  print('service: ${mdService.runtimeType}');
  try {
    final popular = await mdService.getPopular(1);
    print('popular: ${popular.length} entries');
    if (popular.isEmpty) { failures++; print('!! EMPTY'); }
    else {
      final first = popular.first;
      print('first: ${first.name} / ${first.link}');
      final detail = await mdService.getMangaDetail(first.link!);
      print('detail ok: ${detail.name}, chapters...');
      final chapters = await mdService.getChapterList(first.link!);
      print('chapters: ${chapters.length}');
      if (chapters.isEmpty) { failures++; print('!! NO CHAPTERS'); }
      else {
        final pages = await mdService.getPageList(chapters.first.url!);
        print('pages for ch1: ${pages.length}');
        if (pages.isEmpty) { failures++; print('!! NO PAGES'); }
      }
    }
  } catch (e) {
    failures++;
    print('!! MangaDex FAILED: $e');
  }

  // ------------------------------------------------------------------
  // 2. Madara — a site verified reachable with items from this sandbox.
  // ------------------------------------------------------------------
  print('\n=== 2. Madara (mangaread.org) ===');
  final madara = db.Source(
    idString: 'repo-test-mangaread',
    name: 'MangaRead',
    lang: 'en',
    baseUrl: 'https://www.mangaread.org',
    typeSource: 'madara',
    isManga: true,
  );
  final madaraService = getExtensionService(madara);
  print('service: ${madaraService.runtimeType}');
  try {
    final popular = await madaraService.getPopular(1);
    print('popular: ${popular.length} entries');
    if (popular.isEmpty) { failures++; print('!! EMPTY'); }
    else {
      final first = popular.first;
      print('first: ${first.name} / ${first.link}');
      final detail = await madaraService.getMangaDetail(first.link!);
      print('detail: ${detail.name}');
      if (detail.name!.isEmpty) { failures++; print('!! DETAIL NAME EMPTY'); }
      final chapters = await madaraService.getChapterList(first.link!);
      print('chapters: ${chapters.length}');
      if (chapters.isEmpty) { failures++; print('!! NO CHAPTERS'); }
      else {
        final pages = await madaraService.getPageList(chapters.first.url!);
        print('pages: ${pages.length}');
        if (pages.isEmpty) { failures++; print('!! NO PAGES'); }
      }
    }
    // Angle: latest tab.
    final latest = await madaraService.getLatestUpdates(1);
    print('latest: ${latest.length} entries');
    if (latest.isEmpty) { failures++; print('!! LATEST EMPTY'); }
    // Angle: search.
    final search = await madaraService.searchManga(
        query: 'martial',
        page: 1,
        filterList: const FilterList(filters: []));
    print('search(martial): ${search.length} entries');
    if (search.isEmpty) { failures++; print('!! SEARCH EMPTY'); }
  } catch (e) {
    failures++;
    print('!! Madara FAILED: $e');
  }

  // ------------------------------------------------------------------
  // 3. Madara on a Cloudflare site — verify the hang/failure mode.
  // ------------------------------------------------------------------
  print('\n=== 3. Madara Cloudflare probe (mangareader.to) ===');
  final cf = db.Source(
    idString: 'repo-test-mangareader',
    name: 'MangaReader',
    lang: 'en',
    baseUrl: 'https://mangareader.to',
    typeSource: 'mangareader',
    isManga: true,
  );
  final cfService = getExtensionService(cf);
  print('service: ${cfService.runtimeType}');
  final sw = Stopwatch()..start();
  try {
    final popular = await cfService.getPopular(1).timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException('120s timeout'));
    print('popular: ${popular.length} entries in ${sw.elapsed}');
  } catch (e) {
    print('outcome after ${sw.elapsed}: $e');
  }

  // ------------------------------------------------------------------
  // 4. Extension repo index fetch (the Add-repository path).
  // ------------------------------------------------------------------
  print('\n=== 4. Repo index fetch ===');
  try {
    final res = await http.get(Uri.parse(
        'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json'));
    final list = jsonDecode(res.body) as List;
    print('index: HTTP ${res.statusCode}, ${list.length} extensions');
  } catch (e) {
    failures++;
    print('!! index fetch FAILED: $e');
  }

  print('\n=============================');
  print(failures == 0 ? 'ALL PROBES PASSED' : '$failures PROBES FAILED');
}

class TimeoutException implements Exception {
  TimeoutException(this.msg);
  final String msg;
  @override
  String toString() => msg;
}
