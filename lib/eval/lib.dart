/*
 * Lumina Reader - A Mangayomi fork
 * Copyright (C) 2024 Lumina Reader Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Original Mangayomi source: Copyright (c) 2023-2024 kodjode33
 * SPDX-License-Identifier: Apache-2.0
 */

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/interface.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/madara_source.dart';
import 'package:lumina_reader/eval/native/mangadex_source.dart';
import 'package:lumina_reader/eval/native/mangareader_source.dart';
import 'package:lumina_reader/eval/null_extension_service.dart';
import 'package:lumina_reader/models/source.dart';

export 'package:lumina_reader/eval/base_service.dart';
export 'package:lumina_reader/eval/null_extension_service.dart';

// NOTE: the d4rt (Dart interpreter) backend was removed — every published
// d4rt version conflicts with isar_generator's analyzer constraints and the
// backend was parked as experimental. Dart-language extension sources route
// to NullExtensionService below with an honest reason.

/// Built-in native sources, keyed by their `builtin:` scheme identifier
/// (stored in [Source.sourceCode]). Native sources are pure Dart and speak
/// the [ExtensionService] interface directly — no interpreter involved.
///
/// The `builtin:<template>` multisrc entries power the Mangayomi extension
/// repo ecosystem: `madara` covers 151 repo extensions, `mangareader` 87 —
/// installing an extension just persists a configured Source row (see
/// ExtensionRepoService), no code download or interpreter needed.
final Map<String, BaseExtensionService Function(Source)> _nativeSources = {
  'builtin:mangadex': (s) => MangaDexSource(s),
  'builtin:madara': (s) => MadaraSource(s),
  'builtin:mangareader': (s) => MangaReaderSource(s),
};

/// Multisrc template identifiers natively supported by this build — repo
/// entries whose `typeSource` is in this set can be installed and will run
/// through the corresponding `builtin:` implementation above.
const Set<String> kSupportedTemplates = {
  'madara',
  'mangareader',
  // MangaDex sites in the repo use a JS single-source; we ship a native
  // MangaDex implementation instead (installed as builtin.mangadex).
  'mangadex',
};

/// Creates the appropriate [ExtensionService] for the given [source].
///
/// Dispatch order:
///
///   1. `sourceCode` starting with `builtin:` → native Dart source
///      (see eval/native/). This is the primary, fully-supported path.
///   2. [SourceCodeLanguage.javascript] / [SourceCodeLanguage.dart] →
///      interpreter-backed services. NOTE: the interpreter backends are
///      parked as EXPERIMENTAL in this build — their routing is kept so a
///      validated interpreter can be enabled by flipping this switch, but
///      until then JS/Dart-code sources degrade to [NullExtensionService]
///      with an honest reason instead of crashing.
///   3. `null` / unknown → [NullExtensionService].
ExtensionService getExtensionService(Source source) {
  // 1. Built-in native sources — either the explicit `builtin:` scheme or a
  //    repo-installed row whose typeSource maps to a native template.
  final code = source.displaySourceCode;
  if (code != null && code.startsWith('builtin:')) {
    final factory = _nativeSources[code];
    if (factory != null) return factory(source);
    return NullExtensionService(source,
        reason: 'Unknown built-in source "$code".');
  }
  final template = source.typeSource?.toLowerCase();
  if (template != null && kSupportedTemplates.contains(template)) {
    final factory = _nativeSources['builtin:$template'];
    if (factory != null) {
      // MangaDex repo rows reuse the native MangaDex implementation.
      if (template == 'mangadex') return MangaDexSource(source);
      return factory(source);
    }
  }

  // 2. Interpreter-backed sources (EXPERIMENTAL — see class docs).
  switch (source.sourceCodeLanguage) {
    case SourceCodeLanguage.javascript:
      // QuickJS backend (eval/javascript/) compiles but is not yet
      // runtime-validated. Enable by constructing JsExtensionService here
      // once validated on device.
      return NullExtensionService(source,
          reason: 'JS interpreter sources are experimental in this build; '
              'only built-in native sources are active.');
    case SourceCodeLanguage.dart:
      return NullExtensionService(source,
          reason: 'The Dart interpreter backend is not available in this '
              'build; only built-in native sources are active.');
    case SourceCodeLanguage.lua:
      // Lua extensions are not supported, but we honour the enum so
      // user-installed sources never crash on launch.
      return NullExtensionService(source,
          reason: 'Lua extensions are not supported in this build of '
              'Lumina Reader.');
    case null:
      return NullExtensionService(source,
          reason: 'Source has no code path or inline source code and '
              'cannot be loaded.');
  }
}

/// Type-check variant of [getExtensionService] for hosts that need to know
/// whether the returned service can actually execute extension code.
({ExtensionService service, bool isFunctional}) tryGetExtensionService(
    Source source) {
  final service = getExtensionService(source);
  return (service: service, isFunctional: service is! NullExtensionService);
}

/// Convenience: converts an Isar [Source] row into the eval-layer [MSource]
/// metadata DTO (used by interpreter services and diagnostics).
MSource sourceToMSource(Source s) => MSource(
      id: s.idString ?? s.id.toString(),
      name: s.displayName,
      baseUrl: s.displayBaseUrl,
      lang: s.lang,
    );
