// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// SETTINGS REPOSITORY — single-row settings persistence (id = 227).
// Loads defaults merged with whatever the user actually saved; saves are
// field-explicit so a schema evolution can never wipe unknown fields.

import 'package:isar/isar.dart';

import '../models/mappers.dart' as map;
import '../models/settings.dart' as db;
import '../providers/storage_provider.dart';

class SettingsRepository {
  SettingsRepository(StorageProvider storage) : _isar = storage.isar;
  final Isar _isar;

  static const int _settingsId = 227;

  /// Loads the settings row, falling back to defaults for never-set fields.
  Future<db.Settings> load() async {
    final saved = await _isar.settings.get(_settingsId);
    return map.mergeSettings(db.Settings.defaults(), saved);
  }

  /// Persists a full settings row (write-all; the row IS the source of truth
  /// once the user has changed anything).
  Future<void> save(db.Settings settings) async {
    settings.id = _settingsId;
    settings.lastUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    await _isar.writeTxn(() async {
      await _isar.settings.put(settings);
    });
  }

  /// Targeted mutation helper: loads, applies [mutate], persists.
  Future<void> update(Future<void> Function(db.Settings s) mutate) async {
    final s = await load();
    await mutate(s);
    await save(s);
  }

  Stream<void> watch() {
    return _isar.settings.watchLazy(fireImmediately: true);
  }
}
