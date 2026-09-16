// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// No-op extension service. Returned by getExtensionService() when a source
// cannot be executed (unsupported language, missing code, or a backend that
// is not available in this build). Never throws — callers get empty results
// and can surface [reason] to the user.

import 'package:lumina_reader/eval/base_service.dart';

class NullExtensionService extends BaseExtensionService {
  NullExtensionService(super.source, {this.reason = 'Source unavailable.'});

  /// Human-readable explanation shown in logs / UI.
  final String reason;

  @override
  String toString() => 'NullExtensionService(${source.displayName}: $reason)';
}
