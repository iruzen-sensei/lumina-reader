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
import '../../core/ui/lumina_ui.dart';
import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The statistics screen.
///
/// Combines:
///  - A 2×2 grid of headline stat cards: Books Read, Reading Streak,
///    Total Time, Pages Read.
///  - A GitHub-style activity heat-map (custom [CustomPainter], 20 columns,
///    purple intensity ramp).
///  - The reading goal progress bar.
///  - A streak info panel with freeze tokens.
///  - A reading history summary panel.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final summary = ref.watch(statsSummaryProvider);
    final goals = ref.watch(statsGoalsProvider);
    final streak = ref.watch(streakProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
                child: Text(
                  'Statistics',
                  style: HeroTokens.display.copyWith(color: h.foreground),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _StreakCard(streak: streak),
            ),
            SliverToBoxAdapter(
              child: _StatCardGrid(summary: summary, streak: streak),
            ),
            SliverToBoxAdapter(
              child: _HeatmapSection(),
            ),
            SliverToBoxAdapter(
              child: _GoalProgressCard(goals: goals),
            ),
            SliverToBoxAdapter(
              child: _HistorySummaryCard(summary: summary, streak: streak),
            ),
            // Bottom nav bar clearance.
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Streak card — real metrics + the goal editor.
// ---------------------------------------------------------------------------
class _StreakCard extends ConsumerWidget {
  const _StreakCard({required this.streak});
  final StreakState streak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final heatmap = ref.watch(statsHeatmapProvider);
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final activeDays =
        heatmap.where((d) => d.date.isAfter(cutoff) && d.count > 0).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: h.successSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.local_fire_department_rounded,
                      size: 20, color: h.success),
                ),
                const SizedBox(width: 12),
                Text('Reading streak',
                    style: HeroTokens.title.copyWith(color: h.foreground)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StreakMetric(
                    value: '${streak.currentStreak}',
                    label: 'Current',
                    color: h.warning,
                  ),
                ),
                Container(width: 1, height: 40, color: h.separator),
                Expanded(
                  child: _StreakMetric(
                    value: '${streak.longestStreak}',
                    label: 'Longest',
                    color: h.success,
                  ),
                ),
                Container(width: 1, height: 40, color: h.separator),
                Expanded(
                  child: _StreakMetric(
                    // Real metric from the heatmap (the previous third
                    // slot showed "Freeze tokens: 0" — hardcoded, with a
                    // permanently disabled button).
                    value: '$activeDays',
                    label: 'Active days',
                    color: h.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            HeroButton(
              // REAL goal editor (previously a snackbar-only stub).
              label: 'Set goal',
              icon: Icons.flag_outlined,
              size: HeroButtonSize.sm,
              variant: HeroButtonVariant.soft,
              fullWidth: true,
              onPressed: () => _showGoalEditor(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  /// REAL goal editor: pick one of the tracked goals and set a new target;
  /// persists through StatsRepository.setGoalTarget (previously a
  /// snackbar-only stub — the seeded goals were read-only forever).
  void _showGoalEditor(BuildContext context, WidgetRef ref) {
    final goals = ref.read(statsGoalsProvider);
    if (goals.isEmpty) {
      showSnack(ref, context, 'No goals tracked yet');
      return;
    }
    showHeroSheet<void>(
      context: context,
      title: 'Edit goals',
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                for (final g in goals) _GoalEditorTile(goal: g),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GoalEditorTile extends ConsumerStatefulWidget {
  const _GoalEditorTile({required this.goal});
  final Goal goal;

  @override
  ConsumerState<_GoalEditorTile> createState() => _GoalEditorTileState();
}

class _GoalEditorTileState extends ConsumerState<_GoalEditorTile> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.goal.target}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.goal.label,
                  style: HeroTokens.body.copyWith(
                    color: h.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${widget.goal.current} / ${widget.goal.target} ${widget.goal.unit}',
                  style: HeroTokens.caption.copyWith(color: h.muted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: HeroInput(
              controller: _controller,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          HeroButton(
            label: 'Save',
            size: HeroButtonSize.sm,
            variant: HeroButtonVariant.light,
            onPressed: () async {
              final value = int.tryParse(_controller.text.trim());
              if (value == null || value <= 0) {
                showSnack(ref, context, 'Enter a positive number');
                return;
              }
              await ref
                  .read(data.statsRepositoryProvider)
                  .setGoalTarget(widget.goal.id, value);
              if (context.mounted) {
                showSnack(ref, context, 'Goal updated to $value');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _StreakMetric extends StatelessWidget {
  const _StreakMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return Column(
      children: [
        Text(value, style: HeroTokens.titleLarge.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(label, style: HeroTokens.caption.copyWith(color: h.muted)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2x2 headline stat grid: Books Read, Reading Streak, Total Time, Pages Read
// ---------------------------------------------------------------------------
class _StatCardGrid extends StatelessWidget {
  const _StatCardGrid({required this.summary, required this.streak});
  final Map<String, int> summary;
  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final cards = <_StatCardData>[
      _StatCardData(
        icon: Icons.menu_book_rounded,
        label: 'Books Read',
        value: summary['mangaRead'] ?? 0,
        color: h.accent,
      ),
      _StatCardData(
        icon: Icons.local_fire_department_rounded,
        label: 'Reading Streak',
        value: streak.currentStreak,
        suffix: ' days',
        color: h.warning,
      ),
      _StatCardData(
        icon: Icons.timer_outlined,
        label: 'Total Time',
        value: summary['minutesRead'] ?? 0,
        suffix: ' min',
        color: h.success,
      ),
      _StatCardData(
        icon: Icons.description_outlined,
        label: 'Pages Read',
        value: summary['pagesRead'] ?? 0,
        color: h.danger,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Taller cells for the mono 28 stat values + Inter captions.
        childAspectRatio: 1.1,
        children: cards.map((c) => _StatCard(data: c)).toList(),
      ),
    );
  }
}

class _StatCardData {
  const _StatCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.suffix = '',
  });
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final String suffix;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    return HeroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: h.isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 18),
          ),
          const Spacer(),
          // FittedBox: the mono value can never wrap or overflow the grid
          // cell — it scales down a touch instead.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${_format(data.value)}${data.suffix}',
              maxLines: 1,
              // JetBrains Mono — the x.ai metric-counter dialect.
              style: HeroTokens.eyebrow.copyWith(
                color: h.foreground,
                fontSize: 26,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HeroTokens.caption.copyWith(color: h.muted),
          ),
        ],
      ),
    );
  }

  String _format(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}

// ---------------------------------------------------------------------------
// Heatmap (GitHub-style, 20 columns, purple intensity)
// ---------------------------------------------------------------------------
class _HeatmapSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    // Always 20 columns × 7 rows = 140 days of history.
    final days = ref.watch(statsHeatmapProvider).take(20 * 7).toList();
    final total = days.fold<int>(0, (a, b) => a + b.count);
    final active = days.where((d) => d.count > 0).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: h.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.calendar_view_month_rounded,
                      size: 18, color: h.accent),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text('Activity (last 20 weeks)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.title.copyWith(color: h.foreground)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$total contributions • $active active days',
              style: HeroTokens.caption.copyWith(color: h.muted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 130,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: HeatmapCalendar(days: days),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Less',
                    style: HeroTokens.caption.copyWith(color: h.muted)),
                const SizedBox(width: 8),
                ...LuminaTheme.heatLevels.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _HeatCell(color: c, size: 12),
                    )),
                const SizedBox(width: 8),
                Text('More',
                    style: HeroTokens.caption.copyWith(color: h.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// GitHub-style activity heat-map rendered via [CustomPainter].
///
/// Layout: 20 columns × 7 rows. Each column is a week, each row is a day of
/// the week. Intensity uses the 5-step [LuminaTheme.heatLevels] purple ramp.
class HeatmapCalendar extends StatelessWidget {
  const HeatmapCalendar({super.key, required this.days});

  /// Must be ordered oldest → newest. The widget renders 20 columns (140
  /// days), padding missing days with the level-0 colour.
  final List<StatDay> days;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeatmapPainter(days: days),
      size: const Size(20 * (_HeatmapPainter.cell + _HeatmapPainter.gap),
          7 * (_HeatmapPainter.cell + _HeatmapPainter.gap)),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.days});
  final List<StatDay> days;

  static const double cell = 13;
  static const double gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    // Each column represents a week; rows are days of the week.
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final col = i ~/ 7;
      final row = i % 7;
      final x = col * (cell + gap);
      final y = row * (cell + gap);
      final rect = Rect.fromLTWH(x, y, cell, cell);
      final paint = Paint()..color = LuminaTheme.heatLevels[day.level];
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) =>
      days != oldDelegate.days;
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goal progress bar (the user's "main" reading goal surfaced at the top of
// the goals card).
// ---------------------------------------------------------------------------
class _GoalProgressCard extends ConsumerWidget {
  const _GoalProgressCard({required this.goals});
  final List<Goal> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    // The first weekly goal acts as the headline progress bar.
    final primary = goals.isNotEmpty
        ? goals.first
        : Goal(
            id: 0,
            label: 'Weekly goal',
            target: 1,
            current: 0,
            unit: '',
            period: GoalPeriod.weekly);
    final pct = (primary.progress * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: h.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.flag_rounded, size: 18, color: h.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    primary.label,
                    style: HeroTokens.title.copyWith(color: h.foreground),
                  ),
                ),
                HeroChip(
                  label: '$pct%',
                  small: true,
                  color: primary.progress >= 1
                      ? HeroColorRole.success
                      : HeroColorRole.accent,
                ),
              ],
            ),
            const SizedBox(height: 16),
            HeroProgress(
              value: primary.progress,
              height: 10,
              color: primary.progress >= 1 ? h.success : h.accent,
            ),
            const SizedBox(height: 8),
            Text(
              '${primary.current}/${primary.target} ${primary.unit} • ${primary.period.label}',
              style: HeroTokens.caption.copyWith(color: h.muted),
            ),
            const SizedBox(height: 16),
            Text('All goals',
                style: HeroTokens.body.copyWith(
                  color: h.foreground,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 4),
            ...goals.map((g) => _GoalTile(goal: g)),
          ],
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final pct = (goal.progress * 100).round();
    final done = goal.progress >= 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(goal.label,
                    style: HeroTokens.body.copyWith(
                      color: h.foreground,
                      fontWeight: FontWeight.w600,
                    )),
              ),
              Text(
                '${goal.current}/${goal.target} ${goal.unit}',
                style: HeroTokens.caption.copyWith(color: h.muted),
              ),
              const SizedBox(width: 8),
              HeroChip(
                label: '$pct%',
                small: true,
                color: done ? HeroColorRole.success : HeroColorRole.accent,
              ),
              const SizedBox(width: 8),
              Text(goal.period.label,
                  style: HeroTokens.caption.copyWith(color: h.muted)),
            ],
          ),
          const SizedBox(height: 8),
          HeroProgress(
            value: goal.progress,
            height: 6,
            color: done ? h.success : h.accent,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reading history summary — a short timeline of the user's recent activity
// pulled from the stats summary map.
// ---------------------------------------------------------------------------
class _HistorySummaryCard extends StatelessWidget {
  const _HistorySummaryCard({required this.summary, required this.streak});
  final Map<String, int> summary;
  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final rows = <_SummaryRow>[
      _SummaryRow(
        icon: Icons.menu_book_rounded,
        label: 'Chapters read',
        value: summary['chaptersRead'] ?? 0,
        color: h.accent,
      ),
      _SummaryRow(
        icon: Icons.live_tv_rounded,
        label: 'Episodes watched',
        value: summary['episodesWatched'] ?? 0,
        color: h.success,
      ),
      _SummaryRow(
        icon: Icons.local_fire_department_rounded,
        label: 'Longest streak',
        value: streak.longestStreak,
        suffix: ' days',
        color: h.warning,
      ),
      _SummaryRow(
        icon: Icons.calendar_today_outlined,
        label: 'Last active',
        value: streak.lastActiveDay != null ? 1 : 0,
        suffix: streak.lastActiveDay != null
            ? ' • ${_dayLabel(streak.lastActiveDay!)}'
            : '',
        color: h.accent,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: HeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: h.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.history_rounded, size: 18, color: h.accent),
                ),
                const SizedBox(width: 12),
                Text('Reading history',
                    style: HeroTokens.title.copyWith(color: h.foreground)),
              ],
            ),
            const SizedBox(height: 12),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color:
                              r.color.withValues(alpha: h.isDark ? 0.20 : 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(r.icon, size: 16, color: r.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(r.label,
                            style:
                                HeroTokens.body.copyWith(color: h.foreground)),
                      ),
                      Text(
                        '${r.value}${r.suffix}',
                        style: HeroTokens.body.copyWith(
                          color: h.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff < 7) return '$diff days ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _SummaryRow {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.suffix = '',
  });
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final String suffix;
}
