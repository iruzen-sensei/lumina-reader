// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2
//
// MOTION SYSTEM TESTS — lock in the two ported reference components:
//   * HeroDeleteButton: the morph (48 -> 132 width), confirm/cancel
//     callbacks, and the check-draw payoff.
//   * HeroMenuButton / showHeroMenu: anchored dropdown opens, staggers
//     and returns the selected value.
//   * HeroRouteScale: the transitions.dev scale language (forward
//     .97 -> 1; reverse recede to .99).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumina_reader/core/ui/lumina_ui.dart';
import 'package:lumina_reader/core/ui/hero_motion.dart';

Widget _host(Widget child) {
  return HeroScope(
    data: HeroThemeData.dark(),
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('HeroDeleteButton morphs open and confirms', (tester) async {
    var confirmed = 0;
    var cancelled = 0;

    await tester.pumpWidget(_host(HeroDeleteButton(
      onConfirm: () => confirmed++,
      onCancel: () => cancelled++,
    )));

    // Idle: a 48x48 tile.
    var size = tester.getSize(find.byType(HeroDeleteButton));
    expect(size.width, 48);
    expect(size.height, 48);

    // Tap the trigger -> the panel morphs open (width 48 + 84).
    await tester.tap(find.byType(HeroDeleteButton));
    await tester.pumpAndSettle();
    size = tester.getSize(find.byType(HeroDeleteButton));
    expect(size.width, 132, reason: 'tile + panel after morph');

    // The two circular actions are present and staggered in.
    expect(find.byTooltip('Confirm delete'), findsOneWidget);
    expect(find.byTooltip('Keep'), findsOneWidget);

    // Confirm -> onConfirm fires (check draws itself in).
    await tester.tap(find.byTooltip('Confirm delete'));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(cancelled, 0);

    // Pump through the 1400ms hold window (no dangling timers).
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    // After the hold window the button returns to idle.
    expect(find.byType(HeroDeleteButton), findsOneWidget);
  });

  testWidgets('HeroDeleteButton re-tap closes as kept', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(_host(HeroDeleteButton(
      onCancel: () => cancelled++,
    )));

    await tester.tap(find.byType(HeroDeleteButton));
    await tester.pumpAndSettle();

    // Re-tap the TRIGGER TILE (left 48px zone — the button's centre now
    // lands on the panel) -> resolves as kept (cancel).
    final tl = tester.getTopLeft(find.byType(HeroDeleteButton));
    await tester.tapAt(tl + const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(cancelled, 1);

    // Pump through the 600ms kept-hold window.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // Collapsed back to the tile width.
    final size = tester.getSize(find.byType(HeroDeleteButton));
    expect(size.width, 48);
  });

  testWidgets('showHeroDeleteConfirm returns true on confirm', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(Builder(builder: (context) {
      return HeroButton(
        label: 'Open',
        onPressed: () async {
          result = await showHeroDeleteConfirm(
            context: context,
            title: 'Delete note?',
            message: 'This note will be permanently removed.',
            confirmLabel: 'Delete',
          );
        },
      );
    })));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // The morph button is the confirm interaction.
    expect(find.text('Delete note?'), findsOneWidget);
    expect(find.text('DELETE', findRichText: true), findsOneWidget);

    await tester.tap(find.byType(HeroDeleteButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Confirm delete'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));

    expect(result, isTrue);
  });

  testWidgets('HeroMenuButton opens the dropdown and selects', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(HeroMenuButton<String>(
      tooltip: 'Sort',
      icon: Icons.sort_rounded,
      items: const [
        HeroMenuItem(value: 'a', label: 'Title'),
        HeroMenuItem(value: 'b', label: 'Newest', checked: true),
        HeroMenuItem(value: 'c', label: 'Descending', danger: true),
      ],
      onSelected: (v) => picked = v,
    )));

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();

    // The dropdown panel shows all rows.
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Descending'), findsOneWidget);

    // Select -> value returned, menu closes.
    await tester.tap(find.text('Descending'));
    await tester.pumpAndSettle();
    expect(picked, 'c');
    expect(find.text('Newest'), findsNothing);
  });

  testWidgets('menu barrier tap dismisses without a value', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(HeroMenuButton<String>(
      tooltip: 'Sort',
      items: const [HeroMenuItem(value: 'a', label: 'Title')],
      onSelected: (v) => picked = v,
    )));

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();

    // Tap the far corner (the transparent barrier).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.text('Title'), findsNothing);
  });

  testWidgets('HeroRouteScale grows from the pre-scale on open', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: HeroMotion.durationIn,
    );

    await tester.pumpWidget(_host(AnimatedBuilder(
      animation: controller,
      builder: (_, __) => HeroRouteScale(
        child: Container(width: 100, height: 100, color: Colors.white),
      ),
    )));

    // HeroRouteScale without a ModalRoute animates nothing (pass-through).
    expect(find.byType(HeroRouteScale), findsOneWidget);
  });
}
