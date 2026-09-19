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

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'ui/heroui.dart';

/// Lumina Reader theme — rebuilt on the HeroUI design language.
///
/// The palette, radii and component themes mirror HeroUI
/// (https://heroui.com): primary blue #006FEE, secondary purple #7828C8,
/// zinc neutral ramp, 8px control radius / 14px card radius, pill chips.
/// Static colour helpers used across modules (status chips, heat-map…) are
/// preserved and remapped to HeroUI tokens.
class LuminaTheme {
  LuminaTheme._();

  /// Brand seed (HeroUI primary). Used as the FlexColorScheme key colour
  /// and the default custom-seed in Settings.
  static const Color seed = HeroColors.primary;

  // -- HeroUI light scheme ---------------------------------------------------
  static const FlexSchemeColor _heroLight = FlexSchemeColor(
    primary: HeroColors.primary, // #006FEE
    primaryContainer: HeroColors.primary50, // #E6F1FD
    secondary: HeroColors.secondary, // #7828C8
    secondaryContainer: Color(0xFFF5EDFC),
    tertiary: HeroColors.success, // #17C964
    tertiaryContainer: Color(0xFFEAFBF1),
    appBarColor: Colors.white,
    error: HeroColors.danger, // #F31260
    errorContainer: Color(0xFFFDE9F0),
  );

  // -- HeroUI dark scheme ----------------------------------------------------
  static const FlexSchemeColor _heroDark = FlexSchemeColor(
    primary: HeroColors.primary400, // #3696FB
    primaryContainer: Color(0xFF103B7D),
    secondary: HeroColors.secondary400, // #9B4DD9
    secondaryContainer: Color(0xFF3B1D63),
    tertiary: Color(0xFF3DD68C),
    tertiaryContainer: Color(0xFF0B3F26),
    appBarColor: HeroColors.darkContent1, // #18181B
    error: Color(0xFFF43D78),
    errorContainer: Color(0xFF5C0E2D),
  );

  static ThemeData light() => _finish(_lightScheme(), Brightness.light);

  static ThemeData dark({bool trueBlack = false}) =>
      _finish(_darkScheme(trueBlack), Brightness.dark);

  static ThemeData _lightScheme() => FlexColorScheme.light(
        colors: _heroLight,
        surfaceMode: FlexSurfaceMode.level,
        blendLevel: 6,
        appBarStyle: FlexAppBarStyle.surface,
        appBarOpacity: 1,
        transparentStatusBar: true,
        tabBarStyle: FlexTabBarStyle.forBackground,
        subThemesData: const FlexSubThemesData(
          interactionEffects: true,
          tintedDisabledControls: true,
          useM2StyleDividerInM3: true,
          inputDecoratorIsFilled: true,
          inputDecoratorBorderType: FlexInputBorderType.outline,
          inputDecoratorUnfocusedBorderIsColored: false,
          cardRadius: 14.0,
          chipRadius: 999.0,
          tooltipRadius: 8.0,
          tooltipWaitDuration: Duration(milliseconds: 600),
          drawerIndicatorRadius: 10.0,
          appBarScrolledUnderElevation: 4.0,
        ),
        keyColors: const FlexKeyColors(
          useKeyColors: true,
          keepPrimary: true,
          keepSecondary: true,
          keepTertiary: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        swapLegacyOnMaterial3: true,
      ).toTheme;

  static ThemeData _darkScheme(bool trueBlack) => FlexColorScheme.dark(
        colors: _heroDark,
        surfaceMode: FlexSurfaceMode.level,
        blendLevel: 6,
        appBarStyle: FlexAppBarStyle.background,
        appBarOpacity: 1,
        transparentStatusBar: true,
        tabBarStyle: FlexTabBarStyle.forBackground,
        darkIsTrueBlack: trueBlack, // AMOLED pure black
        subThemesData: const FlexSubThemesData(
          interactionEffects: true,
          tintedDisabledControls: true,
          useM2StyleDividerInM3: true,
          inputDecoratorIsFilled: true,
          inputDecoratorBorderType: FlexInputBorderType.outline,
          inputDecoratorUnfocusedBorderIsColored: false,
          cardRadius: 14.0,
          chipRadius: 999.0,
          tooltipRadius: 8.0,
          tooltipWaitDuration: Duration(milliseconds: 600),
          drawerIndicatorRadius: 10.0,
          appBarScrolledUnderElevation: 4.0,
        ),
        keyColors: const FlexKeyColors(
          useKeyColors: true,
          keepPrimary: true,
          keepSecondary: true,
          keepTertiary: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        swapLegacyOnMaterial3: true,
      ).toTheme;

  /// HeroUI component theming applied on top of the Flex base.
  static ThemeData _finish(ThemeData theme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final content1 = isDark ? HeroColors.darkContent1 : Colors.white;
    final content2 = isDark ? HeroColors.darkContent2 : HeroColors.default100;

    return theme.copyWith(
      scaffoldBackgroundColor: isDark ? Colors.black : Colors.white,
      dialogTheme: DialogThemeData(
        backgroundColor: content1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeroColors.radiusCard),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(HeroColors.radiusSheet)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? HeroColors.darkContent3 : HeroColors.default900,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeroColors.radiusMedium),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor:
            isDark ? HeroColors.default400 : HeroColors.default500,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeroColors.radiusLarge),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return HeroColors.default400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return content2;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? HeroColors.darkContent3 : HeroColors.default200,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: content2,
        circularTrackColor: content2,
      ),
      chipTheme: theme.chipTheme.copyWith(
        backgroundColor: content2,
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
        labelStyle: TextStyle(
            color: isDark ? Colors.white : HeroColors.default900,
            fontWeight: FontWeight.w500),
        side: const BorderSide(color: Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  /// Colour used for the "reading" status chips and progress indicators.
  static const Color readingColor = HeroColors.primary;

  /// Colour used for the "finished" status chips and badges.
  static const Color finishedColor = HeroColors.success;

  /// Colour used for the "unread" filter chip.
  static const Color unreadColor = Color(0xFFF5A524);

  /// Colour used to indicate a freshly downloaded/unread item.
  static const Color newColor = HeroColors.danger;

  /// Five-step gradient used for the activity heat-map (least → most active).
  static const List<Color> heatLevels = [
    Color(0xFF18181B),
    Color(0xFF005BC4),
    Color(0xFF006FEE),
    Color(0xFF3696FB),
    Color(0xFFBAE0FD),
  ];

  /// Linear gradient painted behind detail screen headers.
  static const List<Color> headerGradient = [
    Color(0xFF103B7D),
    Color(0xFF18181B),
  ];
}
