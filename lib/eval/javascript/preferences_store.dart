// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Per-source preference VALUES for extension-backed sources.
//
// Port of upstream Mangayomi's extension_preferences_providers, backed by
// the Isar [Source] row itself (`sourcePreferencesJson`: a JSON
// `{key: value}` map) instead of separate preference tables. JS extensions
// reach this through the `SharedPreferences` glue class.

import 'dart:convert';

import 'package:isar/isar.dart';

import 'package:lumina_reader/models/source.dart';
import 'package:lumina_reader/providers/storage_provider.dart';

Map<String, dynamic> _readMap(int sourceId) {
  final isar = StorageProvider().isar;
  final row = isar.sources.getSync(sourceId);
  final raw = row?.sourcePreferencesJson;
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  } catch (_) {
    return {};
  }
}

Future<void> _writeMap(int sourceId, Map<String, dynamic> values) async {
  final isar = StorageProvider().isar;
  await isar.writeTxn(() async {
    final row = await isar.sources.get(sourceId);
    if (row == null) return;
    row.sourcePreferencesJson = values.isEmpty ? null : jsonEncode(values);
    await isar.sources.put(row);
  });
}

/// JS `SharedPreferences.get(key)` — returns the stored value (any JSON
/// type) or null.
dynamic getPreferenceValue(int sourceId, String key) =>
    _readMap(sourceId)[key];

/// JS `SharedPreferences.getString(key, default)` — string flavour.
String getSourcePreferenceStringValue(
    int sourceId, String key, dynamic defaultValue) {
  final v = _readMap(sourceId)[key];
  return v?.toString() ?? defaultValue?.toString() ?? '';
}

/// JS `SharedPreferences.setString(key, value)`.
Future<void> setSourcePreferenceStringValue(
    int sourceId, String key, dynamic value) async {
  final map = _readMap(sourceId);
  map[key] = value?.toString();
  await _writeMap(sourceId, map);
}

/// Writes a batch of preference values (used by the preferences UI).
Future<void> setPreferenceValues(
    int sourceId, Map<String, dynamic> values) async {
  final map = _readMap(sourceId);
  map.addAll(values);
  await _writeMap(sourceId, map);
}
