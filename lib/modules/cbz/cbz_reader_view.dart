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

import 'dart:async' show Timer, unawaited;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/providers.dart' as data;
import '../../providers/providers.dart' show incognitoModeProvider;

/// Comic-archive (CBZ / ZIP) viewer.
///
/// Loads the archive, keeps only image entries, sorts them with a NATURAL
/// ordering (page 2 before page 10 — plain lexicographic sort breaks comic
/// page sequences with zero-padded and non-padded names mixed) and renders
/// them in a horizontal PageView with pinch-zoom per page.
///
/// Whole-file decode is a deliberate v1 trade-off: comic chapters are
/// typically 5–60 MB, and archive's ZipDecoder needs the central directory
/// in memory anyway. Streaming per-entry extraction can come later if users
/// import library-sized archives.
class CbzReaderView extends StatefulWidget {
  const CbzReaderView({
    super.key,
    required this.path,
    required this.title,
    this.mangaId,
  });

  /// Local file path to the .cbz / .zip archive.
  final String path;
  final String title;

  /// Library entry id — enables progress + history persistence.
  final int? mangaId;

  @override
  State<CbzReaderView> createState() => _CbzReaderViewState();
}

class _CbzReaderViewState extends State<CbzReaderView> {
  final PageController _controller = PageController();

  /// Captured in initState — safe to use from dispose() (reading the
  /// provider scope via context in dispose is not).
  late final ProviderContainer _container;
  bool _containerReady = false;

  /// Decoded page bytes in display order.
  List<Uint8List> _pages = const [];

  /// Failure reason when the archive could not be opened (not a zip,
  /// zero images, IO error, ...). Rendered as an actionable error state.
  String? _error;

  int _index = 0;

  // Session tracking for stats (duration + pages turned this session).
  final DateTime _sessionStart = DateTime.now();

  /// Page index when the session began (AFTER the resume jump) — the stats
  /// count only pages turned THIS session. The old hardcoded 0 counted the
  /// resume offset as freshly-read on every reopened comic.
  int _sessionStartIndex = 0;
  bool _chromeVisible = false;
  Timer? _progressSaver;

