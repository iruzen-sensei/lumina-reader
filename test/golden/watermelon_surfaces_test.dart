// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// WATERMELON SURFACE USABILITY TESTS — boot the REAL app against the
// seeded fixture DB and drive the new watermelon.sh surfaces end-to-end:
//   * Explore: Morphing Discovery Bar present, morphs open, search runs
//     the global search, source picker switches the active source
//   * Extensions: Quick Option Picker drives the section tabs
//   * Downloads: Status Picker renders the state tabs
//
// These complement watermelon_interactions_test.dart (component-level)
// and flow_test.dart (library picker flow) by exercising the components
// as WIRED INTO the real screens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_reader/core/ui/watermelon.dart';
import 'package:lumina_reader/router/router.dart' show routerProvider;
import 'package:lumina_reader/modules/browse/browse_screen.dart';
import 'package:lumina_reader/modules/browse/extensions_screen.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('explore: discovery bar + source picker + mode picker',
      (tester) async {
    await tester.runAsync(() async {
      await loadRealFonts();
      await setupFixture(dark: true);
    });
    final c = await bootApp(tester);
    c.read(routerProvider).go('/browse');
    await flush(tester, rounds: 10);

    // 1. The Explore screen renders with the Morphing Discovery Bar and
    //    the pinned picker row (Source + Popular/Latest) — the old source
    //    strip and 3-way segmented control are gone.
    expect(find.byType(BrowseScreen), findsOneWidget);
    expect(find.byType(WmDiscoveryBar), findsOneWidget);
    expect(find.byType(WmQuickOptionPicker<int>), findsAtLeastNWidgets(2));

    // 2. The discovery bar morphs open into a live search field.
    //    (Tap the collapsed SEARCH PILL at the bar's left — tapping the
    //    bar's center would hit a category pill instead.)
    final barTopLeft = tester.getTopLeft(find.byType(WmDiscoveryBar));
    await tester.tapAt(barTopLeft + const Offset(28, 22));
    await flush(tester, rounds: 4);
    expect(find.byType(TextField), findsOneWidget);

    // 3. Type a query and submit -> the global search results sheet opens
    //    (a full-height HeroSheet listing the installed sources).
    await tester.enterText(find.byType(TextField), 'wind');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await flush(tester, rounds: 8);
    expect(find.textContaining('across'), findsOneWidget);
    // The results sheet closes via its close button (HeroIconButton, not
    // a nav back button).
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await flush(tester, rounds: 4);

    // 4. The source picker pops its tray and switches the active source:
    //    the pill relabels to the chosen source.
    final sourcePicker = find
        .byWidgetPredicate((w) => w is WmQuickOptionPicker<int>)
        .first;
    await tester.tap(sourcePicker);
    await flush(tester, rounds: 4);
    final manganatoOption = find.text('Manganato').last;
    await tester.tap(manganatoOption);
    await flush(tester, rounds: 6);
    expect(find.text('Manganato'), findsWidgets);

    // ignore: unnecessary_statements
    c;
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('extensions: quick option picker drives the section tabs',
      (tester) async {
    final c = await bootApp(tester, warmUp: true);
    c.read(routerProvider).go('/extensions');
    await flush(tester, rounds: 10);

    // 1. The extensions screen renders with ONE picker (not a TabBar).
    expect(find.byType(ExtensionsScreen), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);

    // 2. Open the picker tray and switch to the Catalog section.
    final picker = find.byWidgetPredicate((w) => w is WmQuickOptionPicker<int>);
    expect(picker, findsOneWidget);
    await tester.tap(picker);
    await flush(tester, rounds: 4);
    await tester.tap(find.textContaining('Catalog').last);
    await flush(tester, rounds: 8);

    // 3. The catalog section is now active (its sync/add-repo actions and
    //    the predictive search input are visible).
    expect(find.byType(WmPredictiveInput), findsOneWidget);

    // ignore: unnecessary_statements
    c;
  }, timeout: const Timeout(Duration(minutes: 6)));
}
