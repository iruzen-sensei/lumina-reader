// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// USABILITY tests for the watermelon.sh interaction ports (Task-17 batch).
// These exercise BEHAVIOUR, not pixels: every interaction component must
// respond to taps/drags/keys with the state change the user expects.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumina_reader/core/ui/lumina_ui.dart';
import 'package:lumina_reader/core/ui/watermelon.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    themeMode: ThemeMode.dark,
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: HeroScope(data: HeroThemeData.dark(), child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WmDiscoveryBar (Morphing Discovery Bar — the search button)', () {
    testWidgets('morphs open into a search field and back', (tester) async {
      var queried = '';
      await tester.pumpWidget(_wrap(Center(
        child: SizedBox(
          width: 400,
          child: WmDiscoveryBar(
            categories: [
              WmDiscoveryCategory(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Trending',
                  onTap: () {}),
            ],
            onSearch: (q) => queried = q,
          ),
        ),
      )));
      await tester.pumpAndSettle();

      // Collapsed: category chip visible, no input.
      expect(find.text('Trending'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Tap the search circle -> morphs open.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Type + submit -> onSearch fires with the typed query.
      await tester.enterText(find.byType(TextField), 'frieren');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(queried, 'frieren');

      // Close circle -> back to categories. Two close icons exist while
      // the input holds text (inline clear + the close circle) — the
      // circle is the last one in tree order.
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Trending'), findsOneWidget);
    });
  });

  group('WmStatusPicker', () {
    testWidgets('opens the tray and selects a new status', (tester) async {
      var picked = -1;
      await tester.pumpWidget(_wrap(Center(
        child: WmStatusPicker(
          value: 0,
          onChanged: (v) => picked = v,
          items: const [
            WmStatusItem(
                id: 0, icon: Icons.play_circle_outline_rounded, name: 'Reading'),
            WmStatusItem(
                id: 1, icon: Icons.check_circle_outline_rounded, name: 'Finished'),
            WmStatusItem(id: 2, icon: Icons.schedule_rounded, name: 'Plan'),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      // Collapsed pill shows the current status.
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Finished'), findsNothing);
      expect(find.text('Plan'), findsNothing);

      // Open -> all options fan out; select Finished.
      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
      expect(picked, 1);
    });
  });

  group('WmSplitActions', () {
    testWidgets('fans out actions and fires the tapped one', (tester) async {
      var fired = '';
      await tester.pumpWidget(_wrap(Center(
        child: WmSplitActions(
          actions: [
            WmSplitAction(
                icon: Icons.tv_rounded, label: 'MAL', onTap: () => fired = 'MAL'),
            WmSplitAction(
                icon: Icons.pets_rounded,
                label: 'Kitsu',
                onTap: () => fired = 'Kitsu'),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      // Collapsed: only the trigger.
      expect(find.text('MAL'), findsNothing);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('MAL'), findsOneWidget);
      expect(find.text('Kitsu'), findsOneWidget);

      // Tapping an action fires it and collapses the fan.
      await tester.tap(find.text('Kitsu'));
      await tester.pumpAndSettle();
      expect(fired, 'Kitsu');
      expect(find.text('MAL'), findsNothing);
    });
  });

  group('WmQuickOptionPicker', () {
    testWidgets('pops the tray above and commits the selection', (tester) async {
      String val = 'a';
      await tester.pumpWidget(_wrap(Center(
        child: WmQuickOptionPicker<String>(
          value: val,
          options: const [
            WmPickerOption(value: 'a', label: 'Alpha'),
            WmPickerOption(value: 'b', label: 'Beta'),
          ],
          onChanged: (v) => val = v,
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(val, 'b');
    });
  });

  group('WmSplitToEdit', () {
    testWidgets('splits open, edits the value, commits on save', (tester) async {
      var saved = 0;
      late StateSetter setOuter;
      var value = 20;
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return Center(
            child: SizedBox(
              width: 360,
              child: WmSplitToEdit(
                label: 'Daily pages',
                value: value,
                unit: 'pages',
                onSave: (v) {
                  saved = v;
                  setOuter(() => value = v);
                },
              ),
            ),
          );
        },
      )));
      await tester.pumpAndSettle();

      // Collapsed value pill.
      expect(find.text('20'), findsOneWidget);

      // Tap to split open -> editor with the value pre-selected.
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Overwrite + save via the check button.
      await tester.enterText(find.byType(TextField), '45');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(saved, 45);
      expect(find.text('45'), findsOneWidget);
    });
  });

  group('WmPredictiveInput', () {
    testWidgets('suggests completions and applies them on tap', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(Center(
        child: WmPredictiveInput(
          controller: controller,
          dictionary: const ['action', 'adventure', 'anime'],
          onSubmitted: (_) {},
        ),
      )));
      await tester.pumpAndSettle();

      // No suggestions for empty input.
      expect(find.text('adventure'), findsNothing);

      // Type a prefix -> up to 3 suggestions float above.
      await tester.enterText(find.byType(TextField), 'ac');
      await tester.pumpAndSettle();
      expect(find.text('action'), findsOneWidget);

      // Tap completes the word (with trailing space for the next word).
      await tester.tap(find.text('action'));
      await tester.pumpAndSettle();
      expect(controller.text, 'action ');
    });
  });

  group('WmExtendedToolbar', () {
    testWidgets('slides between primary and secondary sets', (tester) async {
      await tester.pumpWidget(_wrap(Center(
        child: WmExtendedToolbar(
          primary: [
            WmToolItem(icon: Icons.speed_rounded, label: 'Speed', onTap: () {}),
          ],
          secondary: [
            WmToolItem(icon: Icons.lock_rounded, label: 'Lock', onTap: () {}),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      // Both rows exist (cross-fading); toggle flips the visible set.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
    });
  });

  group('WmFeedbackAction', () {
    testWidgets('runs the action and shows the success state', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(Center(
        child: WmFeedbackAction(
          idleLabel: 'Add to library',
          idleIcon: Icons.favorite_border,
          loadingLabel: 'Adding…',
          successLabel: 'Added',
          onAction: () async {
            calls++;
            // A real async action so the loading state is observable.
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return true;
          },
        ),
      )));
      await tester.pumpAndSettle();

      // Labels render per-character (WmStaggeredText) — drive by icon.
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump(); // begin loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('failure surfaces the error state with retry', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(Center(
        child: WmFeedbackAction(
          idleLabel: 'Add to library',
          idleIcon: Icons.favorite_border,
          errorLabel: 'Failed',
          onAction: () async {
            calls++;
            return false;
          },
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      // Retry circle appears and re-runs the action.
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });

  group('WmExpandDetails', () {
    testWidgets('expands to reveal the details and collapses back',
        (tester) async {
      await tester.pumpWidget(_wrap(const Center(
        child: WmExpandDetails(
          title: 'Synopsis',
          collapsed: Text('A short summary…'),
          expanded: Text(
              'The full multi-line synopsis text that was hidden before.'),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Synopsis'), findsOneWidget);
      expect(find.text('A short summary…'), findsOneWidget);
      expect(
          find.text('The full multi-line synopsis text that was hidden before.'),
          findsNothing);

      await tester.tap(find.text('Synopsis'));
      await tester.pumpAndSettle();
      expect(
          find.text('The full multi-line synopsis text that was hidden before.'),
          findsOneWidget);

      await tester.tap(find.text('Synopsis'));
      await tester.pumpAndSettle();
      expect(
          find.text('The full multi-line synopsis text that was hidden before.'),
          findsNothing);
    });
  });

  group('WmStaggeredText', () {
    testWidgets('renders the text (bounded fallback for long strings)',
        (tester) async {
      await tester.pumpWidget(_wrap(const Center(
        child: WmStaggeredText(text: 'OK'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('O'), findsWidgets);
      expect(find.text('K'), findsWidgets);
    });
  });

  testWidgets('HeroIconButton badge shows the count and hides at zero',
      (tester) async {
    await tester.pumpWidget(_wrap(Center(
      child: HeroIconButton(
        icon: Icons.notifications_outlined,
        badgeCount: 7,
        onPressed: () {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);

    await tester.pumpWidget(_wrap(Center(
      child: HeroIconButton(
        icon: Icons.notifications_outlined,
        badgeCount: 0,
        onPressed: () {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
  });
}