  static const Set<String> _imageExtensions = {
    '.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif', '.bmp',
  };

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _containerReady = true;
    _load();
  }

  @override
  void dispose() {
    _progressSaver?.cancel();
    unawaited(_flushProgress(isFinal: true));
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Progress persistence — CBZ reads previously vanished without a trace:
  // no resume position, no history entry.
  // -----------------------------------------------------------------------

  void _scheduleProgressSave() {
    if (widget.mangaId == null) return;
    _progressSaver?.cancel();
    _progressSaver = Timer(const Duration(seconds: 3), _flushProgress);
  }

  Future<void> _flushProgress({bool isFinal = false}) async {
    final id = widget.mangaId;
    if (id == null || _pages.isEmpty || !_containerReady) return;
    final container = _container;
    if (container.read(incognitoModeProvider)) return;
    final progress = ((_index + 1) / _pages.length).clamp(0.0, 1.0);
    try {
      await container
          .read(data.libraryRepositoryProvider)
          .saveBookProgress(
            id,
            currentPage: _index + 1,
            totalPages: _pages.length,
            progress: progress,
            isFinished: _index >= _pages.length - 1,
          );
      if (isFinal) {
        final manga = await container.read(data.libraryRepositoryProvider).getManga(id);
        if (manga != null) {
          await container.read(data.historyRepositoryProvider).recordRead(
            mangaId: id,
            chapterId: 0,
            chapterName: 'Page ${_index + 1}',
            chapterNumber: (_index + 1).toDouble(),
            mangaTitle: manga.title,
            mangaCover: manga.thumbnailUrl,
            isAnime: false,
            progress: progress,
            page: _index + 1,
            totalPages: _pages.length,
          );
        }
        // Stats: CBZ sessions previously NEVER reached the stats pipeline
        // (reading a whole imported comic moved nothing on the stats page).
        final seconds =
            DateTime.now().difference(_sessionStart).inSeconds;
        if (seconds >= 10) {
          await container.read(data.statsRepositoryProvider).recordSession(
            mangaId: id,
            pagesRead: (_index - _sessionStartIndex).clamp(0, 10000),
            durationSeconds: seconds.clamp(1, 60 * 60 * 6),
          );
        }
      }
    } catch (e) {
      // Persistence must never break reading.
      debugPrint('CBZ reader flush failed: $e');
    }
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      if (!await file.exists()) {
        throw StateError('File not found: ${widget.path}');
      }
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());

      final entries = <(String, ArchiveFile)>[];
      for (final entry in archive) {
        if (entry.isFile) {
          final name = entry.name.toLowerCase();
          if (_imageExtensions.any(name.endsWith)) {
            entries.add((entry.name, entry));
          }
        }
      }
      if (entries.isEmpty) {
        throw StateError('No images found inside the archive. '
            'CBZ files must contain image files (jpg / png / webp).');
      }

      // Natural sort: split the entry name into digit / non-digit chunks so
      // "9.jpg" sorts before "10.jpg".
      entries.sort((a, b) => compareNatural(a.$1, b.$1));

      final pages = <Uint8List>[
        for (final e in entries)
          Uint8List.fromList(e.$2.content as List<int>),
      ];

      if (!mounted) return;
      // Resume at the last-read page (previously CBZ always reopened at
      // page 1 with no trace of the previous session).
      var initialIndex = 0;
      final id = widget.mangaId;
      if (id != null) {
        try {
          final (page, total) =
              await _container.read(data.libraryRepositoryProvider).getBookProgress(id);
          if (total == pages.length && page > 1 && page <= pages.length) {
            initialIndex = page - 1;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _error = null;
        _index = initialIndex;
        _sessionStartIndex = initialIndex;
      });
      if (initialIndex > 0) {
        // Deferred: on first load the PageView may not be mounted yet when
        // the async archive read resolves — jumping immediately (controller
        // without clients) throws, skipping silently loses the resume
        // position. Post-frame the view exists and the jump lands.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.hasClients) {
            _controller.jumpToPage(initialIndex);
          }
        });
      }
      unawaited(WakelockPlus.enable());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFF101010),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: GestureDetector(
          onTap: () => setState(() => _chromeVisible = !_chromeVisible),
          child: Stack(
            children: [
              _body(),
              if (_chromeVisible) ..._chrome(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined,
                  size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              const Text(
                'Could not open this archive',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () {
                  setState(() => _error = null);
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return PageView.builder(
      controller: _controller,
      itemCount: _pages.length,
      onPageChanged: (i) {
        setState(() => _index = i);
        _scheduleProgressSave();
      },
      // ExtendedImage (same engine as the main reader): gesture zoom/pan
      // that cooperates with the PageView instead of the old
      // InteractiveViewer, which fought page swipes and — with
      // clipBehavior: Clip.none — bled zoomed pages over neighbouring UI.
      // Fit-width matches the main reader's industry-standard default.
      itemBuilder: (context, i) => ExtendedImage.memory(
        _pages[i],
        fit: BoxFit.fitWidth,
        mode: ExtendedImageMode.gesture,
        enableSlideOutPage: true,
        onDoubleTap: (state) {
          final pos = state.pointerDownPosition;
          final begin = state.gestureDetails?.totalScale ?? 1.0;
          state.handleDoubleTap(
            scale: begin == 1.0 ? 2.2 : 1.0,
            doubleTapPosition: pos,
          );
        },
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.failed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image,
                      size: 56, color: Colors.white38),
                  TextButton(
                      onPressed: state.reLoadImage,
                      child: const Text('Retry')),
                ],
              ),
            );
          }
          return state.completedWidget;
        },
        initGestureConfigHandler: (state) => GestureConfig(
          minScale: 0.9,
          animationMinScale: 0.7,
          maxScale: 6.0,
          animationMaxScale: 6.5,
          speed: 1.0,
          inertialSpeed: 100.0,
          initialScale: 1.0,
          inPageView: true,
        ),
      ),
    );
  }

  List<Widget> _chrome(BuildContext context) {
    return [
      // Top bar.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // Bottom page indicator + slider.
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${_index + 1} / ${_pages.length}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: Slider(
                      value: _pages.isEmpty
                          ? 0
                          : _index.toDouble().clamp(0, _pages.length - 1),
                      max: _pages.isEmpty ? 1 : (_pages.length - 1).toDouble(),
                      onChanged: (v) {
                        final page = v.round();
                        if (page != _index) {
                          _controller.jumpToPage(page);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: _index >= _pages.length - 1
                        ? null
                        : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Natural (human) string ordering: digit chunks compare numerically,
/// everything else lexicographically. Case-insensitive.
int compareNatural(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final aDigit = a.codeUnitAt(i) >= 0x30 && a.codeUnitAt(i) <= 0x39;
    final bDigit = b.codeUnitAt(j) >= 0x30 && b.codeUnitAt(j) <= 0x39;
    if (aDigit && bDigit) {
      // Consume full digit runs.
      var ai = i;
      while (ai < a.length &&
          a.codeUnitAt(ai) >= 0x30 &&
          a.codeUnitAt(ai) <= 0x39) {
        ai++;
      }
      var bj = j;
      while (bj < b.length &&
          b.codeUnitAt(bj) >= 0x30 &&
          b.codeUnitAt(bj) <= 0x39) {
        bj++;
      }
      final aNum = int.tryParse(a.substring(i, ai)) ?? 0;
      final bNum = int.tryParse(b.substring(j, bj)) ?? 0;
      if (aNum != bNum) return aNum.compareTo(bNum);
      i = ai;
      j = bj;
    } else {
      final cmp = a[i].toLowerCase().compareTo(b[j].toLowerCase());
      if (cmp != 0) return cmp;
      i++;
      j++;
    }
  }
  return a.length.compareTo(b.length);
}
