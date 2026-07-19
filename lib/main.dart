// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/storage_provider.dart';

void main() async {
  // Error boundary — NEVER crash to a black screen
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize storage (Isar database)
    try {
      await StorageProvider().initDB();
    } catch (e) {
      // If DB fails, still launch the app with an error screen
      debugPrint('Database initialization failed: $e');
    }

    // Set image cache limits (prevents OOM on low-RAM devices)
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
