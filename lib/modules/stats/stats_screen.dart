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
    final summary = ref.watch(statsSummaryProvider);
    final goals = ref.watch(statsGoalsProvider);
    final streak = ref.watch(streakProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Statistics',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Streak card with freeze-token affordances.
// ---------------------------------------------------------------------------
class _StreakCard extends ConsumerWidget {
  const _StreakCard({required this.streak});
  final StreakState streak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department,
                      color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text('Reading streak',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StreakMetric(
                      value: '${streak.currentStreak}',
                      label: 'Current',
                      color: Colors.orange.shade700,
                    ),
                  ),
                  Container(
                      width: 1, height: 40, color: theme.dividerColor),
                  Expanded(
                    child: _StreakMetric(
                      value: '${streak.longestStreak}',
                      label: 'Longest',
                      color: LuminaTheme.finishedColor,
                    ),
                  ),
                  Container(
                      width: 1, height: 40, color: theme.dividerColor),
                  Expanded(
                    child: _StreakMetric(
                      value: '${streak.freezeTokens}',
                      label: 'Freeze tokens',
                      color: LuminaTheme.unreadColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: streak.freezeTokens > 0
                          ? () => showSnack(
                              ref, context, 'Used a streak freeze token')
                          : null,
                      icon: const Icon(Icons.ac_unit, size: 18),
                      label: const Text('Use freeze'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showSnack(
                          ref, context, 'Goal: read every day this week'),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Set goal'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    return Column(
      children: [
        Text(value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
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
    final cards = <_StatCardData>[
      _StatCardData(
        icon: Icons.menu_book_rounded,
        label: 'Books Read',
        value: summary['mangaRead'] ?? 0,
        color: LuminaTheme.readingColor,
      ),
      _StatCardData(
        icon: Icons.local_fire_department,
        label: 'Reading Streak',
        value: streak.currentStreak,
        suffix: ' days',
        color: Colors.orange.shade700,
      ),
      _StatCardData(
        icon: Icons.timer_outlined,
        label: 'Total Time',
        value: summary['minutesRead'] ?? 0,
        suffix: ' min',
        color: LuminaTheme.unreadColor,
      ),
      _StatCardData(
        icon: Icons.description_outlined,
        label: 'Pages Read',
        value: summary['pagesRead'] ?? 0,
        color: LuminaTheme.seed,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
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
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: data.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(data.icon, color: data.color, size: 20),
                ),
                const Spacer(),
              ],
            ),
            const Spacer(),
            Text(
              '${_format(data.value)}${data.suffix}',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              data.label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
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
    // Always 20 columns × 7 rows = 140 days of history.
    final days = ref.watch(statsHeatmapProvider).take(20 * 7).toList();
    final theme = Theme.of(context);
    final total = days.fold<int>(0, (a, b) => a + b.count);
    final active = days.where((d) => d.count > 0).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_view_month_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Activity (last 20 weeks)',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$total contributions • $active active days',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  ...LuminaTheme.heatLevels.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _HeatCell(color: c, size: 12),
                      )),
                  const SizedBox(width: 6),
                  Text('More',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
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
      size: Size(20 * (_HeatmapPainter.cell + _HeatmapPainter.gap),
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
    final theme = Theme.of(context);
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      primary.label,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$pct%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: primary.progress,
                  minHeight: 12,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    primary.progress >= 1
                        ? LuminaTheme.finishedColor
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${primary.current}/${primary.target} ${primary.unit} • ${primary.period.label}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text('All goals',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...goals.map((g) => _GoalTile(goal: g)),
            ],
          ),
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
    final theme = Theme.of(context);
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
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(
                '${goal.current}/${goal.target} ${goal.unit}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (done
                          ? LuminaTheme.finishedColor
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: done
                        ? LuminaTheme.finishedColor
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('${goal.period.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal.progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                done ? LuminaTheme.finishedColor : theme.colorScheme.primary,
              ),
            ),
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
    final theme = Theme.of(context);
    final rows = <_SummaryRow>[
      _SummaryRow(
        icon: Icons.menu_book_rounded,
        label: 'Chapters read',
        value: summary['chaptersRead'] ?? 0,
        color: LuminaTheme.readingColor,
      ),
      _SummaryRow(
        icon: Icons.live_tv_rounded,
        label: 'Episodes watched',
        value: summary['episodesWatched'] ?? 0,
        color: LuminaTheme.finishedColor,
      ),
      _SummaryRow(
        icon: Icons.local_fire_department,
        label: 'Longest streak',
        value: streak.longestStreak,
        suffix: ' days',
        color: Colors.orange.shade700,
      ),
      _SummaryRow(
        icon: Icons.calendar_today_outlined,
        label: 'Last active',
        value: streak.lastActiveDay != null ? 1 : 0,
        suffix: streak.lastActiveDay != null
            ? ' • ${_dayLabel(streak.lastActiveDay!)}'
            : '',
        color: LuminaTheme.unreadColor,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Reading history',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: r.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(r.icon, size: 18, color: r.color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(r.label,
                              style: theme.textTheme.bodyMedium),
                        ),
                        Text(
                          '${r.value}${r.suffix}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
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
