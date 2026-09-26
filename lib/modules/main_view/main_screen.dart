// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/lumina_ui.dart';

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
      icon: Icons.library_books_outlined,
      selectedIcon: Icons.library_books_rounded,
      label: 'Library',
    ),
    _NavDestination(
      icon: Icons.play_circle_outline_rounded,
      selectedIcon: Icons.play_circle_rounded,
      label: 'Anime',
    ),
    _NavDestination(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
      label: 'Browse',
    ),
    _NavDestination(
      icon: Icons.download_outlined,
      selectedIcon: Icons.download_rounded,
      label: 'Downloads',
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
    if (location.startsWith('/anime')) {
      selectedIndex = 1;
    } else if (location.startsWith('/browse')) {
      selectedIndex = 2;
    } else if (location.startsWith('/downloads')) {
      selectedIndex = 3;
    } else if (location.startsWith('/more') ||
        location.startsWith('/stats') ||
        location.startsWith('/notes') ||
        location.startsWith('/history') ||
        location.startsWith('/updates') ||
        location.startsWith('/calendar')) {
      selectedIndex = 4;
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
        context.go('/library');
      case 1:
        context.go('/anime');
      case 2:
        context.go('/browse');
      case 3:
        context.go('/downloads');
      case 4:
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

    return HeroGlass(
      blurSigma: 20,
      color: h.glass,
      border: Border(
        top: BorderSide(
          color: h.isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.07),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
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
        ),
      ),
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

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
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
          scale: _pressed ? 0.9 : 1.0,
          duration: heroAnimationsEnabled
              ? HeroTokens.motionTransform
              : Duration.zero,
          curve: HeroTokens.spring,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Soft-white glow pill springs in behind the active icon
              // (x.ai app-shell: active indicator = the white primary).
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
    );
  }
}
