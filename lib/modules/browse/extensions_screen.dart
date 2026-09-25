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

import '../../core/ui/lumina_ui.dart';
import '../../data/providers.dart' as data;
import '../../eval/lib.dart' show kSupportedTemplates;
import 'browse_screen.dart' show showAddRepoSheet;
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Which tab the [ExtensionsScreen] opens on.
enum ExtensionsTab { installed, catalog, repositories }

/// Full-screen extension manager — the dedicated page Settings links to.
///
/// Previously "Manage extensions" / "Add repository" in Settings just hopped
/// to the Browse tab (context.go('/browse')), which looked like a dead end:
/// no management UI, no repo list, nothing to act on. This screen gives the
/// whole extension subsystem one home with three sections:
///
///   * Installed  — live sources with enable / uninstall actions
///   * Catalog    — every extension from every registered repo, searchable,
///                  with install / uninstall / update + honest "not
///                  supported" badges for interpreter-only entries
///   * Repositories — the repo list with sync / remove / add actions
class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key, this.initialTab = ExtensionsTab.installed});

  final ExtensionsTab initialTab;

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: switch (widget.initialTab) {
        ExtensionsTab.installed => 0,
        ExtensionsTab.catalog => 1,
        ExtensionsTab.repositories => 2,
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(extensionCatalogProvider);
    final installed = catalog.where((s) => s.isInstalled).toList();
    final repos = ref.watch(extensionReposProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Installed (${installed.length})'),
            Tab(text: 'Catalog (${catalog.length})'),
            Tab(text: 'Repos (${repos.length})'),
          ],
        ),
        actions: [
          _syncing
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : HeroIconButton(
                  tooltip: 'Sync repositories',
                  icon: Icons.sync_rounded,
                  onPressed: _syncAll,
                ),
          HeroIconButton(
            tooltip: 'Add repository',
            icon: Icons.add_link,
            onPressed: () => showAddRepoSheet(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _InstalledTab(installed: installed, query: _query),
          _CatalogTab(catalog: catalog, query: _query),
          _ReposTab(repos: repos),
        ],
      ),
      // Bottom search field shared by the Installed/Catalog tabs — pinned
      // under the body so the lists scroll independently. Listens to the
      // controller so the field hides the instant the Repos tab appears.
      bottomNavigationBar: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) => _tabController.index == 2
            ? const SizedBox.shrink()
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: HeroInput(
                    controller: _searchController,
                    hint: 'Search extensions…',
                    prefixIcon: Icons.search_rounded,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _syncAll() async {
    setState(() => _syncing = true);
    try {
      await ref.read(data.extensionRepoServiceProvider).syncAll();
    } catch (_) {}
    if (mounted) setState(() => _syncing = false);
  }
}

// ---------------------------------------------------------------------------
// Installed tab
// ---------------------------------------------------------------------------

class _InstalledTab extends ConsumerWidget {
  const _InstalledTab({required this.installed, required this.query});

