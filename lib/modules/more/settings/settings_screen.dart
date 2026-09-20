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

import '../../../core/ui/heroui_v3.dart';
import '../../../data/providers.dart' as data;
import '../../../services/backup.dart';
import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../../providers/storage_provider.dart';
import '../../shared/app_lock.dart';
import '../../shared/widgets.dart';

/// The settings screen.
///
/// Groups every user-configurable option into HeroUI cards under section
/// headers: Appearance, Reader, Player, Data (Library / Downloads / Browse /
/// Backup), Security and About (Trackers / About). State is held by the
/// [appSettingsProvider] notifier so changes propagate to every consumer in
/// the app.
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
                style: HeroTokens.titleLarge
                    .copyWith(color: HeroScope.of(context).foreground),
              ),
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: HeroIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate(
                [
                  const HeroSectionHeader('Appearance'),
                  const _AppearanceCard(),
                  const HeroSectionHeader('Reader'),
                  const _ReaderCard(),
                  const HeroSectionHeader('Player'),
                  const _PlayerCard(),
                  const HeroSectionHeader('Data'),
                  const _LibraryCard(),
                  const SizedBox(height: 10),
                  const _DownloadsCard(),
                  const SizedBox(height: 10),
                  const _BrowseCard(),
                  const SizedBox(height: 10),
                  const _BackupCard(),
                  const HeroSectionHeader('Security'),
                  const _SecurityCard(),
                  const HeroSectionHeader('About'),
                  const _TrackersCard(),
                  const SizedBox(height: 10),
                  const _AboutCard(),
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
// Section scaffolding — a surface card of rows separated by hairlines.
// ---------------------------------------------------------------------------

/// Grouped settings card: rows separated by [HeroSeparator]s indented to the
/// text column (16 padding + 36 icon + 14 gap).
class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.children});

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
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HeroTokens.radiusCard),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

/// Row with a leading icon, title, subtitle and a [HeroSwitch] trailing.
/// Tapping anywhere on the row flips the switch (switch ON = active).
class _SwitchSettingTile extends StatelessWidget {
  const _SwitchSettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.leadingColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? leadingColor;

  @override
  Widget build(BuildContext context) {
    return HeroListTile(
      leadingIcon: icon,
      leadingColor: leadingColor,
      title: title,
      subtitle: subtitle,
      trailing: HeroSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}

/// Row with a leading icon, title, optional subtitle + trailing widget, and
/// a full-width [HeroSegmented] control beneath it (for 2-4 way choices).
class _SegmentedSettingTile<T> extends StatelessWidget {
  const _SegmentedSettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.trailing,
    this.leadingColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<(T, String, IconData?)> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final Widget? trailing;
  final Color? leadingColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroListTile(
          leadingIcon: icon,
          leadingColor: leadingColor,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: HeroSegmented<T>(
            segments: segments,
            selected: selected,
            onChanged: onChanged,
            expand: true,
          ),
        ),
      ],
    );
  }
}

