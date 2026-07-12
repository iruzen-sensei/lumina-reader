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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../shared/widgets.dart';

/// The anime airing schedule.
///
/// Uses [TableCalendar] to pick a day, then renders the list of episodes
/// airing that day (data sourced from the MAL / AniList airing feed via
/// [airingScheduleProvider]) with their episode number, airing time and a
/// live countdown to the airing time.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  @override
  Widget build(BuildContext context) {
    final selectedDay = ref.watch(calendarSelectedDayProvider);
    final focused = ref.watch(calendarFocusedDayProvider);
    final episodes = ref.watch(airingScheduleProvider(selectedDay));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Text(
                    'Airing schedule',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 8),
                  const _TrackerBadge(),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh feed',
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      ref.invalidate(airingScheduleProvider(selectedDay));
                      showSnack(ref, context, 'Airing feed refreshed');
                    },
                  ),
                  IconButton(
                    tooltip: 'Today',
                    icon: const Icon(Icons.today),
                    onPressed: () {
                      final now = DateTime.now();
                      ref.read(calendarFocusedDayProvider.notifier).state =
                          now;
                      ref.read(calendarSelectedDayProvider.notifier).state =
                          now;
                    },
                  ),
                ],
              ),
            ),
            _Calendar(
              focusedDay: focused,
              selectedDay: selectedDay,
              onDaySelected: (selected, focused) {
                ref.read(calendarSelectedDayProvider.notifier).state =
                    selected;
                ref.read(calendarFocusedDayProvider.notifier).state = focused;
              },
              onPageChanged: (focused) {
                ref.read(calendarFocusedDayProvider.notifier).state = focused;
              },
            ),
            const Divider(height: 1),
            _DayHeader(day: selectedDay),
            Expanded(
              child: episodes.isEmpty
                  ? emptyState(
                      context: context,
                      icon: Icons.event_busy,
                      title: 'No episodes airing',
                      subtitle:
                          'No scheduled releases for this day. Try another date.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: episodes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _AiringCard(episode: episodes[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill that tells the user which tracker feeds the schedule.
class _TrackerBadge extends StatelessWidget {
  const _TrackerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: LuminaTheme.finishedColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 12, color: LuminaTheme.finishedColor),
          const SizedBox(width: 4),
          Text(
            'AniList + MAL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: LuminaTheme.finishedColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Calendar extends ConsumerWidget {
  const _Calendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final firstDay = DateTime(now.year - 1, now.month, now.day);
    final lastDay = DateTime(now.year + 2, now.month, now.day);

    return TableCalendar<AiringEpisode>(
      firstDay: firstDay,
      lastDay: lastDay,
      focusedDay: focusedDay,
      selectedDayPredicate: (day) => isSameDay(day, selectedDay),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      calendarFormat: CalendarFormat.month,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Month',
      },
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      calendarStyle: CalendarStyle(
        selectedDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
        todayDecoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
        markerDecoration: const BoxDecoration(
          color: LuminaTheme.newColor,
          shape: BoxShape.circle,
        ),
        markerSize: 6,
        markersMaxCount: 3,
      ),
      eventLoader: (day) => ref.read(airingScheduleProvider(day)),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        weekendStyle: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Text(
            _fullDate(day),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 8),
          if (isSameDay(day, DateTime.now()))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: LuminaTheme.newColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'TODAY',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  String _fullDate(DateTime d) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

class _AiringCard extends StatefulWidget {
  const _AiringCard({required this.episode});
  final AiringEpisode episode;

  @override
  State<_AiringCard> createState() => _AiringCardState();
}

class _AiringCardState extends State<_AiringCard> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final remaining = e.airingAt.difference(DateTime.now());
    final hasAired = remaining.isNegative;
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/animeDetail/${e.animeId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 80,
                  child: e.thumbnailUrl != null
                      ? Image.network(
                          e.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.movie),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'EP ${e.episodeNumber}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.schedule,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          _airTime(e.airingAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          hasAired
                              ? Icons.check_circle
                              : Icons.hourglass_bottom,
                          size: 14,
                          color: hasAired
                              ? LuminaTheme.finishedColor
                              : LuminaTheme.unreadColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasAired
                              ? 'Aired'
                              : 'In ${formatDuration(remaining)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hasAired
                                ? LuminaTheme.finishedColor
                                : LuminaTheme.unreadColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => showMessage(
                    context,
                    hasAired
                        ? 'Watch episode ${e.episodeNumber}'
                        : 'Set reminder'),
                icon: Icon(
                    hasAired
                        ? Icons.play_arrow
                        : Icons.notifications_active_outlined,
                    size: 18),
                label: Text(hasAired ? 'Watch' : 'Remind'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _airTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
