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
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../shared/widgets.dart';

/// All reader rendering modes supported by Lumina's manga viewer.
///
/// Mirrors the seven modes offered by Mangayomi so users coming from that
/// ecosystem find the same controls. [isPaged] selects a [PageView]-based
/// layout, [isContinuous] selects a [ScrollablePositionedList]-based layout,
/// and [isWebtoon] routes through a [PhotoViewGallery] for free-form
/// pan/zoom across a tall vertical strip.
enum LuminaReaderMode {
  /// Paged, swiped vertically (rare, but useful for webtoons split per page).
  verticalPaged,

  /// Paged, left-to-right (Western comics / manhwa).
  leftToRightPaged,

  /// Paged, right-to-left (Japanese manga default).
  rightToLeftPaged,

  /// Continuous vertical scroll.
  verticalContinuous,

  /// Webtoon — continuous vertical with infinite-style gap and no page breaks.
  webtoon,

  /// Continuous horizontal scroll, left-to-right.
  horizontalContinuous,

  /// Continuous horizontal scroll, right-to-left.
  horizontalContinuousRtl,
}

extension LuminaReaderModeX on LuminaReaderMode {
  bool get isPaged =>
      this == LuminaReaderMode.verticalPaged ||
      this == LuminaReaderMode.leftToRightPaged ||
      this == LuminaReaderMode.rightToLeftPaged;

  bool get isContinuous =>
      this == LuminaReaderMode.verticalContinuous ||
      this == LuminaReaderMode.horizontalContinuous ||
      this == LuminaReaderMode.horizontalContinuousRtl;

  bool get isWebtoon => this == LuminaReaderMode.webtoon;

  bool get isVertical =>
      this == LuminaReaderMode.verticalPaged ||
      this == LuminaReaderMode.verticalContinuous ||
      this == LuminaReaderMode.webtoon;

  bool get isRtl =>
      this == LuminaReaderMode.rightToLeftPaged ||
      this == LuminaReaderMode.horizontalContinuousRtl;

  String get label {
    switch (this) {
      case LuminaReaderMode.verticalPaged:
        return 'Vertical paged';
      case LuminaReaderMode.leftToRightPaged:
        return 'Left → Right paged';
      case LuminaReaderMode.rightToLeftPaged:
        return 'Right → Left paged';
      case LuminaReaderMode.verticalContinuous:
        return 'Vertical continuous';
      case LuminaReaderMode.webtoon:
        return 'Webtoon';
      case LuminaReaderMode.horizontalContinuous:
        return 'Horizontal continuous';
      case LuminaReaderMode.horizontalContinuousRtl:
        return 'Horizontal continuous (RTL)';
    }
  }
}

/// Image-fit strategies available inside the reader.
enum LuminaReaderFit { contain, cover, fill, original }

extension LuminaReaderFitX on LuminaReaderFit {
  BoxFit get boxFit {
    switch (this) {
      case LuminaReaderFit.contain:
        return BoxFit.contain;
      case LuminaReaderFit.cover:
        return BoxFit.cover;
      case LuminaReaderFit.fill:
        return BoxFit.fill;
      case LuminaReaderFit.original:
        return BoxFit.none;
    }
  }

  String get label {
    switch (this) {
      case LuminaReaderFit.contain:
        return 'Fit';
      case LuminaReaderFit.cover:
        return 'Cover';
      case LuminaReaderFit.fill:
        return 'Stretch';
      case LuminaReaderFit.original:
        return 'Original';
    }
  }
}

/// Color filter presets applied on top of every page.
enum LuminaColorFilter {
  off,
  grayscale,
  invert,
  sepia,
  highContrast,
  warm,
}

