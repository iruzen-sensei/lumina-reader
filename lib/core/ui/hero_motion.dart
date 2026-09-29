// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2
//
// HERO MOTION — the two reference motion components, ported natively.
//
// 1. HeroDeleteButton  (from rare-ui / shadcn "delete-button")
//    A trash tile that MORPHS open into a confirm panel: the width grows
//    48 -> 132 on the morph curve, the bin lid swings open on its hinge
//    with an overshoot bounce, the walls sink, and two circular actions
//    (confirm / cancel) stagger in 70ms apart. Confirming swaps the bin
//    for a checkmark that draws itself in; cancelling settles the bin
//    with a 1 -> .86 -> 1 wobble. Press physics are an underdamped
//    spring (stiffness 520 / damping 18 / mass .5) to scale 0.84.
//
// 2. showHeroMenu / HeroMenuButton  (from transitions.dev "menu-dropdown")
//    Anchored dropdown menus: entrances scale .97 -> 1 + fade over 250ms
//    on the house decel, anchored at the trigger's corner; exits recede
//    to .99 in 150ms — never scaling toward the viewer. Menu items
//    stagger in beneath the panel.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/services.dart';

import 'lumina_ui.dart';

// ---------------------------------------------------------------------------
// HeroDeleteButton
// ---------------------------------------------------------------------------

const double _kTile = 48;
const double _kPanel = 84;
const double _kCircle = 28;

/// Geometry of the bin glyph in its 24x24 viewBox.
const double _kWallTop = 6.0;
const double _kWallTopOpen = 13.5;
const double _kWallBase = 20.0;
const Offset _kHinge = Offset(3, 6);
const double _kLidOpenDeg = -35;

class HeroDeleteButton extends StatefulWidget {
  const HeroDeleteButton({
    super.key,
    this.onConfirm,
    this.onCancel,
    this.size = _kTile,
    this.enabled = true,
  });

  /// Fires the moment the user confirms (check circle) — the morph
  /// animation then plays out its check-draw payoff.
  final VoidCallback? onConfirm;

  /// Fires when the user cancels (x circle / re-tap / Escape).
  final VoidCallback? onCancel;

  /// Overall tile size; the expanded width is size + size * 1.75.
  final double size;

  final bool enabled;

  @override
  State<HeroDeleteButton> createState() => _HeroDeleteButtonState();
}

enum _DeleteStatus { idle, deleted, kept }

