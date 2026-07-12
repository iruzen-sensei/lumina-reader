// Copyright 2023 Moustapha Kodjo Amadou (Mangayomi, Apache-2.0)
// Modified for Lumina Reader, Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Riverpod 2.x providers for the MClient stack.
///
/// Provides:
///   * [cookieManagerProvider] — process-wide singleton for [CookieManager].
///   * [cloudflareSolverProvider] — singleton for the headless WebView solver.
///   * [mClientFamilyProvider] — per-source [MClient] cache, kept warm
///     across widgets.
///   * [mClientStateStreamProvider] — live stream of [MClientState]
///     events for the diagnostics panel.
///   * [httpClientBootstrapProvider] — one-shot future that ensures
///     [CookieManager.bootstrap] has run before any HTTP traffic is sent.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'm_client.dart';

/// Boots [CookieManager] exactly once per process. Most providers depend
/// on this so they can assume cookies are wired up.
final httpClientBootstrapProvider = FutureProvider<Unit>((ref) async {
  ref.keepAlive();
  await CookieManager.bootstrap();
  return const Unit();
});

/// Process-wide [CookieManager] singleton. Reads back from
/// [httpClientBootstrapProvider] to force initialisation ordering.
final cookieManagerProvider = FutureProvider<CookieManager>((ref) async {
  await ref.watch(httpClientBootstrapProvider.future);
  return CookieManager.instance;
});

/// Singleton [CloudflareSolver] — one WebView budget for the whole app.
final cloudflareSolverProvider = Provider<CloudflareSolver>((ref) {
  ref.keepAlive();
  return CloudflareSolver.instance;
});

/// Per-source [MClient] cache. Use the `family` overload with the source
/// id; the client stays alive as long as a listener is attached, then
/// disposes when the last listener goes away.
///
/// Callers that need the client to outlive widget rebuilds (e.g. the
/// download manager) should hold a `ProviderSubscription` rather than the
/// client itself.
final mClientFamilyProvider =
    FutureProvider.family<MClient, MClientKey>((ref, key) async {
  // Make sure cookies are bootstrapped before the client ever reads them.
  await ref.watch(cookieManagerProvider.future);

  final client = await MClient.forSource(
    key.sourceId,
    uaProfile: key.uaProfile,
    customUserAgent: key.customUserAgent,
    defaultHeaders: key.defaultHeaders,
  );

  // Keep the client warm across rebuilds while at least one subscriber
  // remains; auto-dispose otherwise.
  ref.keepAlive();

  // Wire the client's state stream into the global tap below so the
  // diagnostics panel can render a single merged feed.
  final stateSub = client.stateStream.listen((state) {
    _globalStateBus.add(state);
  });

  ref.onDispose(() {
    stateSub.cancel();
  });

  return client;
});

/// Identity key for [mClientFamilyProvider]. Two equal keys collapse to a
/// single cached [MClient] instance.
class MClientKey {
  final String sourceId;
  final UserAgentProfile uaProfile;
  final String? customUserAgent;
  final Map<String, String> defaultHeaders;

  const MClientKey({
    required this.sourceId,
    this.uaProfile = UserAgentProfile.desktop,
    this.customUserAgent,
    this.defaultHeaders = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MClientKey &&
          runtimeType == other.runtimeType &&
          sourceId == other.sourceId &&
          uaProfile == other.uaProfile &&
          customUserAgent == other.customUserAgent &&
          _mapEquals(defaultHeaders, other.defaultHeaders);

  @override
  int get hashCode => Object.hash(
        sourceId,
        uaProfile,
        customUserAgent,
        Object.hashAllUnordered(
          defaultHeaders.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Convenience synchronous accessor — returns the cached client if it's
/// already been initialised for [sourceId], otherwise returns null and the
/// caller should fall back to `ref.read(mClientFamilyProvider(key).future)`.
MClient? peekMClient(WidgetRef ref, String sourceId) {
  final key = MClientKey(sourceId: sourceId);
  final container = ref.container;
  try {
    final asyncValue = container.read(mClientFamilyProvider(key));
    return asyncValue.maybeWhen(
      data: (client) => client,
      orElse: () => null,
    );
  } catch (_) {
    return null;
  }
}

/// Global event bus carrying every [MClientState] event from every active
/// client. The Settings → Network → Diagnostics panel listens on this.
final _globalStateBus = StreamController<MClientState>.broadcast();

/// Read-only stream of [MClientState] events across all live clients.
///
/// The underlying [_globalStateBus] is a process-wide broadcast stream
/// that lives for the lifetime of the app; Riverpod manages listener
/// wiring on top.
final mClientStateStreamProvider = StreamProvider<MClientState>((ref) {
  return _globalStateBus.stream;
});

/// Per-source state stream — emits only events from the source identified
/// by [sourceId]. Used by the per-source settings sheet.
final perSourceStateStreamProvider =
    StreamProvider.family<MClientState, String>((ref, sourceId) async* {
  // Force the client to exist for this source — otherwise the stream
  // would be empty.
  await ref.watch(mClientFamilyProvider(
    MClientKey(sourceId: sourceId),
  ).future);

  yield* _globalStateBus.stream.where((s) => s.sourceId == sourceId);
});

/// Helper that wipes cookies for a single source. Safe to call from a
/// button tap in the settings sheet.
Future<void> clearCookiesForSource(WidgetRef ref, String sourceId) async {
  final jar = CookieManager.instance.jarFor(sourceId);
  jar.clear();
  await jar.flush();
}

/// Helper that wipes every cookie in the process. Used by Settings →
/// Privacy → Clear all site data.
Future<void> clearAllCookies(WidgetRef ref) async {
  await CookieManager.instance.clearAll();
  if (kDebugMode) {
    debugPrint('m_client_provider: cleared all cookies');
  }
}

/// Riverpod `Unit` stand-in — `package:riverpod` doesn't export one and we
/// don't want to depend on `dartz` just for a sentinel.
class Unit {
  const Unit();
}
