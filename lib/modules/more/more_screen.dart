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

import '../../core/theme.dart';
import '../../providers/providers.dart';

/// The "More" screen — a hub of secondary destinations and settings entry
/// points. Each tile navigates via [GoRouter] to its module route.
///
/// Top of the page exposes the two most commonly flipped global toggles —
/// **Incognito mode** (don't record reading / watching activity) and
/// **Downloaded only** (only show content available offline).
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  Widget build(BuildContext context) {
    final incognito = ref.watch(incognitoModeProvider);
    final downloadedOnly = ref.watch(downloadedOnlyProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'More',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const _ProfileCard(),
            _QuickTogglesCard(
              incognito: incognito,
              downloadedOnly: downloadedOnly,
              onToggleIncognito: () => ref
                  .read(incognitoModeProvider.notifier)
                  .state = !incognito,
              onToggleDownloadedOnly: () => ref
                  .read(downloadedOnlyProvider.notifier)
                  .state = !downloadedOnly,
            ),
            const _SectionHeader('Activity'),
            _NavTile(
              icon: Icons.history,
              iconColor: LuminaTheme.readingColor,
              title: 'History',
              subtitle: 'Continue reading or watching',
              onTap: () => context.push('/history'),
            ),
            _NavTile(
              icon: Icons.new_releases_outlined,
              iconColor: LuminaTheme.newColor,
              title: 'Updates',
              subtitle: 'New chapters & episodes',
              onTap: () => context.push('/updates'),
            ),
            _NavTile(
              icon: Icons.insights_outlined,
              iconColor: LuminaTheme.seed,
              title: 'Statistics',
              subtitle: 'Track your reading habits',
              onTap: () => context.push('/stats'),
            ),
            _NavTile(
              icon: Icons.sticky_note_2_outlined,
              iconColor: Colors.amber.shade700,
              title: 'Notes',
              subtitle: 'Highlights & thoughts',
              onTap: () => context.push('/notes'),
            ),
            _NavTile(
              icon: Icons.calendar_month_outlined,
              iconColor: LuminaTheme.finishedColor,
              title: 'Calendar',
              subtitle: 'Airing schedule',
              onTap: () => context.push('/calendar'),
            ),
            _NavTile(
              icon: Icons.download_outlined,
              iconColor: LuminaTheme.unreadColor,
              title: 'Downloads',
              subtitle: 'Queue & offline content',
              onTap: () => context.push('/downloads'),
            ),
            const _SectionHeader('Settings'),
            _NavTile(
              icon: Icons.settings_outlined,
              iconColor: LuminaTheme.seed,
              title: 'Settings',
              subtitle: 'Appearance, reader, player, security…',
              onTap: () => context.push('/settings'),
            ),
            // NOTE: the five `_SettingsCategory` preview blocks that used to
            // live here were removed — every tile was a decoration that
            // showed a hardcoded value and a "tapped" snackbar. All real
            // controls live in the Settings screen.
            const _SectionHeader('About'),
            _NavTile(
              icon: Icons.info_outline,
              title: 'About Lumina Reader',
              subtitle: 'Version 1.0.0 • Apache 2.0',
              onTap: () => _showAbout(context),
            ),
            _NavTile(
              icon: Icons.source_outlined,
              title: 'Open source licenses',
              subtitle: 'View third-party libraries',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Lumina Reader',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2024 Lumina Reader Contributors',
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Lumina Reader • Made with ♥',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.auto_stories, size: 40),
          title: const Text('Lumina Reader'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version 1.0.0'),
              SizedBox(height: 8),
              Text(
                'A fork of Mangayomi — read manga and watch anime from your '
                'favourite sources, all in one place.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text('Licensed under the Apache License, Version 2.0.',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ],
        );
      },
    );
  }
}

/// Card holding the two global quick toggles — Incognito mode and
/// Downloaded-only mode. Surfaced above the activity list because they
/// affect every screen in the app.
class _QuickTogglesCard extends ConsumerWidget {
  const _QuickTogglesCard({
    required this.incognito,
    required this.downloadedOnly,
    required this.onToggleIncognito,
    required this.onToggleDownloadedOnly,
  });

  final bool incognito;
  final bool downloadedOnly;
  final VoidCallback onToggleIncognito;
  final VoidCallback onToggleDownloadedOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (incognito
                          ? LuminaTheme.unreadColor
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  incognito
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_outlined,
                  size: 20,
                  color: incognito
                      ? LuminaTheme.unreadColor
                      : theme.colorScheme.primary,
                ),
              ),
              title: const Text('Incognito mode',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                incognito
                    ? 'Reading & watching won\'t be recorded.'
                    : 'Activity is recorded to history and trackers.',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              value: incognito,
              onChanged: (_) => onToggleIncognito(),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (downloadedOnly
                          ? LuminaTheme.readingColor
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  downloadedOnly
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_outlined,
                  size: 20,
                  color: downloadedOnly
                      ? LuminaTheme.readingColor
                      : theme.colorScheme.primary,
                ),
              ),
              title: const Text('Downloaded only',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                downloadedOnly
                    ? 'Only downloaded content is shown.'
                    : 'Stream and browse online as usual.',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              value: downloadedOnly,
              onChanged: (_) => onToggleDownloadedOnly(),
            ),
          ],
        ),
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
    final summary = ref.watch(statsSummaryProvider);
    final libraryCount = ref.watch(mangaLibraryProvider).length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.auto_stories,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reader',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold)),
                  Text(
                    '$libraryCount in library • ${summary['chaptersRead'] ?? 0} chapters read',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => context.push('/stats'),
              child: const Text('Stats'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Theme.of(context).colorScheme.primary)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            color: iconColor ?? Theme.of(context).colorScheme.primary,
            size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
