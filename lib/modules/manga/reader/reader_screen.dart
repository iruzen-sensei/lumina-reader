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

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
    with SingleTickerProviderStateMixin {
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

  // Current chapter pointer so chapter navigation can mutate it.
  late Chapter _chapter;
  Manga? _manga;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _itemPositionsListener.itemPositions.addListener(_onListPositionsChanged);
    _sessionStart = DateTime.now();
    _loadChapter();
  }

  @override
  void dispose() {
    _flushProgress();
    _recordSession();
    _progressSaveDebounce?.cancel();
    _pageController.dispose();
    _hideTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onListPositionsChanged);
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
      _currentPage =
          _totalPages > 0 ? chapter.lastPageRead.clamp(0, _totalPages - 1) : 0;
      _isLoadingChapter = _totalPages == 0; // until pages stream in
    });
    unawaited(_recordHistoryRead(0));
  }

  void _onListPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions.first;
    if (first.index != _currentPage) {
      setState(() => _currentPage = first.index);
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
    _onPageSettled();
  }

  /// Persists reading progress (debounced — fires at most every 2 s).
  void _onPageSettled() {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(const Duration(seconds: 2), _flushProgress);
  }

  Future<void> _flushProgress() async {
    if (_manga == null || _notFound) return;
    final completed = _totalPages > 0 && _currentPage >= _totalPages - 1;
    try {
      await ref.read(data.libraryRepositoryProvider).saveChapterProgress(
            _chapter.id,
            lastPageRead: _currentPage,
            isRead: completed || _chapter.isRead,
            pageCount: _totalPages,
          );
      if (completed && !_chapter.isRead) {
        _chapter.isRead = true;
        await ref.read(data.statsRepositoryProvider).maybeMarkFinished(_manga!.id);
      }
    } catch (_) {
      // Progress persistence is best-effort; never crash the reader.
    }
    unawaited(_recordHistoryRead(completed ? 1 : 0));
  }

  Future<void> _recordHistoryRead(double progressOverride) async {
    if (ref.read(incognitoModeProvider) || _manga == null) return;
    try {
      final progress = progressOverride > 0
          ? progressOverride
          : (_totalPages > 0 ? _currentPage / _totalPages : 0.0);
      await ref.read(data.historyRepositoryProvider).recordRead(
            mangaId: _manga!.id,
            chapterId: _chapter.id,
            chapterName: _chapter.name,
            chapterNumber: _chapter.number,
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
    if (ref.read(incognitoModeProvider) || _manga == null) return;
    final seconds = DateTime.now().difference(_sessionStart).inSeconds;
    if (seconds < 5) return;
    _sessionStart = DateTime.now();
    try {
      await ref.read(data.statsRepositoryProvider).recordSession(
        mangaId: _manga!.id,
        chapterId: _chapter.id,
        pagesRead: 1,
        durationSeconds: seconds,
      );
    } catch (_) {}
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
      await _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      unawaited(_itemScrollController.scrollTo(
        index: page,
        duration: const Duration(milliseconds: 220),
      ));
    }
    setState(() => _currentPage = page);
  }

  void _nextPage() => _goToPage(_currentPage + 1);
  void _prevPage() => _goToPage(_currentPage - 1);

  Future<void> _nextChapter() async {
    final manga = _manga;
    if (manga == null) return;
    final idx = manga.chapters.indexWhere((c) => c.id == _chapter.id);
    if (idx <= 0) {
      showSnack(ref, context, 'Already at the first chapter');
      return;
    }
    await _flushProgress();
    await _recordSession();
    final next = manga.chapters[idx - 1];
    if (!mounted) return;
    setState(() {
      _chapter = next;
      _totalPages = ref.read(readerPagesProvider(next.id)).length;
      _currentPage = 0;
      _isLoadingChapter = _totalPages == 0;
    });
    unawaited(_recordHistoryRead(0));
    if (ref.read(readerSettingsProvider).mode == ReaderMode.paged &&
        _pageController.hasClients) {
      _pageController.jumpToPage(0);
    } else {
      _itemScrollController.jumpTo(index: 0);
    }
  }

  Future<void> _prevChapter() async {
    final manga = _manga;
    if (manga == null) return;
    final idx = manga.chapters.indexWhere((c) => c.id == _chapter.id);
    if (idx >= manga.chapters.length - 1) {
      showSnack(ref, context, 'Already at the last chapter');
      return;
    }
    await _flushProgress();
    await _recordSession();
    final prev = manga.chapters[idx + 1];
    if (!mounted) return;
    setState(() {
      _chapter = prev;
      _totalPages = ref.read(readerPagesProvider(prev.id)).length;
      _currentPage = _totalPages > 0 ? _totalPages - 1 : 0;
      _isLoadingChapter = _totalPages == 0;
    });
    unawaited(_recordHistoryRead(0));
    if (ref.read(readerSettingsProvider).mode == ReaderMode.paged &&
        _pageController.hasClients) {
      _pageController.jumpToPage(_currentPage);
    } else {
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

    final settings = ref.watch(readerSettingsProvider);
    final pages = ref.watch(readerPagesProvider(_chapter.id));

    // React when the async page list arrives (or grows).
    ref.listen(readerPagesProvider(_chapter.id), (prev, next) {
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
        });
      }
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
            _ReaderBody(
              settings: settings,
              pages: pages,
              pageController: _pageController,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              initialPage: _currentPage,
              onTapLeft: settings.tapToNavigate ? _prevPage : _toggleControls,
              onTapRight: settings.tapToNavigate ? _nextPage : _toggleControls,
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
          chapterName: _chapter.name,
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
    this.onPageChanged,
  });

  final ReaderSettings settings;
  final List<String> pages;
  final PageController pageController;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final int initialPage;
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
    this.onPageChanged,
  });

  final ReaderSettings settings;
  final List<String> pages;
  final PageController controller;
  final int initialPage;
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
        onTapLeft: widget.onTapLeft,
        onTapRight: widget.onTapRight,
        onTapCenter: widget.onTapCenter,
      ),
    );
  }
}

