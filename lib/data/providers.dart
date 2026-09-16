// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// DATA-LAYER RIVERPOD WIRING — one provider per repository. Constructed
// lazily AFTER the database is initialized (see databaseProvider). Every
// UI-level provider depends on these; nothing else may touch Isar.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/storage_provider.dart';
import 'downloads_repository.dart';
import 'history_repository.dart';
import 'library_repository.dart';
import 'notes_repository.dart';
import 'settings_repository.dart';
import 'sources_repository.dart';
import 'stats_repository.dart';

// Re-export the repositories (and the storage bootstrap) so consumers can
// reach everything through the single `data` namespace.
export '../providers/storage_provider.dart';
export 'downloads_repository.dart';
export 'history_repository.dart';
export 'library_repository.dart';
export 'notes_repository.dart';
export 'settings_repository.dart';
export 'sources_repository.dart';
export 'stats_repository.dart';

/// The singleton StorageProvider (initialized in main.dart before runApp).
final storageProvider = Provider<StorageProvider>((ref) => StorageProvider());

/// True when the database is running on the fallback (temporary) store.
/// Screens can show a non-intrusive warning banner when this is true.
final databaseFallbackProvider = Provider<bool>(
  (ref) => ref.watch(storageProvider).isFallback,
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(storageProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(storageProvider)),
);

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => NotesRepository(ref.watch(storageProvider)),
);

final sourcesRepositoryProvider = Provider<SourcesRepository>(
  (ref) => SourcesRepository(ref.watch(storageProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(storageProvider)),
);

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(storageProvider)),
);

final downloadsRepositoryProvider = Provider<DownloadsRepository>(
  (ref) => DownloadsRepository(ref.watch(storageProvider)),
);
