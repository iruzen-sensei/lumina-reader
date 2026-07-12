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
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../shared/widgets.dart';

// ---------------------------------------------------------------------------
// Provider contracts
// ---------------------------------------------------------------------------

/// Background color theme for the EPUB reader.
enum EpubBackgroundTheme { black, grey, white, sepia, cream }

extension EpubBackgroundThemeX on EpubBackgroundTheme {
  Color get color {
    switch (this) {
      case EpubBackgroundTheme.black:
        return const Color(0xFF000000);
      case EpubBackgroundTheme.grey:
        return const Color(0xFF212121);
      case EpubBackgroundTheme.white:
        return const Color(0xFFFFFFFF);
      case EpubBackgroundTheme.sepia:
        return const Color(0xFFF5DEB3);
      case EpubBackgroundTheme.cream:
        return const Color(0xFFFFFBF0);
    }
  }

  Color get foreground {
    switch (this) {
      case EpubBackgroundTheme.black:
      case EpubBackgroundTheme.grey:
        return Colors.white;
      case EpubBackgroundTheme.white:
      case EpubBackgroundTheme.sepia:
      case EpubBackgroundTheme.cream:
        return Colors.black87;
    }
  }

  String get label {
    switch (this) {
      case EpubBackgroundTheme.black:
        return 'Black';
      case EpubBackgroundTheme.grey:
        return 'Grey';
      case EpubBackgroundTheme.white:
        return 'White';
      case EpubBackgroundTheme.sepia:
        return 'Sepia';
      case EpubBackgroundTheme.cream:
        return 'Cream';
    }
  }
}

class EpubReaderSettings {
  EpubReaderSettings({
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.fontFamily = 'serif',
    this.background = EpubBackgroundTheme.white,
    this.keepScreenOn = true,
  });

  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final EpubBackgroundTheme background;
  final bool keepScreenOn;

  EpubReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    EpubBackgroundTheme? background,
    bool? keepScreenOn,
  }) {
    return EpubReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      background: background ?? this.background,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
}

class EpubReaderSettingsNotifier extends StateNotifier<EpubReaderSettings> {
  EpubReaderSettingsNotifier() : super(EpubReaderSettings());

  void setFontSize(double v) => state = state.copyWith(fontSize: v);
  void setLineHeight(double v) => state = state.copyWith(lineHeight: v);
  void setFontFamily(String f) => state = state.copyWith(fontFamily: f);
  void setBackground(EpubBackgroundTheme b) =>
      state = state.copyWith(background: b);
  void toggleKeepScreenOn() =>
      state = state.copyWith(keepScreenOn: !state.keepScreenOn);
}

final epubReaderSettingsProvider = StateNotifierProvider<
    EpubReaderSettingsNotifier, EpubReaderSettings>(
  (ref) => EpubReaderSettingsNotifier(),
);

/// A simplified representation of an EPUB chapter for the reader.
class EpubChapterView {
  EpubChapterView({
    required this.id,
    required this.title,
    required this.html,
    this.href,
  });

  final String id;
  final String title;
  final String html;
  final String? href;
}

/// A bookmark within an EPUB book.
class EpubBookmark {
  EpubBookmark({
    required this.id,
    required this.chapterId,
    required this.position,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final String chapterId;
  final double position; // 0..1 scroll position within chapter
  final String label;
  final DateTime createdAt;
}

/// Loads an EPUB from a file path or byte array and exposes its chapters.
class EpubLoader {
  EpubLoader._();

  static Future<EpubBook> fromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return fromBytes(bytes);
  }

  static Future<EpubBook> fromBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    return EpubReader.readBook(archive);
  }

