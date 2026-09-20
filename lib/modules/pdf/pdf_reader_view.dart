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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/providers.dart' as data;
import '../../models/models.dart';
import '../../providers/providers.dart' show incognitoModeProvider;
import '../shared/widgets.dart';

// ---------------------------------------------------------------------------
// Provider contracts
// ---------------------------------------------------------------------------

/// A bookmark within a PDF document.
class PdfBookmark {
  PdfBookmark({
    required this.id,
    required this.page,
    required this.label,
    required this.createdAt,
  });

  String id;
  final int page;
  final String label;
  final DateTime createdAt;
}

/// User-tunable PDF reader settings.
class PdfReaderSettings {
  PdfReaderSettings({
    this.keepScreenOn = true,
    this.showThumbnails = true,
    this.fitPolicy = PdfPageFitPolicy.fitWidth,
  });

  final bool keepScreenOn;
  final bool showThumbnails;
  final PdfPageFitPolicy fitPolicy;

  PdfReaderSettings copyWith({
    bool? keepScreenOn,
    bool? showThumbnails,
    PdfPageFitPolicy? fitPolicy,
  }) {
    return PdfReaderSettings(
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      showThumbnails: showThumbnails ?? this.showThumbnails,
      fitPolicy: fitPolicy ?? this.fitPolicy,
    );
  }
}

enum PdfPageFitPolicy { fitWidth, fitHeight, fitBoth, original }

extension PdfPageFitPolicyX on PdfPageFitPolicy {
  String get label {
    switch (this) {
      case PdfPageFitPolicy.fitWidth:
        return 'Fit width';
      case PdfPageFitPolicy.fitHeight:
        return 'Fit height';
      case PdfPageFitPolicy.fitBoth:
        return 'Fit both';
      case PdfPageFitPolicy.original:
        return 'Original';
    }
  }
}

class PdfReaderSettingsNotifier extends StateNotifier<PdfReaderSettings> {
  PdfReaderSettingsNotifier() : super(PdfReaderSettings());

  void toggleKeepScreenOn() =>
      state = state.copyWith(keepScreenOn: !state.keepScreenOn);
  void toggleThumbnails() =>
      state = state.copyWith(showThumbnails: !state.showThumbnails);
  void setFitPolicy(PdfPageFitPolicy p) => state = state.copyWith(fitPolicy: p);
}

final pdfReaderSettingsProvider = StateNotifierProvider<
    PdfReaderSettingsNotifier, PdfReaderSettings>(
  (ref) => PdfReaderSettingsNotifier(),
);

// ---------------------------------------------------------------------------
// PdfReaderView
// ---------------------------------------------------------------------------

/// The PDF reader view.
///
/// Renders PDF documents via [pdfrx] with pinch-to-zoom, page navigation,
/// a thumbnail sidebar, bookmark support and landscape/portrait
/// orientation support.
class PdfReaderView extends ConsumerStatefulWidget {
  const PdfReaderView({
    super.key,
    required this.path,
    this.title,
    this.initialPage = 1,
    this.mangaId,
  });

  /// Local file path to the .pdf document.
  final String path;

  /// Optional fallback title shown while the PDF is loading.
  final String? title;

  /// 1-based initial page number.
  final int initialPage;

  /// Library entry id — enables progress / history / bookmark persistence.
  final int? mangaId;

