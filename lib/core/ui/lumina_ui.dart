// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// LUMINA DESIGN SYSTEM — Apple × ElevenLabs
//
// Built strictly from two DESIGN.md analyses (VoltAgent/awesome-design-md):
//
//  APPLE (colors, components, glassmorphism, motion):
//   * Single interactive accent — Action Blue #0066CC (Focus Blue #0071E3 on
//     press, Sky Link Blue #2997FF for tinted text on dark surfaces).
//   * Canvas rhythm — pure white ↔ parchment #F5F5F7; the color change IS
//     the divider. Cards float via 1px hairlines (#E0E0E0), NEVER shadows.
//   * Exactly ONE shadow in the whole system: the product shadow
//     rgba(0,0,0,0.22) 0/5/30 — reserved for imagery resting on a surface.
//   * Radii grammar: pill (999) for every action/CTA/chip/input-search,
//     18px for utility cards, 12px for compact controls.
//   * Glassmorphism: frosted surfaces — backdrop blur + saturate(180%) +
//     translucent canvas fill + hairline (global nav, sub-nav, sticky bars,
//     circular chips over photography at #D2D2D7 @64%).
//   * Micro-interaction: scale(0.95) press on every button — system-wide.
//   * 44px minimum touch targets.
//
//  ELEVENLABS (typography, atmosphere, badges):
//   * Display = editorial serif at weight 300 — NEVER bold. Licensed
//     Waldenburg → open substitute "Spectral Light" (true 300 cut), with
//     negative tracking (-0.32…-0.36px at 32-34px display sizes).
//   * Body/UI = Inter 400/500 with subtle positive tracking (+0.15…+0.18px)
//     — the editorial dialect. Ramp: 16 / 15 / 14 / 13 body-captions,
//     20 / 18 titles, 12/600/+0.96px UPPERCASE section labels & badges.
//   * Atmospheric gradient orbs (mint/peach/lavender/sky/rose) — pure
//     atmosphere, never on controls.
//   * Semantic: success #16A34A, error #DC2626.
//
//  MOTION (iOS-grade, on top of both MDs):
//   * Spring physics everywhere: Cubic(0.34,1.56,0.64,1) for bouncy
//     releases, Cubic(0.22,1,0.36,1) for smooth settles.
//   * Staggered spring entrances for grids and lists.
//   * 380-480ms transforms/entrances, 180ms color fades.
//
// The Hero* widget anatomy (Button/Chip/Card/Input/Tabs/Switch...) keeps the
// exact public API of the previous design system — only the VALUES changed,
// so every screen adopting Hero* inherits the new language for free.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global switch for golden tests: disables infinite animations (shimmer)
/// so pumpAndSettle terminates.
bool heroAnimationsEnabled = true;

// ---------------------------------------------------------------------------
// TOKENS
// ---------------------------------------------------------------------------

/// The Lumina semantic palette (static constants — no BuildContext).
///
/// For theme-aware resolution use [HeroScope.of] / the `Hero*` widgets, which
/// pick light or dark rows automatically.
class HeroTokens {
  HeroTokens._();

  // -- Type families ---------------------------------------------------------
  /// Body / UI family (ElevenLabs body dialect).
  static const String fontSans = 'Inter';

  /// Display family — editorial serif, Light 300 only (ElevenLabs display
  /// dialect; Waldenburg's open substitute with a true 300 cut).
  static const String fontSerif = 'Spectral';

  // -- Accents (Apple: the single interactive color) -------------------------
  /// Action Blue — every interactive element, light surfaces.
  static const Color accent = Color(0xFF0066CC);

  /// Focus Blue — pressed / focused variant (Apple primary-focus).
  static const Color accentHover = Color(0xFF0071E3);

  /// Sky Link Blue — tinted accent text on dark surfaces (Apple
  /// primary-on-dark); Action Blue disappears against near-black tiles.
  static const Color accentOnDark = Color(0xFF2997FF);

  // -- Semantic (ElevenLabs semantic tokens + amber for data states) --------
  static const Color success = Color(0xFF16A34A); // ElevenLabs success
  static const Color successHover = Color(0xFF15803D);
  static const Color successDark = Color(0xFF34C759); // iOS green, on black
  static const Color warningLight = Color(0xFFD97706); // amber data state
  static const Color warningDark = Color(0xFFF5A524);
  static const Color dangerLight = Color(0xFFDC2626); // ElevenLabs error
  static const Color dangerDark = Color(0xFFFF453A); // iOS red, on black
  static const Color dangerHoverLight = Color(0xFFB91C1C);
  static const Color dangerHoverDark = Color(0xFFFF6961);

  // -- Light theme (Apple light surfaces) -------------------------------------
  static const Color lightBackground = Color(0xFFF5F5F7); // parchment canvas
  static const Color lightSurface = Color(0xFFFFFFFF); // white cards
  static const Color lightSurface2 = Color(0xFFFAFAFC); // pearl
  static const Color lightSurface3 = Color(0xFFF0F0F0); // divider-soft fill
  static const Color lightSurfaceHover = Color(0xFFF0EFED); // warm hover
  static const Color lightForeground = Color(0xFF1D1D1F); // near-black ink
  static const Color lightMuted = Color(0xFF7A7A7A); // ink-muted-48
  static const Color lightDefault = Color(0xFFE5E5EA); // iOS gray5 fills
  static const Color lightDefaultHover = Color(0xFFD8D8DC);
  static const Color lightBorder = Color(0xFFE0E0E0); // hairline
  static const Color lightSeparator = Color(0xFFF0F0F0); // divider-soft