  /// Flattens an [EpubBook]'s spine into a list of [EpubChapterView]s.
  static List<EpubChapterView> flattenChapters(EpubBook book) {
    final views = <EpubChapterView>[];

    void walk(EpubChapter chapter, {int depth = 0}) {
      final html = chapter.HtmlContent ?? '';
      views.add(EpubChapterView(
        id: chapter.ContentFileName ?? '${views.length}',
        title: chapter.Title ?? 'Chapter ${views.length + 1}',
        html: html,
        href: chapter.ContentFileName,
      ));
      for (final sub in chapter.SubChapters ?? const <EpubChapter>[]) {
        walk(sub, depth: depth + 1);
      }
    }

    if (book.Chapters?.isNotEmpty ?? false) {
      for (final c in book.Chapters!) {
        walk(c);
      }
    } else {
      // Fallback: derive from the spine content directly.
      final content = book.Content;
      final htmlFiles = content?.Html?.values.toList() ?? const [];
      for (var i = 0; i < htmlFiles.length; i++) {
        views.add(EpubChapterView(
          id: '${i + 1}',
          title: 'Section ${i + 1}',
          html: htmlFiles[i].Content ?? '',
        ));
      }
    }

    if (views.isEmpty) {
      views.add(EpubChapterView(
        id: 'empty',
        title: 'No content',
        html: '<p>This EPUB appears to be empty.</p>',
      ));
    }
    return views;
  }
}

// ---------------------------------------------------------------------------
// EpubReaderView
// ---------------------------------------------------------------------------

/// The EPUB reader view.
///
/// Parses EPUB files via [epubx], renders each chapter's HTML via
/// [flutter_html], and provides chapter-list navigation, font size / family
/// controls, background theme switching, bookmark management, reading
/// progress tracking and full-text search across the book.
class EpubReaderView extends ConsumerStatefulWidget {
  const EpubReaderView({
    super.key,
    required this.path,
    this.title,
  });

  /// Local file path to the .epub archive.
  final String path;

  /// Optional fallback title shown while the EPUB is loading.
  final String? title;

  @override
  ConsumerState<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends ConsumerState<EpubReaderView> {
  bool _loading = true;
  String? _error;
  EpubBook? _book;
  List<EpubChapterView> _chapters = const [];
  int _currentChapterIndex = 0;
  bool _controlsVisible = true;
  bool _chapterListOpen = false;
  final ScrollController _scrollController = ScrollController();
  final List<EpubBookmark> _bookmarks = [];
  double _readingProgress = 0;
  String _searchQuery = '';
  List<({int chapter, int offset})> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadBook();
    if (ref.read(epubReaderSettingsProvider).keepScreenOn) {
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadBook() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final book = await EpubLoader.fromFile(widget.path);
      final chapters = EpubLoader.flattenChapters(book);
      if (!mounted) return;
      setState(() {
        _book = book;
        _chapters = chapters;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to open book: $e';
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    final progress = max <= 0 ? 0 : (offset / max).clamp(0.0, 1.0);
    if ((progress - _readingProgress).abs() > 0.01) {
      setState(() => _readingProgress = progress);
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  Future<void> _goToChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _currentChapterIndex = index;
      _chapterListOpen = false;
      _readingProgress = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _nextChapter() async {
    if (_currentChapterIndex >= _chapters.length - 1) {
      showSnack(ref, context, 'Already at the last chapter');
      return;
    }
    await _goToChapter(_currentChapterIndex + 1);
  }

  Future<void> _prevChapter() async {
    if (_currentChapterIndex <= 0) {
      showSnack(ref, context, 'Already at the first chapter');
      return;
    }
    await _goToChapter(_currentChapterIndex - 1);
  }

  void _toggleBookmark() {
    final chapter = _chapters[_currentChapterIndex];
    final existing = _bookmarks
        .where((b) => b.chapterId == chapter.id)
        .where((b) => (b.position - _readingProgress).abs() < 0.02)
        .firstOrNull;
    if (existing != null) {
      setState(() => _bookmarks.remove(existing));
      showSnack(ref, context, 'Bookmark removed');
    } else {
      setState(() {
        _bookmarks.add(EpubBookmark(
          id: '${chapter.id}-${DateTime.now().millisecondsSinceEpoch}',
          chapterId: chapter.id,
          position: _readingProgress,
          label: '${chapter.title} (${(_readingProgress * 100).round()}%)',
          createdAt: DateTime.now(),
        ));
      });
      showSnack(ref, context, 'Bookmark added');
    }
  }

  void _openBookmark(EpubBookmark bm) {
    final idx = _chapters.indexWhere((c) => c.id == bm.chapterId);
    if (idx < 0) return;
    _goToChapter(idx).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final max = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(max * bm.position);
        }
      });
    });
  }