extension LuminaColorFilterX on LuminaColorFilter {
  ColorFilter? get filter {
    switch (this) {
      case LuminaColorFilter.off:
        return null;
      case LuminaColorFilter.grayscale:
        return const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]);
      case LuminaColorFilter.invert:
        return const ColorFilter.matrix(<double>[
          -1, 0,  0,  0, 255,
          0,  -1, 0,  0, 255,
          0,  0,  -1, 0, 255,
          0,  0,  0,  1, 0,
        ]);
      case LuminaColorFilter.sepia:
        return const ColorFilter.matrix(<double>[
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0,     0,     0,     1, 0,
        ]);
      case LuminaColorFilter.highContrast:
        return const ColorFilter.matrix(<double>[
          1.5, 0,   0,   0, -64,
          0,   1.5, 0,   0, -64,
          0,   0,   1.5, 0, -64,
          0,   0,   0,   1, 0,
        ]);
      case LuminaColorFilter.warm:
        return const ColorFilter.matrix(<double>[
          1.1, 0,   0,   0, 0,
          0,   1.0, 0,   0, 0,
          0,   0,   0.9, 0, 0,
          0,   0,   0,   1, 0,
        ]);
    }
  }

  String get label {
    switch (this) {
      case LuminaColorFilter.off:
        return 'Off';
      case LuminaColorFilter.grayscale:
        return 'Grayscale';
      case LuminaColorFilter.invert:
        return 'Invert';
      case LuminaColorFilter.sepia:
        return 'Sepia';
      case LuminaColorFilter.highContrast:
        return 'High contrast';
      case LuminaColorFilter.warm:
        return 'Warm';
    }
  }
}

/// Comprehensive reader configuration.
class LuminaReaderSettings {
  LuminaReaderSettings({
    this.mode = LuminaReaderMode.rightToLeftPaged,
    this.fit = LuminaReaderFit.contain,
    this.colorFilter = LuminaColorFilter.off,
    this.tapToNavigate = true,
    this.showPageNumber = true,
    this.keepScreenOn = true,
    this.fullScreen = true,
    this.cropBorders = false,
    this.doublePageSpread = false,
    this.backgroundColor = const Color(0xFF000000),
    this.pageGap = 0,
    this.maxZoom = 8.0,
    this.padding = 0,
  });

  final LuminaReaderMode mode;
  final LuminaReaderFit fit;
  final LuminaColorFilter colorFilter;
  final bool tapToNavigate;
  final bool showPageNumber;
  final bool keepScreenOn;
  final bool fullScreen;
  final bool cropBorders;
  final bool doublePageSpread;
  final Color backgroundColor;
  final double pageGap;
  final double maxZoom;
  final double padding;

  LuminaReaderSettings copyWith({
    LuminaReaderMode? mode,
    LuminaReaderFit? fit,
    LuminaColorFilter? colorFilter,
    bool? tapToNavigate,
    bool? showPageNumber,
    bool? keepScreenOn,
    bool? fullScreen,
    bool? cropBorders,
    bool? doublePageSpread,
    Color? backgroundColor,
    double? pageGap,
    double? maxZoom,
    double? padding,
  }) {
    return LuminaReaderSettings(
      mode: mode ?? this.mode,
      fit: fit ?? this.fit,
      colorFilter: colorFilter ?? this.colorFilter,
      tapToNavigate: tapToNavigate ?? this.tapToNavigate,
      showPageNumber: showPageNumber ?? this.showPageNumber,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      fullScreen: fullScreen ?? this.fullScreen,
      cropBorders: cropBorders ?? this.cropBorders,
      doublePageSpread: doublePageSpread ?? this.doublePageSpread,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      pageGap: pageGap ?? this.pageGap,
      maxZoom: maxZoom ?? this.maxZoom,
      padding: padding ?? this.padding,
    );
  }
}

/// State notifier for the reader's user-tunable settings.
class LuminaReaderSettingsNotifier
    extends StateNotifier<LuminaReaderSettings> {
  LuminaReaderSettingsNotifier() : super(LuminaReaderSettings());

  void setMode(LuminaReaderMode m) => state = state.copyWith(mode: m);
  void setFit(LuminaReaderFit f) => state = state.copyWith(fit: f);
  void setColorFilter(LuminaColorFilter f) =>
      state = state.copyWith(colorFilter: f);
  void togglePageNumber() =>
      state = state.copyWith(showPageNumber: !state.showPageNumber);
  void toggleKeepScreenOn() =>
      state = state.copyWith(keepScreenOn: !state.keepScreenOn);
  void toggleFullScreen() =>
      state = state.copyWith(fullScreen: !state.fullScreen);
  void toggleCropBorders() =>
      state = state.copyWith(cropBorders: !state.cropBorders);
  void toggleDoublePageSpread() =>
      state = state.copyWith(doublePageSpread: !state.doublePageSpread);
  void toggleTapToNavigate() =>
      state = state.copyWith(tapToNavigate: !state.tapToNavigate);
  void setBackgroundColor(Color c) =>
      state = state.copyWith(backgroundColor: c);
  void setPageGap(double g) => state = state.copyWith(pageGap: g);
  void setPadding(double p) => state = state.copyWith(padding: p);
}

