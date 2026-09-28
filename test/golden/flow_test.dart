// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// CROSS-COMPONENT FLOW TESTS — pump the REAL app against the seeded
// fixture DB and drive real user flows through the real router:
//   * library grid renders seeded entries
//   * tapping a cover opens the detail screen with matching data
//   * the chapter list is populated and sorted
//   * back navigation returns to the library
//   * filter sheet opens and changes the visible set

import 'package:lumina_reader/core/ui/watermelon.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:lumina_reader/providers/providers.dart'
    show LibraryMediaType;
import 'package:lumina_reader/router/router.dart' show routerProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_reader/modules/anime_home/anime_home_screen.dart';
import 'package:lumina_reader/modules/notes/notes_screen.dart';
import 'package:lumina_reader/modules/library/library_screen.dart';
import 'package:lumina_reader/modules/manga/manga_detail_screen.dart';
import 'package:lumina_reader/modules/shared/widgets.dart' show BookCover;

import 'golden_harness.dart';

void main() {
  testWidgets('flow: library → detail → chapters → back', (tester) async {
    await tester.runAsync(() async {
      await loadRealFonts();
      await setupFixture(dark: true);
    });

    final c = await bootApp(tester);
    await flush(tester, rounds: 10);

    // 0. The app opens on its FRONT PAGE — Anime (the previous build
    //    opened on Library despite Anime being the first tab).
    expect(find.byType(AnimeHomeScreen), findsOneWidget);
    expect(find.byType(LibraryScreen), findsNothing);

    // 0b. Navigate to the Library tab (index 1 in the dock).
    c.read(routerProvider).go('/library');
    await flush(tester, rounds: 10);

    // 1. Library renders seeded manga with covers + titles.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('Blade of the Immortal Wind'), findsWidgets);
    expect(find.text('Neon Tokyo Nights'), findsWidgets);

    // 2. Tap the first cover (the tap target is the cover card, not the
    //    title text below it) → the detail screen opens.
    final firstCover = find.byType(BookCover).first;
    final coverCenter = tester.getCenter(firstCover);
    await tester.tapAt(Offset(coverCenter.dx, coverCenter.dy - 40));
    await tester.pump();
    await flush(tester, rounds: 10);
    expect(find.byType(MangaDetailScreen), findsOneWidget);
    expect(find.text('Blade of the Immortal Wind'), findsWidgets);

    // 3. The chapter list is populated (24 seeded chapters, newest first).
    expect(find.text('Chapter 24'), findsWidgets);
    expect(find.text('Chapter 1'), findsNothing); // below the fold + reversed

    // 4. Back → library again, grid still intact.
    await tester.pageBack();
    await tester.pump();
    await flush(tester, rounds: 6);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(MangaDetailScreen), findsNothing);

    // Silence the unused-container lint when assertions above suffice.
    // ignore: unnecessary_statements
    c;
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('flow: inline picker changes the media filter', (tester) async {
    // The shared Isar from the previous test is reused (single-open rule).
    final c = await bootApp(tester, warmUp: true);
    c.read(routerProvider).go('/library');
    await flush(tester, rounds: 8);

    // The media filter is a watermelon.sh Quick Option Picker: the pill
    // shows the active option; tapping it pops the option tray.
    final mediaPicker = find.byWidgetPredicate(
        (w) => w is WmQuickOptionPicker<LibraryMediaType>);
    expect(mediaPicker, findsOneWidget);

    // Open the tray and switch to Novel → the novel entry is visible,
    // manga entries are not.
    await tester.tap(mediaPicker.first);
    await flush(tester, rounds: 4);
    await tester.tap(find.text('Novel').last);
    await flush(tester, rounds: 6);
    expect(find.text('Ocean of Stars'), findsWidgets);

    // Re-open and switch back to All → everything renders again.
    await tester.tap(mediaPicker.first);
    await flush(tester, rounds: 4);
    await tester.tap(find.text('All').last);
    await flush(tester, rounds: 6);
    expect(find.text('Blade of the Immortal Wind'), findsWidgets);

    // ignore: unnecessary_statements
    c;
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('flow: notes — Expand Details composer creates a note',
      (tester) async {
    // The shared Isar from the previous tests is reused (single-open rule).
    final c = await bootApp(tester, warmUp: true);
    c.read(routerProvider).go('/notes');
    await flush(tester, rounds: 8);

    // The fixture seeds 4 long notes (ellipsized in their cards); the
    // collapsed watermelon.sh Expand Details band sits above the list.
    expect(find.text('New note'), findsOneWidget);
    expect(find.byType(NotesScreen), findsOneWidget);

    // Tap the band header → the composer springs open in place — the
    // user-requested Expand Details create-note flow.
    await tester.tap(find.text('New note'));
    await flush(tester, rounds: 4);
    expect(find.text('Write your note…'), findsOneWidget);

    // Type into the composer field (NOT the "Search notes…" field).
    final composerField = find.byWidgetPredicate((w) =>
        w is TextField &&
        (w.decoration?.hintText ?? '').contains('Write your note'));
    await tester.enterText(composerField, 'Frieren deserves S2');

    // Save → the new card goes live at the head of the list.
    await tester.tap(find.text('Save note'));
    await flush(tester, rounds: 10);
    expect(find.text('Frieren deserves S2'), findsOneWidget);

    // ignore: unnecessary_statements
    c;
  }, timeout: const Timeout(Duration(minutes: 6)));
}
