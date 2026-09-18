// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/downloads_repository.dart' as downloads_db;
import 'data/library_repository.dart';
import 'data/sources_repository.dart';
import 'providers/storage_provider.dart';
import 'services/download_engine.dart';
import 'services/extension_repo_service.dart';

void main() async {
  // Error boundary — NEVER crash to a black screen (the HyperOS lesson).
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

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
          unawaited(repoService.syncAll());
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
      } catch (e) {
        debugPrint('Bootstrap failed (non-fatal): $e');
      }
    }

    // Set image cache limits (prevents OOM on low-RAM devices).
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20; // 64 MB
    PaintingBinding.instance.imageCache.maximumSize = 100;

    runApp(
      const ProviderScope(
        child: LuminaApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack: $stack');
    // Show error app instead of black screen
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