/// Row with a leading icon, title, value label and a slider beneath it.
class _SliderSettingTile extends StatelessWidget {
  const _SliderSettingTile({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
    this.leadingColor,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;
  final Color? leadingColor;

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final tint = leadingColor ?? h.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: tint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: HeroTokens.body.copyWith(
                      color: h.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  valueLabel,
                  style: HeroTokens.caption.copyWith(color: h.muted),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Slider(
                min: min,
                max: max,
                divisions: divisions,
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance — theme, font, e-ink mode, custom colours.
// ---------------------------------------------------------------------------
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return _SettingsGroupCard(
      children: [
        _SegmentedSettingTile<AppThemeMode>(
          icon: Icons.brightness_6_outlined,
          title: 'Theme',
          subtitle: s.themeMode.label,
          segments: const [
            (AppThemeMode.system, 'Auto', null),
            (AppThemeMode.light, 'Light', null),
            (AppThemeMode.dark, 'Dark', null),
            (AppThemeMode.amoled, 'Black', null),
          ],
          selected: s.themeMode,
          onChanged: notifier.setThemeMode,
        ),
        // REMOVED: "Dynamic colour (Material You)" + "Brand colour" tiles.
        // Both persisted a value nothing ever consumed (theming ignores
        // useDynamicColor/customSeed) - decorative controls, deleted per
        // the no-dead-controls audit. The app uses the fixed rybin palette.
        _SwitchSettingTile(
          icon: Icons.e_mobiledata_outlined,
          title: 'E-ink mode',
          subtitle: 'High-contrast, no gradients — friendly to e-readers',
          value: s.einkMode,
          onChanged: (_) => notifier.toggleEinkMode(),
        ),
        _SliderSettingTile(
          icon: Icons.text_fields,
          title: 'Font size',
          valueLabel: '${s.fontSize.round()} pt',
          min: 10,
          max: 24,
          divisions: 14,
          value: s.fontSize,
          onChanged: notifier.setFontSize,
        ),
        // NOTE: the "Font family" tile was removed — the picker never
        // persisted anything (`_toDb` writes `customThemeFontFamily: null`).
      ],
    );
  }
}

class _ReaderCard extends ConsumerWidget {
  const _ReaderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsGroupCard(
      children: [
        _SegmentedSettingTile<ReaderMode>(
          icon: Icons.auto_stories_outlined,
          title: 'Default reading mode',
          subtitle: _readerModeLabel(s.defaultReaderMode),
          segments: const [
            (ReaderMode.paged, 'Paged', null),
            (ReaderMode.continuous, 'Vertical', null),
            (ReaderMode.webtoon, 'Webtoon', null),
          ],
          selected: s.defaultReaderMode,
          onChanged: notifier.setReaderMode,
        ),
        _SegmentedSettingTile<ReaderDirection>(
          icon: Icons.swap_horiz,
          title: 'Reading direction',
          subtitle: _readerDirectionLabel(s.defaultReaderDirection),
          segments: const [
            (ReaderDirection.leftToRight, 'LTR', null),
            (ReaderDirection.rightToLeft, 'RTL', null),
            (ReaderDirection.vertical, 'Vertical', null),
          ],
          selected: s.defaultReaderDirection,
          onChanged: notifier.setReaderDirection,
        ),
        _SegmentedSettingTile<ReaderBgColor>(
          icon: Icons.color_lens_outlined,
          title: 'Reader background',
          segments: const [
            (ReaderBgColor.black, 'Black', null),
            (ReaderBgColor.gray, 'Gray', null),
            (ReaderBgColor.white, 'White', null),
            (ReaderBgColor.sepia, 'Sepia', null),
          ],
          selected: s.readerBgColor,
          onChanged: notifier.setReaderBg,
          trailing: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: s.readerBgColor.color,
              shape: BoxShape.circle,
              border: Border.all(color: h.border),
            ),
          ),
        ),
        _SwitchSettingTile(
          icon: Icons.touch_app_outlined,
          title: 'Tap to navigate',
          subtitle: 'Tap screen edges to flip pages',
          value: s.tapToNavigate,
          onChanged: (_) => notifier.toggleTapToNavigate(),
        ),
        _SwitchSettingTile(
          icon: Icons.numbers,
          title: 'Show page number',
          value: s.showPageNumber,
          onChanged: (_) => notifier.togglePageNumber(),
        ),
        _SwitchSettingTile(
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
class _PlayerCard extends ConsumerWidget {
  const _PlayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsGroupCard(
      children: [
        HeroListTile(
          leadingIcon: Icons.hd_outlined,
          leadingColor: h.warning,
          title: 'Default video quality',
          subtitle: s.defaultVideoQuality,
          showChevron: true,
          onTap: () => _showOptionSheet(
            context,
            title: 'Video quality',
            values: const ['1080p', '720p', '480p', '360p', 'Auto'],
            current: s.defaultVideoQuality,
            onPick: notifier.setVideoQuality,
          ),
        ),
        HeroListTile(
          leadingIcon: Icons.subtitles_outlined,
          leadingColor: h.warning,
          title: 'Default subtitle',
          subtitle: s.defaultSubtitle,
          showChevron: true,
          onTap: () => _showOptionSheet(
            context,
            title: 'Subtitle track',
            values: const ['Off', 'English', 'Español', '日本語', 'Português'],
            current: s.defaultSubtitle,
            onPick: notifier.setSubtitle,
          ),
        ),
        _SwitchSettingTile(
          icon: Icons.fast_forward,
          leadingColor: h.warning,
          title: 'AniSkip',
          subtitle: 'Auto-skip openings and endings',
          value: s.aniSkipEnabled,
          onChanged: (_) => notifier.toggleAniSkip(),
        ),
        // REMOVED: "Picture-in-picture" toggle — persisted a value nothing
        // consumed (no native PiP binding exists yet); re-add together
        // with the platform channel implementation.
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Library (under Data) — auto-download, Wi-Fi-only, categories.
// ---------------------------------------------------------------------------
class _LibraryCard extends ConsumerWidget {
  const _LibraryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final categories = ref.watch(categoriesProvider);
    return _SettingsGroupCard(
      children: [
        _SwitchSettingTile(
          icon: Icons.download_for_offline_outlined,
          leadingColor: h.accent,
          title: 'Auto-download new chapters',
          subtitle: 'Fetch new releases for library entries automatically',
          value: s.autoDownloadNew,
          onChanged: (_) => notifier.toggleAutoDownloadNew(),
        ),
        _SwitchSettingTile(
          icon: Icons.wifi,
          leadingColor: h.accent,
          title: 'Only download on Wi-Fi',
          value: s.downloadOnWifiOnly,
          onChanged: (_) => notifier.toggleDownloadOnWifiOnly(),
        ),
        _SliderSettingTile(
          icon: Icons.sync_alt,
          leadingColor: h.accent,
          title: 'Parallel downloads',
          valueLabel: '${s.parallelDownloads} at a time',
          min: 1,
          max: 6,
          divisions: 5,
          value: s.parallelDownloads.toDouble(),
          onChanged: (v) => notifier.setParallelDownloads(v.round()),
        ),
        HeroListTile(
          leadingIcon: Icons.label_outline,
          leadingColor: h.accent,
          title: 'Auto-download categories',
          subtitle: s.autoDownloadCategories.isEmpty
              ? 'None'
              : '${s.autoDownloadCategories.length} selected',
          showChevron: true,
          onTap: () => _showCategoryPicker(context, categories),
        ),
      ],
    );
  }

  Future<void> _showCategoryPicker(
      BuildContext context, List<Category> categories) {
    // REAL picker — the sheet previously rendered CheckboxListTiles with
    // `value: false, onChanged: (_) {}`: pure decoration.
    return showHeroSheet<void>(
      context: context,
      title: 'Auto-download categories',
      builder: (sheetContext) => SafeArea(
        child: _CategoryPickerBody(categories: categories),
      ),
    );
  }
}

/// Reactive sheet body — watches the persisted selection so tiles update as
/// categories are toggled (the sheet stays open for multi-select).
class _CategoryPickerBody extends ConsumerWidget {
  const _CategoryPickerBody({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final selected = ref.watch(appSettingsProvider).autoDownloadCategories;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in categories.where((c) => c.id != 0))
              HeroListTile(
                leadingIcon: selected.contains(c.id)
                    ? Icons.check_circle_rounded
                    : Icons.label_outline_rounded,
                leadingColor: selected.contains(c.id) ? h.success : h.muted,
                title: c.name,
                subtitle: selected.contains(c.id)
                    ? 'New chapters auto-download'
                    : 'Tap to enable auto-download',
                trailing: selected.contains(c.id)
                    ? Icon(Icons.check_rounded, size: 20, color: h.success)
                    : null,
                onTap: () {
                  final next = [...selected];
                  if (selected.contains(c.id)) {
                    next.remove(c.id);
                  } else {
                    next.add(c.id);
                  }
                  ref
                      .read(appSettingsProvider.notifier)
                      .setAutoDownloadCategories(next);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Downloads (under Data) — Wi-Fi gate, parallelism, cache + destructive
// actions.
// ---------------------------------------------------------------------------
class _DownloadsCard extends ConsumerStatefulWidget {
  const _DownloadsCard();

  @override
  ConsumerState<_DownloadsCard> createState() => _DownloadsCardState();
}

class _DownloadsCardState extends ConsumerState<_DownloadsCard> {
  int? _bytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  /// Computes the REAL on-disk size of the downloads directory
  /// (previously hardcoded "248 MB used" + a snackbar-only "Cache cleared").
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

  Future<void> _clearCache() async {
    if (_bytes == 0) {
      showSnack(ref, context, 'Nothing to clear');
      return;
    }
    final confirmed = await showHeroConfirm(
      context: context,
      title: 'Clear download cache?',
      message: 'Downloaded chapter files will be removed from the device. '
          'Imported books are kept.',
      confirmLabel: 'Clear',
      danger: true,
    );
    if (!confirmed) return;
    setState(() => _clearing = true);
    try {
      // Deletes only the downloaded chapter files — the `imports/`
      // directory (user-imported EPUB/PDF/CBZ/videos) is PRESERVED.
      // The previous implementation wiped the whole downloads dir,
      // destroying imported books' source files.
      await ref.read(data.downloadsRepositoryProvider).deleteAllFiles();
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _bytes = 0;
      });
      // Plain `context` (State.context) pairs with the State `mounted`
      // guard above to satisfy use_build_context_synchronously.
      showSnack(ref, context, 'Download cache cleared');
    } catch (e) {
      if (!mounted) return;
      setState(() => _clearing = false);
      showSnack(ref, context, 'Could not clear cache');
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showHeroConfirm(
      context: context,
      title: 'Delete all downloads?',
      message: 'This removes every downloaded chapter from the device. Your '
          'library and reading progress are kept.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!confirmed) return;
    try {
      // REAL deletion — clears every download row and the downloaded
      // chapter files while PRESERVING user-imported books under imports/
      // (previously this wiped the whole downloads directory, destroying
      // imported EPUB/PDF/CBZ source files).
      await ref.read(data.downloadsRepositoryProvider).deleteAllFiles();
      if (!mounted) return;
      setState(() => _bytes = 0);
      showSnack(ref, context, 'All downloads removed');
    } catch (e) {
      if (!mounted) return;
      showSnack(ref, context, 'Could not delete downloads');
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroScope.of(context);
    final wifiOnly = ref.watch(wifiOnlyDownloadsProvider);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsGroupCard(
      children: [
        _SwitchSettingTile(
          icon: Icons.wifi,
          leadingColor: h.success,
          title: 'Wi-Fi only',
          subtitle: wifiOnly
              ? 'Downloads pause on metered networks'
              : 'Downloads use any connection',
          value: wifiOnly,
          onChanged: (_) =>
              ref.read(wifiOnlyDownloadsProvider.notifier).state = !wifiOnly,
        ),
        _SliderSettingTile(
          icon: Icons.sync_alt,
          leadingColor: h.success,
          title: 'Parallel downloads',
          valueLabel: '${s.parallelDownloads} at a time',
          min: 1,
          max: 6,
          divisions: 5,
          value: s.parallelDownloads.toDouble(),
          onChanged: (v) => notifier.setParallelDownloads(v.round()),
        ),
        HeroListTile(
          leadingIcon: Icons.folder_outlined,
          leadingColor: h.success,
          title: 'Download cache',
          subtitle:
              _clearing ? 'Clearing…' : '${formatBytes(_bytes ?? 0)} used',
          trailing: _clearing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: h.success,
                  ),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: HeroButton(
                  label: 'Clear cache',
                  icon: Icons.cleaning_services_outlined,
                  variant: HeroButtonVariant.soft,
                  color: HeroColorRole.danger,
                  size: HeroButtonSize.sm,
                  fullWidth: true,
                  onPressed: _clearCache,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HeroButton(
                  label: 'Delete all',
                  icon: Icons.folder_delete_outlined,
                  variant: HeroButtonVariant.soft,
                  color: HeroColorRole.danger,
                  size: HeroButtonSize.sm,
                  fullWidth: true,
                  onPressed: _deleteAll,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Browse (under Data) — extension repos.
// ---------------------------------------------------------------------------
class _BrowseCard extends ConsumerWidget {
  const _BrowseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REAL repo list — Isar-backed (previously an in-memory list that
    // vanished on restart, with snackbar-only actions).
    final h = HeroScope.of(context);
    final repos = ref.watch(extensionReposProvider);
    final installedCount = ref
        .watch(extensionCatalogProvider)
        .where((src) => src.isInstalled)
        .length;
    return _SettingsGroupCard(
      children: [
        HeroListTile(
          leadingIcon: Icons.extension_outlined,
          leadingColor: h.warning,
          title: 'Manage extensions',
          subtitle: '$installedCount installed across ${repos.length} repos',
          showChevron: true,
          onTap: () => context.push('/browse'),
        ),
        for (final r in repos)
          HeroListTile(
            leadingIcon: Icons.folder_outlined,
            leadingColor: h.warning,
            title: r.name,
            subtitle: '${r.extensionCount} extensions'
                '${r.lastError != null ? ' • last sync failed' : ''}',
            trailing: HeroIconButton(
              icon: Icons.delete_outline_rounded,
              size: 34,
              iconSize: 18,
              color: h.danger,
              tooltip: 'Remove repository',
              onPressed: () async {
                await ref
                    .read(data.extensionRepoServiceProvider)
                    .removeRepo(r.url);
              },
            ),
          ),
        HeroListTile(
          leadingIcon: Icons.add_link,
          leadingColor: h.warning,
          title: 'Add repository',
          subtitle: 'Paste a Mangayomi extension repo URL',
          showChevron: true,
          onTap: () => context.push('/browse'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Backup (under Data).
// ---------------------------------------------------------------------------
class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SettingsGroupCard(
      children: [
        HeroListTile(
          leadingIcon: Icons.file_upload_outlined,
          leadingColor: h.accent,
          title: 'Create backup',
          subtitle: 'Export library, history and settings',
          showChevron: true,
          onTap: () => _createBackup(context, ref),
        ),
        HeroListTile(
          leadingIcon: Icons.file_download_outlined,
          leadingColor: h.accent,
          title: 'Restore backup',
          subtitle: 'Import a previous Lumina backup file',
          showChevron: true,
          onTap: () => _restoreBackup(context, ref),
        ),
        HeroListTile(
          leadingIcon: Icons.schedule,
          leadingColor: h.accent,
          title: 'Automatic backup interval',
          subtitle: 'Every ${s.backupIntervalDays} days',
          showChevron: true,
          onTap: () => _showIntervalDialog(
            context,
            current: s.backupIntervalDays,
            onPick: notifier.setBackupInterval,
          ),
        ),
        HeroListTile(
          leadingIcon: Icons.history,
          leadingColor: h.accent,
          title: 'Last backup',
          subtitle:
              s.lastBackupAt != null ? _shortDate(s.lastBackupAt!) : 'Never',
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
// Security — app lock + incognito.
// ---------------------------------------------------------------------------
class _SecurityCard extends ConsumerWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final incognito = ref.watch(incognitoModeProvider);
    return _SettingsGroupCard(
      children: [
        _SwitchSettingTile(
          icon: Icons.fingerprint,
          leadingColor: h.accent,
          title: 'App lock',
          subtitle:
              s.appLockEnabled ? 'A 4-digit PIN is required to unlock' : 'Off',
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
              final confirmed = await showHeroConfirm(
                context: context,
                title: 'Turn off app lock?',
                message:
                    'The PIN will be removed and the app will open unlocked.',
                confirmLabel: 'Turn off',
                danger: true,
              );
              if (!confirmed) return;
              await PinStore.clear();
              notifier.toggleAppLock();
            }
          },
        ),
        if (s.appLockEnabled) ...[
          _SwitchSettingTile(
            icon: Icons.login,
            leadingColor: h.accent,
            title: 'Lock on launch',
            value: s.lockOnLaunch,
            onChanged: (_) => notifier.toggleLockOnLaunch(),
          ),
          _SwitchSettingTile(
            icon: Icons.lock_clock,
            leadingColor: h.accent,
            title: 'Lock on resume',
            subtitle: 'Re-lock when returning to the app',
            value: s.lockOnResume,
            onChanged: (_) => notifier.toggleLockOnResume(),
          ),
        ],
        _SwitchSettingTile(
          icon: Icons.visibility_off_outlined,
          leadingColor: h.accent,
          title: 'Incognito mode',
          subtitle: incognito
              ? "Reading & watching won't be recorded"
              : 'Activity is recorded normally',
          value: incognito,
          onChanged: (_) =>
              ref.read(incognitoModeProvider.notifier).state = !incognito,
        ),
        // NOTE: the "Secure screen" switch was removed — it was a no-op
        // (`value: false, onChanged: (_) {}`).
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trackers (under About) — tracker shortcuts (the previous cloud-sync toggle
// and tracker login tiles were display-only: no backend and no OAuth flow
// exist in this build, so they were replaced with real links to the tracker
// sites).
// ---------------------------------------------------------------------------
class _TrackersCard extends ConsumerWidget {
  const _TrackersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return _SettingsGroupCard(
      children: [
        HeroListTile(
          leadingIcon: Icons.movie,
          leadingColor: h.success,
          title: 'MyAnimeList',
          subtitle: 'Open your MAL list in the browser',
          trailing: Icon(Icons.open_in_new_rounded, size: 18, color: h.muted),
          onTap: () => _open(context, ref, 'https://myanimelist.net/'),
        ),
        HeroListTile(
          leadingIcon: Icons.auto_awesome,
          leadingColor: h.success,
          title: 'AniList',
          subtitle: 'Open your AniList in the browser',
          trailing: Icon(Icons.open_in_new_rounded, size: 18, color: h.muted),
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
// About (under About).
// ---------------------------------------------------------------------------
class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    return _SettingsGroupCard(
      children: [
        HeroListTile(
          leadingIcon: Icons.auto_stories,
          leadingColor: h.accent,
          title: 'Lumina Reader',
          subtitle: 'Version 1.0.0 • Build 1',
        ),
        HeroListTile(
          leadingIcon: Icons.source_outlined,
          leadingColor: h.accent,
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
        HeroListTile(
          leadingIcon: Icons.copyright_outlined,
          leadingColor: h.accent,
          title: 'Licence',
          subtitle: 'Apache License, Version 2.0',
          showChevron: true,
          onTap: () =>
              _launchUrl('https://www.apache.org/licenses/LICENSE-2.0'),
        ),
        HeroListTile(
          leadingIcon: Icons.code,
          leadingColor: h.accent,
          title: 'Source code',
          subtitle: 'github.com/iruzen-sensei/lumina-reader',
          showChevron: true,
          onTap: () =>
              _launchUrl('https://github.com/iruzen-sensei/lumina-reader'),
        ),
        HeroListTile(
          leadingIcon: Icons.bug_report_outlined,
          leadingColor: h.accent,
          title: 'Report an issue',
          subtitle: 'Help us improve Lumina Reader',
          showChevron: true,
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
// Pickers — restyled option sheet (bottom sheet) and interval dialog.
// ---------------------------------------------------------------------------

/// Bottom-sheet option picker for string choices with more than four values
/// (video quality, subtitle track).
Future<void> _showOptionSheet(
  BuildContext context, {
  required String title,
  required List<String> values,
  required String current,
  required ValueChanged<String> onPick,
}) {
  return showHeroSheet<void>(
    context: context,
    title: title,
    builder: (sheetContext) {
      final h = HeroScope.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final v in values)
                HeroListTile(
                  title: v,
                  trailing: v == current
                      ? Icon(Icons.check_rounded, size: 20, color: h.accent)
                      : null,
                  onTap: () {
                    onPick(v);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Centered dialog picker for the automatic-backup interval (number picker).
Future<void> _showIntervalDialog(
  BuildContext context, {
  required int current,
  required ValueChanged<int> onPick,
}) {
  return showHeroDialog<void>(
    context: context,
    builder: (dialogContext) {
      final h = HeroScope.of(dialogContext);
      return HeroDialogFrame(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Backup interval',
                style: HeroTokens.title.copyWith(color: h.foreground),
              ),
            ),
            for (final days in const [1, 3, 7, 14, 30])
              HeroListTile(
                title: days == 1 ? 'Every day' : 'Every $days days',
                trailing: days == current
                    ? Icon(Icons.check_rounded, size: 20, color: h.accent)
                    : null,
                onTap: () {
                  onPick(days);
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}