  // -- Dark theme (Apple dark tiles + iOS system darks) -----------------------
  static const Color darkBackground = Color(0xFF000000); // true void
  static const Color darkSurface = Color(0xFF1C1C1E); // cards on void
  static const Color darkSurface2 = Color(0xFF2A2A2C); // Apple tile-2
  static const Color darkSurface3 = Color(0xFF252527); // Apple tile-3 wells
  static const Color darkSurfaceHover = Color(0xFF232326);
  static const Color darkForeground = Color(0xFFFFFFFF);
  static const Color darkMuted = Color(0xFFCCCCCC); // Apple body-muted
  static const Color darkDefault = Color(0xFF2C2C2E); // iOS gray5 dark
  static const Color darkDefaultHover = Color(0xFF3A3A3C);
  static const Color darkBorder = Color(0xFF38383A);
  static const Color darkSeparator = Color(0xFF26262A);
  static const Color darkSegment = Color(0xFF48484A);

  // -- Radii (Apple radius grammar) -------------------------------------------
  /// Base radius (Apple rounded.lg — store utility cards).
  static const double radius = 18;

  /// Field radius — pill (Apple search-input is a full pill).
  static const double radiusField = 999;

  /// Chip radius — pill (Apple configurator chips / ElevenLabs badge-pill).
  static const double radiusChip = 999;

  /// Card radius (Apple rounded.lg utility card).
  static const double radiusCard = 18;

  /// Button radius — pill (the signature Apple CTA grammar).
  static const double radiusButton = 999;

  /// Tabs container radius — pill (iOS segmented control).
  static const double radiusTabs = 999;

  // -- Shadows -----------------------------------------------------------------
  /// Apple: cards NEVER carry shadows — definition comes from the 1px
  /// hairline. Elevation in light mode = surface-color change.
  static const List<BoxShadow> surfaceShadowLight = [];

  /// Overlays (modals, menus, popovers) — the one soft detachment shadow.
  static const List<BoxShadow> overlayShadowLight = [
    BoxShadow(
      color: Color(0x29000000),
      offset: Offset(0, 16),
      blurRadius: 48,
    ),
  ];

  /// Dark-mode: no elevation shadows — hairline only.
  static const List<BoxShadow> surfaceShadowDark = [];

  /// THE product shadow — Apple's single drop, reserved for imagery
  /// (book covers, posters) resting on a surface. Never on cards/buttons.
  static const List<BoxShadow> productShadow = [
    BoxShadow(
      color: Color(0x38000000), // rgba(0,0,0,0.22)
      offset: Offset(0, 5),
      blurRadius: 30,
    ),
  ];

  /// Product shadow on dark surfaces.
  static const List<BoxShadow> productShadowDark = [
    BoxShadow(
      color: Color(0x66000000),
      offset: Offset(0, 5),
      blurRadius: 30,
    ),
  ];

  // -- Motion (iOS spring physics) ---------------------------------------------
  /// Smooth settle curve (fast-out, long soft landing).
  static const Curve easeSmooth = Curves.easeOutCubic;

  /// The iOS bounce — overshoot-and-settle for releases and entrances.
  static const Curve spring = Cubic(0.34, 1.56, 0.64, 1.0);

  /// Gentle spring — big elements (sheets, cards, cursors).
  static const Curve springSoft = Cubic(0.22, 1, 0.36, 1);

  /// Transform duration (spring releases, presses).
  static const Duration motionTransform = Duration(milliseconds: 380);

  /// Colour/fade duration.
  static const Duration motionColor = Duration(milliseconds: 180);

  /// Entrance duration for modals/sheets/staggers.
  static const Duration motionEntrance = Duration(milliseconds: 460);

  // -- Spacing (Apple 8px base rhythm) ------------------------------------------
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  // -- Typography (ElevenLabs ramp: Spectral 300 display / Inter body) ---------
  /// Display headline — Spectral Light 300, tight tracking, never bold.
  static const TextStyle display = TextStyle(
    fontFamily: fontSerif,
    fontSize: 34,
    height: 1.13,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.34,
  );

  /// Large screen titles — Spectral Light 300.
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontSerif,
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.26,
  );

  /// Component titles — Inter 500 (ElevenLabs title dialect).
  static const TextStyle title = TextStyle(
    fontFamily: fontSans,
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  );

  /// Body copy — Inter 400 with the editorial +0.16px tracking.
  static const TextStyle body = TextStyle(
    fontFamily: fontSans,
    fontSize: 15.5,
    height: 1.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.16,
  );

  /// Secondary body — Inter 400 (ElevenLabs body-sm).
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontSans,
    fontSize: 14,
    height: 1.47,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.14,
  );

  /// Captions — Inter 400.
  static const TextStyle caption = TextStyle(
    fontFamily: fontSans,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Section labels & badges — ElevenLabs caption-uppercase:
  /// Inter 600, 12px, +0.96px tracking, always uppercased.
  static const TextStyle captionUpper = TextStyle(
    fontFamily: fontSans,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.96,
  );

  // -- Atmosphere (ElevenLabs gradient orbs — pure decoration) -----------------
  static const Color orbMint = Color(0xFFA7E5D3);
  static const Color orbPeach = Color(0xFFF4C5A8);
  static const Color orbLavender = Color(0xFFC8B8E0);
  static const Color orbSky = Color(0xFFA8C8E8);
  static const Color orbRose = Color(0xFFE8B8C4);
}

