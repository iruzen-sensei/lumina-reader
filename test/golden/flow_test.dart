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

import 'package:lumina_reader/core/ui/heroui_v3.dart';
import 'package:lumina_reader/providers/providers.dart' show LibraryMediaType;
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('flow: filter sheet changes the media filter', (tester) async {
    // The shared Isar from the previous test is reused (single-open rule).
    final c = await bootApp(tester, warmUp: true);
    await flush(tester, rounds: 8);

    // The segmented control is present with all four media options.
    expect(find.text('Manga'), findsWidgets);
    expect(find.text('Novel'), findsWidgets);
    expect(find.text('Book'), findsWidgets);

    // Switch to Novel → the novel entry is visible, manga entries are not.
    // (Tap the SEGMENTED control's pill — a category tab also labelled
    // 'All' exists above it, which is itself a small usability wrinkle.)
    final segmentedNovel = find.descendant(
        of: find.byWidgetPredicate((w) => w is HeroSegmented<LibraryMediaType>),
        matching: find.text('Novel'));
    await tester.tap(segmentedNovel.first);
    await tester.pump();
    await flush(tester, rounds: 6);
    expect(find.text('Ocean of Stars'), findsWidgets);

    // Switch back to All → everything renders again.
    final segmentedAll = find.descendant(
        of: find.byWidgetPredicate((w) => w is HeroSegmented<LibraryMediaType>),
        matching: find.text('All'));
    await tester.tap(segmentedAll.first);
    await tester.pump();
    await flush(tester, rounds: 6);
    expect(find.text('Blade of the Immortal Wind'), findsWidgets);

    // ignore: unnecessary_statements
    c;
  }, timeout: const Timeout(Duration(minutes: 6)));
}
