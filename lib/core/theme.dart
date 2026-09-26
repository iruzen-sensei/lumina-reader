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

import 'ui/lumina_ui.dart';

/// Lumina Reader theme — "Lumina Noir".
///
/// A monochrome black premium language (x.ai / OpenAI / ElevenLabs dark
/// dialect): layered blacks (#0A0A0A canvas, #141414 cards, #1C1C1E fills)
/// separated by 1px hairlines, pure white as THE interactive colour
/// (white pill CTAs with near-black text), Inter 400/500 typography with
/// the ElevenLabs +0.15px body tracking, JetBrains Mono uppercase
/// eyebrows. No chromatic accent anywhere in the chrome; semantic hues
/// appear only as data indicators (status dots, finished/error states).
/// Light mode is the same system polarity-flipped (off-white canvas,
/// near-black ink CTAs).
///
/// The Material [ThemeData] below keeps every remaining Material widget
/// (NavigationBars, AppBars, TabBars, dialogs...) on-system so screens can
/// adopt the explicit Hero* widgets incrementally without visual drift.
class LuminaTheme {
  LuminaTheme._();

  /// Brand seed — white on the noir canvas (the interactive colour).
  /// Used as the scheme key colour.
  static const Color seed = HeroTokens.accent;

  // -- Semantic status colours (referenced across modules) ------------------
  // NOTE: these are DATA indicators (status dots, filter chips), not UI
  // chrome — they intentionally stay OUTSIDE the monochrome chrome language
  // so meaning survives in both themes. Hues follow the ElevenLabs MD
  // (success #16A34A / error #DC2626) with iOS-dark vivid variants for the
  // noir canvas. Each value is readable on black AND white.

  /// Colour used for the "reading" status chips and progress indicators —
  /// WHITE on the noir canvas (the monochrome working state).
  static const Color readingColor = Color(0xFFFFFFFF);

  /// Colour used for the "finished" status chips and badges
  /// (ElevenLabs semantic success).
  static const Color finishedColor = Color(0xFF16A34A);

  /// Colour used for the "unread" filter chip (amber data state).
  static const Color unreadColor = Color(0xFFD97706);

  /// Colour used to indicate a freshly downloaded/unread item
  /// (ElevenLabs semantic error red, repurposed as the "new" signal).
  static const Color newColor = Color(0xFFDC2626);

  /// Five-step gradient for the activity heat-map — the monochrome white
  /// ramp (black ladder into pure white, the x.ai data-viz dialect).
  static const List<Color> heatLevels = [
    Color(0xFF1C1C1E),
    Color(0xFF3A3A3E),
    Color(0xFF5E5E64),
    Color(0xFF9A9AA2),
    Color(0xFFFFFFFF),
  ];

  /// Linear gradient painted behind detail screen headers (the noir
  /// ladder: card surface fading into canvas).
  static const List<Color> headerGradient = [
    Color(0xFF141414),
    Color(0xFF0A0A0A),
  ];

  // ---------------------------------------------------------------------------
  // Light (secondary — monochrome inverted)
  // ---------------------------------------------------------------------------

  static ThemeData light() => _build(Brightness.light, HeroThemeData.light());

  // ---------------------------------------------------------------------------
  // Dark (PRIMARY — the noir canvas)
  // ---------------------------------------------------------------------------

