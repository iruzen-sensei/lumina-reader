// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// HEROIU DESIGN SYSTEM — a native-Flutter implementation of the HeroUI
// (https://heroui.com) component language.
//
// HeroUI itself is a React library; a Flutter app cannot import it, so this
// file re-implements its design tokens and the components the app needs
// pixel-faithfully:
//   * exact HeroUI colour palette (primary #006FEE, secondary #7828C8,
//     success #17C964, warning #F5A524, danger #F31260, zinc default ramp)
//   * HeroUI radius scale (medium 8 / large 12 / card 14 / sheet 20)
//   * the signature press interaction: scale 0.97 + opacity dip
//   * variants modelled on the HeroUI docs: Button (solid / bordered /
//     light / flat / ghost), Chip (solid / bordered / flat / dot),
//     Switch, Card, Modal & Sheet, Progress.
//
// Every widget here is dependency-free (pure Material + painting) so it can
// be used from any screen without setup.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Design tokens
// ---------------------------------------------------------------------------

/// HeroUI semantic palette. Light and dark rows per the HeroUI theme spec.
class HeroColors {
  HeroColors._();

  // -- Accents (HeroUI "colors" scale, 100/400/500/600 stops) --------------
  static const Color primary = Color(0xFF006FEE);
  static const Color primary400 = Color(0xFF3696FB);
  static const Color primary600 = Color(0xFF005BC4);
  static const Color primary100 = Color(0xFFBAE0FD);
  static const Color primary50 = Color(0xFFE6F1FD);

  static const Color secondary = Color(0xFF7828C8);
  static const Color secondary400 = Color(0xFF9B4DD9);
  static const Color secondary600 = Color(0xFF6421AE);
  static const Color secondary100 = Color(0xFFEAD8FB);

  static const Color success = Color(0xFF17C964);
  static const Color success600 = Color(0xFF12A150);
  static const Color success100 = Color(0xFFD3F4DF);

  static const Color warning500 = Color(0xFFF5A524);
  static const Color warning600 = Color(0xFFD98D0E);
  static const Color warning100 = Color(0xFFFDECC8);

  static const Color danger = Color(0xFFF31260);
  static const Color danger600 = Color(0xFFDE0E54);
  static const Color danger100 = Color(0xFFFDD3E1);

  // -- Neutral (HeroUI "default" zinc ramp) ---------------------------------
  static const Color default50 = Color(0xFFFAFAFA);
  static const Color default100 = Color(0xFFF4F4F5);
  static const Color default200 = Color(0xFFE4E4E7);
  static const Color default300 = Color(0xFFD4D4D8);
  static const Color default400 = Color(0xFFA1A1AA);
  static const Color default500 = Color(0xFF71717A);
  static const Color default600 = Color(0xFF52525B);
  static const Color default900 = Color(0xFF18181B);

  // -- Dark theme content surfaces ------------------------------------------
  static const Color darkContent1 = Color(0xFF18181B);
  static const Color darkContent2 = Color(0xFF202024);
  static const Color darkContent3 = Color(0xFF27272A);
  static const Color darkContent4 = Color(0xFF3F3F46);

  // -- Radii (HeroUI scale) --------------------------------------------------
  static const double radiusSmall = 4;
  static const double radiusMedium = 8;
  static const double radiusLarge = 12;
  static const double radiusCard = 14;
  static const double radiusSheet = 20;

  /// HeroUI divider colour for the current brightness.
  static Color divider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkContent3
          : default200;

  /// HeroUI "content2" surface — used by inputs, ghost hovers, chips bg.
  static Color content2(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkContent2
          : default100;
}

/// Resolves a [HeroVariant] colour to its 500-stop / 100-stop / foreground.
class HeroPalette {
  const HeroPalette(
    this.base,
    this.subtle, [
    this.onSolid = Colors.white,
    this.onSubtle = const Color(0xFF11181C),
  ]);

  final Color base; // 500 stop (solid background / bordered border+text)
  final Color subtle; // 100 stop (light/flat background)
  final Color onSolid; // text on solid
  final Color onSubtle; // text on subtle