/// Riverpod provider for [LuminaReaderSettings].
final luminaReaderSettingsProvider = StateNotifierProvider<
    LuminaReaderSettingsNotifier, LuminaReaderSettings>(
  (ref) => LuminaReaderSettingsNotifier(),
);

/// Pages for a chapter — delegates to the existing [readerPagesProvider]
/// for backwards compatibility with seed data.
final luminaReaderPagesProvider =
    Provider.family<List<String>, int>((ref, chapterId) {
  return ref.watch(readerPagesProvider(chapterId));
});

/// Bidirectional chapter preloader with an LRU cache.
///
/// Adjacent chapters are loaded eagerly (up to [preloadRadius] in each
/// direction) so navigation between chapters is instant. The cache is
/// bounded by [maxCachedChapters]; older entries are evicted when full.
class ChapterPreloader {
  ChapterPreloader({
    this.maxCachedChapters = 4,
    this.preloadRadius = 1,
  }) : _cache = LinkedHashMap<int, List<String>>();

  final int maxCachedChapters;
  final int preloadRadius;
  final LinkedHashMap<int, List<String>> _cache;

  /// Returns the cached pages for [chapterId], or null if not present.
  List<String>? get(int chapterId) {
    final pages = _cache.remove(chapterId);
    if (pages != null) {
      _cache[chapterId] = pages;
    }
    return pages;
  }

  /// Stores pages for [chapterId], evicting the oldest if necessary.
  void put(int chapterId, List<String> pages) {
    _cache.remove(chapterId);
    _cache[chapterId] = pages;
    while (_cache.length > maxCachedChapters) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Pre-fetches siblings of [center] using [fetch].
  Future<void> preloadAround(
    int center,
    List<int> siblingIds,
    Future<List<String>> Function(int) fetch,
  ) async {
    final ordered = <int>[center];
    for (var i = 1; i <= preloadRadius; i++) {
      if (i < siblingIds.length) ordered.add(siblingIds[i]);
      if (i < siblingIds.length) ordered.insert(0, siblingIds[i]);
    }
    for (final id in ordered) {
      if (_cache.containsKey(id)) continue;
      try {
        final pages = await fetch(id);
        put(id, pages);
      } catch (_) {
        // Preload failures are non-fatal; the user will see a retry button.
      }
    }
  }

  void clear() => _cache.clear();

  Iterable<int> get cachedIds => _cache.keys;
}

// ---------------------------------------------------------------------------
// Reader view
// ---------------------------------------------------------------------------

/// The main manga reader widget.
///
/// A [ConsumerStatefulWidget] that listens to [luminaReaderSettingsProvider]
/// and the chapter currently being read. It supports all seven reader modes
/// of [LuminaReaderMode], bidirectional chapter preloading with LRU
/// eviction, tap-zone navigation, pinch-to-zoom (up to 8x), color filters,
/// border cropping, optional double-page spread, full-screen toggling and
/// a settings sheet with every option.
class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({
    super.key,
    required this.mangaId,
    required this.chapterId,
  });

  final int mangaId;
  final int chapterId;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ChapterPreloader _preloader = ChapterPreloader();

  // PhotoView gallery controller (page-based) for webtoon.
  late final PageController _webtoonController;

  int _currentPage = 0;
  int _totalPages = 0;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isLoadingChapter = false;
  bool _appBootstrapped = false;

