// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// HEROUI v3 DESIGN SYSTEM — a faithful native-Flutter port of the HeroUI
// component language (https://heroui.com).
//
// Every token below was extracted from HeroUI's official stylesheet
// (packages/styles/themes, v3 default theme) and converted from oklch to
// sRGB:
//   * accent        oklch(0.6204 0.195 253.83)  ->  #0485F7
//   * success       oklch(0.7329 0.1935 150.81) ->  #17C964
//   * warning       oklch(0.7819 0.1585 72.33)  ->  #F5A524  (light)
//   * danger        oklch(0.6532 0.2328 25.74)  ->  #FF383C  (light)
//   * dark surface  oklch(0.2103 0.0059 285.89) ->  #18181B
//   * light bg      oklch(0.9702 0 0)           ->  #F5F5F5
//
// Component anatomy mirrors the HeroUI CSS exactly:
//   * Button  — pill (rounded-3xl), h-10, px-4, text-sm medium, press
//               scale(0.97) with 250ms smooth easing, 100ms bg transition
//   * Chip    — rounded-2xl (16px), px-2, py-0.5, text-xs, soft tints
//   * Card    — radius min(32px, 3xl) = 24px, p-4, light-mode triple
//               surface shadow, dark-mode borderless hairline
//   * Input   — field radius (radius * 1.5 = 12px), filled, focus ring
//   * Tabs    — container bg-default, radius radius*2.5 = 20px
//   * Switch  — accent track when checked, default track otherwise
//   * Skeleton— shimmer sweep
//
// Pure Flutter (no dependencies) so any screen can adopt it incrementally.

import 'package:flutter/material.dart';

/// Global switch for golden tests: disables infinite animations (shimmer)
/// so pumpAndSettle terminates.
bool heroAnimationsEnabled = true;

// ---------------------------------------------------------------------------
// TOKENS
// ---------------------------------------------------------------------------

/// The HeroUI v3 semantic palette (static constants — no BuildContext).
///
/// For theme-aware resolution use [Hero.of] / the `Hero*` widgets, which
/// pick light or dark rows automatically.
class HeroTokens {
  HeroTokens._();

  // -- Accents (identical in light + dark) --------------------------------
  static const Color accent = Color(0xFF0485F7);
  static const Color accentHover = Color(0xFF1D91F8);
  static const Color success = Color(0xFF17C964);
  static const Color successHover = Color(0xFF2BCD75);
  static const Color warningLight = Color(0xFFF5A524);
  static const Color warningDark = Color(0xFFF7B750);
  static const Color dangerLight = Color(0xFFFF383C);
  static const Color dangerDark = Color(0xFFDB3B3E);
  static const Color dangerHoverLight = Color(0xFFFF5155);
  static const Color dangerHoverDark = Color(0xFFE25255);

  // -- Light theme ----------------------------------------------------------
  static const Color lightBackground = Color(0xFFF5F5F5); // oklch(.9702 0 0)
  static const Color lightSurface = Color(0xFFFFFFFF); // white
  static const Color lightSurface2 = Color(0xFFEFEFF0);
  static const Color lightSurface3 = Color(0xFFEAEAEB);
  static const Color lightSurfaceHover = Color(0xFFEDEDED); // white92/ecl8
  static const Color lightForeground = Color(0xFF18181B); // "eclipse"
  static const Color lightMuted = Color(0xFF71717A);
  static const Color lightDefault = Color(0xFFEBEBEC);
  static const Color lightDefaultHover = Color(0xFFF1F1F2);
  static const Color lightBorder = Color(0xFFDEDEE0);
  static const Color lightSeparator = Color(0xFFE4E4E7);

  // -- Dark theme -----------------------------------------------------------
  static const Color darkBackground = Color(0xFF060607); // oklch(12% .005 …)
  static const Color darkSurface = Color(0xFF18181B); // "eclipse"
  static const Color darkSurface2 = Color(0xFF232325);
  static const Color darkSurface3 = Color(0xFF262728);
  static const Color darkSurfaceHover = Color(0xFF2A2A2D); // surface92/snow8
  static const Color darkForeground = Color(0xFFFCFCFC); // "snow"
  static const Color darkMuted = Color(0xFF9F9FA9);
  static const Color darkDefault = Color(0xFF27272A);
  static const Color darkDefaultHover = Color(0xFF303032);
  static const Color darkBorder = Color(0xFF28282C);
  static const Color darkSeparator = Color(0xFF212124);
  static const Color darkSegment = Color(0xFF46464C);

