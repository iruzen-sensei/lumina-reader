// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Riverpod wiring for the MClient HTTP stack.
//
// REWRITTEN: the previous version targeted a phantom MClient API
// (bootstrap/instance/stateStream members that never existed in
// m_client.dart) and therefore could not compile. This version wires the
// REAL API.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'm_client.dart';

/// A shared, cookie-managed, Cloudflare-retrying HTTP client for general
/// app use (sources go through MClient.forSource instead).
final httpProvider = Provider<http.Client>((ref) {
  final client = MClient.httpClient(useLogger: false);
  ref.onDispose(client.close);
  return client;
});

/// Access to the shared cookie manager (read cookies, set cookies, purge).
final cookieManagerProvider = Provider<MCookieManager>(
  (ref) => MClient.cookieManager,
);

/// Clears every cookie for every host (used by Settings → Clear cookies).
final clearAllCookiesProvider = Provider<Future<void> Function()>(
  (ref) => deleteAllCookies,
);

/// Per-source client family (extensions must use this so their cookies and
/// lifetime are managed centrally; see MClient.forSource).
final sourceClientProvider =
    Provider.family<http.Client, int>((ref, sourceId) {
  final client = MClient.forSource(sourceId);
  // NOTE: per-source clients are cached inside MClient and intentionally
  // NOT closed on dispose — closing would break other holders of the same
  // cached instance. Use MClient.closeAllSourceClients() for a full purge.
  return client;
});

/// Submits a Cloudflare challenge to the WebView broker (advanced use).
final cloudflareSolverProvider =
    Provider<Future<Map<String, String>> Function(Uri url)>(
  (ref) => (url) => solveCloudFlare(url),
);
