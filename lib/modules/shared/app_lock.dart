// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// APP LOCK — the Settings screen has exposed "App lock / Lock on launch /
// Lock on resume" switches since the skeleton, but no gate ever consumed
// those flags. This module provides the real thing:
//
//   * [PinStore]     — persists a SHA-256 PIN hash under the app documents
//                      directory (no Isar schema change needed).
//   * [AppLockGate]  — wraps the navigator; shows a full-screen HeroUI
//                      numeric PIN sheet on launch and/or app resume.
//   * [showSetPinSheet] — PIN creation flow used by Settings when the user
//                      enables the lock.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/ui/heroui.dart';

/// Persistent PIN storage (hash on disk — never the raw PIN).
class PinStore {
  PinStore._();

  static const String _fileName = 'applock.pin';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<bool> hasPin() async {
    try {
      final f = await _file();
      return f.existsSync() && f.readAsStringSync().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setPin(String pin) async {
    final f = await _file();
    await f.writeAsString(_hash(pin));
  }

  static Future<void> clear() async {
    final f = await _file();
    if (f.existsSync()) await f.delete();
  }

  static Future<bool> verify(String pin) async {
    try {
      final f = await _file();
      if (!f.existsSync()) return false;
      final stored = f.readAsStringSync().trim();
      return stored == _hash(pin);
    } catch (_) {
      return false;
    }
  }

  static String _hash(String pin) =>
      sha256.convert(utf8.encode('lumina:$pin')).toString();
}

/// Wraps the app and blocks it behind the PIN overlay when configured.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    this.lockOnLaunch = true,
    this.lockOnResume = false,
  });

  final Widget child;
  final bool lockOnLaunch;
  final bool lockOnResume;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  Future<void> _init() async {
    final hasPin = await PinStore.hasPin();
    if (hasPin && widget.lockOnLaunch && mounted) {
      setState(() => _locked = true);
    }
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.lockOnResume &&
        _initialized) {
      PinStore.hasPin().then((has) {
        if (has && mounted) setState(() => _locked = true);
      });
    }
  }

  void _unlock() => setState(() => _locked = false);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _PinLockScreen(onUnlocked: _unlock),
          ),
      ],
    );
  }
}

class _PinLockScreen extends StatefulWidget {
  const _PinLockScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<_PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<_PinLockScreen> {
  String _pin = '';
  String? _error;

  void _tap(int n) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += '$n';
      _error = null;
    });
    if (_pin.length == 4) {
      PinStore.verify(_pin).then((ok) {
        if (!mounted) return;
        if (ok) {
          widget.onUnlocked();
        } else {
          setState(() {
            _pin = '';
            _error = 'Wrong PIN — try again';
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? Colors.black : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const Icon(Icons.lock_rounded,
                size: 40, color: HeroColors.primary),
            const SizedBox(height: 12),
            Text(
              'Enter your PIN',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : HeroColors.default900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Lumina Reader is locked',
              style: TextStyle(
                fontSize: 13,
                color: _error != null
                    ? HeroColors.danger
                    : (isDark ? HeroColors.default400 : HeroColors.default500),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _pin.length;
                return Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? HeroColors.primary : Colors.transparent,
                    border: Border.all(
                      color: filled
                          ? HeroColors.primary
                          : HeroColors.default400,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 264,
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  for (final n in [1, 2, 3, 4, 5, 6, 7, 8, 9])
                    _Key(label: '$n', onTap: () => _tap(n)),
                  const SizedBox.shrink(),
                  _Key(label: '0', onTap: () => _tap(0)),
                  _Key(
                    icon: Icons.backspace_outlined,
                    onTap: () => setState(() {
                      if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                    }),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.onTap, this.label, this.icon});

  final VoidCallback onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? HeroColors.darkContent2 : HeroColors.default100,
      borderRadius: BorderRadius.circular(HeroColors.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(HeroColors.radiusLarge),
        onTap: onTap,
        child: Center(
          child: label != null
              ? Text(
                  label!,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : HeroColors.default900,
                  ),
                )
              : Icon(icon,
                  size: 20,
                  color: isDark ? Colors.white : HeroColors.default900),
        ),
      ),
    );
  }
}

/// PIN creation flow. Returns true when a PIN was set.
Future<bool> showSetPinSheet(BuildContext context) async {
  final result = await hSheet<bool>(
    context: context,
    title: 'Set a 4-digit PIN',
    builder: (sheetContext) => const _SetPinBody(),
  );
  return result ?? false;
}

class _SetPinBody extends StatefulWidget {
  const _SetPinBody();

  @override
  State<_SetPinBody> createState() => _SetPinBodyState();
}

class _SetPinBodyState extends State<_SetPinBody> {
  String _first = '';
  String _second = '';
  bool _confirming = false;

  void _tap(int n) {
    final target = _confirming ? _second : _first;
    if (target.length >= 4) return;
    setState(() {
      if (_confirming) {
        _second += '$n';
      } else {
        _first += '$n';
      }
    });
    if ((_confirming ? _second : _first).length == 4) {
      if (!_confirming) {
        setState(() => _confirming = true);
        return;
      }
      if (_first == _second) {
        PinStore.setPin(_first).then((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
      } else {
        setState(() {
          _first = '';
          _second = '';
          _confirming = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PINs did not match — start over')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pin = _confirming ? _second : _first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _confirming ? 'Confirm your PIN' : 'You will need this PIN to unlock the app',
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? HeroColors.default400 : HeroColors.default500,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < pin.length;
              return Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? HeroColors.primary : Colors.transparent,
                  border: Border.all(
                    color:
                        filled ? HeroColors.primary : HeroColors.default400,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 264,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                for (final n in [1, 2, 3, 4, 5, 6, 7, 8, 9])
                  _Key(label: '$n', onTap: () => _tap(n)),
                const SizedBox.shrink(),
                _Key(label: '0', onTap: () => _tap(0)),
                _Key(
                  icon: Icons.backspace_outlined,
                  onTap: () => setState(() {
                    if (_confirming && _second.isNotEmpty) {
                      _second = _second.substring(0, _second.length - 1);
                    } else if (!_confirming && _first.isNotEmpty) {
                      _first = _first.substring(0, _first.length - 1);
                    }
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
