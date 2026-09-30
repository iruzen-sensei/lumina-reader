// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/lumina_ui.dart';
import '../../core/ui/watermelon.dart';

/// App shell with the Lumina Noir navigation.
///
/// Phone: a docked frosted tab bar — the noir canvas at ~78% over a
/// clipped backdrop blur with a whisper top hairline (functional frost,
/// never decorative). The active item is WHITE with a soft-white glow
/// pill that springs in behind the icon (iOS bounce), a selection haptic
/// and the scale press micro-interaction. `extendBody` lets scrollable
/// content pass beneath the frost wherever a screen allows it.
/// Wide (>=800): navigation rail.
class MainScreen extends StatelessWidget {
  const MainScreen({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    _NavDestination(
      icon: Icons.play_circle_outline_rounded,
      selectedIcon: Icons.play_circle_rounded,
      label: 'Anime',
    ),
    _NavDestination(
      icon: Icons.library_books_outlined,
      selectedIcon: Icons.library_books_rounded,
      label: 'Library',
    ),
    _NavDestination(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
      label: 'Explore',
    ),
    _NavDestination(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      label: 'More',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final h = HeroScope.of(context);
    int selectedIndex = 0;
    if (location.startsWith('/library')) {
      selectedIndex = 1;
    } else if (location.startsWith('/browse')) {
      selectedIndex = 2;
    } else if (location.startsWith('/more') ||
        location.startsWith('/stats') ||
        location.startsWith('/notes') ||
        location.startsWith('/history') ||
        location.startsWith('/calendar') ||
        location.startsWith('/downloads') ||
        location.startsWith('/updates')) {
      selectedIndex = 3;
    }

    // Wide OR LANDSCAPE phones get the navigation rail. Width alone missed
    // every phone in landscape (~700-780 logical width but only ~360 dp of
    // height): they kept the 58pt bottom bar eating 20% of the short axis —
    // the "landscape UI bugs out / components cut off" report. shortestSide
    // < 600 keeps small portrait phones on the bottom bar.
    final size = MediaQuery.sizeOf(context);
    final isWide =
        size.width >= 800 || size.shortestSide < 600 && size.width > size.height;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => _navigate(context, i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(thickness: 1, width: 1, color: h.separator),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: _GlassTabBar(
        destinations: _destinations,
        selectedIndex: selectedIndex,
        onSelect: (i) => _navigate(context, i),
      ),
    );
  }

  void _navigate(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/anime');
      case 1:
        context.go('/library');
      case 2:
        context.go('/browse');
      case 3:
        context.go('/more');
    }
  }
}

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Frosted bottom tab bar — the noir nav surface: backdrop blur over a
/// near-black translucent canvas fill, single top hairline, 58pt tall +
/// safe-area padding. Compact production height (ChatGPT/Codex-class).
class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    // The system-navigation inset (Android 3-button / gesture bar). The
    // interactive strip stays FROSTED, but the zone behind the system
    // buttons gets an OPAQUE canvas backing: with extendBody, page content
    // scrolls under the bar and previously showed through the translucent
    // glass BEHIND the Android buttons — the "anime visible below the nav
    // bar, transparent with a white tint" artifact. Solid there, frost
    // only where the blur belongs.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // The glass layer (blur + fill + hairline) and the TAB ITEMS are
    // separate layers. HeroGlass must ClipRect so the backdrop blur stays
    // inside the bar — but that clip also sliced the bouncing icons at
    // 1.3x scale + lift (the "dock animation cut off by the nav bar's
    // own padding" report). With the items in an UNCLIPPED layer above
    // the glass, the selection pop can overshoot the bar's top edge and
    // draw over the content scrolling beneath (extendBody) — the exact
    // watermelon.sh Dock behavior.
    //
    // Below the 58pt interactive strip sits an OPAQUE canvas strip for
    // the Android system-navigation zone: with extendBody, page content
    // scrolls under the bar and previously showed through the translucent
    // glass BEHIND the system buttons — the "anime visible below the nav
    // bar, transparent with a white tint" artifact. Solid there, frost
    // only where the blur belongs.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 58,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: HeroGlass(
                  blurSigma: 20,
                  color: h.glass,
                  border: Border(
                    top: BorderSide(
                      color: h.isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.07),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _TabItem(
                        destination: destinations[i],
                        selected: i == selectedIndex,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (bottomInset > 0)
          Container(height: bottomInset, color: h.background),
      ],
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _pressed = false;

  /// Dock selection pop: true for ~200ms after the tap lands — the item
  /// scales to 1.3 and lifts, then settles (watermelon.sh Dock physics).
  bool _popping = false;

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
    if (heroAnimationsEnabled) {
      setState(() => _popping = true);
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _popping = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final d = widget.destination;
    final active = widget.selected;

    return Semantics(
      button: true,
      selected: active,
      label: d.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _handleTap,
        child: AnimatedScale(
          // Dock pattern: press = 0.9 dip; selection pop = 1.3 bounce.
          scale: _popping ? 1.3 : (_pressed ? 0.9 : 1.0),
          duration: heroAnimationsEnabled
              ? (_popping
                  ? const Duration(milliseconds: 200)
                  : HeroTokens.motionTransform)
              : Duration.zero,
          curve: _popping ? const WmBounceCurve() : HeroTokens.spring,
          child: AnimatedSlide(
            // Lift the icon while popping (dock magnification feel).
            offset: Offset(0, _popping ? -0.08 : 0),
            duration: heroAnimationsEnabled
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            curve: const WmBounceCurve(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedScale(
                      scale: active ? 1.0 : 0.0,
                      duration: heroAnimationsEnabled
                          ? HeroTokens.motionTransform
                          : Duration.zero,
                      curve: HeroTokens.spring,
                      child: Container(
                        width: 48,
                        height: 30,
                        decoration: BoxDecoration(
                          color: h.accentSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Icon(
                      active ? d.selectedIcon : d.icon,
                      size: 23,
                      color: active ? h.accent : h.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Dock selection dot — fades/scales in under the active
                // item (the source's indicator pattern).
                AnimatedScale(
                  scale: active ? 1.0 : 0.0,
                  duration: heroAnimationsEnabled
                      ? const Duration(milliseconds: 220)
                      : Duration.zero,
                  curve: const WmBounceCurve(),
                  child: AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: heroAnimationsEnabled
                        ? const Duration(milliseconds: 180)
                        : Duration.zero,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: h.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  d.label,
                  style: TextStyle(
                    fontFamily: HeroTokens.fontSans,
                    fontSize: 10,
                    height: 1.1,
                    letterSpacing: 0.06,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? h.foreground : h.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