class _ContinuousBody extends StatelessWidget {
  const _ContinuousBody({
    required this.settings,
    required this.pages,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.initialPage,
    required this.isWebtoon,
  });

  final ReaderSettings settings;
  final List<String> pages;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final int initialPage;
  final bool isWebtoon;

  @override
  Widget build(BuildContext context) {
    return ScrollablePositionedList.builder(
      initialScrollIndex: initialPage,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      padding: EdgeInsets.symmetric(vertical: isWebtoon ? 24 : 0),
      itemCount: pages.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _ReaderPage(
          url: pages[index],
          fit: isWebtoon ? ReaderFit.contain : settings.fit,
          isWebtoon: isWebtoon,
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
    this.onTapLeft,
    this.onTapRight,
    this.onTapCenter,
    this.isWebtoon = false,
  });

  final String url;
  final ReaderFit fit;
  final VoidCallback? onTapLeft;
  final VoidCallback? onTapRight;
  final VoidCallback? onTapCenter;
  final bool isWebtoon;

  @override
  Widget build(BuildContext context) {
    final boxFit = switch (fit) {
      ReaderFit.contain => BoxFit.contain,
      ReaderFit.cover => BoxFit.cover,
      ReaderFit.fill => BoxFit.fill,
      ReaderFit.original => BoxFit.none,
    };
    return Stack(
      fit: isWebtoon ? StackFit.loose : StackFit.expand,
      children: [
        ExtendedImage.network(
          url,
          fit: boxFit,
          mode: ExtendedImageMode.gesture,
          enableSlideOutPage: true,
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
                      // extended_image 8.x: the retry hook is `reLoadImage`
                      // (the old `reLoad` getter no longer exists).
                      onPressed: state.reLoadImage,
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
              maxScale: 4.0,
              animationMaxScale: 4.5,
              speed: 1.0,
              inertialSpeed: 100.0,
              initialScale: 1.0,
              inPageView: !isWebtoon,
            );
          },
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
                    child: Slider(
                      value: currentPage.toDouble().clamp(1, totalPages).toDouble(),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
        return 'Fit';
      case ReaderFit.cover:
        return 'Cover';
      case ReaderFit.fill:
        return 'Stretch';
      case ReaderFit.original:
        return 'Original';
    }
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
