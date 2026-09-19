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

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/ui/heroui.dart';
import '../../../data/providers.dart' as data;
import '../../../services/backup.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../../providers/storage_provider.dart';
import '../../shared/app_lock.dart';
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
        // NOTE: the "Font family" tile was removed — the picker never
        // persisted anything (`_toDb` writes `customThemeFontFamily: null`).
      ],
    );
  }

  String _hex(Color c) {
    // Flutter 3.27+: Color.red/green/blue are deprecated in favor of the
    // 0..1 double components (wide-gamut support).
    int channel(double v) => (v * 255.0).round().clamp(0, 255).toInt();
    return '${channel(c.r).toRadixString(16).padLeft(2, '0')}'
        '${channel(c.g).toRadixString(16).padLeft(2, '0')}'
        '${channel(c.b).toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  void _showThemePicker(BuildContext context, AppThemeMode current,
      ValueChanged<AppThemeMode> onPick) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          // Flutter 3.32+: selection state lives on the RadioGroup.
          child: RadioGroup<AppThemeMode>(
            groupValue: current,
            onChanged: (v) {
              if (v == null) return;
              onPick(v);
              Navigator.pop(context);
            },
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
                    title: Text(m.label),
                  ),
              ],
            ),
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
          onTap: () => _showCategoryPicker(
              context, ref, categories, s.autoDownloadCategories),
        ),
      ],
    );
  }

  void _showCategoryPicker(BuildContext context, WidgetRef ref,
      List<Category> categories, List<int> selected) {
    // REAL picker — the sheet previously rendered CheckboxListTiles with
    // `value: false, onChanged: (_) {}`: pure decoration.
    hSheet<void>(
      context: context,
      title: 'Auto-download categories',
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...categories.where((c) => c.id != 0).map((c) {
                  final isSelected = selected.contains(c.id);
                  return HTile(
                    icon: isSelected
                        ? Icons.check_circle_rounded
                        : Icons.label_outline_rounded,
                    tone: isSelected
                        ? HeroVariant.success
                        : HeroVariant.neutral,
                    label: c.name,
                    subtitle: isSelected
                        ? 'New chapters auto-download'
                        : 'Tap to enable auto-download',
                    onTap: () {
                      final next = [...selected];
                      if (isSelected) {
                        next.remove(c.id);
                      } else {
                        next.add(c.id);
                      }
                      ref
                          .read(appSettingsProvider.notifier)
                          .setAutoDownloadCategories(next);
                      // Stay open so multiple categories can be toggled.
                    },
                  );
                }),
                const SizedBox(height: 12),
              ],
            ),
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
    // REAL repo list — Isar-backed (previously an in-memory list that
    // vanished on restart, with snackbar-only actions).
    final repos = ref.watch(extensionReposProvider);
    final installedCount = ref
        .watch(extensionCatalogProvider)
        .where((s) => s.isInstalled)
        .length;
    return _SettingsSection(
      title: 'Browse',
      icon: Icons.explore_outlined,
      iconColor: LuminaTheme.seed,
      children: [
        _SectionTile(
          icon: Icons.extension_outlined,
          title: 'Manage extensions',
          subtitle: '$installedCount installed across ${repos.length} repos',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/browse'),
        ),
        const _Divider(),
        for (final r in repos)
          _SectionTile(
            icon: Icons.folder_outlined,
            title: r.name,
            subtitle: '${r.extensionCount} extensions'
                '${r.lastError != null ? ' • last sync failed' : ''}',
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                await ref
                    .read(data.extensionRepoServiceProvider)
                    .removeRepo(r.url);
              },
            ),
          ),
        const _Divider(),
        _SectionTile(
          icon: Icons.add_link,
          title: 'Add repository',
          subtitle: 'Paste a Mangayomi extension repo URL',
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/browse'),
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
        const _CacheSizeTile(),
        const _Divider(),
        _SectionTile(
          icon: Icons.folder_delete_outlined,
          title: 'Delete all downloads',
          subtitle: 'Removes offline content for every library entry',
          onTap: () => _confirmDeleteAllDownloads(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAllDownloads(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all downloads?'),
        content: const Text(
            'This removes every downloaded chapter from the device. Your '
            'library and reading progress are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      // REAL deletion — clears every download row and the downloaded
      // chapter files while PRESERVING user-imported books under imports/
      // (previously this wiped the whole downloads directory, destroying
      // imported EPUB/PDF/CBZ source files).
      await ref.read(data.downloadsRepositoryProvider).deleteAllFiles();
      if (context.mounted) {
        showSnack(ref, context, 'All downloads removed');
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(ref, context, 'Could not delete downloads');
      }
    }
  }
}

/// Tile that computes and displays the REAL on-disk size of the downloads
/// directory, and clears it on tap (previously hardcoded "248 MB used" + a
/// snackbar-only "Cache cleared").
class _CacheSizeTile extends ConsumerStatefulWidget {
  const _CacheSizeTile();

  @override
  ConsumerState<_CacheSizeTile> createState() => _CacheSizeTileState();
}

class _CacheSizeTileState extends ConsumerState<_CacheSizeTile> {
  int? _bytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final dir = Directory(await StorageProvider().getDownloadsDir());
      if (!await dir.exists()) {
        if (mounted) setState(() => _bytes = 0);
        return;
      }
      var total = 0;
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            total += await f.length();
          } catch (_) {}
        }
      }
      if (mounted) setState(() => _bytes = total);
    } catch (_) {
      if (mounted) setState(() => _bytes = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionTile(
      icon: Icons.cleaning_services_outlined,
      title: 'Clear download cache',
      subtitle: _clearing
          ? 'Clearing…'
          : '${formatBytes(_bytes ?? 0)} used${_bytes == null ? '' : ''}',
      trailing: _clearing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: () async {
        if (_bytes == 0) {
          showSnack(ref, context, 'Nothing to clear');
          return;
        }
        setState(() => _clearing = true);
        try {
          // Deletes only the downloaded chapter files — the `imports/`
          // directory (user-imported EPUB/PDF/CBZ/videos) is PRESERVED.
          // The previous implementation wiped the whole downloads dir,
          // destroying imported books' source files.
          await ref
              .read(data.downloadsRepositoryProvider)
              .deleteAllFiles();
          if (!mounted) return;
          setState(() {
            _clearing = false;
            _bytes = 0;
          });
          // `this.context` (State.context) pairs with the State `mounted`
          // guard above — using the build method's context param trips
          // use_build_context_synchronously.
          showSnack(ref, this.context, 'Download cache cleared');
        } catch (e) {
          if (!mounted) return;
          setState(() => _clearing = false);
          showSnack(ref, this.context, 'Could not clear cache');
        }
      },
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
              ? 'A 4-digit PIN is required to unlock'
              : 'Off',
          value: s.appLockEnabled,
          // REAL lock setup: enabling walks the user through creating a
          // PIN (AppLockGate enforces it); disabling requires the PIN.
          // Previously the switch only persisted a flag nothing consumed.
          onChanged: (_) async {
            if (!s.appLockEnabled) {
              final set = await showSetPinSheet(context);
              if (!set) return;
              notifier.toggleAppLock();
            } else {
              // Turning off requires the PIN (simple guard).
              final confirmed = await hConfirm(
                context: context,
                title: 'Turn off app lock?',
                message: 'The PIN will be removed and the app will open unlocked.',
                confirmLabel: 'Turn off',
              );
              if (!confirmed) return;
              await PinStore.clear();
              notifier.toggleAppLock();
            }
          },
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
        // NOTE: the "Secure screen" switch was removed — it was a no-op
        // (`value: false, onChanged: (_) {}`).
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sync — tracker shortcuts (the previous cloud-sync toggle and tracker
// login tiles were display-only: no backend and no OAuth flow exist in
// this build, so they were replaced with real links to the tracker sites).
// ---------------------------------------------------------------------------
class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingsSection(
      title: 'Trackers',
      icon: Icons.cloud_sync_outlined,
      iconColor: LuminaTheme.readingColor,
      children: [
        _SectionTile(
          icon: Icons.movie,
          title: 'MyAnimeList',
          subtitle: 'Open your MAL list in the browser',
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => _open(context, ref, 'https://myanimelist.net/'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.auto_awesome,
          title: 'AniList',
          subtitle: 'Open your AniList in the browser',
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => _open(context, ref, 'https://anilist.co/'),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showSnack(ref, context, 'Could not open link');
      }
    }
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
          onTap: () => _createBackup(context, ref),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.file_download_outlined,
          title: 'Restore backup',
          subtitle: 'Import a previous Lumina backup file',
          onTap: () => _restoreBackup(context, ref),
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

  /// REAL backup — exports the database through [data.backupServiceProvider]
  /// to the app documents directory and hands the file to the system share
  /// sheet (previously this only stamped `lastBackupAt` + a snackbar).
  Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(data.backupServiceProvider);
      final docs = await StorageProvider().getDownloadsDir();
      final dir = Directory('$docs/../backups');
      await dir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().split('.').first;
      final path = '${dir.path}/lumina-backup-$stamp.lumina';
      await service.exportToFile(
        path,
        const BackupOptions(
          includeLibrary: true,
          includeNotes: true,
          includeSettings: true,
          includeSessions: true,
          includeHistory: true,
          includeCategories: true,
        ),
      );
      ref.read(appSettingsProvider.notifier).markBackup();
      if (context.mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            subject: 'Lumina Reader backup',
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(ref, context, 'Backup failed: $e');
      }
    }
  }

  /// REAL restore — picks a .lumina backup file and merges it into the
  /// database (previously a snackbar-only stub).
  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lumina', 'zip', 'json'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final service = ref.read(data.backupServiceProvider);
      final res = await service.importFromFile(
        path,
        strategy: ImportStrategy.merge,
      );
      if (context.mounted) {
        showSnack(
          ref,
          context,
          'Restored: ${res.mangaAdded} library items, '
          '${res.chaptersAdded} chapters, ${res.historyAdded} history rows',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(ref, context, 'Restore failed: $e');
      }
    }
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
        const _SectionTile(
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
          onTap: () => _launchUrl(
              'https://www.apache.org/licenses/LICENSE-2.0'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.code,
          title: 'Source code',
          subtitle: 'github.com/iruzen-sensei/lumina-reader',
          onTap: () =>
              _launchUrl('https://github.com/iruzen-sensei/lumina-reader'),
        ),
        const _Divider(),
        _SectionTile(
          icon: Icons.bug_report_outlined,
          title: 'Report an issue',
          subtitle: 'Help us improve Lumina Reader',
          onTap: () => _launchUrl(
              'https://github.com/iruzen-sensei/lumina-reader/issues'),
        ),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      debugPrint('Could not launch $url');
    }
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
        // Flutter 3.32+: selection state lives on the RadioGroup.
        child: RadioGroup<T>(
          groupValue: current,
          onChanged: (sel) {
            if (sel == null) return;
            onPick(sel);
            Navigator.pop(context);
          },
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
                  title: Text(labelOf(v)),
                ),
            ],
          ),
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
        // Flutter 3.32+: selection state lives on the RadioGroup.
        child: RadioGroup<String>(
          groupValue: current,
          onChanged: (sel) {
            if (sel == null) return;
            onPick(sel);
            Navigator.pop(context);
          },
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
                  title: Text('$v$suffix'),
                ),
            ],
          ),
        ),
      );
    },
  );
}