  static const HeroPalette primaryPal = HeroPalette(
      HeroColors.primary, HeroColors.primary50, Colors.white, Color(0xFF00480F));
  static const HeroPalette secondaryPal = HeroPalette(
      HeroColors.secondary, HeroColors.secondary100, Colors.white, Color(0xFF4A1D77));
  static const HeroPalette successPal = HeroPalette(
      HeroColors.success, HeroColors.success100, Colors.white, Color(0xFF0B7A3C));
  static const HeroPalette warningPal = HeroPalette(
      HeroColors.warning500, HeroColors.warning100, Colors.white, Color(0xFF6A3514));
  static const HeroPalette dangerPal = HeroPalette(
      HeroColors.danger, HeroColors.danger100, Colors.white, Color(0xFF9F0B40));
  static const HeroPalette neutralPal = HeroPalette(
      Color(0xFF71717A), HeroColors.default100, Colors.white, Color(0xFF27272A));
}

/// Semantic colour names, mirroring HeroUI's `color` prop.
enum HeroVariant { primary, secondary, success, warning, danger, neutral }

extension HeroVariantX on HeroVariant {
  HeroPalette get palette => switch (this) {
        HeroVariant.primary => HeroPalette.primaryPal,
        HeroVariant.secondary => HeroPalette.secondaryPal,
        HeroVariant.success => HeroPalette.successPal,
        HeroVariant.warning => HeroPalette.warningPal,
        HeroVariant.danger => HeroPalette.dangerPal,
        HeroVariant.neutral => HeroPalette.neutralPal,
      };
}

// ---------------------------------------------------------------------------
// HButton — HeroUI Button
// ---------------------------------------------------------------------------

/// HeroUI's button with its five variants (solid / bordered / light / flat /
/// ghost), three sizes and the signature scale-on-press interaction.
class HButton extends StatefulWidget {
  const HButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.variant = HButtonVariant.solid,
    this.color = HeroVariant.primary,
    this.size = HButtonSize.md,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final HButtonVariant variant;
  final HeroVariant color;
  final HButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  State<HButton> createState() => _HButtonState();
}

enum HButtonVariant { solid, bordered, light, flat, ghost }

enum HButtonSize { sm, md, lg }

class _HButtonState extends State<HButton> {
  bool _pressed = false;

  double get _hPadding => switch (widget.size) {
        HButtonSize.sm => 12,
        HButtonSize.md => 16,
        HButtonSize.lg => 24,
      };

  double get _vPadding => switch (widget.size) {
        HButtonSize.sm => 6,
        HButtonSize.md => 10,
        HButtonSize.lg => 14,
      };

  double get _fontSize => switch (widget.size) {
        HButtonSize.sm => 13,
        HButtonSize.md => 14,
        HButtonSize.lg => 16,
      };

  double get _iconSize => switch (widget.size) {
        HButtonSize.sm => 15,
        HButtonSize.md => 18,
        HButtonSize.lg => 20,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pal = widget.color.palette;
    final enabled = widget.onPressed != null && !widget.loading;

    Color bg;
    Color fg;
    Color? border;

    switch (widget.variant) {
      case HButtonVariant.solid:
        bg = pal.base;
        fg = pal.onSolid;
        break;
      case HButtonVariant.bordered:
        bg = Colors.transparent;
        fg = isDark ? _lighten(pal.base) : pal.base;
        border = fg;
        break;
      case HButtonVariant.light:
        // HeroUI "light": subtle tinted bg, strong coloured text.
        bg = isDark ? pal.base.withValues(alpha: 0.15) : pal.subtle;
        fg = isDark ? _lighten(pal.base) : pal.onSubtle;
        break;
      case HButtonVariant.flat:
        bg = isDark ? pal.base.withValues(alpha: 0.20) : pal.subtle;
        fg = isDark ? _lighten(pal.base) : pal.onSubtle;
        break;
      case HButtonVariant.ghost:
        bg = _pressed
            ? HeroColors.content2(context)
            : Colors.transparent;
        fg = Theme.of(context).colorScheme.onSurface;
        break;
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.loading)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: _iconSize - 3,
              height: _iconSize - 3,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            ),
          )
        else if (widget.icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(widget.icon, size: _iconSize, color: fg),
          ),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: FontWeight.w500,
            color: fg,
          ),
        ),
      ],
    );

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding:
          EdgeInsets.symmetric(horizontal: _hPadding, vertical: _vPadding),
      decoration: BoxDecoration(
        color: enabled ? bg : bg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(HeroColors.radiusMedium),
        border: border != null ? Border.all(color: border, width: 1.5) : null,
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: content,
      ),
    );

    Widget interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: button,
        ),
      ),
    );

    if (widget.fullWidth) {
      interactive = SizedBox(
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Flexible(child: interactive)],
        ),
      );
    }
    return interactive;
  }

  /// Approximate HeroUI's dark-mode "-100 text stop": lighten the base.
  static Color _lighten(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0)).toColor();
  }
}

