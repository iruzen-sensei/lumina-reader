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

/// Lumina Reader theme — HeroUI v3 design language.
///
/// Palette and component anatomy mirror the official HeroUI default theme
/// (https://heroui.com, packages/styles v3): accent #0485F7, success #17C964,
/// warning #F5A524/#F7B750, danger #FF383C/#DB3B3E, zinc-neutral surfaces
/// (light bg #F5F5F5 / surface white; dark bg #060607 / surface #18181B),
/// pill buttons, 16px chips, 24px cards, 12px fields.
///
/// The Material [ThemeData] below keeps every remaining Material widget
/// (NavigationBars, AppBars, TabBars, dialogs…) on-system so screens can
/// adopt the explicit HeroUI widgets incrementally without visual drift.
class LuminaTheme {
  LuminaTheme._();

  /// Brand seed (HeroUI v3 accent). Used as the FlexColorScheme key colour
  /// and the default custom-seed in Settings.
  static const Color seed = HeroTokens.accent;

  // -- Semantic status colours (referenced across modules) ------------------

  /// Colour used for the "reading" status chips and progress indicators.
  static const Color readingColor = HeroTokens.accent;

  /// Colour used for the "finished" status chips and badges.
  static const Color finishedColor = HeroTokens.success;

  /// Colour used for the "unread" filter chip.
  static const Color unreadColor = HeroTokens.warningLight;

  /// Colour used to indicate a freshly downloaded/unread item.
  static const Color newColor = HeroTokens.dangerLight;

  /// Five-step gradient used for the activity heat-map (least → most active).
  static const List<Color> heatLevels = [
    Color(0xFF232325),
    Color(0xFF0B4E8F),
    Color(0xFF0485F7),
    Color(0xFF53A8F8),
    Color(0xFFB9DBFE),
  ];

  /// Linear gradient painted behind detail screen headers.
  static const List<Color> headerGradient = [
    Color(0xFF0E2C4E),
    Color(0xFF060607),
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
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Roboto',
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
          foregroundColor: Colors.white,
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
        foregroundColor: Colors.white,
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
    return TextTheme(
      displayLarge: HeroTokens.display.copyWith(color: fg),
      displayMedium:
          HeroTokens.display.copyWith(color: fg, fontSize: 26),
      headlineLarge: HeroTokens.titleLarge.copyWith(color: fg),
      headlineMedium: HeroTokens.title.copyWith(color: fg, fontSize: 19),
      headlineSmall: HeroTokens.title.copyWith(color: fg),
      titleLarge: HeroTokens.title.copyWith(color: fg),
      titleMedium: HeroTokens.body
          .copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: 15),
      titleSmall: HeroTokens.bodySmall
          .copyWith(color: fg, fontWeight: FontWeight.w600),
      bodyLarge: HeroTokens.body.copyWith(color: fg, fontSize: 15),
      bodyMedium: HeroTokens.body.copyWith(color: fg),
      bodySmall: HeroTokens.bodySmall.copyWith(color: muted),
      labelLarge: HeroTokens.bodySmall.copyWith(
          color: fg, fontWeight: FontWeight.w600),
      labelMedium: HeroTokens.caption.copyWith(color: muted),
      labelSmall: HeroTokens.caption.copyWith(color: muted, fontSize: 11),
    );
  }
}
