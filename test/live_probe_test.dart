// Live-network probe v2: install a REAL HttpOverrides inside runAsync so
// flutter_test's 400-stub is bypassed. If this works, we can run the app's
// real source chains (MangaDex / Madara / repo sync) as live tests here.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _LiveOverrides extends HttpOverrides {
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real network probe with live override', (tester) async {
    int? code;
    String? bodyHead;
    await tester.runAsync(() async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _LiveOverrides();
      try {
        final req = await HttpClient()
            .getUrl(Uri.parse('https://api.mangadex.org/manga?limit=1'));
        final res = await req.close();
        code = res.statusCode;
        final bytes = <int>[];
        await for (final chunk in res) {
          bytes.addAll(chunk);
        }
        bodyHead = String.fromCharCodes(bytes.take(60));
      } catch (e) {
        code = -1;
        bodyHead = e.toString();
      } finally {
        HttpOverrides.global = previous;
      }
    });
    print('PROBE2 status=$code body=$bodyHead');
    expect(code, 200, reason: 'live override should bypass the 400 stub');
  });
}
