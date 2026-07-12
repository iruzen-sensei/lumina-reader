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

/// Lumina Reader theme configuration built on top of [FlexColorScheme].
///
/// Mirrors the theming approach used by Mangayomi while giving Lumina Reader
/// its own distinctive seed colour. The theme exposes both light and dark
/// [ThemeData] as well as a couple of reusable colour helpers used across the
/// modules (status colours, heat-map gradients, etc.).
class LuminaTheme {
  LuminaTheme._();

  /// Brand seed used to generate the Material 3 tonal palette.
  static const Color seed = Color(0xFF6750A4);

  static const FlexSchemeColor _luminaLight = FlexSchemeColor(
    primary: Color(0xFF6750A4),
    primaryContainer: Color(0xFFEADDFF),
    secondary: Color(0xFF625B71),
    secondaryContainer: Color(0xFFE8DEF8),
    tertiary: Color(0xFF7D5260),
    tertiaryContainer: Color(0xFFFFD8E4),
    appBarColor: Color(0xFFFEF7FF),
    error: Color(0xFFB3261E),
    errorContainer: Color(0xFFF9DEDC),
  );

  static const FlexSchemeColor _luminaDark = FlexSchemeColor(
    primary: Color(0xFFD0BCFF),
    primaryContainer: Color(0xFF4F378B),
    secondary: Color(0xFFCCC2DC),
    secondaryContainer: Color(0xFF4A4458),
    tertiary: Color(0xFFEFB8C8),
    tertiaryContainer: Color(0xFF633B48),
    appBarColor: Color(0xFF1B1B1F),
    error: Color(0xFFF2B8B5),
    errorContainer: Color(0xFF8C1D18),
  );

  static ThemeData light() {
    return FlexColorScheme.light(
      scheme: FlexScheme.deepPurple,
      colors: _luminaLight,
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 20,
      appBarStyle: FlexAppBarStyle.surface,
      appBarOpacity: 1,
      transparentStatusBar: true,
      tabBarStyle: FlexTabBarStyle.flutterDefault,
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        useM2StyleDividerInM3: true,
        inputDecoratorIsFilled: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorUnfocusedBorderIsColored: false,
        cardRadius: 16.0,
        chipRadius: 10.0,
        tooltipRadius: 8.0,
        tooltipWaitDuration: Duration(milliseconds: 800),
        drawerIndicatorRadius: 10.0,
        appBarScrolledUnderElevation: 8.0,
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
  }

  static ThemeData dark() {
    return FlexColorScheme.dark(
      scheme: FlexScheme.deepPurple,
      colors: _luminaDark,
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 30,
      darkIsTrueBlack: false,
      appBarStyle: FlexAppBarStyle.surface,
      appBarOpacity: 1,
      transparentStatusBar: true,
      tabBarStyle: FlexTabBarStyle.flutterDefault,
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        useM2StyleDividerInM3: true,
        inputDecoratorIsFilled: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorUnfocusedBorderIsColored: false,
        cardRadius: 16.0,
        chipRadius: 10.0,
        tooltipRadius: 8.0,
        tooltipWaitDuration: Duration(milliseconds: 800),
        drawerIndicatorRadius: 10.0,
        appBarScrolledUnderElevation: 8.0,
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
  }

  /// Colour used for the "reading" status chips and progress indicators.
  static const Color readingColor = Color(0xFF1E88E5);

  /// Colour used for the "finished" status chips and badges.
  static const Color finishedColor = Color(0xFF43A047);

  /// Colour used for the "unread" filter chip.
  static const Color unreadColor = Color(0xFFFB8C00);

  /// Colour used to indicate a freshly downloaded/unread item.
  static const Color newColor = Color(0xFFE53935);

  /// Five-step gradient used for the activity heat-map (least → most active).
  static const List<Color> heatLevels = [
    Color(0xFF1E1E1E),
    Color(0xFF4A148C),
    Color(0xFF7B1FA2),
    Color(0xFFAB47BC),
    Color(0xFFE1BEE7),
  ];

  /// Linear gradient painted behind detail screen headers.
  static const List<Color> headerGradient = [
    Color(0xFF4F378B),
    Color(0xFF1B1B1F),
  ];
}