  @override
  ConsumerState<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends ConsumerState<PdfReaderView> {
  PdfDocument? _document;
  bool _loading = true;
  String? _error;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _controlsVisible = true;
  bool _thumbnailSidebarOpen = false;
  bool _landscape = false;
  final List<PdfBookmark> _bookmarks = [];
  final GlobalKey _viewerKey = GlobalKey();

  /// Drives the actual document scroll (pdfrx). Previously absent — every
  /// "go to page" affordance only repainted the page LABEL while the
  /// document never moved.
  final PdfViewerController _pdfController = PdfViewerController();

  Timer? _progressSaver;
  bool _restoredInitialPage = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _loadDocument();
    _loadBookmarks();
    if (ref.read(pdfReaderSettingsProvider).keepScreenOn) {
      WakelockPlus.enable();
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _progressSaver?.cancel();
    unawaited(_flushProgress(isFinal: true));
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Progress persistence (saveBookProgress + history)
  // -------------------------------------------------------------------------

  void _scheduleProgressSave() {
    if (widget.mangaId == null) return;
    _progressSaver?.cancel();
    _progressSaver = Timer(const Duration(seconds: 3), () => _flushProgress());
  }

  Future<void> _flushProgress({bool isFinal = false}) async {
    final id = widget.mangaId;
    if (id == null || _totalPages <= 0) return;
    if (ref.read(incognitoModeProvider)) return;
    try {
      await ref.read(data.libraryRepositoryProvider).saveBookProgress(
            id,
            currentPage: _currentPage,
            totalPages: _totalPages,
            progress: (_currentPage / _totalPages).clamp(0.0, 1.0),
            isFinished: _currentPage >= _totalPages,
          );
      if (isFinal) {
        final manga = await ref.read(data.libraryRepositoryProvider).getManga(id);
        if (manga != null) {
          await ref.read(data.historyRepositoryProvider).recordRead(
                mangaId: id,
                chapterId: 0,
                chapterName: 'PDF',
                chapterNumber: _currentPage.toDouble(),
                mangaTitle: manga.title,
                mangaCover: manga.thumbnailUrl,
                isAnime: false,
                progress: (_currentPage / _totalPages).clamp(0.0, 1.0),
                page: _currentPage,
                totalPages: _totalPages,
              );
        }
      }
    } catch (_) {
      // Persistence must never break reading.
    }
  }

  // -------------------------------------------------------------------------
  // Bookmark persistence (stored as tagged Notes)
  // -------------------------------------------------------------------------

  Future<void> _loadBookmarks() async {
    final id = widget.mangaId;
    if (id == null) return;
    try {
      final notes = await ref.read(data.notesRepositoryProvider).getNotes();
      final marks = notes
          .where((n) =>
              n.mangaId == id &&
              n.type == NoteType.thought &&
              n.tags.contains('pdf-bookmark'))
          .toList();
      if (!mounted) return;
      setState(() {
        _bookmarks
          ..clear()
          ..addAll([
            for (final m in marks)
              PdfBookmark(
                id: m.id.toString(),
                page: m.page,
                label: 'Page ${m.page}',
                createdAt: m.createdAt,
              )
          ]);
      });
    } catch (_) {}
  }

  void _toggleBookmark() {
    final existing =
        _bookmarks.where((b) => b.page == _currentPage).firstOrNull;
    if (existing != null) {
      setState(() => _bookmarks.remove(existing));
      final noteId = int.tryParse(existing.id);
      if (noteId != null) {
        ref.read(data.notesRepositoryProvider).deleteNote(noteId);
      }
      showSnack(ref, context, 'Bookmark removed');
    } else {
      final mark = PdfBookmark(
        id: 'bm-${DateTime.now().millisecondsSinceEpoch}',
        page: _currentPage,
        label: 'Page $_currentPage',
        createdAt: DateTime.now(),
      );
      setState(() => _bookmarks.add(mark));
      final id = widget.mangaId;
      if (id != null) {
          ref.read(data.notesRepositoryProvider).addNote(
              mangaId: id,
              text: 'Bookmark — page $_currentPage',
              type: NoteType.thought,
              color: NoteColor.purple,
              page: _currentPage,
              tags: const ['pdf-bookmark'],
            ).then((newId) {
          // Swap the temp id for the persisted note id so removal works.
          if (mounted) {
            setState(() => mark.id = newId.toString());
          }
        });
      }
      showSnack(ref, context, 'Bookmark added');
    }
  }

  /// Maps the fit-policy setting to a real pdfrx sizing delegate
  /// (previously the chips wrote to a provider nothing consumed):
  ///  * fitWidth  → Smart delegate (auto-fits page width)
  ///  * fitHeight → legacy initial zoom = fit-page (page fully visible)
  ///  * fitBoth   → legacy initial zoom = fit-page
  ///  * original  → legacy initial zoom = 1.0 (100%)
  PdfViewerSizeDelegateProvider _sizeDelegateFor(PdfPageFitPolicy p) {
    switch (p) {
      case PdfPageFitPolicy.fitWidth:
        return const PdfViewerSizeDelegateProviderSmart();
      case PdfPageFitPolicy.fitHeight:
      case PdfPageFitPolicy.fitBoth:
        return PdfViewerSizeDelegateProviderLegacy(
          calculateInitialZoom: (document, controller, fitZoom, coverZoom) =>
              math.min(fitZoom, coverZoom),
        );
      case PdfPageFitPolicy.original:
        return const PdfViewerSizeDelegateProviderLegacy(
          calculateInitialZoom: _originalZoom,
        );
    }
  }

  /// 100% zoom (PDF points = device logical pixels, approx).
  static double? _originalZoom(
      PdfDocument document, PdfViewerController controller, double fitZoom, double coverZoom) {
    return 1.0;
  }

  Future<void> _loadDocument() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await PdfDocument.openFile(widget.path);
      if (!mounted) {
        unawaited(doc.dispose());
        return;
      }
      setState(() {
        _document = doc;
        _totalPages = doc.pages.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to open PDF: $e';
      });
    }
  }