  late Chapter _chapter;
  List<String> _pages = const [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _webtoonController = PageController();
    _itemPositionsListener.itemPositions.addListener(_onListPositionsChanged);
    _loadChapter(initial: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applySystemUi();
      if (ref.read(luminaReaderSettingsProvider).keepScreenOn) {
        WakelockPlus.enable();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _webtoonController.dispose();
    _hideTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(
      _onListPositionsChanged,
    );
    _preloader.clear();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _loadChapter({bool initial = false}) {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    final chapter = manga.chapters.firstWhere(
      (c) => c.id == widget.chapterId,
      orElse: () => manga.chapters.first,
    );
    _chapter = chapter;
    final pages = ref.read(luminaReaderPagesProvider(chapter.id));
    _pages = pages;
    _totalPages = pages.length;
    _currentPage = chapter.lastPageRead.clamp(0, math.max(_totalPages - 1, 0));
    _preloader.put(chapter.id, pages);
    _preloadNeighbors();
    if (initial) _appBootstrapped = true;
  }

  Future<void> _preloadNeighbors() async {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    final ids = manga.chapters.map((c) => c.id).toList();
    await _preloader.preloadAround(
      _chapter.id,
      ids,
      (id) async => ref.read(luminaReaderPagesProvider(id)),
    );
  }

  void _onListPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions.first;
    if (first.index != _currentPage) {
      setState(() => _currentPage = first.index);
    }
  }

  void _applySystemUi() {
    final settings = ref.read(luminaReaderSettingsProvider);
    if (settings.fullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _applySystemUi();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
        _applySystemUi();
      }
    });
  }