  final List<Source> installed;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Installed tab ALSO shows the seeded builtins (MangaDex etc.) — they
    // are the sources Browse actually serves content from. The catalog
    // provider only carries repo rows; builtins come from sourcesProvider.
    final allSources = ref.watch(sourcesProvider);
    final builtin = allSources.where((s) => s.isInstalled).toList();
    final merged = <Source>[...builtin, ...installed];
    final q = query.toLowerCase();
    final rows = q.isEmpty
        ? merged
        : merged
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                s.lang.toLowerCase().contains(q))
            .toList();

    if (rows.isEmpty) {
      return _empty(context,
        icon: Icons.extension_outlined,
        title: 'Nothing installed',
        subtitle: 'Install a source from the Catalog tab to start browsing.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const HeroSeparator(indent: 72),
      itemBuilder: (context, i) => _ExtensionTile(
        entry: rows[i],
        isBuiltin: rows[i].idString?.startsWith('builtin.') ?? false,
      ),
    );
  }

  Widget _empty(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle}) {
    final h = HeroScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: h.muted),
            const SizedBox(height: 12),
            Text(title,
                style: HeroTokens.title.copyWith(color: h.foreground)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: HeroTokens.bodySmall.copyWith(color: h.muted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Catalog tab
// ---------------------------------------------------------------------------

class _CatalogTab extends StatelessWidget {
  const _CatalogTab({required this.catalog, required this.query});

  final List<Source> catalog;
  final String query;

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final rows = q.isEmpty
        ? catalog
        : catalog
            .where((s) =>
                s.name.toLowerCase().contains(q) ||
                s.lang.toLowerCase().contains(q))
            .toList();

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No extensions found.\nAdd a repository to fill the catalog.',
            textAlign: TextAlign.center,
            style: HeroTokens.bodySmall.copyWith(color: HeroScope.of(context).muted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const HeroSeparator(indent: 72),
      itemBuilder: (context, i) =>
          _ExtensionTile(entry: rows[i], isBuiltin: false),
    );
  }
}

// ---------------------------------------------------------------------------
// Repositories tab
// ---------------------------------------------------------------------------

class _ReposTab extends ConsumerWidget {
  const _ReposTab({required this.repos});

  final List<ExtensionRepo> repos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    if (repos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off_outlined, size: 56, color: h.muted),
              const SizedBox(height: 12),
              Text('No repositories', style: HeroTokens.title.copyWith(color: h.foreground)),
              const SizedBox(height: 6),
              Text(
                'Add a Mangayomi-compatible repository to fill the catalog.',
                textAlign: TextAlign.center,
                style: HeroTokens.bodySmall.copyWith(color: h.muted),
              ),
              const SizedBox(height: 16),
              HeroButton(
                label: 'Add repository',
                icon: Icons.add_link,
                onPressed: () => showAddRepoSheet(context, ref),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final r in repos)
          HeroListTile(
            leadingIcon: Icons.folder_outlined,
            leadingColor: h.accent,
            title: r.name,
            subtitle: '${r.extensionCount} extensions'
                '${r.lastError != null ? ' • last sync failed' : ''}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HeroIconButton(
                  tooltip: 'Sync this repository',
                  icon: Icons.sync_rounded,
                  size: 34,
                  iconSize: 18,
                  onPressed: () async {
                    try {
                      await ref
                          .read(data.extensionRepoServiceProvider)
                          .syncRepo(r.url);
                    } catch (_) {}
                  },
                ),
                HeroIconButton(
                  tooltip: 'Remove repository',
                  icon: Icons.delete_outline_rounded,
                  variant: HeroColorRole.danger,
                  size: 34,
                  iconSize: 18,
                  onPressed: () async {
                    await ref
                        .read(data.extensionRepoServiceProvider)
                        .removeRepo(r.url);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared extension row
// ---------------------------------------------------------------------------

class _ExtensionTile extends ConsumerWidget {
  const _ExtensionTile({required this.entry, required this.isBuiltin});

  final Source entry;
  final bool isBuiltin;

  bool get _supported =>
      kSupportedTemplates.contains((entry.typeSource ?? '').toLowerCase()) ||
      isBuiltin ||
      // MangaDex language variants arrive as typeSource "single" with the
      // mangadex.org base URL — the native MangaDex template handles them.
      ((entry.typeSource ?? '').toLowerCase() == 'single' &&
          (entry.baseUrl.contains('mangadex.org')));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = HeroScope.of(context);
    final hasUpdate =
        entry.versionLast != null && entry.versionLast != entry.version;
    final template = (entry.typeSource ?? 'unknown').toLowerCase();
    final subtitle = isBuiltin
        ? '${entry.lang} • v${entry.version} • built-in'
        : '$template • v${entry.version}'
            '${hasUpdate ? ' • v${entry.versionLast} available' : ''}';
    return HeroListTile(
      leading: _iconTile(h),
      title: entry.name,
      subtitle: subtitle,
      trailing: _trailing(ref, h),
    );
  }

  Widget _iconTile(HeroThemeData h) {
    if (entry.iconUrl != null) {
      return Container(
        width: 42,
        height: 42,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(11)),
        child: Image.network(
          entry.iconUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(h),
        ),
      );
    }
    return _fallbackIcon(h);
  }

  Widget _fallbackIcon(HeroThemeData h) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: h.accentSoft,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(Icons.extension_rounded, size: 20, color: h.accentSoftFg),
      );

  Widget _trailing(WidgetRef ref, HeroThemeData h) {
    if (!_supported) {
      return const Tooltip(
        message: 'This extension needs the code interpreter, which is not '
            'available in this build',
        child: HeroChip(
          label: 'Not supported',
          variant: HeroChipVariant.bordered,
          color: HeroColorRole.neutral,
          small: true,
        ),
      );
    }
    final idString = entry.idString;
    if (idString == null) return const SizedBox.shrink();
    if (entry.isInstalled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HeroChip(
            label: 'Installed',
            variant: HeroChipVariant.soft,
            small: true,
          ),
          const SizedBox(width: 4),
          HeroIconButton(
            tooltip: 'Uninstall',
            icon: Icons.delete_outline_rounded,
            variant: HeroColorRole.danger,
            size: 32,
            iconSize: 18,
            onPressed: () async {
              await ref
                  .read(data.extensionRepoServiceProvider)
                  .uninstall(idString);
            },
          ),
        ],
      );
    }
    return HeroButton(
      label: 'Install',
      size: HeroButtonSize.sm,
      onPressed: () async {
        await ref.read(data.extensionRepoServiceProvider).install(idString);
      },
    );
  }
}
