// Copyright 2024 Lumina Reader Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/material.dart';

import 'ui/heroui_v3.dart';

/// Lumina Reader theme — rybin design language (andreirybin.com).
///
/// Monochrome palette + one link accent: bg #FFFFFF / text #000000 /
/// secondary #8E8E90 / link #0099FF, hairline borders rgba(0,0,0,0.08),
/// FLAT surfaces (no elevation), Inter 12px uniform type, 8px card radii,
/// 16px pill badges. Dark mode = the reference's black footer inverted
/// into a full theme (#000000 bg, white ink).
///
/// The Material [ThemeData] below keeps every remaining Material widget
/// (NavigationBars, AppBars, TabBars, dialogs...) on-system so screens can
/// adopt the explicit Hero* widgets incrementally without visual drift.
class LuminaTheme {
  LuminaTheme._();

  /// Brand seed (HeroUI v3 accent). Used as the FlexColorScheme key colour
  /// and the default custom-seed in Settings.
  static const Color seed = HeroTokens.accent;

  // -- Semantic status colours (referenced across modules) ------------------
  // NOTE: these are DATA indicators (status dots, filter chips), not UI
  // chrome — they intentionally stay OUTSIDE the rybin monochrome language
  // so meaning survives in both themes (the rybin palette governs the
  // HeroTokens/HeroThemeData chrome layer). Each value is readable on
  // black AND white.

  /// Colour used for the "reading" status chips and progress indicators
  /// (the link accent - readable on black and white).
  static const Color readingColor = Color(0xFF0099FF);

  /// Colour used for the "finished" status chips and badges.
  static const Color finishedColor = Color(0xFF17C964);

  /// Colour used for the "unread" filter chip.
  static const Color unreadColor = Color(0xFFF5A524);

  /// Colour used to indicate a freshly downloaded/unread item.
  static const Color newColor = Color(0xFFFF383C);

  /// Five-step gradient for the activity heat-map — ink into link-blue
  /// (the reference palette: black + #0099FF only).
  static const List<Color> heatLevels = [
    Color(0xFFEBEBEB),
    Color(0xFF99D8FF),
    Color(0xFF4DB8FF),
    Color(0xFF0099FF),
    Color(0xFF006FB3),
  ];

  /// Linear gradient painted behind detail screen headers (reference black).
  static const List<Color> headerGradient = [
    Color(0xFF1A1A1A),
    Color(0xFF000000),
  ];

  // ---------------------------------------------------------------------------
  // Light
  // ---------------------------------------------------------------------------

  static ThemeData light() => _build(Brightness.light, HeroThemeData.light());

  // ---------------------------------------------------------------------------
  // Dark
  // ---------------------------------------------------------------------------

  static ThemeData dark({bool trueBlack = false}) {
    final base = _build(Brightness.dark, HeroThemeData.dark());
    if (!trueBlack) return base;
    // AMOLED: near-black background, keep surfaces distinguishable.
    return base.copyWith(
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
    );
  }

  // ---------------------------------------------------------------------------
  // Builder
  // ---------------------------------------------------------------------------

