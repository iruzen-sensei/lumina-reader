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
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../data/providers.dart' as data;
import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../shared/widgets.dart';

/// The manga reader.
///
/// Supports three rendering modes — paged ([PageView]), continuous and webtoon
/// (both via [ScrollablePositionedList]) — pinch-to-zoom through
/// [ExtendedImage], configurable tap zones for navigation, an auto-hiding
/// controls overlay, a page indicator and prev/next chapter navigation.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.chapterId,
  });

  /// The chapter to open. The parent manga is resolved from the database
  /// so deep links (`/reader/:chapterId` from history / updates) work.
  final int chapterId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final PageController _pageController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  int _currentPage = 0;
  int _totalPages = 0;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isLoadingChapter = false;
  bool _notFound = false;
  DateTime _sessionStart = DateTime.now();
  Timer? _progressSaveDebounce;

  // Session page accounting — REAL pages turned (the session used to be
  // recorded with `pagesRead: 1`, so the pages stat, the heatmap and the
  // pages-per-day goal all counted one page per session and looked frozen).
  int _sessionStartPage = 0;
  int _sessionMaxPage = 0;

  // Resume target: the persisted lastPageRead for the chapter being opened.
  // The page list arrives ASYNC (totalPages is 0 on first build), so the
  // resume position must be held here and applied on the first non-empty
  // page list — previously the saved position was read, multiplied against
  // a zero page count and silently dropped, so every reopen landed on
  // page 1 ("the app can't keep track of progress").
  int _resumePage = 0;
  bool _resumeApplied = false;

  // Current chapter pointer so chapter navigation can mutate it.
  // Nullable: the async Isar resolve in _loadChapter may not have finished
  // when the first frame builds — every access must be guarded (the previous
  // `late` variant crashed with LateInitializationError on first open).
  Chapter? _chapter;
  Manga? _manga;

  /// Per-source HTTP headers for page images (Madara CDNs need Referer).
  Map<String, String>? _sourceHeaders;

  /// True once [_chapter] has been resolved and assigned.
  bool get _chapterReady => _chapter != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _itemPositionsListener.itemPositions.addListener(_onListPositionsChanged);
    _sessionStart = DateTime.now();
    _loadChapter();
    // Honour the persisted keep-screen-on setting (previously a no-op in
    // this screen — only the never-mounted ReaderView applied it).
    if (ref.read(readerSettingsProvider).keepScreenOn) {
      WakelockPlus.enable();
    }
  }

  /// Lifecycle flush: swiping the app away from Recents does NOT run
  /// dispose() — the reading session (and its stats/heatmap contribution)
  /// was silently lost. `inactive` (notification shade, dialogs, app-switch
  /// peek) only flushes PROGRESS; `hidden`/`paused` (actual backgrounding)
  /// also record the session — otherwise every shade pull fragmented a
  /// separate noisy session row.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _flushProgress();
      _recordSession();
    } else if (state == AppLifecycleState.inactive) {
      _flushProgress();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushProgress();
    _recordSession();
    _progressSaveDebounce?.cancel();
    _pageController.dispose();
    _hideTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onListPositionsChanged);
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadChapter() async {
    setState(() => _isLoadingChapter = true);
    final repo = ref.read(data.libraryRepositoryProvider);
    final (manga, chapter) = await repo.resolveChapter(widget.chapterId);
    if (!mounted) return;
    if (manga == null || chapter == null) {
      setState(() {
        _notFound = true;
        _isLoadingChapter = false;
      });
      return;
    }
    setState(() {
      _manga = manga;
      _chapter = chapter;
      _totalPages = ref.read(readerPagesProvider(chapter.id)).length;
      // Hold the persisted position: pages are not loaded yet, so it cannot
      // be clamped here — it is clamped + applied by the pages listener.
      _resumePage = chapter.lastPageRead.clamp(0, 100000);
      _resumeApplied = false;
      _currentPage =
          _totalPages > 0 ? _resumePage.clamp(0, _totalPages - 1) : 0;
      _isLoadingChapter = _totalPages == 0; // until pages stream in
    });
    _resetPageAccounting();
    unawaited(_recordHistoryRead(0));

    // Resolve the source's HTTP headers (Referer / User-Agent) for page
    // images — scraped CDNs 403 hotlinks without them.
    if (manga.sourceId != 0) {
      unawaited(() async {
        final headers = await ref
            .read(extensionCoordinatorProvider)
            .sourceHeaders(manga.sourceId);
        if (mounted && headers.isNotEmpty) {
          setState(() => _sourceHeaders = headers);
        }
      }());
    }
  }

  void _onListPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions.first;
    if (first.index != _currentPage) {
      setState(() => _currentPage = first.index);
      _trackPage(first.index);
      _onPageSettled();
    }
  }

  /// PageView swipe handler — keeps the page indicator in sync with swipes
  /// (previously swipes never updated `_currentPage`) and schedules the
  /// debounced progress save.
  void _onPagedSwipe(int page) {
    if (page != _currentPage) {
      setState(() => _currentPage = page);
    }
    _trackPage(page);
    _onPageSettled();
  }

  /// Records the furthest page reached this session (monotonic — flipping
  /// back and forth never inflates the count).
  void _trackPage(int page) {
    if (page > _sessionMaxPage) _sessionMaxPage = page;
  }

  /// Starts a fresh page-accounting window (chapter open / switch).
  void _resetPageAccounting() {
    _sessionStartPage = _currentPage;
    _sessionMaxPage = _currentPage;
  }

  /// Captures the resume target for chapter switches via prev/next.
  void _switchChapter(Chapter next, {required bool atEnd}) {
    setState(() {
      _chapter = next;
      _totalPages = ref.read(readerPagesProvider(next.id)).length;
      // atEnd with unknown page count: sentinel clamps to the last page
      // when the list arrives (0 would wrongly resume at page 1).
      _resumePage = atEnd
          ? (_totalPages > 0 ? _totalPages - 1 : 1 << 30)
          : (next.lastPageRead.clamp(0, 100000));
      _resumeApplied = false;
      _currentPage = _totalPages > 0
          ? _resumePage.clamp(0, _totalPages - 1)
          : (atEnd ? _totalPages : 0);
      _isLoadingChapter = _totalPages == 0;
    });
    _resetPageAccounting();
  }

  /// Persists reading progress (debounced — fires at most every 2 s).
  void _onPageSettled() {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(const Duration(seconds: 2), _flushProgress);
  }

  Future<void> _flushProgress() async {
    final chapter = _chapter;
    if (_manga == null || chapter == null || _notFound) return;
    final completed = _totalPages > 0 && _currentPage >= _totalPages - 1;
    try {
      await ref.read(data.libraryRepositoryProvider).saveChapterProgress(
            chapter.id,
            lastPageRead: _currentPage,
            isRead: completed || chapter.isRead,
            pageCount: _totalPages,
          );
      if (completed && !chapter.isRead) {
        chapter.isRead = true;
        await ref.read(data.statsRepositoryProvider).maybeMarkFinished(_manga!.id);
      }
    } catch (e) {
      // Progress persistence is best-effort; never crash the reader — but
      // STOP swallowing failures silently: a broken write pipeline is how
      // "stats never update" bugs hide for months.
      debugPrint('Reader._flushProgress failed: $e');
    }
    // Incremental session flush: stats now move WHILE reading (every 2 min
    // of active reading) instead of only when the reader closes — the
    // "stats still not updating even after reading something" report.
    if (DateTime.now().difference(_sessionStart).inSeconds >= 120) {
      await _recordSession();
    }
    unawaited(_recordHistoryRead(completed ? 1 : 0));
  }

  Future<void> _recordHistoryRead(double progressOverride) async {
    final chapter = _chapter;
    if (ref.read(incognitoModeProvider) || _manga == null || chapter == null) {
      return;
    }
    try {
      final progress = progressOverride > 0
          ? progressOverride
          : (_totalPages > 0 ? _currentPage / _totalPages : 0.0);
      await ref.read(data.historyRepositoryProvider).recordRead(
            mangaId: _manga!.id,
            chapterId: chapter.id,
            chapterName: chapter.name,
            chapterNumber: chapter.number,
            mangaTitle: _manga!.title,
            mangaCover: _manga!.thumbnailUrl,
            isAnime: false,
            progress: progress,
            page: _currentPage,
            totalPages: _totalPages,
          );
    } catch (_) {}
  }

  Future<void> _recordSession() async {
    final chapter = _chapter;
    if (ref.read(incognitoModeProvider) ||
        _manga == null ||
        chapter == null) {
      return;
    }
    final seconds = DateTime.now().difference(_sessionStart).inSeconds;
    if (seconds < 5) return;
    final pagesThisSession = _sessionMaxPage - _sessionStartPage;
    _sessionStart = DateTime.now();
    _resetPageAccounting();
    try {
      await ref.read(data.statsRepositoryProvider).recordSession(
        mangaId: _manga!.id,
        chapterId: chapter.id,
        pagesRead: pagesThisSession.clamp(0, 10000),
        durationSeconds: seconds,
      );
    } catch (e) {
      debugPrint('Reader._recordSession failed: $e');
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  Future<void> _goToPage(int page) async {
    if (page < 0 || page >= _totalPages) return;
    final settings = ref.read(readerSettingsProvider);
    if (settings.mode == ReaderMode.paged) {
      if (!_pageController.hasClients) return;
      await _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Guarded: jumpTo on a detached controller (pages still streaming in,
      // or the continuous body not yet mounted after a mode switch) throws
      // and took down the reader mid-read.
      if (!_itemScrollController.isAttached) return;
      unawaited(_itemScrollController.scrollTo(
        index: page,
        duration: const Duration(milliseconds: 220),
      ));
    }
    _trackPage(page);
    setState(() => _currentPage = page);
  }

  void _nextPage() => _goToPage(_currentPage + 1);
  void _prevPage() => _goToPage(_currentPage - 1);

  Future<void> _nextChapter() async {
    final manga = _manga;
    final chapter = _chapter;
    if (manga == null || chapter == null) return;
    final idx = manga.chapters.indexWhere((c) => c.id == chapter.id);
    // Stored newest-first: a lower index = a HIGHER chapter number. Being
    // at index 0 means the latest released chapter — nothing newer exists.
    if (idx <= 0) {
      showSnack(ref, context, 'No newer chapter yet');
      return;
    }
    await _flushProgress();
    await _recordSession();
    final next = manga.chapters[idx - 1];
    if (!mounted) return;
    _switchChapter(next, atEnd: false);
    unawaited(_recordHistoryRead(0));
    if (ref.read(readerSettingsProvider).mode == ReaderMode.paged &&
        _pageController.hasClients) {
      _pageController.jumpToPage(0);
    } else if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: 0);
    }
  }

  Future<void> _prevChapter() async {
    final manga = _manga;
    final chapter = _chapter;
    if (manga == null || chapter == null) return;
    final idx = manga.chapters.indexWhere((c) => c.id == chapter.id);
    // Stored newest-first: index length-1 is chapter 1 — nothing older.
    if (idx >= manga.chapters.length - 1) {
      showSnack(ref, context, 'Already at the first chapter');
      return;
    }
    await _flushProgress();
    await _recordSession();
    final prev = manga.chapters[idx + 1];
    if (!mounted) return;
    _switchChapter(prev, atEnd: true);
    unawaited(_recordHistoryRead(0));
    if (ref.read(readerSettingsProvider).mode == ReaderMode.paged &&
        _pageController.hasClients) {
      _pageController.jumpToPage(_currentPage);
    } else if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: _currentPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chapter')),
        body: emptyState(
          context: context,
          icon: Icons.search_off,
          title: 'Chapter not found',
          subtitle: 'This chapter is no longer in your library.',
        ),
      );
    }

    // Guard the async chapter resolve: `_chapter` is assigned by
    // _loadChapter() after the first frame — watching a provider family with
    // an uninitialized `late` id crashed the first open.
    if (!_chapterReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final settings = ref.watch(readerSettingsProvider);
    final pages = ref.watch(readerPagesProvider(_chapter!.id));

    // Apply keep-screen-on changes made from the settings sheet live.
    ref.listen(readerSettingsProvider.select((s) => s.keepScreenOn),
        (prev, next) {
      next ? WakelockPlus.enable() : WakelockPlus.disable();
    });

    // React when the async page list arrives (or grows).
    ref.listen(readerPagesProvider(_chapter!.id), (prev, next) {
      if (next.length != _totalPages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _totalPages = next.length;
            if (_currentPage >= _totalPages) {
              _currentPage = _totalPages > 0 ? _totalPages - 1 : 0;
            }
            _isLoadingChapter = _totalPages == 0;
          });
          // First non-empty page list → jump to the persisted position.
          if (!_resumeApplied && next.isNotEmpty && _resumePage > 0) {
            _resumeApplied = true;
            final target = _resumePage.clamp(0, next.length - 1);
            if (settings.mode == ReaderMode.paged) {
              if (_pageController.hasClients) {
                _pageController.jumpToPage(target);
              }
            } else if (_itemScrollController.isAttached) {
              _itemScrollController.jumpTo(index: target);
            }
            setState(() => _currentPage = target);
            // Re-baseline page accounting AFTER the resume jump: the jump
            // lands after _resetPageAccounting() ran at chapter open, so
            // without this, resuming on page 30 of 40 counted the 30
            // already-read pages as freshly read (inflated stats) — or a
            // resume followed by re-reading yielded max − start = 0.
            _resetPageAccounting();
          } else if (next.isNotEmpty) {
            _resumeApplied = true;
          }
        });
      }
    });

    // Direction flips invert the PageView's axis semantics: without a
    // re-sync the visible page jumped to its mirror position (page 3 of 20
    // became 17) — the "reader bugs out when I change settings" report.
    ref.listen(readerSettingsProvider.select((s) => s.direction),
        (prev, next) {
      if (prev == next || settings.mode != ReaderMode.paged) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(_currentPage);
      });
    });

    return Scaffold(
      backgroundColor: settings.backgroundColor,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        // Tap-zone navigation handled by the inner stack so taps on the
        // center toggle controls while left/right navigate.
        child: Stack(
          children: [
            // RTL paged mode flips the PageView, so the tap zones must
            // flip with it — previously tap-left always went backwards.
            _ReaderBody(
              settings: settings,
              pages: pages,
              pageController: _pageController,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              initialPage: _currentPage,
              headers: _sourceHeaders,
              onTapLeft: settings.tapToNavigate
                  ? (settings.direction == ReaderDirection.rightToLeft
                      ? _nextPage
                      : _prevPage)
                  : _toggleControls,
              onTapRight: settings.tapToNavigate
                  ? (settings.direction == ReaderDirection.rightToLeft
                      ? _prevPage
                      : _nextPage)
                  : _toggleControls,
              onTapCenter: _toggleControls,
              onPageChanged: _onPagedSwipe,
            ),
            if (_isLoadingChapter && pages.isEmpty)
              const Center(child: CircularProgressIndicator()),
            if (_controlsVisible) _buildControls(settings, pages),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(ReaderSettings settings, List<String> pages) {
    final manga = _manga;
    return Stack(
      children: [
        _TopBar(
          title: manga?.title ?? '',
          chapterName: _chapter?.name ?? '',
          onClose: () => Navigator.maybePop(context),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomBar(
            currentPage: _currentPage + 1,
            totalPages: pages.length,
            showPageNumber: settings.showPageNumber,
            onPrev: _prevPage,
            onNext: _nextPage,
            onPrevChapter: _prevChapter,
            onNextChapter: _nextChapter,
            onSliderChanged: (v) => _goToPage(v.round() - 1),
            onSettings: () => _showSettingsSheet(),
          ),
        ),
      ],
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _ReaderSettingsSheet(),
    ).then((_) {
      // Re-show controls when the sheet closes.
      if (mounted) {
        setState(() => _controlsVisible = true);
        _scheduleHide();
      }
    });
  }
}

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.settings,
    required this.pages,
    required this.pageController,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.initialPage,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onTapCenter,
    this.headers,
    this.onPageChanged,
  });

  final ReaderSettings settings;
  final List<String> pages;
  final PageController pageController;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final int initialPage;

  /// Per-source HTTP headers forwarded to every page image (Referer etc.).
  final Map<String, String>? headers;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onTapCenter;
  final ValueChanged<int>? onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (settings.mode == ReaderMode.paged) {
      return _PagedBody(
        settings: settings,
        pages: pages,
        controller: pageController,
        initialPage: initialPage,
        headers: headers,
        onTapLeft: onTapLeft,
        onTapRight: onTapRight,
        onTapCenter: onTapCenter,
        onPageChanged: onPageChanged,
      );
    }
    return _ContinuousBody(
      settings: settings,
      pages: pages,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      initialPage: initialPage,
      isWebtoon: settings.mode == ReaderMode.webtoon,
      headers: headers,
    );
  }
}

