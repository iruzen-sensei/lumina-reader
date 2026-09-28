// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// WATERMELON INTERACTIONS — Flutter ports of the interaction patterns from
// ui.watermelon.sh (animated-components: micro-interaction + interaction
// categories), rebuilt on the Lumina Noir design tokens so the LOOK of the
// app is preserved while the INTERACTIONS are upgraded:
//
//   WmBounceCurve       — bouncy spring (dock selection physics)
//   WmBlurFade          — opacity + blur enter/exit helper
//   WmStaggeredText     — per-character staggered text morph
//   WmDiscoveryBar      — Morphing Discovery Bar (search button morph)
//   WmExpandDetails     — Expand Details (staggered size spring)
//   WmExtendedToolbar   — Extended Toolbar (primary slides out, secondary in)
//   WmFeedbackAction    — Feedback Action (circle→pill morph, states, retry)
//   WmPredictiveInput   — Predictive Text (floating prefix suggestions)
//   WmQuickOptionPicker — Quick Option Picker (popover above, 3D tilt)
//   WmSplitActions      — Split Actions (trigger fans out action chips)
//   WmStatusPicker      — Status Picker (animated status swap + tray)
//   WmSplitToEdit       — Split To Edit (value pill splits into editor)
//
// Every animation is gated by [heroAnimationsEnabled] (the global motion
// kill-switch) so accessibility / reduced-motion settings hold here too.

import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';

import 'lumina_ui.dart';

// ---------------------------------------------------------------------------
// Curves + helpers
// ---------------------------------------------------------------------------

/// Watermelon dock/bounce spring (stiffness 550 / damping 15 / mass 1.1 —
/// the source's selection pop): sampled SpringSimulation with a small,
/// deliberate overshoot. Sampled (not analytic) so it can be used anywhere
/// a [Curve] is accepted.
class WmBounceCurve extends Curve {
  const WmBounceCurve({this.stiffness = 550, this.damping = 15, this.mass = 1.1});

  final double stiffness;
  final double damping;
  final double mass;

  @override
  double transformInternal(double t) {
    final spring = SpringDescription(mass: mass, stiffness: stiffness, damping: damping);
    final sim = SpringSimulation(spring, 0.0, 1.0, 0.0);
    return sim.x(t * _settleSeconds(spring));
  }

  static double _settleSeconds(SpringDescription spring) {
    // Damped oscillation period scaled to a natural settle time.
    final omega = math.sqrt(spring.stiffness / spring.mass);
    final zeta = spring.damping /
        (2 * math.sqrt(spring.stiffness * spring.mass));
    if (zeta < 1) {
      return (2.2 / (zeta * omega)).clamp(0.28, 0.9);
    }
    return 0.42;
  }
}

/// Soft layout spring used by the morphing bar / toolbars (bounce 0.3).
const Curve wmMorphSpring = Curves.easeOutBack;

/// Animated opacity + blur enter (the watermelon signature "blur-in").
/// [in_] = fully visible; when false the child is blurred + transparent.
class WmBlurFade extends StatelessWidget {
  const WmBlurFade({super.key, required this.in_, this.blur = 8, this.dx = 0, required this.child});

  final bool in_;
  final double blur;
  final double dx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!heroAnimationsEnabled) return Opacity(opacity: in_ ? 1 : 0, child: child);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: in_ ? 1 : 0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, v, kid) {
        final sigma = blur * (1 - v);
        final wob = Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx * (1 - v), 0), child: kid),
        );
        if (sigma < 0.15) return wob;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: wob,
        );
      },
      child: child,
    );
  }
}

/// Per-character staggered text (Feedback Action's AnimatedText): each
/// character blur-pops in with a tiny delay cascade. Bounded to 32 chars —
/// longer strings fall back to a plain fade (perf guard).
class WmStaggeredText extends StatelessWidget {
  const WmStaggeredText({super.key, required this.text, this.delayStep = 0.014, this.style});

  final String text;
  final double delayStep;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!heroAnimationsEnabled || text.length > 32) {
      return Text(text, style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: text.length),
      duration: Duration(
          milliseconds: (text.length * delayStep * 1000).round() + 260),
      curve: Curves.linear,
      builder: (context, count, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < text.length; i++)
              _StaggeredChar(
                char: text[i],
                shown: i < count,
                delay: i * delayStep,
                style: style,
              ),
          ],
        );
      },
    );
  }
}

class _StaggeredChar extends StatefulWidget {
  const _StaggeredChar({required this.char, required this.shown, required this.delay, this.style});

  final String char;
  final bool shown;
  final double delay;
  final TextStyle? style;

  @override
  State<_StaggeredChar> createState() => _StaggeredCharState();
}