  Future<void> _goToPage(int page) async {
    if (page < 0 || page >= _totalPages) return;
    final settings = ref.read(luminaReaderSettingsProvider);
    if (settings.mode.isPaged) {
      if (_pageController.hasClients) {
        await _pageController.animateToPage(
          page,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (settings.mode.isWebtoon) {
      if (_webtoonController.hasClients) {
        await _webtoonController.animateToPage(
          page,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      _itemScrollController.scrollTo(
        index: page,
        duration: const Duration(milliseconds: 220),
      );
    }
    setState(() => _currentPage = page);
  }

  void _nextPage() => _goToPage(_currentPage + 1);
  void _prevPage() => _goToPage(_currentPage - 1);

  Future<void> _nextChapter() async {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    final idx = manga.chapters.indexWhere((c) => c.id == _chapter.id);
    if (idx <= 0) {
      showSnack(ref, context, 'Already at the first chapter');
      return;
    }
    setState(() => _isLoadingChapter = true);
    final next = manga.chapters[idx - 1];
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final cached = _preloader.get(next.id);
    final pages = cached ?? ref.read(luminaReaderPagesProvider(next.id));
    _preloader.put(next.id, pages);
    setState(() {
      _chapter = next;
      _pages = pages;
      _totalPages = pages.length;
      _currentPage = 0;
      _isLoadingChapter = false;
    });
    _jumpToPage(0);
    _preloadNeighbors();
  }

  Future<void> _prevChapter() async {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    final idx = manga.chapters.indexWhere((c) => c.id == _chapter.id);
    if (idx >= manga.chapters.length - 1) {
      showSnack(ref, context, 'Already at the last chapter');
      return;
    }
    setState(() => _isLoadingChapter = true);
    final prev = manga.chapters[idx + 1];
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final cached = _preloader.get(prev.id);
    final pages = cached ?? ref.read(luminaReaderPagesProvider(prev.id));
    _preloader.put(prev.id, pages);
    setState(() {
      _chapter = prev;
      _pages = pages;
      _totalPages = pages.length;
      _currentPage = _totalPages - 1;
      _isLoadingChapter = false;
    });
    _jumpToPage(_currentPage);
    _preloadNeighbors();
  }

  void _jumpToPage(int page) {
    final settings = ref.read(luminaReaderSettingsProvider);
    if (settings.mode.isPaged && _pageController.hasClients) {
      _pageController.jumpToPage(page);
    } else if (settings.mode.isWebtoon && _webtoonController.hasClients) {
      _webtoonController.jumpToPage(page);
    } else {
      _itemScrollController.jumpTo(index: page);
    }
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    // Persist progress on the chapter model.
    _chapter.lastPageRead = page;
    _chapter.progress = _totalPages == 0 ? 0 : page / _totalPages;
    if (page >= _totalPages - 1) {
      _chapter.isRead = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(luminaReaderSettingsProvider);

    return Scaffold(
      backgroundColor: settings.backgroundColor,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          children: [
            _ReaderBody(
              settings: settings,
              pages: _pages,
              pageController: _pageController,
              webtoonController: _webtoonController,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              initialPage: _currentPage,
              onPageChanged: _onPageChanged,
              onTapLeft: settings.tapToNavigate ? _prevPage : _toggleControls,
              onTapRight: settings.tapToNavigate ? _nextPage : _toggleControls,
              onTapCenter: _toggleControls,
            ),
            if (_isLoadingChapter)
              const Center(child: CircularProgressIndicator()),
            if (_controlsVisible) _buildControls(settings),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(LuminaReaderSettings settings) {
    final manga = ref.watch(mangaDetailProvider(widget.mangaId));
    return Stack(
      children: [
        ReaderTopBar(
          title: manga.title,
          chapterName: _chapter.name,
          onClose: () => Navigator.maybePop(context),
          onBookmark: () {
            setState(() => _chapter.isBookmarked = !_chapter.isBookmarked);
            showSnack(
              ref,
              context,
              _chapter.isBookmarked
                  ? 'Bookmark added'
                  : 'Bookmark removed',
            );
          },
          isBookmarked: _chapter.isBookmarked,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ReaderBottomBar(
            currentPage: _currentPage + 1,
            totalPages: _pages.length,
            showPageNumber: settings.showPageNumber,
            isRtl: settings.mode.isRtl,
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
      builder: (context) => const ReaderSettingsSheet(),
    ).then((_) {
      if (mounted) {
        setState(() => _controlsVisible = true);
        _scheduleHide();
        _applySystemUi();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Reader body — picks the right widget for the active mode
// ---------------------------------------------------------------------------

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.settings,
    required this.pages,
    required this.pageController,
    required this.webtoonController,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.initialPage,
    required this.onPageChanged,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onTapCenter,
  });

  final LuminaReaderSettings settings;
  final List<String> pages;
  final PageController pageController;
  final PageController webtoonController;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onTapCenter;

  @override
  Widget build(BuildContext context) {
    if (settings.mode.isWebtoon) {
      return _WebtoonBody(
        settings: settings,
        pages: pages,
        controller: webtoonController,
        initialPage: initialPage,
        onPageChanged: onPageChanged,
      );
    }
    if (settings.mode.isPaged) {
      return _PagedBody(
        settings: settings,
        pages: pages,
        controller: pageController,
        initialPage: initialPage,
        onPageChanged: onPageChanged,
        onTapLeft: onTapLeft,
        onTapRight: onTapRight,
        onTapCenter: onTapCenter,
      );
    }
    return _ContinuousBody(
      settings: settings,
      pages: pages,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      initialPage: initialPage,
    );
  }
}

// ---------------------------------------------------------------------------
// Paged body
// ---------------------------------------------------------------------------

class _PagedBody extends StatefulWidget {
  const _PagedBody({
    required this.settings,
    required this.pages,
    required this.controller,
    required this.initialPage,
    required this.onPageChanged,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onTapCenter,
  });

  final LuminaReaderSettings settings;
  final List<String> pages;
  final PageController controller;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onTapCenter;

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
    final s = widget.settings;
    final reverse = s.mode == LuminaReaderMode.rightToLeftPaged;
    final scrollDirection = s.mode == LuminaReaderMode.verticalPaged
        ? Axis.vertical
        : Axis.horizontal;

    // Double-page spread shows two side-by-side pages on landscape.
    if (s.doublePageSpread &&
        scrollDirection == Axis.horizontal &&
        widget.pages.length > 1) {
      return _DoublePageSpread(
        pages: widget.pages,
        controller: widget.controller,
        reverse: reverse,
        settings: s,
        onPageChanged: widget.onPageChanged,
        onTapLeft: widget.onTapLeft,
        onTapRight: widget.onTapRight,
        onTapCenter: widget.onTapCenter,
      );
    }

    return PageView.builder(
      controller: widget.controller,
      scrollDirection: scrollDirection,
      reverse: reverse,
      itemCount: widget.pages.length,
      onPageChanged: widget.onPageChanged,
      itemBuilder: (context, index) => _ReaderPage(
        url: widget.pages[index],
        fit: s.fit,
        colorFilter: s.colorFilter,
        cropBorders: s.cropBorders,
        backgroundColor: s.backgroundColor,
        maxZoom: s.maxZoom,
        inPageView: true,
        onTapLeft: widget.onTapLeft,
        onTapRight: widget.onTapRight,
        onTapCenter: widget.onTapCenter,
      ),
    );
  }
}

class _DoublePageSpread extends StatelessWidget {
  const _DoublePageSpread({
    required this.pages,
    required this.controller,
    required this.reverse,
    required this.settings,
    required this.onPageChanged,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onTapCenter,
  });

  final List<String> pages;
  final PageController controller;
  final bool reverse;
  final LuminaReaderSettings settings;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onTapCenter;

  int get _spreadCount => (pages.length / 2).ceil();

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.horizontal,
      reverse: reverse,
      itemCount: _spreadCount,
      onPageChanged: (i) => onPageChanged(i * 2),
      itemBuilder: (context, spreadIndex) {
        final leftIdx = spreadIndex * 2;
        final rightIdx = leftIdx + 1;
        final left = pages[leftIdx];
        final right = rightIdx < pages.length ? pages[rightIdx] : null;
        return Row(
          children: [
            Expanded(
              child: _ReaderPage(
                url: reverse ? (right ?? left) : left,
                fit: settings.fit,
                colorFilter: settings.colorFilter,
                cropBorders: settings.cropBorders,
                backgroundColor: settings.backgroundColor,
                maxZoom: settings.maxZoom,
                inPageView: true,
                onTapLeft: onTapLeft,
                onTapRight: onTapRight,
                onTapCenter: onTapCenter,
              ),
            ),
            if (right != null)
              Expanded(
                child: _ReaderPage(
                  url: reverse ? left : right,
                  fit: settings.fit,
                  colorFilter: settings.colorFilter,
                  cropBorders: settings.cropBorders,
                  backgroundColor: settings.backgroundColor,
                  maxZoom: settings.maxZoom,
                  inPageView: true,
                  onTapLeft: onTapLeft,
                  onTapRight: onTapRight,
                  onTapCenter: onTapCenter,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Continuous body (vertical and horizontal)
// ---------------------------------------------------------------------------

class _ContinuousBody extends StatelessWidget {
  const _ContinuousBody({
    required this.settings,
    required this.pages,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.initialPage,
  });

  final LuminaReaderSettings settings;
  final List<String> pages;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final int initialPage;

  @override
  Widget build(BuildContext context) {
    final horizontal = settings.mode == LuminaReaderMode.horizontalContinuous ||
        settings.mode == LuminaReaderMode.horizontalContinuousRtl;
    return ScrollablePositionedList.builder(
      initialScrollIndex: initialPage,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      reverse: settings.mode == LuminaReaderMode.horizontalContinuousRtl,
      padding: EdgeInsets.symmetric(
        vertical: horizontal ? 0 : 12,
        horizontal: horizontal ? 12 : 0,
      ),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(
            right: horizontal ? 12 : 0,
            bottom: horizontal ? 0 : 12,
          ),
          child: _ReaderPage(
            url: pages[index],
            fit: settings.fit,
            colorFilter: settings.colorFilter,
            cropBorders: settings.cropBorders,
            backgroundColor: settings.backgroundColor,
            maxZoom: settings.maxZoom,
            inPageView: false,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Webtoon body — uses PhotoViewGallery for free-form pan/zoom
// ---------------------------------------------------------------------------

class _WebtoonBody extends StatefulWidget {
  const _WebtoonBody({
    required this.settings,
    required this.pages,
    required this.controller,
    required this.initialPage,
    required this.onPageChanged,
  });

  final LuminaReaderSettings settings;
  final List<String> pages;
  final PageController controller;
  final int initialPage;
  final ValueChanged<int> onPageChanged;

  @override
  State<_WebtoonBody> createState() => _WebtoonBodyState();
}

class _WebtoonBodyState extends State<_WebtoonBody> {
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
    final s = widget.settings;
    return PhotoViewGallery.builder(
      pageController: widget.controller,
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (context, index) => PhotoViewGalleryPageOptions.customChild(
        child: ExtendedImage.network(
          widget.pages[index],
          fit: BoxFit.contain,
          mode: ExtendedImageMode.gesture,
          cache: true,
          loadStateChanged: (state) {
            if (state.extendedImageLoadState == LoadState.loading) {
              return _PagePlaceholder(
                child: inlineLoader(context, size: 28),
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
                      onPressed: state.reLoad,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            return state.completedWidget;
          },
          initGestureConfigHandler: (state) {
            return GestureConfig(
              minScale: 0.9,
              animationMinScale: 0.7,
              maxScale: s.maxZoom,
              animationMaxScale: s.maxZoom + 1.0,
              speed: 1.0,
              inertialSpeed: 100.0,
              initialScale: 1.0,
              inPageView: false,
            );
          },
        ),
        minScale: PhotoViewComputedScale.contained * 0.9,
        maxScale: PhotoViewComputedScale.covered * s.maxZoom,
        initialScale: PhotoViewComputedScale.contained,
        heroAttributes: PhotoViewHeroAttributes(tag: 'webtoon-page-$index'),
      ),
      itemCount: widget.pages.length,
      loadingBuilder: (context, event) => _PagePlaceholder(
        child: inlineLoader(context, size: 28),
      ),
      backgroundDecoration: BoxDecoration(color: s.backgroundColor),
      onPageChanged: widget.onPageChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// A single reader page rendered with ExtendedImage
// ---------------------------------------------------------------------------

/// A single manga page rendered with [ExtendedImage] for pinch-to-zoom,
/// wrapped in a [ColorFiltered] when a [LuminaColorFilter] is active, with
/// an optional border-cropping [ClipRect] and three transparent tap zones
/// (left / center / right) overlaying the image.
class _ReaderPage extends StatelessWidget {
  const _ReaderPage({
    required this.url,
    required this.fit,
    required this.colorFilter,
    required this.cropBorders,
    required this.backgroundColor,
    required this.maxZoom,
    required this.inPageView,
    this.onTapLeft,
    this.onTapRight,
    this.onTapCenter,
  });

  final String url;
  final LuminaReaderFit fit;
  final LuminaColorFilter colorFilter;
  final bool cropBorders;
  final Color backgroundColor;
  final double maxZoom;
  final bool inPageView;
  final VoidCallback? onTapLeft;
  final VoidCallback? onTapRight;
  final VoidCallback? onTapCenter;

  @override
  Widget build(BuildContext context) {
    Widget image = ExtendedImage.network(
      url,
      fit: fit.boxFit,
      mode: ExtendedImageMode.gesture,
      enableSlideOutPage: true,
      cache: true,
      loadStateChanged: (state) {
        if (state.extendedImageLoadState == LoadState.loading) {
          return _PagePlaceholder(child: inlineLoader(context, size: 28));
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
                  onPressed: state.reLoad,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        return state.completedWidget;
      },
      initGestureConfigHandler: (state) {
        return GestureConfig(
          minScale: 0.9,
          animationMinScale: 0.7,
          maxScale: maxZoom,
          animationMaxScale: maxZoom + 1.0,
          speed: 1.0,
          inertialSpeed: 100.0,
          initialScale: 1.0,
          inPageView: inPageView,
        );
      },
    );

    if (colorFilter.filter != null) {
      image = ColorFiltered(colorFilter: colorFilter.filter!, child: image);
    }

    if (cropBorders) {
      image = ClipRect(
        child: Align(
          alignment: Alignment.center,
          widthFactor: 0.96,
          heightFactor: 0.96,
          child: image,
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: backgroundColor),
        image,
        if (onTapLeft != null)
          Row(
            children: [
              Expanded(flex: 1, child: GestureDetector(onTap: onTapLeft)),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: onTapCenter,
                  behavior: HitTestBehavior.translucent,
                ),
              ),
              Expanded(flex: 1, child: GestureDetector(onTap: onTapRight)),
            ],
          ),
      ],
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

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.chapterName,
    required this.onClose,
    required this.onBookmark,
    required this.isBookmarked,
  });

  final String title;
  final String chapterName;
  final VoidCallback onClose;
  final VoidCallback onBookmark;
  final bool isBookmarked;

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
                IconButton(
                  icon: Icon(
                    isBookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: isBookmarked
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                  ),
                  onPressed: onBookmark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar
// ---------------------------------------------------------------------------

class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.showPageNumber,
    required this.isRtl,
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
  final bool isRtl;
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
                    child: Slider(
                      value: currentPage.toDouble().clamp(1, totalPages),
                      min: 1,
                      max: totalPages.toDouble(),
                      onChanged: onSliderChanged,
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Colors.white24,
                    ),
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
                    tooltip: isRtl ? 'Next page' : 'Previous page',
                    icon: Icon(
                      isRtl ? Icons.chevron_right : Icons.chevron_left,
                      color: Colors.white,
                    ),
                    onPressed: isRtl ? onNext : onPrev,
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
                    tooltip: isRtl ? 'Previous page' : 'Next page',
                    icon: Icon(
                      isRtl ? Icons.chevron_left : Icons.chevron_right,
                      color: Colors.white,
                    ),
                    onPressed: isRtl ? onPrev : onNext,
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

// ---------------------------------------------------------------------------
// Settings sheet
// ---------------------------------------------------------------------------

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(luminaReaderSettingsProvider);
    final notifier = ref.read(luminaReaderSettingsProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
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
                runSpacing: 4,
                children: [
                  for (final m in LuminaReaderMode.values)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: settings.mode == m,
                      onSelected: (_) => notifier.setMode(m),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _SectionLabel('Image fit'),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in LuminaReaderFit.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: settings.fit == f,
                      onSelected: (_) => notifier.setFit(f),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _SectionLabel('Color filter'),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in LuminaColorFilter.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: settings.colorFilter == c,
                      onSelected: (_) => notifier.setColorFilter(c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _SectionLabel('Background color'),
              Wrap(
                spacing: 8,
                children: [
                  _ColorSwatch(
                    color: Colors.black,
                    selected: settings.backgroundColor == Colors.black,
                    onTap: () => notifier.setBackgroundColor(Colors.black),
                  ),
                  _ColorSwatch(
                    color: Colors.grey[900]!,
                    selected:
                        settings.backgroundColor == Colors.grey[900],
                    onTap: () =>
                        notifier.setBackgroundColor(Colors.grey[900]!),
                  ),
                  _ColorSwatch(
                    color: Colors.grey[800]!,
                    selected:
                        settings.backgroundColor == Colors.grey[800],
                    onTap: () =>
                        notifier.setBackgroundColor(Colors.grey[800]!),
                  ),
                  _ColorSwatch(
                    color: const Color(0xFFF5DEB3),
                    selected:
                        settings.backgroundColor == const Color(0xFFF5DEB3),
                    onTap: () => notifier.setBackgroundColor(
                        const Color(0xFFF5DEB3)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Crop borders'),
                value: settings.cropBorders,
                onChanged: (_) => notifier.toggleCropBorders(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Double-page spread (landscape)'),
                value: settings.doublePageSpread,
                onChanged: (_) => notifier.toggleDoublePageSpread(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show page number'),
                value: settings.showPageNumber,
                onChanged: (_) => notifier.togglePageNumber(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tap to navigate'),
                value: settings.tapToNavigate,
                onChanged: (_) => notifier.toggleTapToNavigate(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep screen on'),
                value: settings.keepScreenOn,
                onChanged: (_) => notifier.toggleKeepScreenOn(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Full screen'),
                value: settings.fullScreen,
                onChanged: (_) {
                  notifier.toggleFullScreen();
                  // Apply immediately so the user sees the effect.
                  if (settings.fullScreen) {
                    SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.edgeToEdge);
                  } else {
                    SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.immersiveSticky);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Converts a [Chapter] from the legacy model into the current reader's
/// progress map (used by [ChapterPreloader] consumers).
extension ChapterProgressX on Chapter {
  Map<String, dynamic> toProgressMap() => {
        'chapterId': id,
        'lastPageRead': lastPageRead,
        'totalPages': totalPages,
        'progress': progress,
        'isRead': isRead,
        'isBookmarked': isBookmarked,
      };
}

/// A [ScrollController]-free pagination helper used by tests / preview when
/// no [PageController] is available.
class PagedIndexTracker {
  PagedIndexTracker(this.total);
  final int total;
  int _current = 0;
  int get current => _current;
  bool get hasNext => _current < total - 1;
  bool get hasPrev => _current > 0;
  void next() => _current = (_current + 1).clamp(0, total - 1);
  void prev() => _current = (_current - 1).clamp(0, total - 1);
  void jump(int p) => _current = p.clamp(0, total - 1);
}

/// Stub for legacy callers expecting a non-Riverpod API surface.
class ReaderViewLegacy {
  ReaderViewLegacy({required this.mangaId, required this.chapterId});
  final int mangaId;
  final int chapterId;

  Widget build(BuildContext context) => ReaderView(
        mangaId: mangaId,
        chapterId: chapterId,
      );
}