class _PagedBody extends StatefulWidget {
  const _PagedBody({
    required this.settings,
    required this.pages,
    required this.controller,
    required this.initialPage,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onTapCenter,
    this.headers,
    this.onPageChanged,
  });

  final ReaderSettings settings;
  final List<String> pages;
  final PageController controller;
  final int initialPage;
  final Map<String, String>? headers;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onTapCenter;
  final ValueChanged<int>? onPageChanged;

  @override
  State<_PagedBody> createState() => _PagedBodyState();
}

class _PagedBodyState extends State<_PagedBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.controller.hasClients) {
        widget.controller.jumpToPage(widget.initialPage);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reverse = widget.settings.direction == ReaderDirection.rightToLeft;
    final scrollDirection = widget.settings.direction == ReaderDirection.vertical
        ? Axis.vertical
        : Axis.horizontal;
    return PageView.builder(
      controller: widget.controller,
      scrollDirection: scrollDirection,
      reverse: reverse,
      itemCount: widget.pages.length,
      onPageChanged: widget.onPageChanged,
      itemBuilder: (context, index) => _ReaderPage(
        url: widget.pages[index],
        fit: widget.settings.fit,
        headers: widget.headers,
        onTapLeft: widget.onTapLeft,
        onTapRight: widget.onTapRight,
        onTapCenter: widget.onTapCenter,
      ),
    );
  }
}