/// Semantic colors resolved for the current brightness.
class HeroThemeData {
  const HeroThemeData({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.surfaceHover,
    required this.foreground,
    required this.muted,
    required this.dflt,
    required this.defaultHover,
    required this.border,
    required this.separator,
    required this.accent,
    required this.accentSoft,
    required this.accentSoftFg,
    required this.accentFg,
    required this.success,
    required this.successSoft,
    required this.successSoftFg,
    required this.warning,
    required this.warningSoft,
    required this.warningSoftFg,
    required this.danger,
    required this.dangerSoft,
    required this.dangerSoftFg,
    required this.surfaceShadow,
    required this.overlayShadow,
  });

  final Brightness brightness;
  final Color background, surface, surface2, surface3, surfaceHover;
  final Color foreground, muted;
  final Color dflt, defaultHover;
  final Color border, separator;

  final Color accent, accentSoft, accentSoftFg, accentFg;
  final Color success, successSoft, successSoftFg;
  final Color warning, warningSoft, warningSoftFg;
  final Color danger, dangerSoft, dangerSoftFg;

  final List<BoxShadow> surfaceShadow, overlayShadow;

  bool get isDark => brightness == Brightness.dark;

  /// Frosted-glass fill — the Apple sub-nav recipe: canvas at ~78% over a
  /// backdrop blur (pair with [HeroGlass]).
  Color get glass =>
      isDark ? const Color(0xD11C1C1E) : const Color(0xC7F5F5F7);

  /// Circular control chips floating over imagery (Apple translucent chip,
  /// #D2D2D7 at 64%).
  Color get chipTranslucent =>
      isDark ? const Color(0xA63A3A3C) : const Color(0xA3D2D2D7);

  /// The single imagery shadow, theme-aware.
  List<BoxShadow> get productShadow =>
      isDark ? HeroTokens.productShadowDark : HeroTokens.productShadow;

  /// Backdrop for modals (Apple scrim).
  Color get backdrop =>
      isDark ? const Color(0x99000000) : const Color(0x59000000);

  static HeroThemeData light() => const HeroThemeData(
        brightness: Brightness.light,
        background: HeroTokens.lightBackground,
        surface: HeroTokens.lightSurface,
        surface2: HeroTokens.lightSurface2,
        surface3: HeroTokens.lightSurface3,
        surfaceHover: HeroTokens.lightSurfaceHover,
        foreground: HeroTokens.lightForeground,
        muted: HeroTokens.lightMuted,
        dflt: HeroTokens.lightDefault,
        defaultHover: HeroTokens.lightDefaultHover,
        border: HeroTokens.lightBorder,
        separator: HeroTokens.lightSeparator,
        accent: HeroTokens.accent,
        accentSoft: Color(0x1A0066CC), // Action Blue 10%
        accentSoftFg: Color(0xFF0066CC),
        accentFg: Colors.white, // white on Action Blue (4.6:1)
        success: HeroTokens.success,
        successSoft: Color(0x1A16A34A),
        successSoftFg: Color(0xFF15803D),
        warning: HeroTokens.warningLight,
        warningSoft: Color(0x1FD97706),
        warningSoftFg: Color(0xFFB45309),
        danger: HeroTokens.dangerLight,
        dangerSoft: Color(0x1ADC2626),
        dangerSoftFg: Color(0xFFB91C1C),
        surfaceShadow: HeroTokens.surfaceShadowLight,
        overlayShadow: HeroTokens.overlayShadowLight,
      );

