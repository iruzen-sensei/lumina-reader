// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/ui/lumina_ui.dart';
import 'modules/shared/app_lock.dart';
import 'providers/providers.dart';
import 'router/router.dart';

/// Root widget.
///
/// The theme is driven by the PERSISTED app settings ([appSettingsProvider]):
///   * themeMode  → system / light / dark / amoled (true-black)
///   * customSeed → FlexColorScheme key colour (defaults to HeroUI primary)
///   * fontSize   → applied app-wide via a [TextScaler] override
///   * einkMode   → global grayscale filter (previously persisted but never
///     consumed by anything)
///   * appLock    → PIN gate on launch / resume (previously flags only)
class LuminaApp extends ConsumerWidget {
  const LuminaApp({super.key});

  /// Reference body text size the in-app font-size slider scales from.
  static const double _baseFontSize = 14.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(appSettingsProvider);

    final lightTheme = LuminaTheme.light();
    final darkTheme =
        LuminaTheme.dark(trueBlack: settings.themeMode == AppThemeMode.amoled);

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
        final settings = ref.watch(appSettingsProvider);
        Widget app = MediaQuery(
          // COMPOUND the in-app font slider with the SYSTEM text scale —
          // the previous override REPLACED the system scaler, so a user
          // with Android "Largest" fonts (2.0x) got 1.0x text whenever the
          // in-app slider was off-neutral (an accessibility regression).
          data: mediaQuery.copyWith(
            textScaler: textScale == 1.0
                ? mediaQuery.textScaler
                : _CompoundScaler(mediaQuery.textScaler, textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );

        // HeroUI v3 design-system scope: resolves semantic tokens for every
        // Hero* widget below (light/dark rows from the official palette).
        final platformDark = mediaQuery.platformBrightness == Brightness.dark;
        final effectiveDark = switch (settings.themeMode) {
          AppThemeMode.system => platformDark,
          AppThemeMode.light => false,
          AppThemeMode.dark || AppThemeMode.amoled => true,
        };
        app = HeroScope(
          data: effectiveDark ? HeroThemeData.dark() : HeroThemeData.light(),
          child: app,
        );

        // E-ink mode: strip colour to grayscale e-paper look.
        if (settings.einkMode) {
          app = ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: app,
          );
        }

        // App lock gate: wraps the navigator with the PIN overlay when the
        // user enabled locking (launch / resume).
        if (settings.appLockEnabled) {
          app = AppLockGate(
            lockOnLaunch: settings.lockOnLaunch,
            lockOnResume: settings.lockOnResume,
            child: app,
          );
        }
        return app;
      },
    );
  }
}

/// Multiplies a (possibly non-linear, platform) [TextScaler] by a linear
/// in-app factor — keeps Android's per-size accessibility curve intact.
class _CompoundScaler extends TextScaler {
  const _CompoundScaler(this._inner, this._factor);

  final TextScaler _inner;
  final double _factor;

  @override
  double scale(double fontSize) => _inner.scale(fontSize) * _factor;

  // Canonical nonlinear derivation (the deprecated base getter is linear
  // only for LinearScaler); 14 = the platform's reference font size.
  @override
  double get textScaleFactor => scale(14) / 14;
}
