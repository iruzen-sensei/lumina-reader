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
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/lumina_ui.dart';
import '../../data/providers.dart' as data;
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
    final h = HeroScope.of(context);
    final selectedDay = ref.watch(calendarSelectedDayProvider);
    final focused = ref.watch(calendarFocusedDayProvider);
    final episodes = ref.watch(airingScheduleProvider(selectedDay));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Airing schedule',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HeroTokens.display.copyWith(
                        color: h.foreground,
                        fontSize: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Which tracker feeds the schedule.
                  const HeroChip(
                    label: 'AniList',
                    icon: Icons.auto_awesome_rounded,
                    small: true,
                  ),
                  const Spacer(),
                  HeroIconButton(
                    tooltip: 'Refresh feed',
                    icon: Icons.refresh_rounded,
                    onPressed: () {
                      ref.invalidate(airingScheduleProvider(selectedDay));
                      showSnack(ref, context, 'Airing feed refreshed');
                    },
                  ),
                  HeroIconButton(
                    tooltip: 'Today',
                    icon: Icons.today_rounded,
                    onPressed: () {
                      final now = DateTime.now();
                      ref.read(calendarFocusedDayProvider.notifier).state = now;
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
                ref.read(calendarSelectedDayProvider.notifier).state = selected;
                ref.read(calendarFocusedDayProvider.notifier).state = focused;
              },
              onPageChanged: (focused) {
                ref.read(calendarFocusedDayProvider.notifier).state = focused;
              },
            ),
            const HeroSeparator(),
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
                      // Bottom nav bar clearance.
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
    final h = HeroScope.of(context);
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
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: HeroTokens.body.copyWith(
          color: h.foreground,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        leftChevronIcon: Icon(Icons.chevron_left_rounded, color: h.muted),
        rightChevronIcon: Icon(Icons.chevron_right_rounded, color: h.muted),
      ),
      calendarStyle: CalendarStyle(
        // Selected day: accent pill with white text.
        selectedDecoration: BoxDecoration(
          color: h.accent,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        // Today: accent ring (no fill).
        todayDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: h.accent, width: 1.6),
        ),
        todayTextStyle: TextStyle(
          color: h.accentSoftFg,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        // Every other day: muted.
        defaultTextStyle: TextStyle(color: h.muted, fontSize: 14),
        weekendTextStyle: TextStyle(color: h.muted, fontSize: 14),
        outsideTextStyle:
            TextStyle(color: h.muted.withValues(alpha: 0.5), fontSize: 14),
        markerDecoration: BoxDecoration(
          color: h.accent,
          shape: BoxShape.circle,
        ),
        markerSize: 6,
        markersMaxCount: 3,
      ),
      eventLoader: (day) => ref.read(airingScheduleProvider(day)),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          color: h.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        weekendStyle: TextStyle(
          color: h.muted,
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
    final h = HeroScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Flexible(
            child: Text(
              _fullDate(day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HeroTokens.title.copyWith(color: h.foreground),
            ),
          ),
          const SizedBox(width: 8),
          if (isSameDay(day, DateTime.now()))
            const HeroChip(
              label: 'TODAY',
              small: true,
              variant: HeroChipVariant.solid,
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

class _AiringCard extends ConsumerStatefulWidget {
  const _AiringCard({required this.episode});
  final AiringEpisode episode;

  @override
  ConsumerState<_AiringCard> createState() => _AiringCardState();
}

class _AiringCardState extends ConsumerState<_AiringCard> {
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

  /// Resolves the calendar entry against the library; when found pushes the
  /// real anime detail screen, otherwise opens AniList in the browser
  /// (previously the card pushed /animeDetail/<anilistId> which ALWAYS
  /// resolved to "Not found" — the library never stored that id).
  Future<void> _openAnime() async {
    final e = widget.episode;
    final repo = ref.read(data.libraryRepositoryProvider);
    final match = await repo.findByAniListId(e.animeId);
    if (!mounted) return;
    if (match != null) {
      unawaited(context.push('/animeDetail/${match.id}'));
      return;
    }
    final uri = Uri.tryParse('https://anilist.co/anime/${e.animeId}');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final e = widget.episode;
    final remaining = e.airingAt.difference(DateTime.now());
    final hasAired = remaining.isNegative;

    return HeroCard(
      padding: const EdgeInsets.all(12),
      // REAL navigation: resolve the AniList id against the LIBRARY
      // (previously this pushed /animeDetail/<anilistId>, which always
      // resolved to "Not found" because the library never stored that
      // id). Falls back to opening the AniList page in the browser.
      onTap: () => _openAnime(),
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
                        color: h.dflt,
                        child: Icon(Icons.movie_rounded, color: h.muted),
                      ),
                    )
                  : Container(
                      color: h.dflt,
                      child: Icon(Icons.movie_rounded, color: h.muted),
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
                  style: HeroTokens.body.copyWith(
                    color: h.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: h.accentSoft,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        'EP ${e.episodeNumber}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: h.accentSoftFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.schedule_rounded, size: 13, color: h.muted),
                    const SizedBox(width: 4),
                    Text(
                      _airTime(e.airingAt),
                      style: HeroTokens.caption.copyWith(
                        color: h.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      hasAired
                          ? Icons.check_circle_rounded
                          : Icons.hourglass_bottom_rounded,
                      size: 14,
                      color: hasAired ? h.success : h.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasAired ? 'Aired' : 'In ${formatDuration(remaining)}',
                      style: HeroTokens.caption.copyWith(
                        color: hasAired ? h.success : h.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          HeroButton(
            // REAL action: in-library → open detail; otherwise open the
            // AniList page in the browser (the previous "Watch" and
            // "Remind" handlers were snackbar-only stubs — no player
            // navigation and no notification scheduler existed).
            label: hasAired ? 'Watch' : 'AniList',
            icon:
                hasAired ? Icons.play_arrow_rounded : Icons.open_in_new_rounded,
            size: HeroButtonSize.sm,
            variant:
                hasAired ? HeroButtonVariant.solid : HeroButtonVariant.soft,
            onPressed: _openAnime,
          ),
        ],
      ),
    );
  }

  String _airTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
