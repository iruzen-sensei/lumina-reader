// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Minimal port of upstream Mangayomi's utils/extensions/others.dart — only
// the pieces the extension runtime actually consumes (Map/Dart-Future
// coercion helpers used by the JS bridge and extractors).

import 'dart:convert';

extension MapExtensions on Map? {
  /// Shallow JSON-decode of a nested dynamic map (JS interop results).
  Map<String, dynamic>? get toMapStringDynamic {
    final m = this;
    if (m == null) return null;
    return m.map((k, v) => MapEntry(k.toString(), v));
  }

  Map<String, String>? get toMapStringString {
    final m = this;
    if (m == null) return null;
    return m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }
}

extension ListExtensions on List? {
  List<String>? get toListString {
    final l = this;
    if (l == null) return null;
    return l.map((e) => e.toString()).toList();
  }
}

extension DynamicExtensions on dynamic {
  /// Best-effort `toString` for JS round-trips.
  String? get asString => this == null ? null : toString();
}

/// Decodes a JSON string that may carry a top-level list or map.
dynamic tryJsonDecode(String input) {
  try {
    return jsonDecode(input);
  } catch (_) {
    return null;
  }
}