  static HeroThemeData dark() => const HeroThemeData(
        brightness: Brightness.dark,
        background: HeroTokens.darkBackground,
        surface: HeroTokens.darkSurface,
        surface2: HeroTokens.darkSurface2,
        surface3: HeroTokens.darkSurface3,
        surfaceHover: HeroTokens.darkSurfaceHover,
        foreground: HeroTokens.darkForeground,
        muted: HeroTokens.darkMuted,
        dflt: HeroTokens.darkDefault,
        defaultHover: HeroTokens.darkDefaultHover,
        border: HeroTokens.darkBorder,
        separator: HeroTokens.darkSeparator,
        accent: HeroTokens.accent, // Action Blue still works on dark
        accentSoft: Color(0x292997FF), // Sky Link Blue 16% on dark
        accentSoftFg: Color(0xFF66B2FF), // readable Sky Link on tint
        accentFg: Colors.white,
        success: HeroTokens.successDark,
        successSoft: Color(0x2434C759),
        successSoftFg: Color(0xFF5AD177),
        warning: HeroTokens.warningDark,
        warningSoft: Color(0x24F5A524),
        warningSoftFg: Color(0xFFFBBF24),
        danger: HeroTokens.dangerDark,
        dangerSoft: Color(0x24FF453A),
        dangerSoftFg: Color(0xFFFF6961),
        surfaceShadow: HeroTokens.surfaceShadowDark,
        overlayShadow: [
          BoxShadow(
            color: Color(0x80000000),
            offset: Offset(0, 16),
            blurRadius: 48,
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Inherited resolution
// ---------------------------------------------------------------------------

class HeroScope extends InheritedWidget {
  const HeroScope({super.key, required this.data, required super.child});
  final HeroThemeData data;

  static HeroThemeData of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<HeroScope>();
    if (w != null) return w.data;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark
        ? HeroThemeData.dark()
        : HeroThemeData.light();
  }

  @override
  bool updateShouldNotify(HeroScope oldWidget) => oldWidget.data != data;
}

/// Convenience accessor: `final h = Hero.of(context);`
// ignore: non_constant_identifier_names
HeroThemeData HeroOf(BuildContext context) => HeroScope.of(context);

// ---------------------------------------------------------------------------
// Semantic color roles for enum-driven components
// ---------------------------------------------------------------------------

enum HeroColorRole { accent, success, warning, danger, neutral }

_HeroRoleColors _role(HeroThemeData h, HeroColorRole role) {
  switch (role) {
    case HeroColorRole.accent:
      return _HeroRoleColors(
        base: h.accent,
        soft: h.accentSoft,
        softFg: h.accentSoftFg,
        onBase: h.accentFg,
      );
    case HeroColorRole.success:
      return _HeroRoleColors(
        base: h.success,
        soft: h.successSoft,
        softFg: h.successSoftFg,
        onBase: Colors.white,
      );
    case HeroColorRole.warning:
      return _HeroRoleColors(
        base: h.warning,
        soft: h.warningSoft,
        softFg: h.warningSoftFg,
        onBase: Colors.white,
      );
    case HeroColorRole.danger:
      return _HeroRoleColors(
        base: h.danger,
        soft: h.dangerSoft,
        softFg: h.dangerSoftFg,
        onBase: Colors.white,
      );
    case HeroColorRole.neutral:
      return _HeroRoleColors(
        base: h.foreground,
        soft: h.dflt,
        softFg: h.foreground,
        onBase: h.background,
      );
  }
}

class _HeroRoleColors {
  const _HeroRoleColors({
    required this.base,
    required this.soft,
    required this.softFg,
    required this.onBase,
  });
  final Color base, soft, softFg, onBase;
}

/// sRGB mix helper (approximates CSS color-mix for token derivations).
Color _mix(Color a, Color b, double t) {
  return Color.fromARGB(
    ((a.a + (b.a - a.a) * t) * 255).round().clamp(0, 255),
    ((a.r + (b.r - a.r) * t) * 255).round().clamp(0, 255),
    ((a.g + (b.g - a.g) * t) * 255).round().clamp(0, 255),
    ((a.b + (b.b - a.b) * t) * 255).round().clamp(0, 255),
  );
}

// ---------------------------------------------------------------------------
// HeroGlass — Apple frosted surface (backdrop blur + translucent canvas
// fill + hairline). The sub-nav / sticky-bar / over-imagery material.
// ---------------------------------------------------------------------------

class HeroGlass extends StatelessWidget {
  const HeroGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.color,
    this.blurSigma = 22,
    this.border,
    this.padding,
  });

  final Widget child;

  /// null = square (bars); pass [BorderRadius.circular] for cards/chips.
  final BorderRadius? borderRadius;

  /// Fill over the blur — defaults to the theme glass recipe (canvas @ ~78%).
  final Color? color;
  final double blurSigma;

  /// Hairline over the glass; null = none.
  final Border? border;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final radius = borderRadius;

    // ALWAYS clip the backdrop filter: an unclipped BackdropFilter applies
    // its blur to the entire backdrop region (the whole screen), not just
    // the glass surface — the classic frosted-glass footgun.
    Widget body = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? h.glass,
            borderRadius: radius,
            border: border,
          ),
          child: child,
        ),
      ),
    );

    if (radius != null) body = ClipRRect(borderRadius: radius, child: body);
    return body;
  }
}

/// Circular frosted control chip floating over imagery — Apple's
/// translucent chip (#D2D2D7 @64%) with a hairline and press bounce.
class HeroGlassIconButton extends StatefulWidget {
  const HeroGlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  State<HeroGlassIconButton> createState() => _HeroGlassIconButtonState();
}

class _HeroGlassIconButtonState extends State<HeroGlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final enabled = widget.onPressed != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration:
            heroAnimationsEnabled ? HeroTokens.motionTransform : Duration.zero,
        curve: HeroTokens.spring,
        child: HeroGlass(
          borderRadius: BorderRadius.circular(widget.size / 2),
          color: h.chipTranslucent,
          border: Border.all(
            color: h.isDark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.45),
            width: 1,
          ),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.color ??
                  (h.isDark ? Colors.white : HeroTokens.lightForeground),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroScaleTap — the Apple system-wide scale(0.95) press micro-interaction
// wrapped around any child, released on an iOS spring.
// ---------------------------------------------------------------------------

class HeroScaleTap extends StatefulWidget {
  const HeroScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<HeroScaleTap> createState() => _HeroScaleTapState();
}

class _HeroScaleTapState extends State<HeroScaleTap> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    if (v && widget.haptic) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: heroAnimationsEnabled
            ? HeroTokens.motionTransform
            : Duration.zero,
        curve: HeroTokens.spring,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroEntrance — staggered spring entrance (fade + rise + micro-scale).
// Give grid/list children an increasing [index]; each delays ~45ms.
// ---------------------------------------------------------------------------

class HeroEntrance extends StatefulWidget {
  const HeroEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 45),
  });

  final Widget child;
  final int index;
  final Duration step;

  @override
  State<HeroEntrance> createState() => _HeroEntranceState();
}