  void _runSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = const [];
      });
      return;
    }
    final results = <({int chapter, int offset})>[];
    final lower = query.toLowerCase();
    for (var i = 0; i < _chapters.length; i++) {
      final html = _chapters[i].html.toLowerCase();
      var start = 0;
      while (true) {
        final idx = html.indexOf(lower, start);
        if (idx < 0) break;
        results.add((chapter: i, offset: idx));
        start = idx + 1;
        if (results.length >= 200) break;
      }
    }
    setState(() {
      _searchQuery = query;
      _searchResults = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(epubReaderSettingsProvider);
    return Scaffold(
      backgroundColor: settings.background.color,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _loadBook)
                : Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        child: _EpubContent(
                          chapter: _chapters[_currentChapterIndex],
                          settings: settings,
                          scrollController: _scrollController,
                        ),
                      ),
                      if (_controlsVisible) _buildTopBar(settings),
                      if (_controlsVisible) _buildBottomBar(settings),
                      if (_chapterListOpen) _buildChapterList(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildTopBar(EpubReaderSettings settings) {
    final title = _book?.Title ?? widget.title ?? 'EPUB';
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: settings.background.color.withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: settings.background.foreground),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: settings.background.foreground,
                              fontWeight: FontWeight.w600)),
                      Text(
                        _chapters[_currentChapterIndex].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: settings.background.foreground
                                .withValues(alpha: 0.7),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.search,
                      color: settings.background.foreground),
                  onPressed: _showSearchSheet,
                ),
                IconButton(
                  icon: Icon(Icons.bookmark_border_outlined,
                      color: settings.background.foreground),
                  onPressed: _toggleBookmark,
                ),
                IconButton(
                  icon: Icon(Icons.bookmarks_outlined,
                      color: settings.background.foreground),
                  onPressed: _showBookmarksSheet,
                ),
                IconButton(
                  icon: Icon(Icons.list, color: settings.background.foreground),
                  onPressed: () => setState(
                      () => _chapterListOpen = !_chapterListOpen),
                ),
                IconButton(
                  icon: Icon(Icons.tune,
                      color: settings.background.foreground),
                  onPressed: _showSettingsSheet,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(EpubReaderSettings settings) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: settings.background.color.withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _readingProgress,
                  backgroundColor:
                      settings.background.foreground.withValues(alpha: 0.1),
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous chapter',
                      icon: Icon(Icons.skip_previous_rounded,
                          color: settings.background.foreground),
                      onPressed: _prevChapter,
                    ),
                    Expanded(
                      child: Slider(
                        value: _readingProgress,
                        onChanged: (v) {
                          if (_scrollController.hasClients) {
                            final max = _scrollController
                                .position.maxScrollExtent;
                            _scrollController.jumpTo(max * v);
                          }
                        },
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: settings.background.foreground
                            .withValues(alpha: 0.1),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next chapter',
                      icon: Icon(Icons.skip_next_rounded,
                          color: settings.background.foreground),
                      onPressed: _nextChapter,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChapterList() {
    final settings = ref.watch(epubReaderSettingsProvider);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 320,
        color: settings.background.color.withValues(alpha: 0.97),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text('Contents',
                        style: TextStyle(
                            color: settings.background.foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: settings.background.foreground),
                      onPressed: () =>
                          setState(() => _chapterListOpen = false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _chapters.length,
                  itemBuilder: (context, index) {
                    final ch = _chapters[index];
                    final selected = index == _currentChapterIndex;
                    return ListTile(
                      title: Text(
                        ch.title,
                        style: TextStyle(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : settings.background.foreground,
                        ),
                      ),
                      onTap: () => _goToChapter(index),
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
      builder: (context) => const EpubReaderSettingsSheet(),
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
                          '${bm.createdAt.toLocal()}'
                          .split('.').first,
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

  void _showSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Search in book',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (q) {
                      _runSearch(q);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_searchQuery.isNotEmpty)
                    Text('${_searchResults.length} results'),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, i) {
                        final r = _searchResults[i];
                        final ch = _chapters[r.chapter];
                        final snippet = _extractSnippet(ch.html, r.offset);
                        return ListTile(
                          title: Text(ch.title),
                          subtitle: Text(snippet,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(context);
                            _goToChapter(r.chapter);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _extractSnippet(String html, int offset) {
    final clean = html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final start = (offset - 40).clamp(0, clean.length);
    final end = (offset + 80).clamp(0, clean.length);
    final pre = start > 0 ? '…' : '';
    final post = end < clean.length ? '…' : '';
    return '$pre${clean.substring(start, end)}$post';
  }
}

// ---------------------------------------------------------------------------
// EPUB content renderer
// ---------------------------------------------------------------------------

class _EpubContent extends StatelessWidget {
  const _EpubContent({
    required this.chapter,
    required this.settings,
    required this.scrollController,
  });

  final EpubChapterView chapter;
  final EpubReaderSettings settings;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 80),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              Text(
                chapter.title,
                style: TextStyle(
                  fontSize: settings.fontSize * 1.6,
                  fontWeight: FontWeight.bold,
                  color: settings.background.foreground,
                ),
              ),
              const SizedBox(height: 16),
              Html(
                data: chapter.html,
                style: {
                  'body': Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(settings.lineHeight),
                    fontFamily: settings.fontFamily,
                    color: settings.background.foreground,
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                  ),
                  'p': Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(settings.lineHeight),
                    color: settings.background.foreground,
                    margin: Margins.only(bottom: 12),
                  ),
                  'h1': Style(
                    fontSize: FontSize(settings.fontSize * 1.5),
                    color: settings.background.foreground,
                    margin: Margins.only(top: 16, bottom: 8),
                  ),
                  'h2': Style(
                    fontSize: FontSize(settings.fontSize * 1.3),
                    color: settings.background.foreground,
                    margin: Margins.only(top: 12, bottom: 6),
                  ),
                  'img': Style(
                    width: Width.auto(),
                    height: Height.auto(),
                    margin: Margins.symmetric(vertical: 12),
                  ),
                  'blockquote': Style(
                    color: settings.background.foreground
                        .withValues(alpha: 0.8),
                    padding: HtmlPaddings.only(left: 16),
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                    margin: Margins.symmetric(vertical: 12),
                  ),
                },
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings sheet
// ---------------------------------------------------------------------------

class EpubReaderSettingsSheet extends ConsumerWidget {
  const EpubReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(epubReaderSettingsProvider);
    final notifier = ref.read(epubReaderSettingsProvider.notifier);
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
              Text('Font size: ${settings.fontSize.toStringAsFixed(0)} pt'),
              Slider(
                value: settings.fontSize,
                min: 12,
                max: 32,
                divisions: 20,
                onChanged: notifier.setFontSize,
              ),
              const SizedBox(height: 8),
              Text('Line height: ${settings.lineHeight.toStringAsFixed(2)}'),
              Slider(
                value: settings.lineHeight,
                min: 1.0,
                max: 2.2,
                divisions: 24,
                onChanged: notifier.setLineHeight,
              ),
              const SizedBox(height: 8),
              const _SectionLabel('Font family'),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in const ['serif', 'sans-serif', 'monospace'])
                    ChoiceChip(
                      label: Text(f),
                      selected: settings.fontFamily == f,
                      onSelected: (_) => notifier.setFontFamily(f),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _SectionLabel('Background'),
              Wrap(
                spacing: 8,
                children: [
                  for (final b in EpubBackgroundTheme.values)
                    ChoiceChip(
                      label: Text(b.label),
                      selected: settings.background == b,
                      onSelected: (_) => notifier.setBackground(b),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep screen on'),
                value: settings.keepScreenOn,
                onChanged: (_) => notifier.toggleKeepScreenOn(),
              ),
            ],
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
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
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
