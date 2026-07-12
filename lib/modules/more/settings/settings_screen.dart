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
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../providers/providers.dart';
import '../../shared/widgets.dart';

/// The settings screen.
///
/// Groups every user-configurable option into ten expandable sections:
/// Appearance, Reader, Player, Library, Browse, Downloads, Security, Sync,
/// Backup and About. State is held by the [appSettingsProvider] notifier so
/// changes propagate to every consumer in the app.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              automaticallyImplyLeading: false,
              title: Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate(
                [
                  const _AppearanceSection(),
                  const _ReaderSection(),
                  const _PlayerSection(),
                  const _LibrarySection(),
                  const _BrowseSection(),
                  const _DownloadsSection(),
                  const _SecuritySection(),
                  const _SyncSection(),
                  const _BackupSection(),
                  const _AboutSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section scaffolding
// ---------------------------------------------------------------------------

class _SettingsSection extends StatefulWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<_SettingsSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(widget.icon, color: widget.iconColor, size: 20),
            ),
            title: Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.chevron_right),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(children: widget.children),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 56, endIndent: 8);
}

// ---------------------------------------------------------------------------
// Appearance — theme, font, e-ink mode, custom colours.
// ---------------------------------------------------------------------------
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return _SettingsSection(
      title: 'Appearance',
      icon: Icons.palette_outlined,
      iconColor: LuminaTheme.seed,
      initiallyExpanded: true,
      children: [
        _SectionTile(
          icon: Icons.brightness_6_outlined,
          title: 'Theme',
          subtitle: s.themeMode.label,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showThemePicker(context, s.themeMode, notifier.setThemeMode),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.auto_awesome_outlined,
          title: 'Dynamic colour (Material You)',
          subtitle: s.useDynamicColor
              ? 'Pull palette from wallpaper'
              : 'Use brand palette',
          value: s.useDynamicColor,
          onChanged: (_) => notifier.toggleDynamicColor(),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.e_mobiledata_outlined,
          title: 'E-ink mode',
          subtitle: 'High-contrast, no gradients — friendly to e-readers',
          value: s.einkMode,
          onChanged: (_) => notifier.toggleEinkMode(),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.text_fields,
          title: 'Font size',
          subtitle: '${s.fontSize.round()} pt',
          trailing: SizedBox(
            width: 140,
            child: Slider(
              min: 10,
              max: 24,
              divisions: 14,
              value: s.fontSize,
              onChanged: notifier.setFontSize,
            ),
          ),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.format_color_fill_outlined,
          title: 'Brand colour',
          subtitle: '#${_hex(s.customSeed)}',
          trailing: CircleAvatar(
            radius: 14,
            backgroundColor: s.customSeed,
          ),
          onTap: () => _showColorPicker(context, s.customSeed, (c) {
            notifier.setCustomSeed(c);
            showSnack(ref, context, 'Brand colour updated');
          }),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.font_download_outlined,
          title: 'Font family',
          subtitle: 'Roboto (Google Fonts)',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showFontPicker(context),
        ),
      ],
    );
  }

  String _hex(Color c) =>
      '${c.red.toRadixString(16).padLeft(2, '0')}'
      '${c.green.toRadixString(16).padLeft(2, '0')}'
      '${c.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

  void _showThemePicker(BuildContext context, AppThemeMode current,
      ValueChanged<AppThemeMode> onPick) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Theme',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final m in AppThemeMode.values)
                RadioListTile<AppThemeMode>(
                  value: m,
                  groupValue: current,
                  title: Text(m.label),
                  onChanged: (v) {
                    if (v == null) return;
                    onPick(v);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showColorPicker(
      BuildContext context, Color current, ValueChanged<Color> onPick) {
    final palette = [
      LuminaTheme.seed,
      LuminaTheme.readingColor,
      LuminaTheme.finishedColor,
      LuminaTheme.unreadColor,
      LuminaTheme.newColor,
      const Color(0xFF00897B),
      const Color(0xFF6D4C41),
      const Color(0xFF455A64),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: palette
                  .map((c) => GestureDetector(
                        onTap: () {
                          onPick(c);
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: c == current
                                ? Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    width: 3)
                                : null,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  void _showFontPicker(BuildContext context) {
    final fonts = ['Roboto', 'Inter', 'Lato', 'Merriweather', 'Source Serif'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Font family',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final f in fonts)
                ListTile(
                  title: Text(f,
                      style: GoogleFonts.getFont(
                        f.toLowerCase().replaceAll(' ', ''),
                      )),
                  onTap: () => Navigator.pop(context),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reader — manga reader settings.
// ---------------------------------------------------------------------------
class _ReaderSection extends ConsumerWidget {
  const _ReaderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsSection(
      title: 'Reader',
      icon: Icons.menu_book_outlined,
      iconColor: LuminaTheme.readingColor,
      children: [
        _SectionTile(
          icon: Icons.auto_stories_outlined,
          title: 'Default reading mode',
          subtitle: _readerModeLabel(s.defaultReaderMode),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showPicker<ReaderMode>(
            context,
            title: 'Reading mode',
            values: ReaderMode.values,
            current: s.defaultReaderMode,
            labelOf: _readerModeLabel,
            onPick: notifier.setReaderMode,
          ),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.swap_horiz,
          title: 'Reading direction',
          subtitle: _readerDirectionLabel(s.defaultReaderDirection),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showPicker<ReaderDirection>(
            context,
            title: 'Reading direction',
            values: ReaderDirection.values,
            current: s.defaultReaderDirection,
            labelOf: _readerDirectionLabel,
            onPick: notifier.setReaderDirection,
          ),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.color_lens_outlined,
          title: 'Reader background',
          subtitle: s.readerBgColor.label,
          trailing: CircleAvatar(
              radius: 12, backgroundColor: s.readerBgColor.color),
          onTap: () => _showPicker<ReaderBgColor>(
            context,
            title: 'Reader background',
            values: ReaderBgColor.values,
            current: s.readerBgColor,
            labelOf: (c) => c.label,
            onPick: notifier.setReaderBg,
          ),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.touch_app_outlined,
          title: 'Tap to navigate',
          subtitle: 'Tap screen edges to flip pages',
          value: s.tapToNavigate,
          onChanged: (_) => notifier.toggleTapToNavigate(),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.numbers,
          title: 'Show page number',
          value: s.showPageNumber,
          onChanged: (_) => notifier.togglePageNumber(),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.brightness_6_outlined,
          title: 'Keep screen on',
          value: s.keepScreenOn,
          onChanged: (_) => notifier.toggleKeepScreenOn(),
        ),
      ],
    );
  }

  String _readerModeLabel(ReaderMode m) {
    switch (m) {
      case ReaderMode.paged:
        return 'Paged';
      case ReaderMode.continuous:
        return 'Continuous vertical';
      case ReaderMode.webtoon:
        return 'Webtoon';
    }
  }

  String _readerDirectionLabel(ReaderDirection d) {
    switch (d) {
      case ReaderDirection.leftToRight:
        return 'Left to right';
      case ReaderDirection.rightToLeft:
        return 'Right to left';
      case ReaderDirection.vertical:
        return 'Vertical';
    }
  }
}

// ---------------------------------------------------------------------------
// Player — anime player settings.
// ---------------------------------------------------------------------------
class _PlayerSection extends ConsumerWidget {
  const _PlayerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsSection(
      title: 'Player',
      icon: Icons.live_tv_outlined,
      iconColor: LuminaTheme.finishedColor,
      children: [
        _SectionTile(
          icon: Icons.hd_outlined,
          title: 'Default video quality',
          subtitle: s.defaultVideoQuality,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showStringPicker(
            context,
            title: 'Video quality',
            values: const ['1080p', '720p', '480p', '360p', 'Auto'],
            current: s.defaultVideoQuality,
            onPick: notifier.setVideoQuality,
          ),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.subtitles_outlined,
          title: 'Default subtitle',
          subtitle: s.defaultSubtitle,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showStringPicker(
            context,
            title: 'Subtitle track',
            values: const ['Off', 'English', 'Español', '日本語', 'Português'],
            current: s.defaultSubtitle,
            onPick: notifier.setSubtitle,
          ),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.fast_forward,
          title: 'AniSkip',
          subtitle: 'Auto-skip openings and endings',
          value: s.aniSkipEnabled,
          onChanged: (_) => notifier.toggleAniSkip(),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.picture_in_picture_outlined,
          title: 'Picture-in-picture',
          subtitle: 'Pop out the player when leaving the app',
          value: s.pipEnabled,
          onChanged: (_) => notifier.togglePip(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Library — auto-download, Wi-Fi-only, categories.
// ---------------------------------------------------------------------------
class _LibrarySection extends ConsumerWidget {
  const _LibrarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final categories = ref.watch(categoriesProvider);
    return _SettingsSection(
      title: 'Library',
      icon: Icons.library_books_outlined,
      iconColor: LuminaTheme.unreadColor,
      children: [
        _SwitchTile(
          icon: Icons.download_for_offline_outlined,
          title: 'Auto-download new chapters',
          subtitle: 'Fetch new releases for library entries automatically',
          value: s.autoDownloadNew,
          onChanged: (_) => notifier.toggleAutoDownloadNew(),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.wifi,
          title: 'Only download on Wi-Fi',
          value: s.downloadOnWifiOnly,
          onChanged: (_) => notifier.toggleDownloadOnWifiOnly(),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.sync_alt,
          title: 'Parallel downloads',
          subtitle: '${s.parallelDownloads} at a time',
          trailing: SizedBox(
            width: 140,
            child: Slider(
              min: 1,
              max: 6,
              divisions: 5,
              value: s.parallelDownloads.toDouble(),
              onChanged: (v) => notifier.setParallelDownloads(v.round()),
            ),
          ),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.label_outline,
          title: 'Auto-download categories',
          subtitle: s.autoDownloadCategories.isEmpty
              ? 'None'
              : '${s.autoDownloadCategories.length} selected',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showCategoryPicker(context, categories),
        ),
      ],
    );
  }

  void _showCategoryPicker(BuildContext context, List<Category> categories) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Auto-download categories',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ...categories
                  .where((c) => c.id != 0)
                  .map((c) => CheckboxListTile(
                        value: false,
                        title: Text(c.name),
                        onChanged: (_) {},
                      )),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Browse — extension repos.
// ---------------------------------------------------------------------------
class _BrowseSection extends ConsumerWidget {
  const _BrowseSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repos = ref.watch(extensionReposProvider);
    return _SettingsSection(
      title: 'Browse',
      icon: Icons.explore_outlined,
      iconColor: LuminaTheme.seed,
      children: [
        _SectionTile(
          icon: Icons.extension_outlined,
          title: 'Manage extensions',
          subtitle: '${repos.fold<int>(0, (a, b) => a + b.installedCount)} '
              'installed across ${repos.length} repos',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showSnack(ref, context, 'Open extensions'),
        ),
        const _Divider(),
        for (final r in repos)
          _SectionTile(
            icon: Icons.folder_outlined,
            title: r.name,
            subtitle: r.url,
            trailing: Text('${r.installedCount} ext'),
            onTap: () => showSnack(ref, context, 'Open ${r.name}'),
          ),
        const _Divider(),
        _SectionTile(
          icon: Icons.add_link,
          title: 'Add repository',
          subtitle: 'Paste a Lumina / Tachiyomi / Aniyomi repo URL',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showSnack(ref, context, 'Add repository'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Downloads.
// ---------------------------------------------------------------------------
class _DownloadsSection extends ConsumerWidget {
  const _DownloadsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wifiOnly = ref.watch(wifiOnlyDownloadsProvider);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsSection(
      title: 'Downloads',
      icon: Icons.download_outlined,
      iconColor: LuminaTheme.unreadColor,
      children: [
        _SwitchTile(
          icon: Icons.wifi,
          title: 'Wi-Fi only',
          subtitle: wifiOnly
              ? 'Downloads pause on metered networks'
              : 'Downloads use any connection',
          value: wifiOnly,
          onChanged: (_) => ref
              .read(wifiOnlyDownloadsProvider.notifier)
              .state = !wifiOnly,
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.sync_alt,
          title: 'Parallel downloads',
          subtitle: '${s.parallelDownloads} at a time',
          trailing: SizedBox(
            width: 140,
            child: Slider(
              min: 1,
              max: 6,
              divisions: 5,
              value: s.parallelDownloads.toDouble(),
              onChanged: (v) => notifier.setParallelDownloads(v.round()),
            ),
          ),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.cleaning_services_outlined,
          title: 'Clear download cache',
          subtitle: '248 MB used',
          onTap: () => showSnack(ref, context, 'Cache cleared'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.folder_delete_outlined,
          title: 'Delete all downloads',
          subtitle: 'Removes offline content for every library entry',
          onTap: () => showSnack(ref, context, 'All downloads removed'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Security — app lock + incognito.
// ---------------------------------------------------------------------------
class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final incognito = ref.watch(incognitoModeProvider);
    return _SettingsSection(
      title: 'Security',
      icon: Icons.lock_outline,
      iconColor: LuminaTheme.newColor,
      children: [
        _SwitchTile(
          icon: Icons.fingerprint,
          title: 'App lock',
          subtitle: s.appLockEnabled
              ? 'Require biometric / PIN to unlock'
              : 'Off',
          value: s.appLockEnabled,
          onChanged: (_) => notifier.toggleAppLock(),
        ),
        if (s.appLockEnabled) ...[
          const _Divider(),
          _SwitchTile(
            icon: Icons.login,
            title: 'Lock on launch',
            value: s.lockOnLaunch,
            onChanged: (_) => notifier.toggleLockOnLaunch(),
          ),
          const _Divider(),
          _SwitchTile(
            icon: Icons.lock_clock,
            title: 'Lock on resume',
            subtitle: 'Re-lock when returning to the app',
            value: s.lockOnResume,
            onChanged: (_) => notifier.toggleLockOnResume(),
          ),
        ],
        const _Divider(),
        _SwitchTile(
          icon: Icons.visibility_off_outlined,
          title: 'Incognito mode',
          subtitle: incognito
              ? 'Reading & watching won\'t be recorded'
              : 'Activity is recorded normally',
          value: incognito,
          onChanged: (_) => ref
              .read(incognitoModeProvider.notifier)
              .state = !incognito,
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.secure_outlined,
          title: 'Secure screen',
          subtitle: 'Hide previews in the app switcher',
          value: false,
          onChanged: (_) {},
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sync — cloud sync + trackers.
// ---------------------------------------------------------------------------
class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsSection(
      title: 'Sync',
      icon: Icons.cloud_sync_outlined,
      iconColor: LuminaTheme.readingColor,
      children: [
        _SwitchTile(
          icon: Icons.cloud_outlined,
          title: 'Cloud sync',
          subtitle: s.cloudSyncEnabled
              ? 'Last synced ${s.lastSyncAt != null ? _shortDate(s.lastSyncAt!) : 'never'}'
              : 'Off',
          value: s.cloudSyncEnabled,
          onChanged: (_) => notifier.toggleCloudSync(),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.sync,
          title: 'Sync now',
          subtitle: 'Push local changes to the cloud',
          onTap: () {
            notifier.markSynced();
            showSnack(ref, context, 'Synced with the cloud');
          },
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.movie,
          title: 'MyAnimeList',
          subtitle: 'Connected • syncs watch & read progress',
          trailing: const Icon(Icons.link),
          onTap: () => showSnack(ref, context, 'Manage MAL'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.auto_awesome,
          title: 'AniList',
          subtitle: 'Not connected',
          trailing: const Icon(Icons.link_off),
          onTap: () => showSnack(ref, context, 'Connect AniList'),
        ),
        const _Divider(),
        _SwitchTile(
          icon: Icons.update,
          title: 'Auto update tracker progress',
          value: s.trackerAutoUpdate,
          onChanged: (_) => notifier.toggleTrackerAutoUpdate(),
        ),
      ],
    );
  }

  String _shortDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Backup.
// ---------------------------------------------------------------------------
class _BackupSection extends ConsumerWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsSection(
      title: 'Backup',
      icon: Icons.backup_outlined,
      iconColor: LuminaTheme.finishedColor,
      children: [
        _SectionTile(
          icon: Icons.file_upload_outlined,
          title: 'Create backup',
          subtitle: 'Export library, history and settings',
          onTap: () {
            notifier.markBackup();
            showSnack(ref, context, 'Backup created');
          },
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.file_download_outlined,
          title: 'Restore backup',
          subtitle: 'Import a previous Lumina backup file',
          onTap: () => showSnack(ref, context, 'Pick a backup file'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.schedule,
          title: 'Automatic backup interval',
          subtitle: 'Every ${s.backupIntervalDays} days',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showStringPicker(
            context,
            title: 'Backup interval',
            values: const ['1', '3', '7', '14', '30'],
            current: '${s.backupIntervalDays}',
            onPick: (v) => notifier.setBackupInterval(int.parse(v)),
            suffix: ' days',
          ),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.history,
          title: 'Last backup',
          subtitle: s.lastBackupAt != null
              ? _shortDate(s.lastBackupAt!)
              : 'Never',
        ),
      ],
    );
  }

  String _shortDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// About.
// ---------------------------------------------------------------------------
class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsSection(
      title: 'About',
      icon: Icons.info_outline,
      iconColor: LuminaTheme.seed,
      children: [
        _SectionTile(
          icon: Icons.auto_stories,
          title: 'Lumina Reader',
          subtitle: 'Version 1.0.0 • Build 1',
        ),
        const _Divider(),
        _SectionTile(
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
        const _Divider(),
        _SectionTile(
          icon: Icons.copyright_outlined,
          title: 'Licence',
          subtitle: 'Apache License, Version 2.0',
          onTap: () => showSnack(ref, context, 'Apache 2.0'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.code,
          title: 'Source code',
          subtitle: 'github.com/lumina/lumina-reader',
          onTap: () => showSnack(ref, context, 'Open GitHub'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.bug_report_outlined,
          title: 'Report an issue',
          subtitle: 'Help us improve Lumina Reader',
          onTap: () => showSnack(ref, context, 'Opening issue tracker…'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Generic picker helper used by Reader / Player / Library sections.
// ---------------------------------------------------------------------------
void _showPicker<T extends Enum>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T current,
  required String Function(T) labelOf,
  required ValueChanged<T> onPick,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final v in values)
              RadioListTile<T>(
                value: v,
                groupValue: current,
                title: Text(labelOf(v)),
                onChanged: (sel) {
                  if (sel == null) return;
                  onPick(sel);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      );
    },
  );
}

void _showStringPicker(
  BuildContext context, {
  required String title,
  required List<String> values,
  required String current,
  required ValueChanged<String> onPick,
  String suffix = '',
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final v in values)
              RadioListTile<String>(
                value: v,
                groupValue: current,
                title: Text('$v$suffix'),
                onChanged: (sel) {
                  if (sel == null) return;
                  onPick(sel);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      );
    },
  );
}