/// Icon-only button in HeroUI style (used for app-bar / row actions).
class HIconButton extends StatefulWidget {
  const HIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color = HeroVariant.neutral,
    this.size = 22,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final HeroVariant color;
  final double size;

  @override
  State<HIconButton> createState() => _HIconButtonState();
}

class _HIconButtonState extends State<HIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.color == HeroVariant.neutral
        ? (isDark ? Colors.white : HeroColors.default900)
        : widget.color.palette.base;
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: widget.onPressed == null ? base.withValues(alpha: 0.35) : base,
    );
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: _pressed ? HeroColors.content2(context) : Colors.transparent,
        borderRadius: BorderRadius.circular(HeroColors.radiusMedium),
      ),
      child: icon,
    );
    final btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onPressed == null ? null : (_) => setState(() => _pressed = true),
      onTapUp:
          widget.onPressed == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel:
          widget.onPressed == null ? null : () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: body,
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}

// ---------------------------------------------------------------------------
// HChip — HeroUI Chip (solid / bordered / flat / dot)
// ---------------------------------------------------------------------------

enum HChipVariant { solid, bordered, flat, dot }

class HChip extends StatelessWidget {
  const HChip({
    super.key,
    required this.label,
    this.variant = HChipVariant.flat,
    this.color = HeroVariant.primary,
    this.selected = false,
    this.onTap,
    this.icon,
    this.small = false,
  });

  final String label;
  final HChipVariant variant;
  final HeroVariant color;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pal = color.palette;
    final active = selected;

    Color bg;
    Color fg;
    Color? border;
    Widget? leading;

    switch (variant) {
      case HChipVariant.solid:
        bg = pal.base;
        fg = pal.onSolid;
        break;
      case HChipVariant.bordered:
        bg = Colors.transparent;
        fg = active
            ? pal.onSolid
            : (isDark ? _HButtonState._lighten(pal.base) : pal.base);
        border = active ? pal.base : (isDark ? _HButtonState._lighten(pal.base) : pal.base);
        break;
      case HChipVariant.flat:
        bg = isDark
            ? (active ? pal.base.withValues(alpha: 0.30) : pal.base.withValues(alpha: 0.15))
            : (active ? pal.subtle : HeroColors.default100);
        fg = active
            ? (isDark ? Colors.white : pal.onSubtle)
            : (isDark ? Colors.white70 : HeroColors.default600);
        break;
      case HChipVariant.dot:
        bg = isDark ? pal.base.withValues(alpha: 0.15) : pal.subtle;
        fg = isDark ? Colors.white : pal.onSubtle;
        leading = _Dot(color: pal.base);
        break;
    }