class _HeroDeleteButtonState extends State<HeroDeleteButton>
    with TickerProviderStateMixin {
  bool _open = false;
  _DeleteStatus _status = _DeleteStatus.idle;

  // Cancellable timers (stagger + hold windows) so dispose never leaves
  // dangling timers — the framework's timers-pending assertion in tests
  // and clean teardown in production.
  Timer? _stagger1;
  Timer? _stagger2;
  Timer? _holdTimer;

  late final AnimationController _morph; // width + walls (620ms)
  late final AnimationController _lid; // lid swing (600ms, bounce)
  late final AnimationController _swap; // bin <-> check crossfade (220ms)
  late final AnimationController _check; // check path draw (450ms)
  late final AnimationController _wobble; // kept settle 1->.86->1 (450ms)
  late final AnimationController _press; // spring press physics
  late final AnimationController _circle1; // confirm circle entrance
  late final AnimationController _circle2; // cancel circle entrance

  double get _factor => heroAnimationsEnabled ? 1.0 : 0.0;

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (620 * _factor).round()),
    );
    _lid = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (600 * _factor).round()),
    );
    _swap = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (220 * _factor).round()),
    );
    _check = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (450 * _factor).round()),
    );
    _wobble = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (450 * _factor).round()),
    );
    _press = AnimationController.unbounded(vsync: this)..value = 1;
    // IN: 440ms on the house decel, first circle delayed 140ms,
    // second staggered +70ms (rare-ui's IN + staggerChildren: .07).
    _circle1 = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (440 * _factor).round()),
    );
    _circle2 = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (440 * _factor).round()),
    );
  }

  @override
  void dispose() {
    _stagger1?.cancel();
    _stagger2?.cancel();
    _holdTimer?.cancel();
    _morph.dispose();
    _lid.dispose();
    _swap.dispose();
    _check.dispose();
    _wobble.dispose();
    _press.dispose();
    _circle1.dispose();
    _circle2.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    _press.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 0.5, stiffness: 520, damping: 18),
        _press.value,
        target,
        0,
      ),
    );
  }

  void _openPanel() {
    HapticFeedback.selectionClick();
    setState(() => _open = true);
    _morph.forward();
    _lid.forward();
    _stagger1?.cancel();
    _stagger2?.cancel();
    _stagger1 = Timer(
        Duration(milliseconds: (140 * _factor).round()),
        () => _circle1.forward(from: 0));
    _stagger2 = Timer(
        Duration(milliseconds: (210 * _factor).round()),
        () => _circle2.forward(from: 0));
  }

  void _closePanel() {
    setState(() => _open = false);
    _morph.reverse();
    _lid.reverse();
    _circle1.value = 0;
    _circle2.value = 0;
  }

  void _resolve(_DeleteStatus next) {
    _closePanel();
    setState(() => _status = next);
    _holdTimer?.cancel();
    if (next == _DeleteStatus.deleted) {
      HapticFeedback.lightImpact();
      _swap.forward(from: 0);
      _check.forward(from: 0);
      _holdTimer = Timer(
        Duration(milliseconds: (1400 * _factor).round()),
        () => mounted && _status == _DeleteStatus.deleted
            ? setState(() {
                _status = _DeleteStatus.idle;
                _swap.reverse();
              })
            : null,
      );
      widget.onConfirm?.call();
    } else {
      HapticFeedback.selectionClick();
      _wobble.forward(from: 0);
      _holdTimer = Timer(
        Duration(milliseconds: (600 * _factor).round()),
        () => mounted && _status == _DeleteStatus.kept
            ? setState(() => _status = _DeleteStatus.idle)
            : null,
      );
      widget.onCancel?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final s = widget.size / _kTile; // scale factor
    final expanded = widget.size + _kPanel * s;

    return Semantics(
      button: true,
      expanded: _open,
      label: 'Delete',
      child: AnimatedContainer(
        duration: _morph.duration!,
        curve: HeroMotion.easeMorph,
        width: _open ? expanded : widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: h.surface2,
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(color: h.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // -- trigger tile ------------------------------------------------
          Positioned(
            left: 0,
            top: 0,
            width: widget.size,
            height: widget.size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.enabled ? (_) => _springTo(0.84) : null,
              onTapUp: widget.enabled ? (_) => _springTo(1.0) : null,
              onTapCancel: widget.enabled ? () => _springTo(1.0) : null,
              onTap: widget.enabled
                  ? () {
                      if (_open) {
                        _resolve(_DeleteStatus.kept);
                      } else if (_status == _DeleteStatus.idle) {
                        _openPanel();
                      }
                    }
                  : null,
              child: AnimatedBuilder(
                animation: _press,
                builder: (_, __) => Transform.scale(
                  scale: _press.value.clamp(0.5, 1.3),
                  child: Center(child: _buildGlyph(h)),
                ),
              ),
            ),
          ),
          // -- confirm panel ------------------------------------------------
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _kPanel * s,
            child: IgnorePointer(
              ignoring: !_open,
              child: _ConfirmPanel(
                morph: _morph,
                circle1: _circle1,
                circle2: _circle2,
                size: widget.size,
                scale: s,
                onConfirm: () => _resolve(_DeleteStatus.deleted),
                onCancel: () => _resolve(_DeleteStatus.kept),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildGlyph(HeroThemeData h) {
    final bin = CustomPaint(
      size: Size.square(20 * (widget.size / _kTile)),
      painter: _BinPainter(
        lidT: Curves.linear.transform(_lid.value),
        wallT: Curves.linear.transform(_morph.value),
        color: h.muted,
        accent: h.danger,
        checkT: Curves.easeOut.transform(_check.value),
        swapT: Curves.easeOut.transform(_swap.value),
        wobbleT: _wobble.value,
      ),
    );
    return bin;
  }
}

/// The recessed action panel: a left-pointing notch ties it to the trigger
/// tile; confirm (check) and cancel (x) circles stagger in 70ms apart.
class _ConfirmPanel extends StatelessWidget {
  const _ConfirmPanel({
    required this.morph,
    required this.circle1,
    required this.circle2,
    required this.size,
    required this.scale,
    required this.onConfirm,
    required this.onCancel,
  });

  final Animation<double> morph;
  final Animation<double> circle1;
  final Animation<double> circle2;
  final double size;
  final double scale;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    // Panel opacity rides the END of the morph so it appears once the
    // container has actually grown around it (and fades early on reverse).
    final t = const Interval(0.10, 0.45, curve: Curves.easeOut)
        .transform(morph.value);

    return Opacity(
      opacity: t,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: h.surface3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircleAction(
                  controller: circle1,
                  scale: scale,
                  color: h.danger,
                  icon: Icons.check_rounded,
                  tooltip: 'Confirm delete',
                  onTap: onConfirm,
                ),
                SizedBox(width: 8 * scale),
                _CircleAction(
                  controller: circle2,
                  scale: scale,
                  color: h.muted,
                  icon: Icons.close_rounded,
                  tooltip: 'Keep',
                  onTap: onCancel,
                ),
              ],
            ),
          ),
        ),
        // The notch: a small triangle pointing at the trigger tile.
        Positioned(
          left: -6 * scale,
          top: 0,
          bottom: 0,
          width: 7 * scale,
          child: Center(
            child: CustomPaint(
              size: Size(7 * scale, 10 * scale),
              painter: _NotchPainter(color: h.surface3),
            ),
          ),
        ),
      ]),
    );
  }
}