class _ContinuousBody extends StatefulWidget {
  const _ContinuousBody({
    required this.settings,
    required this.pages,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.initialPage,
    required this.isWebtoon,
    this.headers,
  });

  final ReaderSettings settings;
  final List<String> pages;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final int initialPage;
  final bool isWebtoon;
  final Map<String, String>? headers;

  @override
  State<_ContinuousBody> createState() => _ContinuousBodyState();
}

class _ContinuousBodyState extends State<_ContinuousBody> {
  @override
  Widget build(BuildContext context) {
    return ScrollablePositionedList.builder(
      initialScrollIndex: widget.initialPage,
      itemScrollController: widget.itemScrollController,
      itemPositionsListener: widget.itemPositionsListener,
      padding: EdgeInsets.symmetric(vertical: widget.isWebtoon ? 24 : 0),
      itemCount: widget.pages.length,
      itemBuilder: (context, index) => _ContinuousPage(
        url: widget.pages[index],
        fit: widget.isWebtoon
            ? ReaderFit.contain
            // "Original" inside an unbounded-height list would bleed over
            // neighbouring items — continuous modes normalise it to fit-width
            // (the same normalisation Tachiyomi-family readers use).
            : widget.settings.fit == ReaderFit.original
                ? ReaderFit.width
                : widget.settings.fit,
        headers: widget.headers,
        isWebtoon: widget.isWebtoon,
      ),
    );
  }
}

