// LIVE TEMPLATE VERIFICATION — runs the full chain (popular → detail →
// chapters → pages) on KNOWN-ALIVE sites from the health probe.
// Manual-only: flutter test test/live_templates_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lumina_reader/eval/interface.dart';
import 'package:lumina_reader/eval/lib.dart' as eval;
import 'package:lumina_reader/models/source.dart' as db;

class _LiveOverrides extends HttpOverrides {
}

Future<bool> _chain(String label, ExtensionService svc) async {
  try {
    final popular = await svc.getPopular(1).timeout(
        const Duration(seconds: 25));
    if (popular.isEmpty) {
      print('  FAIL $label popular=0');
      return false;
    }
    final detail =
        await svc.getMangaDetail(popular.first.link!).timeout(
            const Duration(seconds: 25));
    final chapters =
        await svc.getChapterList(popular.first.link!).timeout(
            const Duration(seconds: 25));
    if (chapters.isEmpty) {
      print('  FAIL $label chapters=0 (detail desc: '
          '${(detail.description ?? '').length} chars)');
      return false;
    }
    final pages =
        await svc.getPageList(chapters.first.url!).timeout(
            const Duration(seconds: 25));
    final ok = pages.isNotEmpty;
    print('  ${ok ? 'PASS' : 'FAIL'} $label popular=${popular.length} '
        'chapters=${chapters.length} pages=${pages.length} '
        'page0=${pages.isEmpty ? '-' : pages.first.substring(0, pages.first.length > 70 ? 70 : pages.first.length)}');
    return ok;
  } catch (e) {
    print('  FAIL $label threw $e');
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // (name, baseUrl, typeSource, seeded) — the SEEDED trio are the app's
  // default installed sources (sources_repository.dart) and form the hard
  // gate; the rest are drift-prone third-party sites (Cloudflare rotations,
  // dead domains) reported informationally. Verified 2026-09-25: S2Manga +
  // KomikStation sit behind JS challenges and Azure is dead — site-level
  // drift, not code regressions, must never fail the chain gate.
  const sites = <(String, String, String, bool)>[
    ('Mangasushi', 'https://mangasushi.org', 'madara', true),
    ('LHTranslation', 'https://lhtranslation.net', 'madara', true),
    ('Ravenscans', 'https://ravenscans.com', 'mangareader', true),
    ('S2Manga', 'https://s2manga.com', 'madara', false),
    ('Azure Scans', 'https://azuremanga.com', 'mangareader', false),
    ('KomikStation', 'https://komikstation.co', 'mangareader', false),
  ];

  testWidgets('LIVE: template chains on alive sites', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = _LiveOverrides();
      var ok = 0;
      var seededOk = 0;
      const seededCount = 3;
      for (final (name, base, tsrc, seeded) in sites) {
        final row = db.Source(
          idString: 'live-test-$name',
          name: name,
          lang: 'en',
          baseUrl: base,
          typeSource: tsrc,
          isManga: true,
          isEnabled: true,
        );
        final svc = eval.getExtensionService(row);
        if (svc is eval.NullExtensionService) {
          print('  FAIL $name dispatch=NullExtensionService');
          continue;
        }
        final chained = await _chain(name, svc);
        if (chained) {
          ok++;
          if (seeded) seededOk++;
        }
      }
      print('== TEMPLATE CHAINS: $ok/${sites.length} sites fully working, '
          'seeded $seededOk/$seededCount ==');
      expect(seededOk, seededCount,
          reason: 'every SEEDED default source must chain end-to-end — '
              'the app ships these installed; third-party sites may drift '
              'behind Cloudflare or die, which is reported but not gated');
    });
  }, timeout: const Timeout(Duration(minutes: 6)));
}