/// One circular action with its staggered entrance (x -6 -> 0 + fade on
/// the house decel) and the spring press.
class _CircleAction extends StatefulWidget {
  const _CircleAction({
    required this.controller,
    required this.scale,
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final Animation<double> controller;
  final double scale;
  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_CircleAction> createState() => _CircleActionState();
}

class _CircleActionState extends State<_CircleAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController.unbounded(vsync: this)..value = 1;
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    _press.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 0.5, stiffness: 520, damping: 18),
        _press.value,
        target,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final d = _kCircle * widget.scale;
    final t = Curves.easeOut.transform(widget.controller.value);

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _springTo(0.84),
        onTapUp: (_) => _springTo(1.0),
        onTapCancel: () => _springTo(1.0),
        onTap: widget.onTap,
        child: Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(-6 * widget.scale * (1 - t), 0),
            child: AnimatedBuilder(
              animation: _press,
              builder: (_, __) => Transform.scale(
                scale: _press.value.clamp(0.5, 1.3),
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: h.surface,
                    border: Border.all(color: h.border),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 15 * widget.scale,
                    color: widget.color,
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

/// The bin glyph, drawn parametrically in a 24x24 viewBox:
///  * walls: the path's top edge sinks 6 -> 13.5 as the panel opens
///    (the bin visually "opens"), wall height = 20 - top;
///  * lid: the handle group rotates around the (3,6) hinge to -35deg;
///  * check: swaps in on confirm and draws itself via PathMetrics.
class _BinPainter extends CustomPainter {
  _BinPainter({
    required this.lidT,
    required this.wallT,
    required this.color,
    required this.accent,
    required this.checkT,
    required this.swapT,
    required this.wobbleT,
  });

  final double lidT;
  final double wallT;
  final Color color;
  final Color accent;
  final double checkT;
  final double swapT;
  final double wobbleT;

  static const _view = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _view;
    // The "kept" settle wobble: 1 -> .86 -> 1 on the settle ease.
    final wobble = _wobbleCurve(wobbleT);

    canvas.save();
    canvas.scale(scale, scale);
    canvas.translate(_view / 2, _view / 2);
    canvas.scale(wobble, wobble);
    canvas.translate(-_view / 2, -_view / 2);

    final binPaint = Paint()
      ..color = Color.lerp(color, accent, swapT)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // -- walls (parametric: top sinks as the panel opens) ------------------
    final top = _kWallTop + (_kWallTopOpen - _kWallTop) * wallT;
    final wallH = _kWallBase - top;
    final walls = Path()
      ..moveTo(19, top)
      ..lineTo(19, top + wallH)
      ..arcToPoint(
        Offset(17, top + wallH + 2),
        radius: const Radius.circular(2),
        clockwise: true,
      )
      ..lineTo(7, top + wallH + 2)
      ..arcToPoint(
        Offset(5, top + wallH),
        radius: const Radius.circular(2),
        clockwise: true,
      )
      ..lineTo(5, top);
    canvas.drawPath(walls, binPaint);

    // -- lid (rotates around the hinge; overshoots on the bounce curve) ---
    final lidAngle = _lidAngle(lidT) * math.pi / 180;
    canvas.save();
    canvas.translate(_kHinge.dx, _kHinge.dy);
    canvas.rotate(lidAngle);
    canvas.translate(-_kHinge.dx, -_kHinge.dy);
    final lid = Path()
      ..moveTo(3, 6)
      ..lineTo(21, 6)
      ..moveTo(8, 6)
      ..lineTo(8, 4)
      ..arcToPoint(const Offset(10, 2),
          radius: const Radius.circular(2), clockwise: true)
      ..lineTo(14, 2)
      ..arcToPoint(const Offset(16, 4),
          radius: const Radius.circular(2), clockwise: true)
      ..lineTo(16, 6);
    canvas.drawPath(lid, binPaint);
    canvas.restore();

    // -- check (draws itself in on confirm) --------------------------------
    if (checkT > 0) {
      final checkPath = Path()
        ..moveTo(4, 12.5)
        ..lineTo(9.5, 18)
        ..lineTo(20, 7);
      final checkPaint = Paint()
        ..color = Color.lerp(accent, accent, swapT)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final metrics = checkPath.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final m = metrics.first;
        final drawn =
            m.extractPath(0, m.length * math.min(checkT, 1.0));
        canvas.drawPath(drawn, checkPaint);
      }
    }

    canvas.restore();
  }

  /// Lid angle with the 1.1 overshoot baked into the curve evaluation —
  /// we re-evaluate the bounce curve here because the controller stores
  /// linear progress and the overshoot must not also hit the walls.
  double _lidAngle(double t) => _kLidOpenDeg * t;

  double _wobbleCurve(double t) {
    if (t <= 0) return 1;
    // 1 -> 0.86 -> 1 over the settle window.
    final phase = t < 0.5 ? t * 2 : (1 - t) * 2;
    final eased = Curves.easeOut.transform(phase);
    return 1 - 0.14 * eased;
  }

  @override
  bool shouldRepaint(_BinPainter old) =>
      old.lidT != lidT ||
      old.wallT != wallT ||
      old.checkT != checkT ||
      old.swapT != swapT ||
      old.wobbleT != wobbleT ||
      old.color != color;
}

/// Left-pointing triangle notch that visually connects the panel to the
/// trigger tile.
class _NotchPainter extends CustomPainter {
  _NotchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NotchPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// showHeroDeleteConfirm — destructive confirmation, hosted around the
// morph button. Returns true when the user confirms (check), false on
// cancel / barrier dismiss.
// ---------------------------------------------------------------------------

Future<bool> showHeroDeleteConfirm({
  required BuildContext context,
  required String title,
  String? message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showHeroDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final h = HeroScope.of(ctx);
      return HeroDialogFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: HeroTokens.title.copyWith(
                color: h.foreground,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: HeroTokens.bodySmall
                      .copyWith(color: h.muted, height: 1.55),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Center(
              child: HeroDeleteButton(
                onConfirm: () async {
                  // Let the check draw itself before the dialog pops.
                  await Future<void>.delayed(
                      Duration(milliseconds: heroAnimationsEnabled ? 520 : 0));
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                },
                onCancel: () async {
                  await Future<void>.delayed(
                      Duration(milliseconds: heroAnimationsEnabled ? 160 : 0));
                  if (ctx.mounted) Navigator.of(ctx).pop(false);
                },
              ),
            ),
            const SizedBox(height: 14),
            Text(
              confirmLabel.toUpperCase(),
              textAlign: TextAlign.center,
              style: HeroTokens.eyebrow.copyWith(
                color: h.danger,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Menu dropdown (transitions.dev "menu-dropdown", ported natively).
//
// Entrances: scale .97 -> 1 + fade, 250ms, house decel, transform-origin
// at the trigger's corner. Exits: 150ms recede to .99. Items stagger in
// beneath the panel (x -6 -> 0 + fade, 40ms apart).
// ---------------------------------------------------------------------------

/// One row of a [HeroMenuButton] menu.
class HeroMenuItem<T> {
  const HeroMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.checked = false,
    this.danger = false,
    this.dividerAfter = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool checked;

  /// Destructive rows render in the danger colour.
  final bool danger;

  /// Paint a hairline divider below this row.
  final bool dividerAfter;
}

/// Opens the anchored dropdown. [position] is the trigger rect relative to
/// the overlay (the same convention as [showMenu] — see
/// [HeroMenuButton] for the usual way to compute it).
Future<T?> showHeroMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<HeroMenuItem<T>> items,
}) {
  return Navigator.of(context, rootNavigator: true)
      .push<T>(HeroMenuRoute<T>(position: position, items: items));
}

class HeroMenuRoute<T> extends PopupRoute<T> {
  HeroMenuRoute({required this.position, required this.items});

  final RelativeRect position;
  final List<HeroMenuItem<T>> items;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => HeroMotion.durationIn;

  @override
  Duration get reverseTransitionDuration => HeroMotion.durationOut;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return HeroMenuPanel(route: this, animation: animation);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }
}

class HeroMenuPanel<T> extends StatelessWidget {
  const HeroMenuPanel({super.key, required this.route, required this.animation});

  final HeroMenuRoute<T> route;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);

    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final menuW = math.min(280.0, size.width - 24);
      const rowH = 44.0;
      final estH =
          route.items.length * rowH + 12; // + card padding (6 top/bottom)

      // Prefer below the anchor; flip above when it would overflow.
      //
      // RelativeRect semantics: `top` = distance from the OVERLAY top to
      // the button top; `bottom` = distance from the BUTTON bottom to the
      // overlay bottom. The previous code used `position.bottom` as the
      // button's bottom-Y (it is the inverse) — for a header-anchored
      // trigger that computed a below-slot near the screen FLOOR and the
      // menu rendered at the very bottom, half-clipped by the nav dock
      // (the "extreme bottom, cut off" report).
      final buttonBottom = size.height - route.position.bottom;
      final belowTop = buttonBottom + 6;
      final bool below = belowTop + estH <= size.height - 16;
      final double top;
      if (below) {
        top = belowTop;
      } else {
        final aboveTop = route.position.top - 6 - estH;
        top = aboveTop >= 16
            ? aboveTop
            : math.max(16.0, size.height - estH - 16);
      }

      final double left = route.position.left
          .clamp(12.0, (size.width - menuW - 12).clamp(12.0, double.infinity));

      // Transform-origin at the trigger's horizontal position on the edge
      // facing the trigger (the .t-dropdown data-origin rule).
      final originX =
          (((route.position.left + route.position.right) / 2 - left) /
                  menuW)
              .clamp(0.0, 1.0);
      final origin = Alignment(-1 + 2 * originX, below ? -1.0 : 1.0);

      return Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: menuW,
          child: AnimatedBuilder(
            animation: animation,
            builder: (_, __) {
              final t = animation.value;
              // Forward: .97 -> 1 on the house decel. Reverse: recede to
              // .99 — the exit never shrinks toward the viewer.
              final double scale;
              if (animation.status == AnimationStatus.reverse) {
                scale = lerpDouble(HeroMotion.closingScale, 1.0, t)!;
              } else {
                scale = lerpDouble(
                    HeroMotion.preScale, 1.0, HeroMotion.easeOut.transform(t))!;
              }
              return Transform.scale(
                scale: scale,
                alignment: origin,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: h.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: h.border),
                    boxShadow: h.overlayShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < route.items.length; i++) ...[
                        _HeroMenuRow(
                          item: route.items[i],
                          entrance: Interval(
                            (i * 0.09).clamp(0.0, 0.8),
                            1.0,
                            curve: HeroMotion.easeOut,
                          ).transform(HeroMotion.easeOut.transform(t)),
                          onTap: () =>
                              Navigator.of(context).pop(route.items[i].value),
                        ),
                        if (route.items[i].dividerAfter)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: HeroSeparator(),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ]);
    });
  }
}

