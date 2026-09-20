// Copyright 2024 Lumina Reader Contributors
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

import 'dart:async';

import 'package:flutter/material.dart';

/// The signature black footer of the reference design
/// (andreirybin.com): a full-bleed #000000 block with quiet gray rows and
/// a LIVE CLOCK ticking every second.
///
/// Reference anatomy, translated to the app:
///   * top row    - "Lumina Reader" (gray) + live clock on the left,
///                  "Let's keep reading" centred, a one-line note right
///   * middle     - the vast black void (breathing room)
///   * bottom row - "(c) <year>" left, "Reading, without noise" centre,
///                  "AniList / MangaDex / Local" right
///
/// The whole block is monochrome: #000000 ground, #8E8E90 text, one
/// #0099FF link accent — no other colour is permitted in here.
class RybinFooter extends StatefulWidget {
  const RybinFooter({super.key, this.tagline = "Let's keep reading"});

  /// Centre message of the top row ("Let's stay in touch" in the
  /// reference).
  final String tagline;

  @override
  State<RybinFooter> createState() => _RybinFooterState();
}

class _RybinFooterState extends State<RybinFooter> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _clockText() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    const gray = Color(0xFF8E8E90);
    const link = Color(0xFF0099FF);

    Widget label(String text, {Color color = gray}) => Text(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            letterSpacing: -0.2,
            fontWeight: FontWeight.w400,
            color: color,
          ),
        );

    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Top row: identity + live clock | tagline | quiet note ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Lumina Reader'),
                      const SizedBox(height: 2),
                      // The LIVE CLOCK — same treatment as the reference
                      // footer: quiet gray digits, ticking every second.
                      Text(
                        _clockText(),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          letterSpacing: -0.2,
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: gray,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(child: label(widget.tagline)),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Local-first. No account\nrequired. Your library\nstays on your device.',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          letterSpacing: -0.2,
                          color: gray,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // -- The vast black void (the reference's breathing room) -----
            const SizedBox(height: 56),

            // -- Bottom row: (c) | centre note | sources ------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: label('\u00a9 $year')),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Reading, without noise',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        letterSpacing: -0.2,
                        color: gray,
                      ),
                    ),
                  ),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Sources/AniList, MangaDex',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          letterSpacing: -0.2,
                          color: gray,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'GitHub',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          letterSpacing: -0.2,
                          color: link,
                          decoration: TextDecoration.underline,
                          decorationColor: link,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