/// One item of a continuous list: reserves its space from a cached (or
/// estimated) aspect ratio BEFORE the bitmap decodes, so scroll extents,
/// resume jumps and the page slider map to stable positions — the previous
/// zero-height placeholder made every undecoded page invisible to the
/// scroll maths.
class _ContinuousPage extends StatefulWidget {
  const _ContinuousPage({
    required this.url,
    required this.fit,
    required this.isWebtoon,
    this.headers,
  });

  final String url;
  final ReaderFit fit;
  final bool isWebtoon;
  final Map<String, String>? headers;

  @override
  State<_ContinuousPage> createState() => _ContinuousPageState();
}

class _ContinuousPageState extends State<_ContinuousPage> {
  /// Session-wide url → aspect (height/width) cache. Shared so returning to
  /// a previously decoded page never re-flashes to the estimated height.
  /// Capped: a long reading session must not grow it unboundedly.
  static final Map<String, double> _aspectCache = <String, double>{};
  static const int _aspectCacheMax = 600;

  /// Estimate until decoded: manga/manwha pages ≈ 2:3, webtoon slices are
  /// taller. Close enough to keep jump targets stable.
  double get _aspect => _aspectCache[widget.url] ?? (widget.isWebtoon ? 1.5 : 1.45);

  void _onDecoded(Size imageSize) {
    final ar = imageSize.height / imageSize.width;
    if (!ar.isFinite || ar <= 0 || ar == _aspect) return;
    if (_aspectCache.length >= _aspectCacheMax) {
      _aspectCache.remove(_aspectCache.keys.first);
    }
    _aspectCache[widget.url] = ar;
    // DEFERRED rebuild: loadStateChanged fires synchronously inside
    // ExtendedImage.build — calling setState() here synchronously throws
    // "setState() called during build" (a guaranteed exception storm in
    // continuous mode, where nearly every decoded page differs from its
    // estimate). Schedule the rebuild for the END of the current frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // BOUNDED height is the whole point: the previous implementation
      // placed an unbounded-height item with StackFit.expand inside, which
      // either crashed with an infinite-constraint error or collapsed.
      child: SizedBox(
        width: width,
        height: width * _aspect,
        child: _ReaderPage(
          url: widget.url,
          fit: widget.fit,
          headers: widget.headers,
          isWebtoon: widget.isWebtoon,
          onDecoded: _onDecoded,
        ),
      ),
    );
  }
}

