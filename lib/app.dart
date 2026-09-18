// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/providers.dart';
import 'router/router.dart';

/// Root widget.
///
/// The theme is driven by the PERSISTED app settings ([appSettingsProvider]):
///   * themeMode  → system / light / dark / amoled (true-black)
///   * customSeed → the FlexColorScheme seed colour
///   * fontSize   → applied app-wide via a [TextScaler] override
///
/// Previously this widget built a hardcoded deep-purple pair and ignored the
/// settings row entirely — every theme control in the Settings screen was
/// writing to a database nothing ever read back.
class LuminaApp extends ConsumerWidget {
  const LuminaApp({super.key});

  /// Reference body text size the in-app font-size slider scales from.
  static const double _baseFontSize = 14.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(appSettingsProvider);

    final lightTheme = _light(settings.customSeed);
    final darkTheme = _dark(
      settings.customSeed,
      trueBlack: settings.themeMode == AppThemeMode.amoled,
    );

    // Scale factor applied through a MediaQuery TextScaler override below.
    final textScale =
        (settings.fontSize / _baseFontSize).clamp(0.8, 1.6).toDouble();

    return MaterialApp.router(
      title: 'Lumina Reader',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: switch (settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark || AppThemeMode.amoled => ThemeMode.dark,
      },
      routerConfig: router,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: textScale == 1.0
                ? mediaQuery.textScaler
                : TextScaler.linear(textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  ThemeData _light(Color seed) {
    return FlexThemeData.light(
      // Material-3 tonal palette generated from the user's brand colour.
      keyColors: FlexKeyColors(useKeyColors: true, keyPrimary: seed),
      surfaceMode: FlexSurfaceMode.highScaffoldLevelSurface,
      blendLevel: 20,
      appBarOpacity: 0.00,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        thinBorderWidth: 2.0,
        unselectedToggleIsColored: true,
        inputDecoratorRadius: 24.0,
        chipRadius: 24.0,
      ),
      useMaterial3: true,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );
  }

  ThemeData _dark(Color seed, {required bool trueBlack}) {
    return FlexThemeData.dark(
      keyColors: FlexKeyColors(useKeyColors: true, keyPrimary: seed),
      surfaceMode: FlexSurfaceMode.level,
      blendLevel: 15,
      appBarOpacity: 0.00,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        thinBorderWidth: 2.0,
        unselectedToggleIsColored: true,
        inputDecoratorRadius: 24.0,
        chipRadius: 24.0,
      ),
      useMaterial3: true,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      darkIsTrueBlack: trueBlack, // AMOLED pure black
    );
  }
}