  static ThemeData dark({bool trueBlack = false}) {
    final base = _build(Brightness.dark, HeroThemeData.dark());
    if (!trueBlack) return base;
    // AMOLED: the noir canvas is already near-black; collapse it to true
    // black while keeping the surface ladder distinguishable.
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
      onPrimary: h.accentFg,
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
      // Apple: interactions are scale transforms, not ripples.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
    ).copyWith(
      // -- AppBar: flat canvas, hairline under scroll --------------------
      appBarTheme: AppBarTheme(
        backgroundColor: h.background,
        foregroundColor: h.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
          color: h.foreground,
        ),
        iconTheme: IconThemeData(color: h.foreground, size: 21),
        actionsIconTheme: IconThemeData(color: h.foreground, size: 21),
      ),
      // -- Bottom navigation --------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: h.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: h.accentSoft,
        height: 64,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            letterSpacing: 0.06,
            color: states.contains(WidgetState.selected)
                ? h.foreground
                : h.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color:
                states.contains(WidgetState.selected) ? h.accent : h.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: h.background,
        indicatorColor: h.accentSoft,
        selectedIconTheme: IconThemeData(color: h.accent),
        selectedLabelTextStyle: TextStyle(
            color: h.foreground, fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelTextStyle: TextStyle(color: h.muted, fontSize: 13),
        unselectedIconTheme: IconThemeData(color: h.muted),
      ),
      // -- Buttons: pill CTAs, compact production heights --------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: h.accent,
          foregroundColor: h.accentFg,
          disabledBackgroundColor: h.dflt,
          disabledForegroundColor: h.muted,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          minimumSize: const Size(0, 40),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: h.foreground,
          textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: h.foreground,
          side: BorderSide(color: h.border),
          textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1),
          shape: const StadiumBorder(),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: h.foreground,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: h.accent,
        foregroundColor: h.accentFg,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      // -- Tabs: pill indicator on the control fill --------------------------
      tabBarTheme: TabBarThemeData(
        labelColor: h.foreground,
        unselectedLabelColor: h.muted,
        labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: h.dflt,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      // -- Inputs: rounded-rect fields, hairline; 2px accent focus ----------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? h.surface2 : h.surface,
        hintStyle: TextStyle(
            fontFamily: 'Inter', fontSize: 15, color: h.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.border, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HeroTokens.radiusField),
          borderSide: BorderSide(color: h.danger, width: 2),
        ),
      ),
      // -- Switch (polarity flip: accent track + inverted thumb) ------------
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return h.muted.withValues(alpha: 0.4);
          }
          if (states.contains(WidgetState.selected)) {
            // Inverted thumb on the accent track (noir: black-on-white).
            return isDark ? HeroTokens.darkBackground : Colors.white;
          }
          return isDark ? Colors.white : h.foreground;
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
      ),
      // -- Checkbox / radio ----------------------------------------------------
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return h.accent;
          return Colors.transparent;
        }),
        checkColor:
            const WidgetStatePropertyAll(HeroTokens.darkBackground),
        side: BorderSide(color: h.border, width: 1.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
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
          side: BorderSide(color: h.border, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: h.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: h.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: h.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? h.surface2 : h.foreground,
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: isDark ? h.foreground : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: h.dflt,
        selectedColor: h.accentSoft,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          color: h.foreground,
          fontWeight: FontWeight.w500,
          fontSize: 13,
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
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: h.accent,
        linearTrackColor: h.dflt,
        circularTrackColor: h.dflt,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: h.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: h.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? h.surface3 : h.foreground,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          fontFamily: 'Inter',
          color: isDark ? h.foreground : Colors.white,
          fontSize: 12,
        ),
        waitDuration: const Duration(milliseconds: 600),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: h.accent,
        inactiveTrackColor: h.dflt,
        thumbColor: h.foreground,
        overlayColor: h.accent.withValues(alpha: 0.12),
      ),
    );
  }

  /// The noir type ramp mapped onto Material's slots:
  ///   * display/headline slots → Inter 400 with negative tracking
  ///     (the weight-400 grotesk display; never bold)
  ///   * title/body/label slots → Inter 400/500/600 with the editorial
  ///     +0.15px body tracking
  static TextTheme _textTheme(bool isDark) {
    final fg = isDark ? HeroTokens.darkForeground : HeroTokens.lightForeground;
    final muted = isDark ? HeroTokens.darkMuted : HeroTokens.lightMuted;

    const sans = TextStyle(fontFamily: HeroTokens.fontSans);

    return TextTheme(
      // Apple HIG SF tracking curve on Inter: tightest at 17-20pt (−0.43
      // headline / −0.45 title3), opens positive above 24pt (+0.40 at 34,
      // the largeTitle cadence), ~0 at 12pt, slightly positive below.
      displayLarge: sans.copyWith(
          color: fg, fontSize: 34, height: 1.21, fontWeight: FontWeight.w400, letterSpacing: 0.4),
      displayMedium: sans.copyWith(
          color: fg, fontSize: 30, height: 1.2, fontWeight: FontWeight.w400, letterSpacing: 0.37),
      displaySmall: sans.copyWith(
          color: fg, fontSize: 26, height: 1.2, fontWeight: FontWeight.w400, letterSpacing: 0.19),
      headlineLarge: sans.copyWith(
          color: fg, fontSize: 24, height: 1.25, fontWeight: FontWeight.w400, letterSpacing: 0.01),
      headlineMedium: sans.copyWith(
          color: fg, fontSize: 20, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.45),
      headlineSmall: sans.copyWith(
          color: fg, fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.35),
      titleLarge: sans.copyWith(
          color: fg, fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: -0.43),
      titleMedium: sans.copyWith(
          color: fg, fontSize: 15, height: 1.4, fontWeight: FontWeight.w500, letterSpacing: -0.23),
      titleSmall: sans.copyWith(
          color: fg, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500, letterSpacing: -0.1),
      bodyLarge: sans.copyWith(
          color: fg, fontSize: 15.5, height: 1.45, letterSpacing: -0.2),
      bodyMedium: sans.copyWith(
          color: fg, fontSize: 15, height: 1.45, letterSpacing: -0.23),
      bodySmall: sans.copyWith(
          color: muted, fontSize: 13, height: 1.4, letterSpacing: -0.08),
      labelLarge: sans.copyWith(
          color: fg, fontSize: 14, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: -0.15),
      labelMedium: sans.copyWith(
          color: muted, fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: -0.05),
      labelSmall: sans.copyWith(
          color: muted, fontSize: 11.5, height: 1.3, letterSpacing: 0.06),
    );
  }
}