/// A single reader page rendered with [ExtendedImage] for pinch-to-zoom and
/// an overlay of three transparent tap zones (left / center / right).
class _ReaderPage extends StatelessWidget {
  const _ReaderPage({
    required this.url,
    required this.fit,
    this.headers,
    this.onTapLeft,
    this.onTapRight,
    this.onTapCenter,
    this.isWebtoon = false,
    this.onDecoded,
  });

  final String url;
  final ReaderFit fit;

  /// Per-source HTTP headers (Referer / User-Agent). Scraped CDNs such as
  /// Madara's reject hotlinked page images with 403 unless the site's own
  /// Referer is attached — without this, whole sources render blank pages.
  final Map<String, String>? headers;
  final VoidCallback? onTapLeft;
  final VoidCallback? onTapRight;
  final VoidCallback? onTapCenter;
  final bool isWebtoon;

  /// Notified with the decoded bitmap size (continuous lists use it to
  /// replace their aspect-ratio estimate with the real one).
  final ValueChanged<Size>? onDecoded;

  @override
  Widget build(BuildContext context) {
    // Fit-width is the manga-industry baseline: full-width pages that pan
    // vertically; fit-height is its landscape counterpart. BoxFit.fitWidth/
    // fitHeight inside a full-viewport cell overflow one axis — the
    // ExtendedImage gesture layer pans along it (inPageView keeps the other
    // axis for page swipes).
    final boxFit = switch (fit) {
      ReaderFit.contain => BoxFit.contain,
      ReaderFit.cover => BoxFit.cover,
      ReaderFit.fill => BoxFit.fill,
      ReaderFit.original => BoxFit.contain, // DPR-aware scale below
      ReaderFit.width => BoxFit.fitWidth,
      ReaderFit.height => BoxFit.fitHeight,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: isWebtoon ? StackFit.loose : StackFit.expand,
          children: [
            // Offline-first: downloaded chapters resolve to local file paths
            // (written by the DownloadEngine); remote chapters stay network.
            // onDoubleTap lives on the WIDGET (not GestureConfig): toggle
            // 1x ⇄ 2.2x zoom at the tapped point — a standard reader
            // affordance the app never had.
            url.startsWith('file://')
                ? ExtendedImage.file(
                    File.fromUri(Uri.parse(url)),
                    fit: boxFit,
                    mode: ExtendedImageMode.gesture,
                    enableSlideOutPage: true,
                    loadStateChanged: _pageLoadState,
                    onDoubleTap: _onDoubleTap,
                    initGestureConfigHandler: (state) =>
                        _gestureConfig(context, state, constraints.biggest),
                  )
                : ExtendedImage.network(
                    url,
                    fit: boxFit,
                    mode: ExtendedImageMode.gesture,
                    enableSlideOutPage: true,
                    cache: true,
                    headers: headers,
                    loadStateChanged: _pageLoadState,
                    onDoubleTap: _onDoubleTap,
                    initGestureConfigHandler: (state) =>
                        _gestureConfig(context, state, constraints.biggest),
                  ),
            if (onTapLeft != null)
              Row(
                children: [
                  Expanded(flex: 1, child: GestureDetector(onTap: onTapLeft)),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(onTap: onTapCenter),
                  ),
                  Expanded(flex: 1, child: GestureDetector(onTap: onTapRight)),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _pageLoadState(ExtendedImageState state) {
    if (state.extendedImageLoadState == LoadState.loading) {
      return const _PagePlaceholder(
        child: Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0x73FFFFFF)),
            ),
          ),
        ),
      );
    }
    if (state.extendedImageLoadState == LoadState.failed) {
      return _PagePlaceholder(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 40, color: Colors.white54),
            const SizedBox(height: 8),
            TextButton(
              // extended_image 8.x: the retry hook is `reLoadImage`
              // (the old `reLoad` getter no longer exists).
              onPressed: state.reLoadImage,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    // Decoded: report the real bitmap size so continuous lists can swap
    // their aspect estimate for the exact one (fires once per url).
    final info = state.extendedImageInfo;
    if (info != null) {
      onDecoded?.call(Size(
          info.image.width.toDouble(), info.image.height.toDouble()));
    }
    return state.completedWidget;
  }

  /// Double-tap zoom toggle (1x ⇄ 2.2x at the tapped point).
  void _onDoubleTap(ExtendedImageGestureState state) {
    final Offset? pos = state.pointerDownPosition;
    final double begin = state.gestureDetails?.totalScale ?? 1.0;
    state.handleDoubleTap(
      scale: begin == 1.0 ? 2.2 : 1.0,
      doubleTapPosition: pos,
    );
  }

  GestureConfig _gestureConfig(
      BuildContext context, ExtendedImageState state, Size cell) {
    // "Original size" done right: raw BoxFit.none paints 1 bitmap pixel as
    // 1 LOGICAL dp — on a 420dpi phone that is a permanent ~2.6x zoom
    // ("pages too zoomed in"). Instead keep the contain baseline and set the
    // initial gesture scale so the bitmap renders 1 device pixel per bitmap
    // pixel (imageWidth/dpr logical dp wide).
    var initialScale = 1.0;
    if (fit == ReaderFit.original) {
      final info = state.extendedImageInfo;
      if (info != null && cell.width > 0 && cell.height > 0) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final ar = info.image.width / info.image.height;
        final containWidth =
            cell.width < cell.height * ar ? cell.width : cell.height * ar;
        if (containWidth > 0) {
          initialScale =
              (info.image.width / dpr / containWidth).clamp(0.5, 6.0);
        }
      }
    }
    return GestureConfig(
      minScale: initialScale < 0.9 ? initialScale : 0.9,
      animationMinScale: 0.7,
      maxScale: 6.0,
      animationMaxScale: 6.5,
      speed: 1.0,
      inertialSpeed: 100.0,
      initialScale: initialScale,
      inPageView: !isWebtoon,
    );
  }
}

