// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// AUDIT ROUND 1 — capture EVERY main screen of the real app against a
// seeded database. These goldens are the "before" record for the HeroUI
// redesign and the raw material for the visual (VLM) critique pass.
//
// The Isar instance is opened ONCE for the whole binary (a second open
// deadlocks in flutter_test) and shared across the batched tests below.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lumina_reader/models/settings.dart' as db_s;
import 'package:lumina_reader/router/router.dart';

import 'golden_harness.dart';

/// Opt-in gates:
///   GOLDEN_UPDATE=1 flutter test test/golden/audit_screens_test.dart \
///       --update-goldens   → regenerate + eyeball + VLM review
///   GOLDEN_COMPARE=1 ...   → pixel comparison (time-dependent screens
///                            still drift; see harness header note)
/// Default: skipped so the plain `flutter test` suite stays green.
final _goldenEnabled = Platform.environment.containsKey('GOLDEN_UPDATE') ||
    Platform.environment.containsKey('GOLDEN_COMPARE');

void main() {
  if (!_goldenEnabled) {
    test('golden audit (skipped — GOLDEN_UPDATE=1 to regenerate)', () {});
    return;
  }

  testWidgets('batch 1: main tabs (dark)', (tester) async {
    await tester.runAsync(() async {
      await loadRealFonts();
      await setupFixture(dark: true);
    });
    final c = await bootApp(tester);
    await flush(tester);
    await capture(tester, '01-library-dark');

    for (final e in const <(String, String, int)>[
      ('02-anime-dark', '/anime', 8),
      ('03-browse-dark', '/browse', 10),
      ('04-downloads-dark', '/downloads', 8),
      ('05-more-dark', '/more', 8),
    ]) {
      c.read(routerProvider).go(e.$2);
      await tester.pump();
      await flush(tester, rounds: e.$3);
      await capture(tester, e.$1);
    }
  }, timeout: _t);

  testWidgets('batch 2: details + lists (dark)', (tester) async {
    final c = await bootApp(tester);
    for (final e in const <(String, String, int)>[
      ('06-manga-detail-dark', '/mangaDetail/1', 10),
      ('07-anime-detail-dark', '/animeDetail/9', 10),
      ('08-history-dark', '/history', 8),
      ('09-updates-dark', '/updates', 8),
      ('10-calendar-dark', '/calendar', 10),
    ]) {
      c.read(routerProvider).go(e.$2);
      await tester.pump();
      await flush(tester, rounds: e.$3);
      await capture(tester, e.$1);
    }
  }, timeout: _t);

  testWidgets('batch 3: stats + notes + settings (dark)', (tester) async {
    final c = await bootApp(tester);
    for (final e in const <(String, String, int)>[
      ('11-stats-dark', '/stats', 10),
      ('12-notes-dark', '/notes', 8),
      ('13-settings-dark', '/more/settings', 8),
    ]) {
      c.read(routerProvider).go(e.$2);
      await tester.pump();
      await flush(tester, rounds: e.$3);
      await capture(tester, e.$1);
    }
  }, timeout: _t);

  testWidgets('batch 4: light pass', (tester) async {
    final isar = sharedIsar;
    // Flip the persisted theme row with SYNC Isar calls — after many
    // flush() rounds the async native path is wedged by pending fake-zone
    // reads, but sync FFI calls still work.
    final s = isar.settings.getSync(227) ?? db_s.Settings.defaults();
    s.themeMode = 'light';
    isar.writeTxnSync(() => isar.settings.putSync(s));

    final c = await bootApp(tester);
    await flush(tester, rounds: 6);
    await capture(tester, '14-library-light');

    c.read(routerProvider).go('/more');
    await tester.pump();
    await flush(tester);
    await capture(tester, '15-more-light');

    c.read(routerProvider).go('/mangaDetail/1');
    await tester.pump();
    await flush(tester);
    await capture(tester, '16-manga-detail-light');
  }, timeout: _t);
}

const _t = Timeout(Duration(minutes: 5));
