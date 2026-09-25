// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/downloads_repository.dart' as downloads_db;
import 'data/library_repository.dart';
import 'data/sources_repository.dart';
import 'models/settings.dart' as db_s;
import 'providers/storage_provider.dart';
import 'services/http/m_client.dart';
import 'data/backup_data_source.dart';
import 'services/backup.dart';
import 'services/download_engine.dart';
import 'services/extension_coordinator.dart';
import 'services/extension_repo_service.dart';
import 'services/library_updater.dart';

/// Whether [runApp] has completed and at least one frame was pumped.
///
/// The error boundary behaves differently before/after this flips:
///   * BEFORE — a failure IS fatal (the app never came up): show the
///     full-screen error + Restart button.
///   * AFTER — the app is live; a stray unhandled async error from a
///     background sync / download / updater must NEVER replace the running
///     app with an error screen. It is logged and dropped. Previously ANY
///     zone error re-ran runApp() with the error screen — the "a message
///     pops up saying it has to restart" bug.
bool _startupComplete = false;

void main() async {
  // Error boundary — NEVER crash to a black screen (the HyperOS lesson),
  // but also NEVER kill a RUNNING app over a background hiccup.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Framework (widget-build/layout) errors: print in debug, never abort.
    // In release builds the default handler would render the grey error
    // screen for a single bad frame — we keep the app alive instead.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
    };

    // Platform-level uncaught errors (timers, microtasks outside the zone,
    // platform channels): claim them as handled so the engine does not
    // terminate the isolate.
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Platform error: $error\n$stack');
      return true;
    };

    // media_kit requires a one-time native init before any Player is
    // created — previously missing, which would crash the anime player.
    try {
      MediaKit.ensureInitialized();
    } catch (e) {
      debugPrint('MediaKit init failed (player disabled): $e');
    }

    // Initialize storage (all 14 Isar schemas) with graceful fallback.
    final storage = StorageProvider();
    try {
      await storage.initDB();
    } catch (e) {
      // If even the fallback fails, still launch the app with an error
      // screen instead of dying silently.
      debugPrint('Database initialization failed: $e');
    }

    // Load the persisted cookie jar (file-backed since the webview-broker
    // removal) so Cloudflare clearances survive restarts. Best-effort —
    // a missing store just starts an empty jar.
    try {
      await MCookieManager().preloadFromDisk();
    } catch (e) {
      debugPrint('Cookie jar load failed (starting empty): $e');
    }

    // First-run bootstrap: default categories, built-in sources (MangaDex),
    // the default extension repository, and download-queue recovery after
    // an unclean shutdown.
    if (storage.isAvailable) {
      try {
        final library = LibraryRepository(storage);
        final sources = SourcesRepository(storage);
        final downloads = downloads_db.DownloadsRepository(storage);
        final repoService = ExtensionRepoService(storage.isar);
        await library.ensureDefaultCategories();
        await sources.ensureBuiltinSources();
        await downloads.recoverOrphans();
        // Seed the official Mangayomi extension repo and sync its catalog so
        // the Browse → Extensions sheet has ~360 entries on first open
        // (previously the repo list was in-memory and always empty).
        try {
          await repoService.ensureDefaultRepo();
          // syncAll contains its own per-repo failures; this catch is the
          // last resort (e.g. the settings row itself unreadable).
          unawaited(repoService.syncAll().catchError((e) {
            debugPrint('Extension repo background sync failed: $e');
          }));
        } catch (e) {
          debugPrint('Extension repo seed/sync failed (non-fatal): $e');
        }
        // Start the download engine — drains the queued download rows
        // (previously enqueued chapters sat "queued" forever).
        try {
          DownloadEngine(storage).start();
        } catch (e) {
          debugPrint('Download engine start failed (non-fatal): $e');
        }
        // Periodic library updates — the Updates screen previously promised
        // a "sync interval" that never existed (only manual pull-to-refresh
        // ran LibraryUpdater.runOnce).
        try {
          LibraryUpdater(
            storage: storage,
            library: library,
            coordinator: ExtensionCoordinator(
              sources: sources,
              library: library,
            ),
          ).start();
        } catch (e) {
          debugPrint('Library updater start failed (non-fatal): $e');
        }
        // Periodic auto-backup — the Settings screen offered a backup
        // interval but nothing ever ran a backup on schedule.
        unawaited(_maybeAutoBackup(storage));
      } catch (e) {
        debugPrint('Bootstrap failed (non-fatal): $e');
      }
    }

    // Set image cache limits (prevents OOM on low-RAM devices). The byte
    // cap (64 MB) does the real memory policing; the ENTRY count must stay
    // high because a manga reader keeps hundreds of small cover thumbs and
    // page images live — at the old 100-entry cap the cache thrashed
    // (evict + re-decode on every scroll back), which read as "janky".
    PaintingBinding.instance.imageCache.maximumSizeBytes = 96 << 20; // 96 MB
    PaintingBinding.instance.imageCache.maximumSize = 1000;

    runApp(
      const ProviderScope(
        child: LuminaApp(),
      ),
    );

    // First successful frame = the app is up. From here on, zone errors are
    // NON-fatal (logged, app continues).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupComplete = true;
    });
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack: $stack');
    // Only a STARTUP failure may show the error screen. Once the app is
    // running, background errors are logged above and the UI is untouched —
    // the previous unconditional runApp() here is what wiped the whole app
    // ("it has to restart") whenever a repo sync / download / updater
    // threw.
    if (_startupComplete) return;
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Lumina Reader encountered an error',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => main(),
                  child: const Text('Restart'),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  });
}

/// Runs a backup when the persisted interval has elapsed since the last
/// one (Settings → Backup interval — previously stored but never acted on).
Future<void> _maybeAutoBackup(StorageProvider storage) async {
  try {
    final settings = await storage.isar.settings.get(227);
    final intervalHours = settings?.backupInterval ?? 168; // default 7 days
    final lastBackup = settings?.backupLastBackupAt ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final intervalMs = intervalHours * 3600 * 1000;
    if (lastBackup != 0 && now - lastBackup < intervalMs) return; // not due

    final service = BackupService(IsarBackupDataSource(storage.isar));
    final bytes = await service.export(const BackupOptions());
    // Write into the app documents directory (not user-visible storage,
    // which would need permissions on Android 10+).
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/autobackup-${DateTime.now().millisecondsSinceEpoch}.lumina');
    await file.writeAsBytes(bytes, flush: true);

    // Record the run + prune old auto-backups (keep the newest 3).
    await storage.isar.writeTxn(() async {
      final s = await storage.isar.settings.get(227);
      if (s == null) return;
      s.backupLastBackupAt = now;
      await storage.isar.settings.put(s);
    });
    final backups = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('autobackup-'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in backups.skip(3)) {
      try {
        await old.delete();
      } catch (_) {}
    }
    debugPrint('Auto-backup written: ${file.path}');
  } catch (e) {
    debugPrint('Auto-backup failed (non-fatal): $e');
  }
}
