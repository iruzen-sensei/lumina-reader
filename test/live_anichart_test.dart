// Quick live check: AniList GraphQL airing schedule (feeds Calendar).
// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_reader/services/anichart.dart';

class _Live extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? c) => super.createHttpClient(c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live AniList airing schedule', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = _Live();
      final svc = AniChartService();
      final eps = await svc.getSchedule(
          from: DateTime.now(),
          to: DateTime.now().add(const Duration(days: 2)));
      print('ANICHART episodes: ${eps.length}');
      if (eps.isNotEmpty) {
        print('  first: ${eps.first.title} @ ${eps.first.airingDateTime}');
      }
      expect(eps, isNotEmpty);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}
