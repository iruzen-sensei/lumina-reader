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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/ui/heroui_v3.dart';
import '../../models/models.dart';

/// A book / anime cover card in the HeroUI + Aniyomi/Mangayomi style:
/// rounded cover on top (unread badge + thin progress bar on the image),
/// title + metadata lines below it. Pass [showTitle] = false when the
/// parent already renders the title (list rows).
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.manga,
    this.width = 110,
    this.height = 160,
    this.radius = 14,
    this.showProgress = true,
    this.showTitle = true,
    this.selected = false,
    this.onLongPress,
    this.onTap,
  });

  final Manga manga;
  final double width;
  final double height;
  final double radius;
  final bool showProgress;
  final bool showTitle;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  static const double _titleBlock = 46;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    // Grid cells pass height = double.infinity — the cover then fills the
    // remaining space after the title block (Expanded) instead of computing
    // `infinity - 46` which crashed layout.
    final hasFixedHeight = height.isFinite;
    final coverHeight =
        hasFixedHeight ? (showTitle ? height - _titleBlock : height) : null;

    final cover = _HeroPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      // StackFit.expand forces the cover Container (and the image chain
      // inside it) to fill the parent — without it the loose constraints
      // collapse the unloaded image to 0x0 and covers never appear.
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            width: width,
            height: coverHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: selected ? Border.all(color: h.accent, width: 2.5) : null,
              boxShadow: h.isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (manga.thumbnailUrl != null)
                    Image.network(
                      manga.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const _CoverPlaceholder();
                      },
                    )
                  else
                    const _CoverPlaceholder(),
                  // Unread count badge (HeroUI soft-accent pill).
                  if (manga.unreadCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: h.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${manga.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  // Anime badge.
                  if (manga.isAnime)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text(
                          'EP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (showProgress && manga.progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(radius),
                          bottomRight: Radius.circular(radius),
                        ),
                        child: LinearProgressIndicator(
                          value: manga.progress,
                          minHeight: 3.5,
                          backgroundColor: Colors.black.withValues(alpha: 0.35),
                          valueColor: AlwaysStoppedAnimation(
                            manga.progress >= 1
                                ? LuminaTheme.finishedColor
                                : h.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (selected)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: h.accent,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(3.5),
                child: const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );

    if (!showTitle) {
      return SizedBox(
        width: width,
        height: hasFixedHeight ? height : null,
        child: cover,
      );
    }

    return SizedBox(
      width: width,
      height: hasFixedHeight ? height : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cover),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: h.foreground,
                fontSize: 12,
                height: 1.22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              manga.totalChapters > 0
                  ? (manga.isAnime
                      ? '${manga.totalChapters} eps'
                      : '${manga.totalChapters} ch')
                  : (manga.isAnime ? 'Anime' : 'Manga'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: h.muted,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a child with HeroUI press feedback (scale 0.97, 250ms smooth).
class _HeroPressable extends StatefulWidget {
  const _HeroPressable({required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_HeroPressable> createState() => _HeroPressableState();
}

class _HeroPressableState extends State<_HeroPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp:
          widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration:
            heroAnimationsEnabled ? HeroTokens.motionTransform : Duration.zero,
        curve: HeroTokens.easeSmooth,
        child: widget.child,
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

/// Pill shaped chip used throughout the library / detail screens.
/// Selected: accent-soft bg + accent fg (HeroUI soft chip). Unselected:
/// default bg + muted fg.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.color,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final base = color ?? h.accent;

    final bg = selected
        ? (h.isDark
            ? base.withValues(alpha: 0.20)
            : base.withValues(alpha: 0.12))
        : h.dflt;
    final fg = selected ? (h.isDark ? _lighten(base) : _darken(base)) : h.muted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration:
            heroAnimationsEnabled ? HeroTokens.motionColor : Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(HeroTokens.radiusChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _lighten(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + 0.14).clamp(0.0, 1.0)).toColor();
  }

  static Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.06).clamp(0.0, 1.0)).toColor();
  }
}

/// Formats a [DateTime] into a relative "time ago" string.
String timeAgo(DateTime date, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(date);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

/// Formats a byte count into a human readable string.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
}

/// Formats a bytes-per-second speed.
String formatSpeed(double bytesPerSec) =>
    '${formatBytes(bytesPerSec.round())}/s';

/// Formats a duration into `H:MM:SS` / `M:SS` style strings.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// A helper to build a consistent empty-state widget (HeroUI).
Widget emptyState({
  required BuildContext context,
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? action,
}) {
  return HeroEmptyState(
    icon: icon,
    title: title,
    subtitle: subtitle,
    action: action,
  );
}

/// Small circular loader used inline.
Widget inlineLoader(BuildContext context, {double size = 24}) {
  return SizedBox(
    width: size,
    height: size,
    child: CircularProgressIndicator(
      strokeWidth: 2.4,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

/// A Riverpod-scoped snack bar helper.
void showSnack(WidgetRef ref, BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Context-only snack bar helper for widgets that do not hold a [WidgetRef]
/// (e.g. plain [StatelessWidget] tiles).
void showMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}