class _HeroMenuRow extends StatelessWidget {
  const _HeroMenuRow({
    required this.item,
    required this.entrance,
    required this.onTap,
  });

  final HeroMenuItem<dynamic> item;
  final double entrance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final fg = item.danger ? h.danger : h.foreground;

    return Opacity(
      opacity: entrance,
      child: Transform.translate(
        offset: Offset(-6 * (1 - entrance), 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: item.checked ? h.surface2 : Colors.transparent,
            ),
            child: Row(children: [
              if (item.icon != null) ...[
                Icon(item.icon,
                    size: 18, color: item.danger ? h.danger : h.muted),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: HeroTokens.body.copyWith(
                    color: fg,
                    fontSize: 14.5,
                    fontWeight: item.checked ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (item.checked)
                Icon(Icons.check_rounded, size: 18, color: h.foreground),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A drop-in replacement for [PopupMenuButton] rendered as a
/// [HeroIconButton] that opens the [HeroMenuRoute] anchored to itself.
class HeroMenuButton<T> extends StatelessWidget {
  const HeroMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = Icons.more_horiz_rounded,
    this.tooltip,
  });

  final List<HeroMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final String? tooltip;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rect = RelativeRect.fromRect(
      box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
      Offset.zero & overlay.size,
    );
    final result = await showHeroMenu<T>(context: context, position: rect, items: items);
    if (result != null) onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    return HeroIconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: () => _open(context),
    );
  }
}
