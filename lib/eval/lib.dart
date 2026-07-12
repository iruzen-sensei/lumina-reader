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

import 'package:lumina_reader/eval/interface.dart';
import 'package:lumina_reader/eval/js_extension_service.dart';
import 'package:lumina_reader/eval/dart_extension_service.dart';
import 'package:lumina_reader/eval/null_extension_service.dart';
import 'package:lumina_reader/models/source.dart';

/// Creates the appropriate [ExtensionService] for the given [source].
///
/// The dispatch is performed on [Source.sourceCodeLanguage]:
///
///   * [SourceCodeLanguage.javascript] → [JsExtensionService]
///   * [SourceCodeLanguage.dart]       → [DartExtensionService]
///   * `null` / unknown               → [NullExtensionService]
///
/// Implementations are cached on a per-[Source.id] basis by the host (see
/// `ExtensionServiceProvider`) so callers may invoke this factory freely
/// without worrying about extension re-initialisation.
ExtensionService getExtensionService(Source source) {
  switch (source.sourceCodeLanguage) {
    case SourceCodeLanguage.javascript:
      return JsExtensionService(source);
    case SourceCodeLanguage.dart:
      return DartExtensionService(source);
    case SourceCodeLanguage.lua:
      // Lua extensions are not yet supported by Lumina Reader, but we still
      // honour the enum so user-installed sources do not crash on launch.
      return NullExtensionService(source, reason: 'Lua extensions are '
          'not supported in this build of Lumina Reader.');
    case null:
      // Sources with an unknown language code are treated as JS by default
      // to preserve compatibility with legacy source repositories.
      if (source.codePath != null || source.sourceCode != null) {
        return JsExtensionService(source);
      }
      return NullExtensionService(source, reason: 'Source has no code path '
          'or inline source code and cannot be loaded.');
  }
}

/// Type-check variant of [getExtensionService] for hosts that need to know
/// whether the returned service can actually execute extension code.
({ExtensionService service, bool isFunctional}) tryGetExtensionService(
    Source source) {
  final service = getExtensionService(source);
  return (service: service, isFunctional: service is! NullExtensionService);
}
