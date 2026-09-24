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

  // (name, baseUrl, typeSource) — alive per scripts/probe_sites.py
  const sites = <(String, String, String)>[
    ('S2Manga', 'https://s2manga.com', 'madara'),
    ('Mangasushi', 'https://mangasushi.org', 'madara'),
    ('LHTranslation', 'https://lhtranslation.net', 'madara'),
    ('Ravenscans', 'https://ravenscans.com', 'mangareader'),
    ('Azure Scans', 'https://azuremanga.com', 'mangareader'),
    ('KomikStation', 'https://komikstation.co', 'mangareader'),
  ];

  testWidgets('LIVE: template chains on alive sites', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = _LiveOverrides();
      var ok = 0;
      for (final (name, base, tsrc) in sites) {
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
        if (await _chain(name, svc)) ok++;
      }
      print('== TEMPLATE CHAINS: $ok/${sites.length} sites fully working ==');
      expect(ok, greaterThanOrEqualTo(4),
          reason: 'at least 4 of the alive sites must chain end-to-end');
    });
  }, timeout: const Timeout(Duration(minutes: 6)));
}
