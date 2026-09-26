// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0
//
// Minimal xpath shim for the ported video-host extractors. Every query in
// the extractor corpus is of the form
//     //script[contains(text(), "X")]/text()
// so the full xpath_selector engine is replaced by an html-package scan —
// zero new dependencies, identical behaviour for the used surface.

import 'package:html/parser.dart';

/// Result of a query: the matched text nodes.
class XPathResult {
  XPathResult(this._values);

  final List<String> _values;

  String? get attr => _values.isEmpty ? null : _values.first;

  List<String?> get attrs => _values;

  bool get isEmpty => _values.isEmpty;
}

class _XPathShim {
  _XPathShim(this._html);

  final String _html;

  XPathResult queryXPath(String query) {
    // Supported pattern: //script[contains(text(), "X")]/text()
    final m = RegExp(
      r'^//script\[contains\(text\(\),\s*"((?:[^"\\]|\\.)*)"\)\]/text\(\)$',
    ).firstMatch(query.trim());
    if (m == null) {
      return XPathResult(const []);
    }
    final needle = m.group(1)!.replaceAll('\\"', '"');
    final doc = parse(_html);
    final values = <String>[];
    for (final script in doc.querySelectorAll('script')) {
      final text = script.text;
      if (text.contains(needle) && text.trim().isNotEmpty) {
        values.add(text);
      }
    }
    return XPathResult(values);
  }
}

_XPathShim xpathSelector(String html) => _XPathShim(html);