class _PagePlaceholder extends StatelessWidget {
  const _PagePlaceholder({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.chapterName,
    required this.onClose,
  });

  final String title;
  final String chapterName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onClose,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      Text(chapterName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentPage,
    required this.totalPages,
    required this.showPageNumber,
    required this.onPrev,
    required this.onNext,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onSliderChanged,
    required this.onSettings,
  });

  final int currentPage;
  final int totalPages;
  final bool showPageNumber;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous chapter',
                    icon: const Icon(Icons.skip_previous_rounded,
                        color: Colors.white),
                    onPressed: onPrevChapter,
                  ),
                  Expanded(
                    child: totalPages > 0
                        ? Slider(
                            // Guarded: clamp(1, 0) is an invalid range and
                            // threw ArgumentError while pages streamed in.
                            value: currentPage
                                .toDouble()
                                .clamp(1, totalPages)
                                .toDouble(),
                            min: 1,
                            max: totalPages.toDouble(),
                            onChanged: onSliderChanged,
                            activeColor:
                                Theme.of(context).colorScheme.primary,
                            inactiveColor: Colors.white24,
                          )
                        : const SizedBox(height: 48),
                  ),
                  IconButton(
                    tooltip: 'Next chapter',
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white),
                    onPressed: onNextChapter,
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: onPrev,
                  ),
                  Expanded(
                    child: showPageNumber
                        ? Center(
                            child: Text(
                              '$currentPage / $totalPages',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: onNext,
                  ),
                  IconButton(
                    tooltip: 'Reader settings',
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.white),
                    onPressed: onSettings,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderSettingsSheet extends ConsumerWidget {
  const _ReaderSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    // Scrollable + height-capped: the sheet stacks four chip sections and
    // three switches (~500 px). Uncapped, it overflowed the viewport in
    // landscape (the classic "reader bugs out when changing layouts" —
    // yellow/black overflow stripes over the page).
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reader settings',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const _SectionLabel('Reading mode'),
            Wrap(
              spacing: 8,
              children: [
                for (final m in ReaderMode.values)
                  ChoiceChip(
                    label: Text(_modeLabel(m)),
                    selected: settings.mode == m,
                    onSelected: (_) => notifier.setMode(m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Direction'),
            Wrap(
              spacing: 8,
              children: [
                for (final d in ReaderDirection.values)
                  ChoiceChip(
                    label: Text(_dirLabel(d)),
                    selected: settings.direction == d,
                    onSelected: (_) => notifier.setDirection(d),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Fit'),
            Wrap(
              spacing: 8,
              children: [
                for (final f in ReaderFit.values)
                  ChoiceChip(
                    label: Text(_fitLabel(f)),
                    selected: settings.fit == f,
                    onSelected: (_) => notifier.setFit(f),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Background'),
            Wrap(
              spacing: 8,
              children: [
                for (final bg in ReaderBgColor.values)
                  ChoiceChip(
                    label: Text(bg.label),
                    selected: settings.backgroundColor == bg.color,
                    onSelected: (_) =>
                        ref.read(readerSettingsProvider.notifier).setBackgroundColor(bg.color),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Show page number'),
              value: settings.showPageNumber,
              onChanged: (_) => notifier.togglePageNumber(),
            ),
            SwitchListTile(
              title: const Text('Keep screen on'),
              value: settings.keepScreenOn,
              onChanged: (_) => notifier.toggleKeepScreenOn(),
            ),
            SwitchListTile(
              title: const Text('Tap to navigate'),
              value: settings.tapToNavigate,
              onChanged: (_) => ref
                  .read(readerSettingsProvider.notifier)
                  .toggleTapToNavigate(),
            ),
          ],
        ),
      ),
    );
  }

  String _modeLabel(ReaderMode m) {
    switch (m) {
      case ReaderMode.paged:
        return 'Paged';
      case ReaderMode.continuous:
        return 'Continuous';
      case ReaderMode.webtoon:
        return 'Webtoon';
    }
  }

  String _dirLabel(ReaderDirection d) {
    switch (d) {
      case ReaderDirection.leftToRight:
        return 'Left → Right';
      case ReaderDirection.rightToLeft:
        return 'Right → Left';
      case ReaderDirection.vertical:
        return 'Vertical';
    }
  }

  String _fitLabel(ReaderFit f) {
    switch (f) {
      case ReaderFit.contain:
        return 'Fit Screen';
      case ReaderFit.cover:
        return 'Cover';
      case ReaderFit.fill:
        return 'Stretch';
      case ReaderFit.original:
        return 'Original';
      case ReaderFit.width:
        return 'Fit Width';
      case ReaderFit.height:
        return 'Fit Height';
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
