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
import 'package:go_router/go_router.dart';

import '../../core/ui/heroui_v3.dart';
import '../../core/ui/rybin_footer.dart';
import '../../providers/providers.dart';

/// The "More" screen — a hub of secondary destinations and settings entry
/// points. Each tile navigates via [GoRouter] to its module route.
///
/// Layout follows the HeroUI v3 grouped-list pattern: a profile summary
/// card, then transparent grouped cards under [HeroSectionHeader] labels —
/// **Activity** (navigation destinations with distinct semantic icons and
/// rotating soft tints), **Preferences** (the two global quick toggles —
/// incognito mode and downloaded-only mode) and **Data & about**.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final incognito = ref.watch(incognitoModeProvider);
    final downloadedOnly = ref.watch(downloadedOnlyProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          // Bottom padding keeps the last card clear of the nav bar.
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'More',
                style: HeroTokens.display.copyWith(color: h.foreground),
              ),
            ),
            const _ProfileCard(),
            const HeroSectionHeader('Activity'),
            _GroupCard(
              children: [
                HeroListTile(
                  leadingIcon: Icons.history_rounded,
                  leadingColor: h.accent,
                  title: 'History',
                  subtitle: 'Continue reading or watching',
                  showChevron: true,
                  onTap: () => context.push('/history'),
                ),
                HeroListTile(
                  leadingIcon: Icons.insights_outlined,
                  leadingColor: h.success,
                  title: 'Statistics',
                  subtitle: 'Track your reading habits',
                  showChevron: true,
                  onTap: () => context.push('/stats'),
                ),
                HeroListTile(
                  leadingIcon: Icons.new_releases_outlined,
                  leadingColor: h.warning,
                  title: 'Updates',
                  subtitle: 'New chapters & episodes',
                  showChevron: true,
                  onTap: () => context.push('/updates'),
                ),
                HeroListTile(
                  leadingIcon: Icons.calendar_month_outlined,
                  leadingColor: h.danger,
                  title: 'Calendar',
                  subtitle: 'Airing schedule',
                  showChevron: true,
                  onTap: () => context.push('/calendar'),
                ),
              ],
            ),
            const HeroSectionHeader('Preferences'),
            _GroupCard(
              children: [
                HeroListTile(
                  leadingIcon: Icons.visibility_off_outlined,
                  leadingColor: h.accent,
                  title: 'Incognito mode',
                  subtitle: incognito
                      ? "Reading & watching won't be recorded."
                      : 'Activity is recorded to history and trackers.',
                  trailing: HeroSwitch(
                    value: incognito,
                    onChanged: (_) => ref
                        .read(incognitoModeProvider.notifier)
                        .state = !incognito,
                  ),
                  onTap: () => ref.read(incognitoModeProvider.notifier).state =
                      !incognito,
                ),
                HeroListTile(
                  leadingIcon: Icons.cloud_off_outlined,
                  leadingColor: h.success,
                  title: 'Downloaded only',
                  subtitle: downloadedOnly
                      ? 'Only downloaded content is shown.'
                      : 'Stream and browse online as usual.',
                  trailing: HeroSwitch(
                    value: downloadedOnly,
                    onChanged: (_) => ref
                        .read(downloadedOnlyProvider.notifier)
                        .state = !downloadedOnly,
                  ),
                  onTap: () => ref.read(downloadedOnlyProvider.notifier).state =
                      !downloadedOnly,
                ),
              ],
            ),
            const HeroSectionHeader('Data & about'),
            _GroupCard(
              children: [
                HeroListTile(
                  leadingIcon: Icons.download_outlined,
                  leadingColor: h.accent,
                  title: 'Downloads',
                  subtitle: 'Queue & offline content',
                  showChevron: true,
                  onTap: () => context.push('/downloads'),
                ),
                HeroListTile(
                  leadingIcon: Icons.sticky_note_2_outlined,
                  leadingColor: h.warning,
                  title: 'Notes',
                  subtitle: 'Highlights & thoughts',
                  showChevron: true,
                  onTap: () => context.push('/notes'),
                ),
                HeroListTile(
                  leadingIcon: Icons.settings_outlined,
                  leadingColor: h.accent,
                  title: 'Settings',
                  subtitle: 'Appearance, reader, player, security…',
                  showChevron: true,
                  onTap: () => context.push('/settings'),
                ),
                HeroListTile(
                  leadingIcon: Icons.info_outline,
                  leadingColor: h.muted,
                  title: 'About Lumina Reader',
                  subtitle: 'Version 1.0.0 • Apache 2.0',
                  showChevron: true,
                  onTap: () => _showAbout(context),
                ),
                HeroListTile(
                  leadingIcon: Icons.source_outlined,
                  leadingColor: h.muted,
                  title: 'Open source licenses',
                  subtitle: 'View third-party libraries',
                  showChevron: true,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Lumina Reader',
                    applicationVersion: '1.0.0',
                    applicationLegalese: '© 2024 Lumina Reader Contributors',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Lumina Reader • Made with ♥',
                style: HeroTokens.caption.copyWith(color: h.muted),
              ),
            ),
            const SizedBox(height: 24),
            // Signature black footer w/ live clock (andreirybin.com).
            const RybinFooter(),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showHeroDialog<void>(
      context: context,
      builder: (dialogContext) {
        final h = HeroScope.of(dialogContext);
        return HeroDialogFrame(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: h.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.auto_stories, size: 24, color: h.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lumina Reader',
                      style: HeroTokens.title.copyWith(color: h.foreground),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Version 1.0.0',
                style: HeroTokens.bodySmall.copyWith(color: h.foreground),
              ),
              const SizedBox(height: 8),
              Text(
                'A fork of Mangayomi — read manga and watch anime from your '
                'favourite sources, all in one place.',
                style:
                    HeroTokens.bodySmall.copyWith(color: h.muted, height: 1.55),
              ),
              const SizedBox(height: 12),
              Text(
                'Licensed under the Apache License, Version 2.0.',
                style: HeroTokens.caption.copyWith(color: h.muted),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: HeroButton(
                  label: 'Close',
                  variant: HeroButtonVariant.light,
                  color: HeroColorRole.neutral,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Transparent grouped card (HeroUI pattern): zero padding, rows separated
/// by hairlines indented to the text column (16 padding + 36 icon + 14 gap).
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const HeroSeparator(indent: 66));
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: HeroCard(
        variant: HeroCardVariant.transparent,
        padding: EdgeInsets.zero,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

/// Reading summary card — REAL numbers computed from the stats repository
/// (previously hardcoded "1,842 chapters • 412 episodes" with a fake Edit
/// button).
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final summary = ref.watch(statsSummaryProvider);
    final libraryCount = ref.watch(mangaLibraryProvider).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: HeroCard(
        child: Row(
          children: [
            const HeroAvatar(initials: 'LR', size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reader',
                    style: HeroTokens.title.copyWith(color: h.foreground),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$libraryCount in library • '
                    '${summary['chaptersRead'] ?? 0} chapters read',
                    style: HeroTokens.caption.copyWith(color: h.muted),
                  ),
                ],
              ),
            ),
            HeroButton(
              label: 'Stats',
              size: HeroButtonSize.sm,
              variant: HeroButtonVariant.soft,
              onPressed: () => context.push('/stats'),
            ),
          ],
        ),
      ),
    );
  }
}