  void _toggleControls() => setState(() => _controlsVisible = !_controlsVisible);

  void _toggleLandscape() {
    setState(() => _landscape = !_landscape);
    if (_landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  Future<void> _goToPage(int page) async {
    if (page < 1 || page > _totalPages) return;
    setState(() => _currentPage = page);
    // REAL navigation — scrolls the document itself (previously this only
    // repainted the "Page X of Y" label and the viewer never moved).
    try {
      await _pdfController.goToPage(pageNumber: page);
    } catch (_) {
      // Controller not attached yet — the page state is tracked above.
    }
    _scheduleProgressSave();
  }

  void _nextPage() => _goToPage(_currentPage + 1);
  void _prevPage() => _goToPage(_currentPage - 1);

  void _openBookmark(PdfBookmark bm) {
    _goToPage(bm.page);
    setState(() => _thumbnailSidebarOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(pdfReaderSettingsProvider);

    // Live wakelock toggling (previously only read once in initState).
    ref.listen<PdfReaderSettings>(pdfReaderSettingsProvider, (prev, next) {
      if (prev?.keepScreenOn != next.keepScreenOn) {
        if (next.keepScreenOn) {
          unawaited(WakelockPlus.enable());
        } else {
          unawaited(WakelockPlus.disable());
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _loadDocument)
                : _document == null
                    ? const Center(child: Text('No document'))
                    : Stack(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _toggleControls,
                            child: PdfViewer(
                              // pdfrx 2.x: the viewer takes a document
                              // *reference* positionally; PdfDocumentRefDirect
                              // wraps the already-loaded [PdfDocument].
                              PdfDocumentRefDirect(_document!),
                              key: _viewerKey,
                              controller: _pdfController,
                              params: PdfViewerParams(
                                // REAL fit policy (previously the chips wrote
                                // to a provider nothing consumed).
                                sizeDelegateProvider:
                                    _sizeDelegateFor(settings.fitPolicy),
                                onPageChanged: (page) {
                                  if (page != null) {
                                    setState(() => _currentPage = page + 1);
                                    _scheduleProgressSave();
                                  }
                                },
                                onViewerReady: (document, controller) {
                                  // Resume at the saved page (only once).
                                  if (!_restoredInitialPage &&
                                      widget.initialPage > 1 &&
                                      widget.initialPage <= _totalPages) {
                                    _restoredInitialPage = true;
                                    unawaited(controller.goToPage(
                                        pageNumber: widget.initialPage));
                                  }
                                },
                                pageOverlaysBuilder: (context, pageRect, page) {
                                  return [
                                    Positioned(
                                      top: 4,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${page.pageNumber} / $_totalPages',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ];
                                },
                              ),
                            ),
                          ),
                          if (_controlsVisible) _buildTopBar(),
                          if (_controlsVisible) _buildBottomBar(settings),
                          if (_thumbnailSidebarOpen)
                            _buildThumbnailSidebar(settings),
                        ],
                      ),
      ),
    );
  }

  Widget _buildTopBar() {
    final title = widget.title ??
        _document?.sourceName ??
        'PDF';
    final settings = ref.read(pdfReaderSettingsProvider);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ),
                // Thumbnail sidebar toggle — only offered when the
                // persisted settings enable thumbnails (the switch
                // previously toggled a value nothing consumed).
                if (settings.showThumbnails)
                  IconButton(
                    tooltip: 'Thumbnails',
                    icon: const Icon(Icons.view_carousel, color: Colors.white),
                    onPressed: () => setState(() =>
                        _thumbnailSidebarOpen = !_thumbnailSidebarOpen),
                  ),
                IconButton(
                  tooltip: 'Bookmark page',
                  icon: Icon(
                    _bookmarks.any((b) => b.page == _currentPage)
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _toggleBookmark,
                ),
                IconButton(
                  tooltip: 'Bookmarks',
                  icon: const Icon(Icons.bookmarks_outlined,
                      color: Colors.white),
                  onPressed: _showBookmarksSheet,
                ),
                IconButton(
                  tooltip: _landscape ? 'Portrait' : 'Landscape',
                  icon: Icon(
                    _landscape
                        ? Icons.stay_current_portrait
                        : Icons.stay_current_landscape,
                    color: Colors.white,
                  ),
                  onPressed: _toggleLandscape,
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune, color: Colors.white),
                  onPressed: _showSettingsSheet,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(PdfReaderSettings settings) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
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
                      tooltip: 'Previous page',
                      icon: const Icon(Icons.chevron_left,
                          color: Colors.white),
                      onPressed: _prevPage,
                    ),
                    Expanded(
                      child: Slider(
                        value: _currentPage.toDouble().clamp(1, _totalPages).toDouble(),
                        min: 1,
                        max: _totalPages.toDouble(),
                        onChanged: (v) => _goToPage(v.round()),
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: Colors.white24,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next page',
                      icon: const Icon(Icons.chevron_right,
                          color: Colors.white),
                      onPressed: _nextPage,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Page $_currentPage of $_totalPages',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailSidebar(PdfReaderSettings settings) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 220,
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text('Pages',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(
                          () => _thumbnailSidebarOpen = false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _document == null
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _totalPages,
                        itemBuilder: (context, index) {
                          final pageNum = index + 1;
                          final selected = pageNum == _currentPage;
                          return GestureDetector(
                            onTap: () {
                              _goToPage(pageNum);
                              setState(
                                  () => _thumbnailSidebarOpen = false);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white24,
                                  width: selected ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  AspectRatio(
                                    aspectRatio: 0.7,
                                    child: PdfPageView(
                                      document: _document!,
                                      pageNumber: pageNum,
                                      // pdfrx 2.x: PdfPageView takes
                                      // backgroundColor directly; the old
                                      // PdfPageViewParams wrapper is gone.
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$pageNum',
                                    style: TextStyle(
                                      color: selected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const PdfReaderSettingsSheet(),
    );
  }

  void _showBookmarksSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bookmarks',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (_bookmarks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('No bookmarks yet')),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _bookmarks.length,
                    itemBuilder: (context, i) {
                      final bm = _bookmarks[i];
                      return ListTile(
                        leading: const Icon(Icons.bookmark),
                        title: Text(bm.label),
                        subtitle: Text(
                          '${bm.createdAt.toLocal()}'.split('.').first,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _openBookmark(bm);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() => _bookmarks.removeAt(i));
                            Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  ),
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

class PdfReaderSettingsSheet extends ConsumerWidget {
  const PdfReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(pdfReaderSettingsProvider);
    final notifier = ref.read(pdfReaderSettingsProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reader settings',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text('Fit policy'),
            Wrap(
              spacing: 8,
              children: [
                for (final p in PdfPageFitPolicy.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: settings.fitPolicy == p,
                    onSelected: (_) => notifier.setFitPolicy(p),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show thumbnail sidebar'),
              value: settings.showThumbnails,
              onChanged: (_) => notifier.toggleThumbnails(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep screen on'),
              value: settings.keepScreenOn,
              onChanged: (_) => notifier.toggleKeepScreenOn(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