  // -- Radii -----------------------------------------------------------------
  /// Base radius (HeroUI --radius: 0.5rem).
  static const double radius = 8;

  /// Field radius (calc(radius * 1.5)).
  static const double radiusField = 12;

  /// Chip radius (rounded-2xl).
  static const double radiusChip = 16;

  /// Card radius (min(32px, radius-3xl)).
  static const double radiusCard = 24;

  /// Button pill radius (rounded-3xl — clamps to a full pill at h-10).
  static const double radiusButton = 24;

  /// Tabs container radius (calc(radius * 2.5)).
  static const double radiusTabs = 20;

  // -- Shadows ---------------------------------------------------------------
  /// Light-mode surface shadow (card elevation).
  static const List<BoxShadow> surfaceShadowLight = [
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 0), blurRadius: 1),
  ];

  /// Light-mode overlay shadow (modals, menus).
  static const List<BoxShadow> overlayShadowLight = [
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
    BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
  ];

  /// Dark-mode: no elevation shadows — definition comes from the hairline.
  static const List<BoxShadow> surfaceShadowDark = [];

  // -- Motion ----------------------------------------------------------------
  /// HeroUI "smooth" easing used for transforms.
  static const Curve easeSmooth = Curves.easeOutCubic;

  /// Transform duration (HeroUI: 250ms ease-smooth).
  static const Duration motionTransform = Duration(milliseconds: 250);

  /// Colour/fade duration (HeroUI: 100-150ms).
  static const Duration motionColor = Duration(milliseconds: 120);

  /// Entrance duration for modals/sheets.
  static const Duration motionEntrance = Duration(milliseconds: 220);

  // -- Spacing (Tailwind units, logical px) -----------------------------------
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  // -- Typography -------------------------------------------------------------
  /// HeroUI text styles. Weights stay in the 450-600 band (HeroUI's look is
  /// medium-weight, never heavy).
  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
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

  /// Backdrop for modals (HeroUI: rgba(0,0,0,.5) light / .6 dark).
  Color get backdrop =>
      isDark ? const Color(0x99000000) : const Color(0x80000000);

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
        accentSoft: Color(0x260485F7), // accent 15%
        accentSoftFg: Color(0xFF1E7BD8), // accent 70% + fg 30%
        accentFg: Colors.white,
        success: HeroTokens.success,
        successSoft: Color(0x2617C964),
        successSoftFg: Color(0xFF159B52),
        warning: HeroTokens.warningLight,
        warningSoft: Color(0x26F5A524),
        warningSoftFg: Color(0xFFB47F1E),
        danger: HeroTokens.dangerLight,
        dangerSoft: Color(0x26FF383C),
        dangerSoftFg: Color(0xFFCC3236),
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
        accent: HeroTokens.accent,
        accentSoft: Color(0x1F0485F7), // accent 12%
        accentSoftFg: Color(0xFF53A8F8), // accent 80% + fg 30%
        accentFg: Colors.white,
        success: HeroTokens.success,
        successSoft: Color(0x1F17C964),
        successSoftFg: Color(0xFF3ED57F),
        warning: HeroTokens.warningDark,
        warningSoft: Color(0x1FF7B750),
        warningSoftFg: Color(0xFFE9BE79),
        danger: HeroTokens.dangerDark,
        dangerSoft: Color(0x26DB3B3E),
        dangerSoftFg: Color(0xFFEC6A6D),
        surfaceShadow: HeroTokens.surfaceShadowDark,
        overlayShadow: [
          // dark overlay hairline equivalent: subtle outer glow
          BoxShadow(
              color: Color(0x14000000), offset: Offset(0, 8), blurRadius: 24),
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

// ---------------------------------------------------------------------------
// HeroButton — pill button, press scale 0.97, 250ms transform
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
    HeroButtonSize.sm: (h: 36.0, px: 12.0, font: 13.0, icon: 16.0, scale: 0.98),
    HeroButtonSize.md: (h: 40.0, px: 16.0, font: 14.0, icon: 18.0, scale: 0.97),
    HeroButtonSize.lg: (h: 48.0, px: 22.0, font: 15.0, icon: 20.0, scale: 0.97),
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
        if (_hovered && enabled) bg = _mix(colors.base, colors.onBase, 0.10);
      case HeroButtonVariant.soft:
        bg = colors.soft;
        fg = colors.softFg;
        if (_hovered && enabled) {
          bg = _mix(colors.soft, colors.base, 0.10);
        }
      case HeroButtonVariant.bordered:
        bg = Colors.transparent;
        fg = colors.base;
        border = _mix(colors.base, Colors.transparent, 0.45).withAlpha(255);
        if (_hovered && enabled) bg = colors.soft;
      case HeroButtonVariant.light:
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

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.loading)
          SizedBox(
            width: s.icon,
            height: s.icon,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          )
        else if (widget.icon != null) ...[
          Icon(widget.icon, size: s.icon, color: fg),
          const SizedBox(width: 7),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontSize: s.font,
            fontWeight: FontWeight.w500,
            color: fg,
            height: 1,
          ),
        ),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: 7),
          Icon(widget.trailingIcon, size: s.icon, color: fg),
        ],
      ],
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
              scale: _pressed ? s.scale : 1.0,
              duration: heroAnimationsEnabled
                  ? HeroTokens.motionTransform
                  : Duration.zero,
              curve: HeroTokens.easeSmooth,
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
                  border: border != null ? Border.all(color: border) : null,
                  boxShadow: widget.variant == HeroButtonVariant.solid &&
                          enabled &&
                          !h.isDark
                      ? [
                          BoxShadow(
                            color: colors.base.withValues(alpha: 0.28),
                            offset: const Offset(0, 4),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
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

/// HeroUI icon button — transparent, radius-14, hover bg-default.
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
      scale: _pressed ? 0.92 : 1.0,
      duration:
          heroAnimationsEnabled ? HeroTokens.motionTransform : Duration.zero,
      curve: HeroTokens.easeSmooth,
      child: AnimatedContainer(
        duration:
            heroAnimationsEnabled ? HeroTokens.motionColor : Duration.zero,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.backgroundColor ??
              (_hovered && enabled ? h.dflt : Colors.transparent),
          borderRadius: BorderRadius.circular(14),
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

/// sRGB mix helper (approximates HeroUI's oklab color-mix for tokens).
Color _mix(Color a, Color b, double t) {
  return Color.fromARGB(
    ((a.a + (b.a - a.a) * t) * 255).round().clamp(0, 255),
    ((a.r + (b.r - a.r) * t) * 255).round().clamp(0, 255),
    ((a.g + (b.g - a.g) * t) * 255).round().clamp(0, 255),
    ((a.b + (b.b - a.b) * t) * 255).round().clamp(0, 255),
  );
}

// ---------------------------------------------------------------------------
// HeroChip — rounded-2xl pill, soft tints, text-xs medium
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
        bg = colors.soft;
        fg = colors.softFg;
      case HeroChipVariant.bordered:
        bg = Colors.transparent;
        fg = colors.softFg;
      case HeroChipVariant.outlineText:
        bg = selected ? colors.soft : h.dflt;
        fg = selected ? colors.softFg : h.muted;
    }

    final chip = AnimatedContainer(
      duration: heroAnimationsEnabled ? HeroTokens.motionColor : Duration.zero,
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 5,
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
              fontSize: small ? 11.5 : 12.5,
              height: 1.25,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}

// ---------------------------------------------------------------------------
// HeroCard — radius 24, light shadows / dark hairline
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
      HeroCardVariant.secondary => h.surface2,
      HeroCardVariant.tertiary => h.surface3,
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
        border:
            variant != HeroCardVariant.transparent && (h.isDark || showBorder)
                ? Border.all(color: h.isDark ? h.border : h.separator)
                : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

// ---------------------------------------------------------------------------
// HeroSwitch — accent track checked, default track unchecked
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
          curve: Curves.easeOutBack,
          width: 44,
          height: 26,
          padding: EdgeInsets.all(value ? 2.5 : 2.5),
          decoration: BoxDecoration(
            color: enabled ? track : h.dflt.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: heroAnimationsEnabled
                ? HeroTokens.motionTransform
                : Duration.zero,
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 21,
              height: 21,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x22000000),
                      offset: Offset(0, 1),
                      blurRadius: 3),
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
// HeroInput — filled field, radius 12, focus ring
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
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: h.surface2,
        borderRadius: BorderRadius.circular(HeroTokens.radiusField),
        border: Border.all(
          color: _focused ? h.accent : Colors.transparent,
          width: 1.6,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: h.accent.withValues(alpha: 0.22),
                  offset: const Offset(0, 0),
                  blurRadius: 8,
                ),
              ]
            : null,
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
              style: HeroTokens.body.copyWith(color: h.foreground),
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: HeroTokens.body.copyWith(color: h.muted),
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
// HeroSegmented — HeroUI tabs anatomy: container bg-default radius 20,
// selected cursor = surface pill with shadow (light) / segment (dark)
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
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: h.dflt,
        borderRadius: BorderRadius.circular(HeroTokens.radiusTabs),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              flex: expand ? 1 : 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(segments[i].$1),
                child: AnimatedContainer(
                  duration: heroAnimationsEnabled
                      ? HeroTokens.motionTransform
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected == segments[i].$1
                        ? h.surface
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(HeroTokens.radiusTabs - 4),
                    boxShadow: selected == segments[i].$1 && !h.isDark
                        ? [
                            const BoxShadow(
                              color: Color(0x14000000),
                              offset: Offset(0, 1),
                              blurRadius: 3,
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
                          color: selected == segments[i].$1
                              ? h.foreground
                              : h.muted,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        segments[i].$2,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: selected == segments[i].$1
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected == segments[i].$1
                              ? h.foreground
                              : h.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HeroSkeleton — shimmer sweep (disable via heroAnimationsEnabled)
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
    duration: const Duration(milliseconds: 1400),
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
                        ? Colors.white.withValues(alpha: 0.045)
                        : Colors.white.withValues(alpha: 0.65),
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
            ? const Duration(milliseconds: 350)
            : Duration.zero,
        curve: Curves.easeOutCubic,
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
// HeroListTile — settings/menu rows: leading icon tile, title, subtitle,
// trailing switch/chevron; press feedback; 56px min height
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (widget.danger
                          ? h.danger
                          : widget.leadingColor ?? h.accent)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  widget.leadingIcon,
                  size: 19,
                  color: widget.danger
                      ? h.danger
                      : widget.leadingColor ?? h.accent,
                ),
              )
            : null);

    final title = Text(
      widget.title,
      style: HeroTokens.body.copyWith(
        color: widget.danger ? h.danger : h.foreground,
        fontWeight: FontWeight.w500,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
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
// HeroEmptyState — soft icon disc + title + subtitle + action
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: h.dflt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: h.muted),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: HeroTokens.title.copyWith(color: h.foreground),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: HeroTokens.bodySmall.copyWith(color: h.muted),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
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
// HeroSheet — bottom sheet, radius top 24, drag handle, entrance animation
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
              style: HeroTokens.title.copyWith(color: h.foreground),
            ),
          ),
        Flexible(child: builder(ctx)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// HeroDialog — centered modal: surface + overlay shadow + backdrop
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

/// Standard HeroUI dialog frame.
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
        padding: const EdgeInsets.all(20),
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
// HeroSectionHeader — grouping label used between card groups
// ---------------------------------------------------------------------------

class HeroSectionHeader extends StatelessWidget {
  const HeroSectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
                color: h.muted,
              ),
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
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// showHeroConfirm — HeroUI-styled confirmation dialog
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
            style: HeroTokens.title.copyWith(color: h.foreground),
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style:
                  HeroTokens.bodySmall.copyWith(color: h.muted, height: 1.55),
            ),
          ],
          const SizedBox(height: 22),
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