class _HeroEntranceState extends State<HeroEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: heroAnimationsEnabled
        ? HeroTokens.motionEntrance
        : Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    if (heroAnimationsEnabled) {
      final delay = Duration(
        microseconds:
            (widget.step.inMicroseconds * widget.index).clamp(0, 400000),
      );
      Future.delayed(delay, () {
        if (mounted) _c.forward();
      });
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!heroAnimationsEnabled || _c.isCompleted) return widget.child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: HeroTokens.springSoft),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _c, curve: HeroTokens.spring)),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(
            CurvedAnimation(parent: _c, curve: HeroTokens.spring),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroOrbs — ElevenLabs atmospheric gradient orbs. Pure decoration:
// soft radial blooms drifting behind hero copy / empty states. Never on
// controls, never containing content.
// ---------------------------------------------------------------------------

class HeroOrbs extends StatelessWidget {
  const HeroOrbs({
    super.key,
    this.colors = const [
      HeroTokens.orbSky,
      HeroTokens.orbPeach,
      HeroTokens.orbLavender,
    ],
    this.opacity = 0.5,
    this.seed = 0,
  });

  final List<Color> colors;
  final double opacity;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final hgt = constraints.maxHeight;
        if (!w.isFinite || !hgt.isFinite || w <= 0 || hgt <= 0) {
          return const SizedBox.shrink();
        }
        final big = w * 1.35;

        // Deterministic placement per (index, seed) — stable across rebuilds.
        Offset pos(int i) {
          final x = ((seed * 37 + i * 613) % 100) / 100 * w;
          final y = ((seed * 89 + i * 277) % 100) / 100 * hgt;
          return Offset(x, y);
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < colors.length; i++)
              Positioned(
                left: pos(i).dx - big / 4,
                top: pos(i).dy - big / 4,
                child: IgnorePointer(
                  child: Container(
                    width: big / 2,
                    height: big / 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors[i].withValues(alpha: opacity),
                          colors[i].withValues(alpha: 0),
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HeroLargeTitle — the editorial screen header: ElevenLabs caption-uppercase
// overline + Spectral Light display title (+ optional Inter subtitle).
// ---------------------------------------------------------------------------

class HeroLargeTitle extends StatelessWidget {
  const HeroLargeTitle({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 8),
  });

  final String title;
  final String? overline;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) ...[
                  Text(
                    overline!.toUpperCase(),
                    style: HeroTokens.captionUpper.copyWith(color: h.muted),
                  ),
                  const SizedBox(height: 5),
                ],
                Text(
                  title,
                  style: HeroTokens.display.copyWith(color: h.foreground),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: HeroTokens.bodySmall.copyWith(color: h.muted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroButton — Apple Action-Blue pill CTA. Scale(0.95) press on an iOS
// spring (the system-wide micro-interaction), 44px large target.
// ---------------------------------------------------------------------------

enum HeroButtonVariant { solid, soft, bordered, light, ghost }

enum HeroButtonSize { sm, md, lg }

class HeroButton extends StatefulWidget {
  const HeroButton({
    super.key,
    this.onPressed,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.variant = HeroButtonVariant.solid,
    this.size = HeroButtonSize.md,
    this.color = HeroColorRole.accent,
    this.loading = false,
    this.fullWidth = false,
    this.autofocus = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final HeroButtonVariant variant;
  final HeroButtonSize size;
  final HeroColorRole color;
  final bool loading;
  final bool fullWidth;
  final bool autofocus;

  @override
  State<HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<HeroButton> {
  bool _pressed = false;
  bool _hovered = false;

  static const _sizes = {
    // Apple: 44px touch targets for the primary size; pill grammar;
    // Inter 500 labels (ElevenLabs button dialect).
    HeroButtonSize.sm: (h: 32.0, px: 14.0, font: 14.0, icon: 16.0),
    HeroButtonSize.md: (h: 40.0, px: 18.0, font: 15.0, icon: 18.0),
    HeroButtonSize.lg: (h: 48.0, px: 24.0, font: 17.0, icon: 20.0),
  };

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final colors = _role(h, widget.color);
    final s = _sizes[widget.size]!;
    final enabled = widget.onPressed != null && !widget.loading;

    Color bg;
    Color fg;
    Color? border;
    switch (widget.variant) {
      case HeroButtonVariant.solid:
        bg = colors.base;
        fg = colors.onBase;
        if (_hovered && enabled) bg = _mix(colors.base, Colors.black, 0.12);
      case HeroButtonVariant.soft:
        bg = colors.soft;
        fg = colors.softFg;
        if (_hovered && enabled) {
          bg = _mix(colors.soft, colors.base, 0.10);
        }
      case HeroButtonVariant.bordered:
        // Apple ghost pill: transparent, role-colored text + role border.
        bg = Colors.transparent;
        fg = colors.base;
        border = colors.base.withValues(alpha: 0.45);
        if (_hovered && enabled) bg = colors.soft;
      case HeroButtonVariant.light:
        // Apple pearl capsule: near-white fill, softened ink label.
        bg = widget.color == HeroColorRole.neutral
            ? (h.isDark ? h.dflt : h.surface2)
            : colors.soft;
        fg = widget.color == HeroColorRole.neutral
            ? h.foreground
            : colors.softFg;
        if (_hovered && enabled) {
          bg = _mix(bg, colors.base, 0.08);
        }
      case HeroButtonVariant.ghost:
        bg = Colors.transparent;
        fg = h.muted;
        if (_hovered && enabled) bg = h.dflt;
    }

    // ScaleDown keeps the pill label intact when the host is narrower
    // than the natural content width (no RenderFlex overflow, ever).
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.loading)
            SizedBox(
              width: s.icon,
              height: s.icon,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                strokeCap: StrokeCap.round,
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            )
          else if (widget.icon != null) ...[
            Icon(widget.icon, size: s.icon, color: fg),
            const SizedBox(width: 7),
          ],
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: HeroTokens.fontSans,
              fontSize: s.font,
              fontWeight: FontWeight.w500,
              color: fg,
              height: 1,
              letterSpacing: 0,
            ),
          ),
          if (widget.trailingIcon != null) ...[
            const SizedBox(width: 7),
            Icon(widget.trailingIcon, size: s.icon, color: fg),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: Focus(
        autofocus: widget.autofocus,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel:
                enabled ? () => setState(() => _pressed = false) : null,
            onTap: enabled ? widget.onPressed : null,
            child: AnimatedScale(
              // Apple's system-wide press micro-interaction.
              scale: _pressed ? 0.95 : 1.0,
              duration: heroAnimationsEnabled
                  ? HeroTokens.motionTransform
                  : Duration.zero,
              curve: HeroTokens.spring,
              child: AnimatedContainer(
                duration: heroAnimationsEnabled
                    ? HeroTokens.motionColor
                    : Duration.zero,
                curve: Curves.easeOut,
                height: s.h,
                padding: EdgeInsets.symmetric(horizontal: s.px),
                decoration: BoxDecoration(
                  color: enabled ? bg : h.dflt.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(HeroTokens.radiusButton),
                  border: border != null
                      ? Border.all(color: border, width: 1.2)
                      : null,
                  // Apple: no button shadows — colour + shape carry the
                  // affordance.
                ),
                child: Center(
                  child: Opacity(
                    opacity: enabled ? 1 : 0.55,
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroIconButton — circular quiet control, hover wash, springy press.
// ---------------------------------------------------------------------------

class HeroIconButton extends StatefulWidget {
  const HeroIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 38,
    this.iconSize = 21,
    this.color,
    this.variant = HeroColorRole.neutral,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final HeroColorRole variant;
  final Color? backgroundColor;

  @override
  State<HeroIconButton> createState() => _HeroIconButtonState();
}

class _HeroIconButtonState extends State<HeroIconButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final colors = _role(h, widget.variant);
    final enabled = widget.onPressed != null;
    final fg = widget.color ??
        (widget.variant == HeroColorRole.neutral ? h.foreground : colors.base);

    final btn = AnimatedScale(
      scale: _pressed ? 0.9 : 1.0,
      duration:
          heroAnimationsEnabled ? HeroTokens.motionTransform : Duration.zero,
      curve: HeroTokens.spring,
      child: AnimatedContainer(
        duration:
            heroAnimationsEnabled ? HeroTokens.motionColor : Duration.zero,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.backgroundColor ??
              (_hovered && enabled ? h.dflt : Colors.transparent),
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: enabled ? fg : h.muted.withValues(alpha: 0.5),
        ),
      ),
    );

    Widget result = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: Center(child: btn),
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 600),
        child: result,
      );
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// HeroChip — pill badge (Apple configurator chip × ElevenLabs badge-pill).
// ---------------------------------------------------------------------------

enum HeroChipVariant { solid, soft, bordered, outlineText }

class HeroChip extends StatelessWidget {
  const HeroChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
    this.variant = HeroChipVariant.soft,
    this.color = HeroColorRole.accent,
    this.dotColor,
    this.deleteIcon,
    this.onDeleted,
    this.small = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  /// [HeroChipVariant.outlineText] is used by filter rows: unselected =
  /// neutral text on default bg; selected = role base text on role soft bg.
  final HeroChipVariant variant;
  final HeroColorRole color;
  final Color? dotColor;
  final IconData? deleteIcon;
  final VoidCallback? onDeleted;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final colors = _role(h, color);

    final Color bg;
    final Color fg;
    switch (variant) {
      case HeroChipVariant.solid:
        bg = colors.base;
        fg = colors.onBase;
      case HeroChipVariant.soft:
        bg = selected ? colors.soft : h.dflt;
        fg = selected ? colors.softFg : h.foreground;
      case HeroChipVariant.bordered:
        bg = Colors.transparent;
        fg = colors.softFg;
      case HeroChipVariant.outlineText:
        bg = selected ? colors.soft : h.dflt;
        fg = selected ? colors.softFg : h.muted;
    }

    final chip = AnimatedContainer(
      duration: heroAnimationsEnabled ? HeroTokens.motionColor : Duration.zero,
      // Pill geometry — Apple configurator chip / ElevenLabs badge-pill.
      padding: EdgeInsets.symmetric(
        horizontal: small ? 10 : 12,
        vertical: small ? 3.5 : 5.5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
        border: variant == HeroChipVariant.bordered
            ? Border.all(color: h.border)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: HeroTokens.fontSans,
              fontSize: small ? 12 : 13,
              height: 1.3,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.1,
              color: fg,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDeleted,
              child: Icon(Icons.close_rounded, size: 14, color: fg),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    return HeroScaleTap(
      onTap: onTap,
      scale: 0.94,
      child: chip,
    );
  }
}

// ---------------------------------------------------------------------------
// HeroCard — Apple store utility card: white on parchment, 18px radius,
// 1px hairline, NO shadow (elevation = surface colour change).
// ---------------------------------------------------------------------------

enum HeroCardVariant { defaultVariant, secondary, tertiary, transparent }

class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.variant = HeroCardVariant.defaultVariant,
    this.onTap,
    this.borderRadius,
    this.showBorder = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final HeroCardVariant variant;
  final VoidCallback? onTap;
  final double? borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final radius = borderRadius ?? HeroTokens.radiusCard;

    final bg = switch (variant) {
      HeroCardVariant.defaultVariant => h.surface,
      HeroCardVariant.secondary => h.isDark ? h.surface : h.surface2,
      HeroCardVariant.tertiary => h.isDark ? h.surface3 : h.surface3,
      HeroCardVariant.transparent => Colors.transparent,
    };

    final card = AnimatedContainer(
      duration: heroAnimationsEnabled ? HeroTokens.motionColor : Duration.zero,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow:
            variant == HeroCardVariant.defaultVariant ? h.surfaceShadow : null,
        // Apple hairline: the card's only definition on the parchment canvas.
        border: variant != HeroCardVariant.transparent
            ? Border.all(
                color: showBorder
                    ? h.border
                    : (h.isDark ? h.border : h.border),
              )
            : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return HeroScaleTap(
      onTap: onTap,
      scale: 0.98,
      child: card,
    );
  }
}

// ---------------------------------------------------------------------------
// HeroSwitch — iOS switch anatomy: 51x31 pill track, 27px thumb, Action
// Blue when on, springy travel.
// ---------------------------------------------------------------------------

class HeroSwitch extends StatelessWidget {
  const HeroSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final track = value ? (activeColor ?? h.accent) : h.dflt;
    final enabled = onChanged != null;

    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        onPanEnd: enabled
            ? (d) {
                if (d.velocity.pixelsPerSecond.dx.abs() > 40) {
                  onChanged!(d.velocity.pixelsPerSecond.dx > 0);
                } else {
                  onChanged!(!value);
                }
              }
            : null,
        child: AnimatedContainer(
          duration: heroAnimationsEnabled
              ? HeroTokens.motionTransform
              : Duration.zero,
          curve: HeroTokens.springSoft,
          width: 51,
          height: 31,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: enabled ? track : h.dflt.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: heroAnimationsEnabled
                ? HeroTokens.motionTransform
                : Duration.zero,
            curve: HeroTokens.spring,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 27,
              height: 27,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x24000000),
                      offset: Offset(0, 2),
                      blurRadius: 5),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroInput — Apple search-input grammar: full pill, 44px, white surface +
// hairline; focus thickens the border to 2px Action Blue (ElevenLabs
// focus behaviour on Apple geometry).
// ---------------------------------------------------------------------------

class HeroInput extends StatefulWidget {
  const HeroInput({
    super.key,
    this.controller,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLines;
  final bool enabled;

  @override
  State<HeroInput> createState() => _HeroInputState();
}

class _HeroInputState extends State<HeroInput> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      final focused = _focus.hasFocus;
      if (focused != _focused) setState(() => _focused = focused);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);

    return AnimatedContainer(
      duration: heroAnimationsEnabled ? HeroTokens.motionColor : Duration.zero,
      height: widget.maxLines == 1 ? 44 : null,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: h.surface,
        borderRadius: BorderRadius.circular(HeroTokens.radiusField),
        border: Border.all(
          color: _focused ? h.accent : h.border,
          width: _focused ? 2 : 1.2,
        ),
      ),
      child: Row(
        children: [
          if (widget.prefixIcon != null) ...[
            Icon(
              widget.prefixIcon,
              size: 19,
              color: _focused ? h.accent : h.muted,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              obscureText: widget.obscure,
              keyboardType: widget.keyboardType,
              maxLines: widget.maxLines,
              textAlignVertical: TextAlignVertical.center,
              style: HeroTokens.body.copyWith(
                color: h.foreground,
                fontSize: 16,
              ),
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: HeroTokens.body.copyWith(
                  color: h.muted,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          if (widget.suffix != null) ...[
            const SizedBox(width: 8),
            widget.suffix!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroSegmented — iOS segmented control: pill track on gray5, white pill
// cursor (light) / elevated pill (dark), springy cursor travel.
// ---------------------------------------------------------------------------

class HeroSegmented<T> extends StatelessWidget {
  const HeroSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = false,
  });

  final List<(T, String, IconData?)> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);

    Widget buildSegment(int i, bool bounded) {
      final active = selected == segments[i].$1;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(segments[i].$1),
        child: AnimatedContainer(
          duration: heroAnimationsEnabled
              ? HeroTokens.motionTransform
              : Duration.zero,
          curve: HeroTokens.springSoft,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? (h.isDark ? HeroTokens.darkSegment : h.surface)
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(HeroTokens.radiusTabs - 3),
            boxShadow: active && !h.isDark
                ? [
                    const BoxShadow(
                      color: Color(0x1F000000),
                      offset: Offset(0, 1),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (segments[i].$3 != null) ...[
                Icon(
                  segments[i].$3,
                  size: 16,
                  color: active ? h.foreground : h.muted,
                ),
                const SizedBox(width: 6),
              ],
              // In bounded (expand) mode the label ellipsizes instead of
              // overflowing the segment cell.
              bounded
                  ? Flexible(
                      child: Text(
                        segments[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: HeroTokens.fontSans,
                          fontSize: 13,
                          height: 1.2,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w500,
                          color: active ? h.foreground : h.muted,
                        ),
                      ),
                    )
                  : Text(
                      segments[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: HeroTokens.fontSans,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? h.foreground : h.muted,
                      ),
                    ),
            ],
          ),
        ),
      );
    }

    final segmentsRow = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          if (expand)
            Expanded(child: buildSegment(i, true))
          else
            buildSegment(i, false),
        ],
      ],
    );

    // Unexpanded segmented controls sit at natural size and scale down
    // gracefully when the host is narrower than the content (no overflow).
    final body =
        expand ? segmentsRow : FittedBox(fit: BoxFit.scaleDown, child: segmentsRow);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: h.dflt,
        borderRadius: BorderRadius.circular(HeroTokens.radiusTabs),
      ),
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// HeroSkeleton — shimmer sweep on parchment tones
// (disable via heroAnimationsEnabled)
// ---------------------------------------------------------------------------

class HeroSkeleton extends StatefulWidget {
  const HeroSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<HeroSkeleton> createState() => _HeroSkeletonState();
}

class _HeroSkeletonState extends State<HeroSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final base = h.isDark ? h.surface2 : h.surface3;

    if (!heroAnimationsEnabled) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return FractionalTranslation(
            translation: Offset(-1 + 2 * t, 0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.35, 0.5, 0.65],
                  colors: [
                    base.withValues(alpha: 0),
                    h.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.55),
                    base.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroProgress
// ---------------------------------------------------------------------------

class HeroProgress extends StatelessWidget {
  const HeroProgress({
    super.key,
    required this.value,
    this.height = 8,
    this.color,
    this.trackColor,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: TweenAnimationBuilder<double>(
        duration: heroAnimationsEnabled
            ? const Duration(milliseconds: 420)
            : Duration.zero,
        curve: HeroTokens.springSoft,
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: trackColor ?? h.dflt,
          valueColor: AlwaysStoppedAnimation(color ?? h.accent),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroListTile — Apple settings row: rounded-square tinted icon plate,
// Inter 16 title, caption subtitle, chevron, press wash.
// ---------------------------------------------------------------------------

class HeroListTile extends StatefulWidget {
  const HeroListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingIcon,
    this.leadingColor,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool danger;

  @override
  State<HeroListTile> createState() => _HeroListTileState();
}

class _HeroListTileState extends State<HeroListTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);

    final lead = widget.leading ??
        (widget.leadingIcon != null
            ? Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (widget.danger
                          ? h.danger
                          : widget.leadingColor ?? h.accent)
                      .withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.leadingIcon,
                  size: 20,
                  color: widget.danger
                      ? h.danger
                      : widget.leadingColor ?? h.accent,
                ),
              )
            : null);

    final title = Text(
      widget.title,
      style: HeroTokens.title.copyWith(
        color: widget.danger ? h.danger : h.foreground,
        fontSize: 16,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp:
          widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        color: _pressed ? h.dflt.withValues(alpha: 0.6) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: HeroTokens.caption.copyWith(color: h.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 12),
                widget.trailing!,
              ],
              if (widget.showChevron && widget.trailing == null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: h.muted.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroEmptyState — atmospheric orb bloom behind a soft icon disc; the
// editorial Spectral Light title gives empty screens a magazine-cover feel.
// ---------------------------------------------------------------------------

class HeroEmptyState extends StatelessWidget {
  const HeroEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ElevenLabs atmosphere: pastel orbs blooming behind the disc.
            const SizedBox(
              width: 320,
              height: 320,
              child: HeroOrbs(
                colors: [
                  HeroTokens.orbSky,
                  HeroTokens.orbPeach,
                  HeroTokens.orbLavender,
                ],
                opacity: 0.45,
                seed: 7,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: h.dflt,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 36, color: h.muted),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: HeroTokens.titleLarge.copyWith(
                    color: h.foreground,
                    fontSize: 24,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: HeroTokens.bodySmall.copyWith(
                        color: h.muted,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 26), action!],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroSeparator
// ---------------------------------------------------------------------------

class HeroSeparator extends StatelessWidget {
  const HeroSeparator({super.key, this.height, this.indent = 0});
  final double? height;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Container(
      height: height ?? 1,
      margin: EdgeInsets.only(left: indent),
      color: h.separator,
    );
  }
}

// ---------------------------------------------------------------------------
// HeroSheet — bottom sheet, radius top 24, drag handle
// ---------------------------------------------------------------------------

Future<T?> showHeroSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = false,
}) {
  final h = HeroScope.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: h.surface,
    barrierColor: h.backdrop,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    showDragHandle: true,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Text(
              title,
              style: HeroTokens.title.copyWith(
                color: h.foreground,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Flexible(child: builder(ctx)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// HeroDialog — centered modal: surface + soft overlay shadow + scrim
// ---------------------------------------------------------------------------

Future<T?> showHeroDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final h = HeroScope.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: h.backdrop,
    builder: builder,
  );
}

/// Standard dialog frame — Apple alert geometry: 20px radius, hairline.
class HeroDialogFrame extends StatelessWidget {
  const HeroDialogFrame({
    super.key,
    required this.child,
    this.width,
  });

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: h.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: h.overlayShadow,
          border: h.isDark ? Border.all(color: h.border) : null,
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroSectionHeader — ElevenLabs caption-uppercase section label:
// Inter 600, 12px, +0.96px tracking, between card groups.
// ---------------------------------------------------------------------------

class HeroSectionHeader extends StatelessWidget {
  const HeroSectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: HeroTokens.captionUpper.copyWith(color: h.muted),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroAvatar
// ---------------------------------------------------------------------------

class HeroAvatar extends StatelessWidget {
  const HeroAvatar({
    super.key,
    this.url,
    this.initials,
    this.size = 40,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? url;
  final String? initials;
  final double size;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final bg = backgroundColor ?? h.accentSoft;
    final fg = foregroundColor ?? h.accentSoftFg;

    Widget child;
    if (url != null && url!.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initials(h, bg, fg),
        ),
      );
    } else {
      child = _initials(h, bg, fg);
    }
    return SizedBox(width: size, height: size, child: child);
  }

  Widget _initials(HeroThemeData h, Color bg, Color fg) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          (initials ?? '?').toUpperCase(),
          style: TextStyle(
            fontFamily: HeroTokens.fontSans,
            fontSize: size * 0.34,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// showHeroConfirm — Apple-styled confirmation alert
// ---------------------------------------------------------------------------

Future<bool> showHeroConfirm({
  required BuildContext context,
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final h = HeroScope.of(context);
  final result = await showDialog<bool>(
    context: context,
    barrierColor: h.backdrop,
    builder: (ctx) => HeroDialogFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: HeroTokens.title.copyWith(
              color: h.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style:
                  HeroTokens.bodySmall.copyWith(color: h.muted, height: 1.55),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              HeroButton(
                label: 'Cancel',
                variant: HeroButtonVariant.light,
                color: HeroColorRole.neutral,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              const SizedBox(width: 10),
              HeroButton(
                label: confirmLabel,
                color: danger ? HeroColorRole.danger : HeroColorRole.accent,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