    final text = Text(
      label,
      style: TextStyle(
        fontSize: small ? 11.5 : 13,
        fontWeight: selected || variant == HChipVariant.solid
            ? FontWeight.w600
            : FontWeight.w500,
        color: fg,
      ),
    );

    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 6)],
        if (icon != null) ...[
          Icon(icon, size: small ? 13 : 15, color: fg),
          const SizedBox(width: 5)
        ],
        text,
      ],
    );

    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(
        horizontal: small ? 9 : 12,
        vertical: small ? 3.5 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border, width: 1.2) : null,
      ),
      child: inner,
    );

    final cb = onTap;
    if (cb == null) return container;
    return _Pressable(onTap: cb, child: container);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

// ---------------------------------------------------------------------------
// HCard — HeroUI Card
// ---------------------------------------------------------------------------

class HCard extends StatelessWidget {
  const HCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.color,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (isDark ? HeroColors.darkContent1 : Colors.white),
        borderRadius: BorderRadius.circular(HeroColors.radiusCard),
        border: border
            ? Border.all(
                color: isDark ? HeroColors.darkContent3 : HeroColors.default200)
            : null,
      ),
      child: child,
    );
    final cb = onTap;
    if (cb == null) return card;
    return _Pressable(onTap: cb, child: card);
  }
}

// ---------------------------------------------------------------------------
// HSwitch — HeroUI Switch
// ---------------------------------------------------------------------------

class HSwitch extends StatelessWidget {
  const HSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.color = HeroVariant.primary,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final HeroVariant color;

  @override
  Widget build(BuildContext context) {
    final pal = color.palette;
    final trackColor = value ? pal.base : HeroColors.content2(context);
    final thumbColor = value ? pal.onSolid : HeroColors.default400;

    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration:
                BoxDecoration(color: thumbColor, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HProgress — rounded progress bar
// ---------------------------------------------------------------------------

class HProgress extends StatelessWidget {
  const HProgress({
    super.key,
    required this.value,
    this.color = HeroVariant.primary,
    this.height = 6,
  });

  final double value;
  final HeroVariant color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 250),
        tween: Tween(end: clamped),
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: HeroColors.content2(context),
          valueColor: AlwaysStoppedAnimation(color.palette.base),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared press-interaction wrapper (HeroUI scale + shadow press feedback)
// ---------------------------------------------------------------------------

class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HSheet — HeroUI-styled modal bottom sheet
// ---------------------------------------------------------------------------

/// Opens a HeroUI-styled bottom sheet (rounded top, drag handle, optional
/// title row). Returns the sheet's result.
Future<T?> hSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    backgroundColor: isDark ? HeroColors.darkContent1 : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(HeroColors.radiusSheet),
      ),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : HeroColors.default900,
                ),
              ),
            ),
          Flexible(child: builder(sheetContext)),
        ],
      ),
    ),
  );
}

/// HeroUI-styled confirmation dialog. Returns true when confirmed.
Future<bool> hConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  HeroVariant tone = HeroVariant.danger,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
      return Dialog(
        backgroundColor: isDark ? HeroColors.darkContent1 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeroColors.radiusCard),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : HeroColors.default900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? HeroColors.default400 : HeroColors.default600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  HButton(
                    label: cancelLabel,
                    variant: HButtonVariant.ghost,
                    color: HeroVariant.neutral,
                    size: HButtonSize.sm,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                  const SizedBox(width: 8),
                  HButton(
                    label: confirmLabel,
                    variant: HButtonVariant.solid,
                    color: tone,
                    size: HButtonSize.sm,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// HTile — rounded pressable list tile (sheet/menu rows)
// ---------------------------------------------------------------------------

class HTile extends StatelessWidget {
  const HTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.tone = HeroVariant.primary,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final HeroVariant tone;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? HeroColors.darkContent2 : HeroColors.default50,
          borderRadius: BorderRadius.circular(HeroColors.radiusLarge),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tone.palette.base.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(HeroColors.radiusMedium),
              ),
              child: Icon(icon, size: 18, color: tone.palette.base),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : HeroColors.default900,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? HeroColors.default400
                            : HeroColors.default500,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: HeroColors.default400),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HSection — section heading inside sheets / settings
// ---------------------------------------------------------------------------

class HSection extends StatelessWidget {
  const HSection({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: isDark ? HeroColors.default400 : HeroColors.default500,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
