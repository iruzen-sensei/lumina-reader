// Compile smoke test: forces the Dart compiler to fully compile the app's
// library graph (every screen, provider, service and model reachable from
// main.dart) against the real Flutter VM. If any file in the graph fails to
// compile, this test fails with the underlying compiler error.
//
// This catches what `flutter analyze` cannot: constant evaluation errors,
// bad isar-generated code wiring, and mirror/reflectable misuse.

import 'package:flutter_test/flutter_test.dart';

import 'package:lumina_reader/main.dart' as app;

void main() {
  test('app library graph compiles', () {
    // Touching a public symbol proves the library was linked.
    expect(app.main, isA<Function>());
  });
}