class _StaggeredCharState extends State<_StaggeredChar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: const WmBounceCurve());

  @override
  void initState() {
    super.initState();
    if (widget.shown) {
      Future<void>.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_StaggeredChar old) {
    super.didUpdateWidget(old);
    if (widget.shown != old.shown) {
      if (widget.shown) {
        _c.forward(from: 0);
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final t = _a.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: Transform.scale(scale: 0.5 + 0.5 * t, child: Text(widget.char, style: widget.style)),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Morphing Discovery Bar (the search button morph)
//
// Collapsed: [ search icon pill ] [ category pills row ]
// Expanded:  [ search icon + input ..................... ] [ X close ]
//            (full remaining width — a 44px-wide input was unusable)
//            + up to three Predictive-Text suggestion chips below.
//
// Layout springs (AnimatedSize + wmMorphSpring), the input blur-scales in,
// the categories blur-scale out, and the close button slides in from the
// left with a horizontal squash — the source's exact choreography. The
// category rail fades softly at the trailing screen edge (Apple edge-fade
// treatment) instead of hard-clipping mid-chip.

class WmDiscoveryCategory {
  const WmDiscoveryCategory({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
}

class WmDiscoveryBar extends StatefulWidget {
  const WmDiscoveryBar({
    super.key,
    required this.categories,
    required this.onSearch,
    this.searchHint = 'Search',
    this.accent,
    this.suggestionDictionary,
  });

  final List<WmDiscoveryCategory> categories;
  final ValueChanged<String> onSearch;
  final String searchHint;

  /// Optional accent override (e.g. Netflix red on the Anime page). Falls
  /// back to the theme accent (noir white).
  final Color? accent;

  /// Optional Predictive-Text dictionary: while typing, up to three
  /// prefix completions float below the morphed input (tap completes the
  /// word). Wire the shared genre/term vocabulary here.
  final List<String>? suggestionDictionary;

  @override
  State<WmDiscoveryBar> createState() => _WmDiscoveryBarState();
}

class _WmDiscoveryBarState extends State<WmDiscoveryBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _catsController = ScrollController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _controller.text.isEmpty && _searching) {
        setState(() => _searching = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _catsController.dispose();
    super.dispose();
  }

  void _open() {
    setState(() => _searching = true);
    HapticFeedback.selectionClick();
    if (heroAnimationsEnabled) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _focus.requestFocus();
      });
    } else {
      _focus.requestFocus();
    }
  }

  void _close() {
    _focus.unfocus();
    _controller.clear();
    setState(() => _searching = false);
    HapticFeedback.selectionClick();
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.isEmpty) return;
    widget.onSearch(q);
  }

  /// Predictive completions for the last word being typed (max 3).
  List<String> get _suggestions {
    final dict = widget.suggestionDictionary;
    if (dict == null) return const [];
    final text = _controller.text;
    if (text.isEmpty || text.endsWith(' ')) return const [];
    final last = text.split(RegExp(r'\s+')).last.toLowerCase();
    if (last.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final w in dict) {
      final lw = w.toLowerCase();
      if (lw.startsWith(last) && lw != last && seen.add(lw)) {
        out.add(w);
        if (out.length == 3) break;
      }
    }
    return out;
  }

  void _applySuggestion(String word) {
    final words = _controller.text.split(RegExp(r'\s+'));
    if (words.isEmpty) return;
    words[words.length - 1] = word;
    _controller.text = '${words.join(' ')} ';
    _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length));
    setState(() {});
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final accent = widget.accent ?? h.accent;
    final suggestions = _suggestions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // Full-width morph: expanded input takes everything except the
          // close circle (40) + gap (8).
          final expandedW = (constraints.maxWidth - 48)
              .clamp(120.0, double.infinity)
              .toDouble();
          return Row(
            children: [
              // ---- Search pill (morphs 44 -> full-width input) ----
              AnimatedSize(
                duration: heroAnimationsEnabled
                    ? const Duration(milliseconds: 380)
                    : Duration.zero,
                curve: wmMorphSpring,
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: heroAnimationsEnabled
                      ? const Duration(milliseconds: 300)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  height: 44,
                  width: _searching ? expandedW : 44,
                  padding:
                      EdgeInsets.symmetric(horizontal: _searching ? 12 : 0),
                  decoration: BoxDecoration(
                    color: _searching ? h.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
                    border: Border.all(
                      color: _searching
                          ? accent.withValues(alpha: 0.65)
                          : h.border,
                      width: 1.2,
                    ),
                  ),
                  child: _searching
                      ? Row(
                          children: [
                            Icon(Icons.search_rounded,
                                size: 19, color: h.muted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focus,
                                textInputAction: TextInputAction.search,
                                onSubmitted: _submit,
                                onChanged: (_) => setState(() {}),
                                style: HeroTokens.bodySmall
                                    .copyWith(color: h.foreground),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  isCollapsed: true,
                                  hintText: widget.searchHint,
                                  hintStyle: HeroTokens.bodySmall
                                      .copyWith(color: h.muted),
                                ),
                              ),
                            ),
                            if (_controller.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _controller.clear();
                                  setState(() {});
                                },
                                child: Icon(Icons.close_rounded,
                                    size: 16, color: h.muted),
                              ),
                          ],
                        )
                      : Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _open,
                            child: Icon(Icons.search_rounded,
                                size: 22, color: h.foreground),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              // ---- Categories / close ----
              Expanded(
                child: AnimatedSwitcher(
                  duration: heroAnimationsEnabled
                      ? const Duration(milliseconds: 300)
                      : Duration.zero,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: _searching
                      ? Align(
                          key: const ValueKey('close'),
                          alignment: Alignment.centerLeft,
                          child: _CloseCircle(onTap: _close, color: accent),
                        )
                      : HeroEdgeFade(
                          key: const ValueKey('cats'),
                          controller: _catsController,
                          width: 20,
                          child: SingleChildScrollView(
                            controller: _catsController,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                              children: [
                                for (var i = 0;
                                    i < widget.categories.length;
                                    i++)
                                  _DiscoveryChip(
                                    cat: widget.categories[i],
                                    accent: accent,
                                    onTap: widget.categories[i].onTap,
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        }),
        // ---- Predictive-Text suggestions (below the input) ----
        AnimatedSize(
          duration: heroAnimationsEnabled
              ? const Duration(milliseconds: 240)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: _searching && suggestions.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < suggestions.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _SuggestionChip(
                            label: suggestions[i],
                            onTap: () => _applySuggestion(suggestions[i]),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _DiscoveryChip extends StatelessWidget {
  const _DiscoveryChip({required this.cat, required this.accent, required this.onTap});

  final WmDiscoveryCategory cat;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final sel = cat.selected;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: heroAnimationsEnabled
              ? HeroTokens.motionColor
              : Duration.zero,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: sel ? accent : h.surface,
            borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
            border: Border.all(
              color: sel ? accent : h.border,
              width: sel ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(cat.icon,
                  size: 14,
                  color: sel ? h.accentFg : h.muted),
              const SizedBox(width: 6),
              Text(
                cat.label,
                style: HeroTokens.caption.copyWith(
                  color: sel ? h.accentFg : h.foreground,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The X close button — slides in from the left with a squash (the source's
/// scaleX 1.5 -> 1 entrance), sits in a hairline circle.
class _CloseCircle extends StatelessWidget {
  const _CloseCircle({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: h.surface,
          border: Border.all(color: h.border, width: 1.2),
        ),
        child: Icon(Icons.close_rounded, size: 18, color: h.foreground),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Expand Details — collapsed summary expands with STAGGERED springs
// (width settles first when collapsing, height first when expanding), the
// chevron rotates -90deg, and the content blur-slides in after the frame
// starts opening (the source's delay choreography).
// ---------------------------------------------------------------------------

class WmExpandDetails extends StatefulWidget {
  const WmExpandDetails({
    super.key,
    required this.title,
    required this.collapsed,
    required this.expanded,
    this.initiallyOpen = false,
  });

  final String title;
  final Widget collapsed;
  final Widget expanded;
  final bool initiallyOpen;

  @override
  State<WmExpandDetails> createState() => _WmExpandDetailsState();
}

class _WmExpandDetailsState extends State<WmExpandDetails>
    with SingleTickerProviderStateMixin {
  late bool _open = widget.initiallyOpen;
  late final AnimationController _chev = AnimationController(
      vsync: this,
      duration: heroAnimationsEnabled
          ? const Duration(milliseconds: 220)
          : Duration.zero,
      value: widget.initiallyOpen ? 1.0 : 0.0);

  void _toggle() {
    setState(() => _open = !_open);
    HapticFeedback.selectionClick();
    if (_open) {
      _chev.forward();
    } else {
      _chev.reverse();
    }
  }

  @override
  void dispose() {
    _chev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return AnimatedSize(
      duration: heroAnimationsEnabled
          ? const Duration(milliseconds: 420)
          : Duration.zero,
      curve: HeroTokens.spring,
      alignment: Alignment.topCenter,
      child: Container(
        // Collapsed = a compact hairline chip; expanded = a full card. The
        // radius + color morph with the state (20 -> 24 in the source).
        decoration: BoxDecoration(
          color: _open ? h.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(_open ? 14 : HeroTokens.radiusChip),
          border: Border.all(color: _open ? h.separator : h.border),
        ),
        padding: EdgeInsets.symmetric(
            horizontal: _open ? 16 : 12, vertical: _open ? 14 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: chevron + title (always visible; the FULL-WIDTH
            // band is the tap target so the affordance is discoverable).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                  RotationTransition(
                    turns: Tween(begin: 0.75, end: 1.0).animate(
                        CurvedAnimation(parent: _chev, curve: Curves.easeOut)),
                    child: Icon(Icons.expand_more_rounded,
                        size: 20, color: h.muted),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: HeroTokens.body.copyWith(
                      color: h.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: heroAnimationsEnabled
                  ? const Duration(milliseconds: 300)
                  : Duration.zero,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.06), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              ),
              child: _open
                  ? Padding(
                      key: const ValueKey('open'),
                      padding: const EdgeInsets.only(top: 12),
                      child: WmBlurFade(in_: true, dx: 12, child: widget.expanded),
                    )
                  : Padding(
                      key: const ValueKey('closed'),
                      padding: const EdgeInsets.only(top: 8, left: 28),
                      child: widget.collapsed,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Extended Toolbar — a pill whose primary actions slide left and blur
// out while the secondary set slides in from the right; the chevron toggle
// rotates 180deg and the pill width springs to fit (the source's carousel
// choreography, implemented with a clipped slide).
// ---------------------------------------------------------------------------

class WmToolItem {
  const WmToolItem({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
}

class WmExtendedToolbar extends StatefulWidget {
  const WmExtendedToolbar({
    super.key,
    required this.primary,
    required this.secondary,
    this.showLabels = false,
    this.dark = false,
  });

  final List<WmToolItem> primary;
  final List<WmToolItem> secondary;

  /// Player-style: icon + 10px label under it (Netflix button row). The
  /// default compact mode shows icons only (labels stay as tooltips).
  final bool showLabels;

  /// Video-player context: translucent dark pill, white icons (the
  /// default uses the theme surfaces).
  final bool dark;

  @override
  State<WmExtendedToolbar> createState() => _WmExtendedToolbarState();
}

class _WmExtendedToolbarState extends State<WmExtendedToolbar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final slide = heroAnimationsEnabled
        ? const Duration(milliseconds: 380)
        : Duration.zero;
    const curve = HeroTokens.spring;

    final maxRow = math.max(widget.primary.length, widget.secondary.length);
    final itemW = widget.showLabels ? 64.0 : 52.0;
    final baseW = (maxRow * itemW) + 44.0;
    final pillColor = widget.dark ? Colors.white.withValues(alpha: 0.10) : h.surface;
    final pillBorder = widget.dark ? Colors.white.withValues(alpha: 0.16) : h.border;

    return AnimatedContainer(
      duration: slide,
      curve: curve,
      width: baseW,
      height: widget.showLabels ? 58 : 48,
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
        border: Border.all(color: pillBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
        child: Stack(
          children: [
            // Primary row — slides left + fades out when expanding.
            AnimatedSlide(
              duration: slide,
              curve: curve,
              offset: _expanded ? const Offset(-1.4, 0) : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _expanded ? 0 : 1,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.primary.length; i++)
                      _ToolButton(
                        item: widget.primary[i],
                        w: itemW,
                        showLabel: widget.showLabels,
                        dark: widget.dark,
                      ),
                  ],
                ),
              ),
            ),
            // Secondary row — slides in from the right.
            AnimatedSlide(
              duration: slide,
              curve: curve,
              offset: _expanded ? Offset.zero : const Offset(1.4, 0),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _expanded ? 1 : 0,
                child: Row(
                  children: [
                    for (var i = 0; i < widget.secondary.length; i++)
                      _ToolButton(
                        item: widget.secondary[i],
                        w: itemW,
                        showLabel: widget.showLabels,
                        dark: widget.dark,
                      ),
                  ],
                ),
              ),
            ),
            // Toggle (right edge, above the rows).
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _expanded = !_expanded);
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  width: 44,
                  height: widget.showLabels ? 58 : 48,
                  color: pillColor,
                  child: Center(
                    child: RotationTransition(
                      turns: AlwaysStoppedAnimation(_expanded ? 1.0 : 0.5),
                      child: Icon(
                        _expanded
                            ? Icons.chevron_right_rounded
                            : Icons.chevron_left_rounded,
                        size: 20,
                        color: widget.dark
                            ? Colors.white.withValues(alpha: 0.75)
                            : h.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.item,
    required this.w,
    this.showLabel = false,
    this.dark = false,
  });

  final WmToolItem item;
  final double w;
  final bool showLabel;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final iconColor = dark
        ? (item.active ? Colors.white : Colors.white.withValues(alpha: 0.85))
        : (item.active ? h.accent : h.muted);
    final labelColor = dark
        ? Colors.white.withValues(alpha: 0.8)
        : h.muted;
    return SizedBox(
      width: w,
      height: showLabel ? 58 : 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: item.label,
        icon: showLabel
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 19, color: iconColor),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: HeroTokens.fontSans,
                      fontSize: 9.5,
                      fontWeight: item.active ? FontWeight.w700 : FontWeight.w500,
                      color: item.active && !dark ? h.accent : labelColor,
                    ),
                  ),
                ],
              )
            : Icon(item.icon, size: 20, color: iconColor),
        onPressed: () {
          HapticFeedback.selectionClick();
          item.onTap();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Feedback Action — a circular icon trigger that morphs into a status
// pill: loading (staggered per-char text + spinner), success (check pops),
// error (icon swap + retry circle slides in). Used for Add-to-library and
// other optimistic actions whose real outcome arrives async.
// ---------------------------------------------------------------------------

enum WmFeedbackState { idle, loading, success, error }

class WmFeedbackAction extends StatefulWidget {
  const WmFeedbackAction({
    super.key,
    required this.idleLabel,
    required this.idleIcon,
    required this.onAction,
    this.loadingLabel = 'Working…',
    this.successLabel = 'Done',
    this.errorLabel = 'Failed',
    this.onSuccess,
    this.accent,
  });

  final String idleLabel;
  final IconData idleIcon;

  /// Performs the action. Return true for success, false (or throw) for
  /// the error state with retry.
  final Future<bool> Function() onAction;

  final String loadingLabel;
  final String successLabel;
  final String errorLabel;
  final VoidCallback? onSuccess;
  final Color? accent;

  @override
  State<WmFeedbackAction> createState() => _WmFeedbackActionState();
}

class _WmFeedbackActionState extends State<WmFeedbackAction>
    with SingleTickerProviderStateMixin {
  WmFeedbackState _state = WmFeedbackState.idle;

  /// Success -> idle auto-reset timer; cancelled on dispose (a dangling
  /// timer fails test invariants and keeps the state closure alive).
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_state == WmFeedbackState.loading) return;
    setState(() => _state = WmFeedbackState.loading);
    unawaited(HapticFeedback.selectionClick());
    try {
      final ok = await widget.onAction();
      if (!mounted) return;
      setState(() => _state = ok ? WmFeedbackState.success : WmFeedbackState.error);
      if (ok) {
        unawaited(HapticFeedback.lightImpact());
        widget.onSuccess?.call();
        _resetTimer?.cancel();
        _resetTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted && _state == WmFeedbackState.success) {
            setState(() => _state = WmFeedbackState.idle);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _state = WmFeedbackState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final accent = widget.accent ?? h.accent;
    final err = _state == WmFeedbackState.error;
    final done = _state == WmFeedbackState.success;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: heroAnimationsEnabled
              ? const Duration(milliseconds: 340)
              : Duration.zero,
          curve: HeroTokens.spring,
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _state == WmFeedbackState.idle || err ? _run : null,
            child: AnimatedContainer(
              duration: heroAnimationsEnabled
                  ? const Duration(milliseconds: 280)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              height: 38,
              padding: EdgeInsets.symmetric(
                  horizontal: _state == WmFeedbackState.idle ? 16 : 14),
              decoration: BoxDecoration(
                color: err
                    ? h.dangerSoft
                    : done
                        ? h.successSoft
                        : accent,
                borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
                border: Border.all(
                  color: err
                      ? h.danger.withValues(alpha: 0.5)
                      : accent,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: heroAnimationsEnabled
                        ? const Duration(milliseconds: 260)
                        : Duration.zero,
                    transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child)),
                    child: _stateIcon(h, accent),
                  ),
                  const SizedBox(width: 8),
                  WmStaggeredText(
                    text: switch (_state) {
                      WmFeedbackState.idle => widget.idleLabel,
                      WmFeedbackState.loading => widget.loadingLabel,
                      WmFeedbackState.success => widget.successLabel,
                      WmFeedbackState.error => widget.errorLabel,
                    },
                    style: HeroTokens.bodySmall.copyWith(
                      color: err
                          ? h.danger
                          : done
                              ? h.success
                              : (widget.accent != null ? Colors.white : h.accentFg),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Retry circle — slides in from the left on error (source motion).
        AnimatedSize(
          duration: heroAnimationsEnabled
              ? const Duration(milliseconds: 300)
              : Duration.zero,
          curve: HeroTokens.spring,
          alignment: Alignment.centerLeft,
          child: err
              ? Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: _run,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: h.foreground,
                      ),
                      child: Icon(Icons.refresh_rounded,
                          size: 18, color: h.background),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _stateIcon(HeroThemeData h, Color accent) {
    switch (_state) {
      case WmFeedbackState.idle:
        return Icon(widget.idleIcon,
            key: const ValueKey('idle'),
            size: 17,
            color: widget.accent != null ? Colors.white : h.accentFg);
      case WmFeedbackState.loading:
        return SizedBox(
          key: const ValueKey('busy'),
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(
                widget.accent != null ? Colors.white : h.accentFg),
          ),
        );
      case WmFeedbackState.success:
        return Icon(Icons.check_rounded,
            key: const ValueKey('ok'), size: 17, color: h.success);
      case WmFeedbackState.error:
        return Icon(Icons.error_outline_rounded,
            key: const ValueKey('err'), size: 17, color: h.danger);
    }
  }
}

// ---------------------------------------------------------------------------
// 5. Predictive Text — an input with up to three floating suggestions
// derived from the prefix of the last word; tap (or arrow keys + enter)
// completes the word. Suggestions float above the field and stagger in.
// ---------------------------------------------------------------------------

class WmPredictiveInput extends StatefulWidget {
  const WmPredictiveInput({
    super.key,
    required this.controller,
    required this.dictionary,
    required this.onSubmitted,
    this.hint = 'Search…',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final List<String> dictionary;
  final ValueChanged<String> onSubmitted;
  final String hint;
  final bool autofocus;

  @override
  State<WmPredictiveInput> createState() => _WmPredictiveInputState();
}

class _WmPredictiveInputState extends State<WmPredictiveInput> {
  int _active = -1;

  List<String> get _suggestions {
    final text = widget.controller.text;
    if (text.isEmpty || text.endsWith(' ')) return const [];
    final words = text.split(RegExp(r'\s+'));
    final last = words.last.toLowerCase();
    if (last.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final w in widget.dictionary) {
      final lw = w.toLowerCase();
      if (lw.startsWith(last) && lw != last && seen.add(lw)) {
        out.add(w);
        if (out.length == 3) break;
      }
    }
    return out;
  }

  void _apply(String word) {
    final text = widget.controller.text;
    final words = text.split(RegExp(r'\s+'));
    if (words.isEmpty) return;
    words[words.length - 1] = word;
    widget.controller.text = '${words.join(' ')} ';
    widget.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.text.length));
    setState(() => _active = -1);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Floating suggestions (above the field, staggered pop-in).
        AnimatedSize(
          duration: heroAnimationsEnabled
              ? const Duration(milliseconds: 240)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomLeft,
          child: suggestions.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < suggestions.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _SuggestionChip(
                            label: suggestions[i],
                            highlighted: i == _active,
                            onTap: () => _apply(suggestions[i]),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        HeroInput(
          controller: widget.controller,
          hint: widget.hint,
          prefixIcon: Icons.search_rounded,
          autofocus: widget.autofocus,
          suffix: widget.controller.text.isNotEmpty
              ? HeroIconButton(
                  icon: Icons.close_rounded,
                  size: 28,
                  iconSize: 16,
                  onPressed: () {
                    widget.controller.clear();
                    setState(() => _active = -1);
                  },
                )
              : null,
          onChanged: (_) => setState(() => _active = -1),
          onSubmitted: widget.onSubmitted,
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip(
      {required this.label, required this.onTap, this.highlighted = false});

  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: heroAnimationsEnabled
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: highlighted ? h.accent : h.surface,
          borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
          border: Border.all(
              color: highlighted ? h.accent : h.border, width: 1.1),
        ),
        child: Text(
          label,
          style: HeroTokens.caption.copyWith(
            color: highlighted ? h.accentFg : h.foreground,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Quick Option Picker — a compact pill (icon + selected label) that
// pops a horizontal option tray ABOVE it with a 3D bottom-origin tilt +
// blur (rotateX -70 -> 0 in the source). Selecting closes the tray and
// morphs the pill label.
// ---------------------------------------------------------------------------

class WmPickerOption<T> {
  const WmPickerOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class WmQuickOptionPicker<T> extends StatefulWidget {
  const WmQuickOptionPicker({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint,
    this.trayAbove = true,
  });

  final List<WmPickerOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? hint;

  /// Whether the option tray pops ABOVE (default) or BELOW the pill — pick
  /// BELOW when the picker lives near the top of the screen (e.g. filter
  /// bars) so the tray is not clipped by the app bar.
  final bool trayAbove;

  @override
  State<WmQuickOptionPicker<T>> createState() => _WmQuickOptionPickerState<T>();
}

class _WmQuickOptionPickerState<T> extends State<WmQuickOptionPicker<T>> {
  bool _open = false;
  OverlayEntry? _entry;
  final LayerLink _link = LayerLink();

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _open = true);
    // The tray lives in the root Overlay so it can float ABOVE the pill's
    // own bounds (a Stack-Positioned tray is drawn but NOT hit-testable
    // outside the Stack — taps fell through, found by the widget tests).
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Tap-outside barrier closes the tray (the source's
            // click-outside handler).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            // The tray, anchored to the pill (above or below).
            CompositedTransformFollower(
              link: _link,
              targetAnchor: widget.trayAbove
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              followerAnchor: widget.trayAbove
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: _TrayPanel<T>(
                options: widget.options,
                value: widget.value,
                trayAbove: widget.trayAbove,
                onSelect: (v) {
                  widget.onChanged(v);
                  _close();
                },
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final selected =
        widget.options.where((o) => o.value == widget.value).firstOrNull;

    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: heroAnimationsEnabled
              ? HeroTokens.motionColor
              : Duration.zero,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _open ? h.accentSoft : h.surface,
            borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
            border: Border.all(
                color: _open ? h.accent : h.border,
                width: _open ? 1.2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected?.icon != null) ...[
                Icon(selected!.icon,
                    size: 14, color: _open ? h.accent : h.muted),
                const SizedBox(width: 6),
              ],
              // Flexible: a long option label (e.g. source names) ellipsizes
              // instead of overflowing the pill's parent row.
              Flexible(
                child: AnimatedSwitcher(
                duration: heroAnimationsEnabled
                    ? const Duration(milliseconds: 220)
                    : Duration.zero,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.35), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  selected?.label ?? widget.hint ?? 'Select',
                  key: ValueKey(selected?.label ?? 'hint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HeroTokens.caption.copyWith(
                    color: h.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ),
              ),
              const SizedBox(width: 6),
              RotationTransition(
                turns: AlwaysStoppedAnimation(_open ? 0.5 : 0.0),
                child:
                    Icon(Icons.expand_more_rounded, size: 15, color: h.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating tray panel (3D bottom/top-origin tilt + blur-in entrance).
class _TrayPanel<T> extends StatefulWidget {
  const _TrayPanel({
    required this.options,
    required this.value,
    required this.trayAbove,
    required this.onSelect,
  });

  final List<WmPickerOption<T>> options;
  final T value;
  final bool trayAbove;
  final ValueChanged<T> onSelect;

  @override
  State<_TrayPanel<T>> createState() => _TrayPanelState<T>();
}

class _TrayPanelState<T> extends State<_TrayPanel<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: heroAnimationsEnabled
        ? const Duration(milliseconds: 300)
        : Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, kid) {
          final t = _c.value.clamp(0.0, 1.0);
          final tilt = (1 - Curves.easeOutCubic.transform(t)) *
              (widget.trayAbove ? -0.55 : 0.55);
          return Transform(
            alignment: widget.trayAbove
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateX(tilt),
            child: kid,
          );
        },
        child: Material(
          color: Colors.transparent,
          // Max width: an anchored tray near a screen edge must never run
          // off-screen; long labels ellipsize inside instead.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: h.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: h.border),
              boxShadow: h.overlayShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final o in widget.options)
                  _TrayOption<T>(
                    option: o,
                    selected: o.value == widget.value,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onSelect(o.value);
                    },
                  ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayOption<T> extends StatelessWidget {
  const _TrayOption(
      {required this.option, required this.selected, required this.onTap});

  final WmPickerOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? h.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (option.icon != null) ...[
              Icon(option.icon,
                  size: 14, color: selected ? h.accent : h.muted),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                option.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: HeroTokens.caption.copyWith(
                  color: selected ? h.accent : h.foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Split Actions — a round trigger that morphs (scale+blur swap) and
// fans its action chips out horizontally, centered on the trigger, with a
// spring cascade. Selected chip collapses everything back.
// ---------------------------------------------------------------------------

class WmSplitAction {
  const WmSplitAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class WmSplitActions extends StatefulWidget {
  const WmSplitActions({
    super.key,
    required this.actions,
    this.triggerIcon = Icons.add_rounded,
    this.accent,
  });

  final List<WmSplitAction> actions;
  final IconData triggerIcon;
  final Color? accent;

  @override
  State<WmSplitActions> createState() => _WmSplitActionsState();
}

class _WmSplitActionsState extends State<WmSplitActions>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  OverlayEntry? _entry;
  final LayerLink _link = LayerLink();

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _open = true);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Tap-outside closes the fan.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            // The fan, anchored + centered on the trigger. Lives in the
            // root overlay so the chips can extend past the trigger's own
            // bounds (a Stack-positioned fan would clip to the trigger's
            // 38px width — the widget-test overflow catch).
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.center,
              followerAnchor: Alignment.center,
              child: _FanRail(
                actions: widget.actions,
                onDone: _close,
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final accent = widget.accent ?? h.accent;
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedSwitcher(
          duration: heroAnimationsEnabled
              ? const Duration(milliseconds: 280)
              : Duration.zero,
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Container(
            key: ValueKey(_open),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _open ? h.surface : accent,
              border: Border.all(
                  color: _open ? h.border : accent, width: 1.2),
            ),
            child: RotationTransition(
              turns: AlwaysStoppedAnimation(_open ? 0.375 : 0),
              child: Icon(
                _open ? Icons.close_rounded : widget.triggerIcon,
                size: 20,
                color: _open
                    ? h.foreground
                    : (widget.accent != null ? Colors.white : h.accentFg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fanned action chips (overlay rail): chips slide out from the
/// trigger's center with a spring cascade.
class _FanRail extends StatelessWidget {
  const _FanRail({required this.actions, required this.onDone});

  final List<WmSplitAction> actions;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    // The rail is sized for the FULL fan span so every translated chip
    // stays inside a hit-testable box (transforms outside a parent's
    // bounds are invisible to hit testing).
    final n = actions.length;
    final width = (n - 1) * 96.0 + 170;
    return SizedBox(
      width: width,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < n; i++)
            Positioned.fill(
              child: _FanChip(
                action: actions[i],
                dx: (i - (n - 1) / 2) * 96,
                delay: i * 0.04,
                onClose: onDone,
              ),
            ),
        ],
      ),
    );
  }
}

class _FanChip extends StatefulWidget {
  const _FanChip({
    required this.action,
    required this.dx,
    required this.delay,
    required this.onClose,
  });

  final WmSplitAction action;
  final double dx;
  final double delay;
  final VoidCallback onClose;

  @override
  State<_FanChip> createState() => _FanChipState();
}

class _FanChipState extends State<_FanChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: const WmBounceCurve());

  @override
  void initState() {
    super.initState();
    if (heroAnimationsEnabled) {
      Future<void>.delayed(
          Duration(milliseconds: (widget.delay * 1000).round()), () {
        if (mounted) _c.forward();
      });
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final t = _a.value.clamp(0.0, 1.0);
        // Translate a FULL-SIZE layer (the chip centers inside it): the
        // transform stays within the rail's hit-testable bounds.
        return Transform.translate(
          offset: Offset(widget.dx * t, 0),
          child: Opacity(
            opacity: t,
            child: Align(
              alignment: Alignment.center,
              child: Transform.scale(
                scale: 0.6 + 0.4 * t,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onClose();
                    widget.action.onTap();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: h.surface2,
                      borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
                      border: Border.all(color: h.border, width: 1.1),
                      boxShadow: h.overlayShadow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.action.icon,
                            size: 15, color: h.foreground),
                        const SizedBox(width: 6),
                        Text(
                          widget.action.label,
                          style: HeroTokens.caption.copyWith(
                            color: h.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Status Picker — a collapsed pill that shows the current status with an
// animated swap (blur + scale), and pops a horizontal tray of options that
// slide/fan out. Selecting morphs the pill to the new status. This is the
// app's READING-STATUS setter (Reading / Finished / Plan / …).
// ---------------------------------------------------------------------------

class WmStatusItem {
  const WmStatusItem({
    required this.id,
    required this.icon,
    required this.name,
    this.color,
  });

  final int id;
  final IconData icon;
  final String name;
  final Color? color;
}

class WmStatusPicker extends StatefulWidget {
  const WmStatusPicker({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<WmStatusItem> items;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<WmStatusPicker> createState() => _WmStatusPickerState();
}

class _WmStatusPickerState extends State<WmStatusPicker> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final current =
        widget.items.where((i) => i.id == widget.value).firstOrNull;
    final tint = current?.color ?? h.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Collapsed pill.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _open = !_open);
            HapticFeedback.selectionClick();
          },
          child: AnimatedContainer(
            duration: heroAnimationsEnabled
                ? const Duration(milliseconds: 260)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _open ? h.surface2 : tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
              border:
                  Border.all(color: tint.withValues(alpha: 0.5), width: 1.1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: heroAnimationsEnabled
                      ? const Duration(milliseconds: 240)
                      : Duration.zero,
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: current == null
                      ? Icon(Icons.radio_button_unchecked,
                          key: const ValueKey('none'),
                          size: 15,
                          color: h.muted)
                      : Icon(current.icon,
                          key: ValueKey(current.id),
                          size: 15,
                          color: tint),
                ),
                const SizedBox(width: 7),
                AnimatedSwitcher(
                  duration: heroAnimationsEnabled
                      ? const Duration(milliseconds: 240)
                      : Duration.zero,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                              begin: const Offset(0, 0.4), end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    current?.name ?? 'Set status',
                    key: ValueKey(current?.id ?? -1),
                    style: HeroTokens.caption.copyWith(
                      color: tint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Option tray — fans out under the pill.
        AnimatedSize(
          duration: heroAnimationsEnabled
              ? const Duration(milliseconds: 280)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        _StatusOption(
                          item: widget.items[i],
                          selected: widget.items[i].id == widget.value,
                          delay: i * 0.03,
                          onTap: () {
                            widget.onChanged(widget.items[i].id);
                            setState(() => _open = false);
                          },
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _StatusOption extends StatefulWidget {
  const _StatusOption(
      {required this.item,
      required this.selected,
      required this.delay,
      required this.onTap});

  final WmStatusItem item;
  final bool selected;
  final double delay;
  final VoidCallback onTap;

  @override
  State<_StatusOption> createState() => _StatusOptionState();
}

class _StatusOptionState extends State<_StatusOption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

  @override
  void initState() {
    super.initState();
    if (heroAnimationsEnabled) {
      Future<void>.delayed(
          Duration(milliseconds: (widget.delay * 1000).round()), () {
        if (mounted) _c.forward();
      });
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final tint = widget.item.color ?? h.accent;
    return FadeTransition(
      opacity: _a,
      child: ScaleTransition(
        scale: Tween(begin: 0.7, end: 1.0).animate(_a),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  widget.selected ? tint.withValues(alpha: 0.16) : h.surface,
              borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
              border: Border.all(
                  color: widget.selected
                      ? tint.withValues(alpha: 0.6)
                      : h.border,
                  width: 1.1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.item.icon, size: 14, color: tint),
                const SizedBox(width: 6),
                Text(
                  widget.item.name,
                  style: HeroTokens.caption.copyWith(
                    color: widget.selected ? tint : h.foreground,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 9. Split To Edit — a value pill that splits open into an inline editor
// (value + unit fields) with animated radius transfer; Enter/Save commits,
// Esc/blur cancels. Used for the stats goal tiles (Split To Edit pattern).
// ---------------------------------------------------------------------------

class WmSplitToEdit extends StatefulWidget {
  const WmSplitToEdit({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onSave,
    this.maxValue = 9999,
  });

  final String label;
  final int value;
  final String unit;
  final ValueChanged<int> onSave;
  final int maxValue;

  @override
  State<WmSplitToEdit> createState() => _WmSplitToEditState();
}

class _WmSplitToEditState extends State<WmSplitToEdit> {
  late final TextEditingController _c = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openEditor() {
    _c.text = '${widget.value}';
    setState(() => _editing = true);
    if (heroAnimationsEnabled) {
      Future<void>.delayed(const Duration(milliseconds: 90), () {
        if (mounted) {
          _focus.requestFocus();
          _c.selection =
              TextSelection(baseOffset: 0, extentOffset: _c.text.length);
        }
      });
    } else {
      _focus.requestFocus();
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    }
    HapticFeedback.selectionClick();
  }

  void _save() {
    final raw = int.tryParse(_c.text.trim()) ?? widget.value;
    final v = raw.clamp(1, widget.maxValue);
    _focus.unfocus();
    setState(() => _editing = false);
    if (v != widget.value) {
      widget.onSave(v);
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            style: HeroTokens.bodySmall.copyWith(color: h.foreground),
          ),
        ),
        const SizedBox(width: 12),
        AnimatedSwitcher(
          duration: heroAnimationsEnabled
              ? const Duration(milliseconds: 300)
              : Duration.zero,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: _editing
              ? Row(
                  key: const ValueKey('editing'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Editor: input + unit + check — the "split open" pill
                    // (left field carries the left radii, check the right).
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: h.surface2,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                        border: Border.all(color: h.accent, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: TextField(
                              controller: _c,
                              focusNode: _focus,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onSubmitted: (_) => _save(),
                              style: HeroTokens.bodySmall.copyWith(
                                color: h.foreground,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                isCollapsed: true,
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 12),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              widget.unit,
                              style: HeroTokens.caption
                                  .copyWith(color: h.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _save,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: h.accent,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 17,
                            color: h.accentFg),
                      ),
                    ),
                    HeroIconButton(
                      icon: Icons.close_rounded,
                      size: 30,
                      iconSize: 16,
                      onPressed: () {
                        _focus.unfocus();
                        setState(() => _editing = false);
                      },
                    ),
                  ],
                )
              : GestureDetector(
                  key: const ValueKey('display'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openEditor,
                  child: Container(
                    height: 38,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: h.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: h.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.value}',
                          style: HeroTokens.bodySmall.copyWith(
                            color: h.foreground,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.unit,
                          style:
                              HeroTokens.caption.copyWith(color: h.muted),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_rounded, size: 14, color: h.muted),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
