// ignore_for_file: avoid_print
// Live check of the new AniList browse/recommendations queries.
// Run: dart test test/live_anilist_browse_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_reader/services/anilist.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _LiveOverrides();

  test('browse with filters (genre Action, sort Rating)', () async {
    final svc = AniListService();
    final list = await svc.browse(genre: 'Action', sort: 'SCORE_DESC');
    expect(list, isNotEmpty);
    expect(list.first.genres, contains('Action'));
    print('browse Action top: ${list.first.bestTitle} '
        '(${list.first.averageScore}%)');
  });

  test('browse with search + year + format', () async {
    final svc = AniListService();
    final list = await svc.browse(
        search: 'frieren', format: 'TV', sort: 'SEARCH_MATCH');
    expect(list, isNotEmpty);
    print('search frieren: ${list.first.bestTitle} ${list.first.seasonYear}');
  });

  test('topRated + upcoming + recommendations', () async {
    final svc = AniListService();
    final top = await svc.topRated();
    expect(top, isNotEmpty);
    print('top: ${top.first.bestTitle} (${top.first.averageScore}%)');
    final up = await svc.upcoming();
    expect(up, isNotEmpty);
    print('upcoming: ${up.first.bestTitle} (${up.first.seasonYear})');
    final recs = await svc.recommendations(top.first.id);
    print('recs for ${top.first.bestTitle}: ${recs.length}');
    expect(recs, isNotEmpty);
  });
}

class _LiveOverrides extends HttpOverrides {}