  static ThemeData _build(Brightness brightness, HeroThemeData h) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: h.accent,
      onPrimary: Colors.white,
      primaryContainer: h.accentSoft,
      onPrimaryContainer: h.accentSoftFg,
      secondary: h.success,
      onSecondary: Colors.white,
      secondaryContainer: h.successSoft,
      onSecondaryContainer: h.successSoftFg,
      tertiary: h.warning,
      onTertiary: Colors.white,
      tertiaryContainer: h.warningSoft,
      onTertiaryContainer: h.warningSoftFg,
      error: h.danger,
      onError: Colors.white,
      errorContainer: h.dangerSoft,
      onErrorContainer: h.dangerSoftFg,
      surface: h.surface,
      onSurface: h.foreground,
      surfaceContainerHighest: h.surface2,
      surfaceContainerHigh: h.surface2,
      surfaceContainerLow: h.isDark ? h.background : h.surface2,
      surfaceContainer: h.surface2,
      surfaceDim: h.isDark ? h.background : h.surface3,
      surfaceBright: h.isDark ? h.surface2 : Colors.white,
      onSurfaceVariant: h.muted,
      outline: h.border,
      outlineVariant: h.separator,
      inverseSurface: isDark ? h.foreground : h.surface,
      onInverseSurface: isDark ? h.surface : h.foreground,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final textTheme = Typography.blackMountainView
        .apply(bodyColor: h.foreground, displayColor: h.foreground)
        .merge(_textTheme(isDark));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: h.background,
      canvasColor: h.background,
      textTheme: textTheme,
      // rybin: no ripple — interactions are quiet colour fades.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
    ).copyWith(
      // -- AppBar: flat surface, no elevation, centered-free left title -----
      appBarTheme: AppBarTheme(
        backgroundColor: h.background,
        foregroundColor: h.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.6,
        centerTitle: false,
        titleTextStyle: HeroTokens.title.copyWith(color: h.foreground),
        iconTheme: IconThemeData(color: h.foreground, size: 22),
        actionsIconTheme: IconThemeData(color: h.foreground, size: 22),
      ),
      // -- Bottom navigation: HeroUI-style pill indicator ------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: h.isDark ? h.surface : h.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: h.accentSoft,
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? h.accentSoftFg
                : h.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? h.accent
                : h.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: h.background,
        indicatorColor: h.accentSoft,
        selectedIconTheme: IconThemeData(color: h.accent),
        selectedLabelTextStyle: TextStyle(
            color: h.accentSoftFg, fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(color: h.muted, fontSize: 12),
        unselectedIconTheme: IconThemeData(color: h.muted),
      ),
      // -- Buttons -----------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: h.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: h.dflt,
          disabledForegroundColor: h.muted,
          textStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, height: 1),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          minimumSize: const Size(0, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HeroTokens.radiusButton),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: h.accent,
          textStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, height: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HeroTokens.radiusButton),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: h.accent,
          side: BorderSide(color: h.accent.withValues(alpha: 0.5)),
          textStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, height: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HeroTokens.radiusButton),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: h.foreground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: h.accent,
        foregroundColor: Colors.black,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      // -- Tabs: pill indicator on surface2 ----------------------------------
      tabBarTheme: TabBarThemeData(
        labelColor: h.foreground,
        unselectedLabelColor: h.muted,
        labelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: h.dflt,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      // -- Inputs: filled, radius 12, accent focus ---------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: h.surface2,
        hintStyle: TextStyle(color: h.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.danger, width: 1.6),
        ),
      ),
      // -- Switch ------------------------------------------------------------
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return h.muted.withValues(alpha: 0.4);
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return h.dflt;
          }
          if (states.contains(WidgetState.selected)) return h.accent;
          return h.dflt;
        }),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Icon(Icons.check_rounded,
                size: 15, color: h.accent.withValues(alpha: 0.9));
          }
          return null;
        }),
      ),
      // -- Checkbox / radio ----------------------------------------------------
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return h.accent;
          return Colors.transparent;
        }),
        side: BorderSide(color: h.border, width: 1.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? h.accent : h.muted),
      ),
      // -- Cards / dialogs / sheets -------------------------------------------
      cardTheme: CardThemeData(
        color: h.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
          side: BorderSide(
              color: h.isDark ? h.border : h.separator, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: h.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: h.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: h.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? h.surface3 : h.foreground,
        contentTextStyle: TextStyle(
          color: isDark ? h.foreground : Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: h.dflt,
        selectedColor: h.accentSoft,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        labelStyle: TextStyle(
          color: isDark ? h.foreground : h.foreground,
          fontWeight: FontWeight.w500,
          fontSize: 12.5,
        ),
        side: const BorderSide(color: Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: h.separator,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: h.foreground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: h.accent,
        linearTrackColor: h.dflt,
        circularTrackColor: h.dflt,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: h.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? h.surface3 : h.foreground,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          color: isDark ? h.foreground : Colors.white,
          fontSize: 12,
        ),
        waitDuration: const Duration(milliseconds: 600),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: h.accent,
        inactiveTrackColor: h.dflt,
        thumbColor: Colors.white,
        overlayColor: h.accent.withValues(alpha: 0.12),
      ),
    );
  }

  static TextTheme _textTheme(bool isDark) {
    final fg = isDark ? HeroTokens.darkForeground : HeroTokens.lightForeground;
    final muted = isDark ? HeroTokens.darkMuted : HeroTokens.lightMuted;
    // The reference sets everything at 12px / 1.3 line-height; hierarchy
    // comes from weight only. Material's ramp is collapsed onto it so
    // stock widgets (AppBar titles, dialogs, list tiles) inherit the
    // same quiet voice as the Hero* components.
    const s = 12.0;
    return TextTheme(
      displayLarge: HeroTokens.display.copyWith(color: fg, fontSize: s),
      displayMedium: HeroTokens.display.copyWith(color: fg, fontSize: s),
      displaySmall: HeroTokens.display.copyWith(color: fg, fontSize: s),
      headlineLarge: HeroTokens.titleLarge.copyWith(color: fg, fontSize: s),
      headlineMedium: HeroTokens.titleLarge.copyWith(color: fg, fontSize: s),
      headlineSmall: HeroTokens.title.copyWith(color: fg, fontSize: s),
      titleLarge: HeroTokens.title.copyWith(color: fg, fontSize: s),
      titleMedium:
          HeroTokens.title.copyWith(color: fg, fontSize: s, fontWeight: FontWeight.w500),
      titleSmall: HeroTokens.title.copyWith(color: fg, fontSize: s),
      bodyLarge: HeroTokens.body.copyWith(color: fg, fontSize: s),
      bodyMedium: HeroTokens.body.copyWith(color: fg, fontSize: s),
      bodySmall: HeroTokens.body.copyWith(color: muted, fontSize: s),
      labelLarge: HeroTokens.body.copyWith(
          color: fg, fontSize: s, fontWeight: FontWeight.w500),
      labelMedium: HeroTokens.caption.copyWith(color: muted, fontSize: s),
      labelSmall: HeroTokens.caption.copyWith(color: muted, fontSize: s),
    );
  }
}
