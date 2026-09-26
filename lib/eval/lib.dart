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

import 'dart:io' show Platform;

import 'package:lumina_reader/eval/base_service.dart';
import 'package:lumina_reader/eval/interface.dart';
import 'package:lumina_reader/eval/javascript/service.dart';
import 'package:lumina_reader/eval/mihon/service.dart';
import 'package:lumina_reader/eval/model/m_models.dart';
import 'package:lumina_reader/eval/native/anizone_source.dart';
import 'package:lumina_reader/eval/native/madara_source.dart';
import 'package:lumina_reader/eval/native/mangabox_source.dart';
import 'package:lumina_reader/eval/native/mangadex_source.dart';
import 'package:lumina_reader/eval/native/mangareader_source.dart';
import 'package:lumina_reader/eval/native/mmrcms_source.dart';
import 'package:lumina_reader/eval/null_extension_service.dart';
import 'package:lumina_reader/models/source.dart';
import 'package:lumina_reader/services/extension_server.dart';

export 'package:lumina_reader/eval/base_service.dart';
export 'package:lumina_reader/eval/null_extension_service.dart';

// NOTE: the d4rt (Dart interpreter) backend is not shipped — Dart-language
// extension sources (the madara/mangareader .dart multisrc singles beyond
// the native templates) route to NullExtensionService with an honest
// reason. The madara/mangareader templates they describe are covered
// natively by eval/native/.

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
  'builtin:mangabox': (s) => MangaBoxSource(s),
  'builtin:mmrcms': (s) => MmrcmsSource(s),
  // Anilili-style anime streaming: AniList catalog + AniZone streams.
  'builtin:anizone': (s) => AniZoneSource(s),
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
  // Classic "MangaBox" family (Mangabat / Mangakakalot / Manganato /
  // Mangairo) — live-verified against mangabats.com.
  'mangabox',
  // MMRCMS family (scan-vf.net, onma.top, readcomicsonline.ru) —
  // live-verified against scan-vf.net.
  'mmrcms',
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

  // MangaDex LANGUAGE VARIANTS: 45 of the repo's `single` entries are the
  // same MangaDex site in different languages (baseUrl = mangadex.org with
  // a per-language sourceCode). Routing them through the native MangaDex
  // template turns 45 "Not supported" rows into working extensions.
  final baseUrl = (source.displayBaseUrl).toLowerCase();
  if (baseUrl.contains('mangadex.org')) {
    return MangaDexSource(source);
  }

  // 2. Interpreter-backed sources.
  switch (source.sourceCodeLanguage) {
    case SourceCodeLanguage.javascript:
      // QuickJS host (eval/javascript/) — the Mangayomi JS extension
      // ecosystem runs for real: Client/Document/SharedPreferences/extractor
      // glue is ported from upstream, and the source code (fetched at
      // install time) lives in source.displaySourceCode.
      final code = source.displaySourceCode;
      if (code == null || code.trim().isEmpty) {
        return NullExtensionService(source,
            reason: 'JS extension has no source code — reinstall it from '
                'the extension manager.');
      }
      return JsExtensionService(source);
    case SourceCodeLanguage.mihon:
      // Aniyomi/Mihon APK extension — runs through the on-device Dex class
      // loader bridge (services/extension_server.dart + eval/mihon/).
      final apk = source.sourceCode;
      if (apk == null || apk.isEmpty) {
        return NullExtensionService(source,
            reason: 'APK extension not downloaded — reinstall it from the '
                'extension manager.');
      }
      if (!Platform.isAndroid) {
        return NullExtensionService(source,
            reason: 'APK extensions only run on Android.');
      }
      return MihonExtensionService(
          source, ExtensionServerRuntime.instance);
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

/// Whether a repo catalog row can run in THIS build — single source of
/// truth for the extension manager UI, the browse catalog sheet and the
/// install flow.
///
/// Supported runtimes:
///   * native multisrc templates (madara / mangareader / mangadex /
///     mangabox / mmrcms)
///   * MangaDex language variants (`single` on mangadex.org)
///   * JavaScript extensions (QuickJS host, eval/javascript/)
///   * Aniyomi/Mihon APK extensions (Dex bridge, eval/mihon/) — Android only
bool isRepoRowSupported(Source s) {
  final template = (s.typeSource ?? '').toLowerCase();
  if (kSupportedTemplates.contains(template)) return true;
  if (template == 'single' &&
      (s.baseUrl ?? '').contains('mangadex.org')) {
    return true;
  }
  switch (s.sourceCodeLanguage) {
    case SourceCodeLanguage.javascript:
      return true;
    case SourceCodeLanguage.mihon:
      return true;
    case SourceCodeLanguage.dart:
    case SourceCodeLanguage.lua:
    case null:
      return false;
  }
}

/// DTO-flavoured variant for UI tiles that hold the view model Source
/// (models/models.dart) instead of the Isar row.
bool isRepoDtoSupported({
  required String? typeSource,
  required String baseUrl,
  required int? sourceCodeLanguage,
}) {
  final template = (typeSource ?? '').toLowerCase();
  if (kSupportedTemplates.contains(template)) return true;
  if (template == 'single' && baseUrl.contains('mangadex.org')) return true;
  return sourceCodeLanguage == 1 || sourceCodeLanguage == 3;
}
