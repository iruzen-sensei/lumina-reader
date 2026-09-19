// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/heroui_v3.dart';

/// App shell with the HeroUI-style navigation.
///
/// Phone: bottom bar — 5 destinations, pill indicator on the accent-soft
/// tint, 68pt tall, hairline top border in dark mode (HeroUI surfaces get
/// definition from borders, not elevation shadows).
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

    final isWide = MediaQuery.of(context).size.width >= 800;

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
      body: child,
      bottomNavigationBar: _HeroNavBar(
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

/// HeroUI-style bottom navigation bar.
///
/// * surface background with a hairline top border (dark) / shadow (light)
/// * selected item: accent-soft pill behind the icon, accent icon + label
/// * press feedback: icon scale dip, 250ms smooth easing
/// * 68pt tall + safe-area padding
class _HeroNavBar extends StatelessWidget {
  const _HeroNavBar({
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: h.surface,
        border: Border(
          top: BorderSide(color: h.isDark ? h.border : h.separator),
        ),
        boxShadow: !h.isDark
            ? [
                const BoxShadow(
                  color: Color(0x0D000000),
                  offset: Offset(0, -2),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavBarItem(
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

class _NavBarItem extends StatefulWidget {
  const _NavBarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final d = widget.destination;
    final active = widget.selected;
    final iconColor = active ? h.accent : h.muted;

    return Semantics(
      button: true,
      selected: active,
      label: d.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: heroAnimationsEnabled
              ? HeroTokens.motionTransform
              : Duration.zero,
          curve: HeroTokens.easeSmooth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: heroAnimationsEnabled
                    ? HeroTokens.motionTransform
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
                decoration: BoxDecoration(
                  color: active ? h.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  active ? d.selectedIcon : d.icon,
                  size: 23,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                d.label,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.1,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? h.accentSoftFg : h.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
