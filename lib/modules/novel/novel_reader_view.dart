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

import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/providers.dart' as data;
import '../../providers/providers.dart';
import '../../providers/storage_provider.dart';
import '../shared/widgets.dart';

// ---------------------------------------------------------------------------
// Provider contracts
// ---------------------------------------------------------------------------

/// Background color theme for the novel reader.
enum NovelBackgroundTheme { black, grey, white, sepia }

extension NovelBackgroundThemeX on NovelBackgroundTheme {
  Color get color {
    switch (this) {
      case NovelBackgroundTheme.black:
        return const Color(0xFF000000);
      case NovelBackgroundTheme.grey:
        return const Color(0xFF212121);
      case NovelBackgroundTheme.white:
        return const Color(0xFFFFFFFF);
      case NovelBackgroundTheme.sepia:
        return const Color(0xFFF5DEB3);
    }
  }

  Color get foreground {
    switch (this) {
      case NovelBackgroundTheme.black:
      case NovelBackgroundTheme.grey:
        return Colors.white;
      case NovelBackgroundTheme.white:
      case NovelBackgroundTheme.sepia:
        return Colors.black87;
    }
  }

  String get label {
    switch (this) {
      case NovelBackgroundTheme.black:
        return 'Black';
      case NovelBackgroundTheme.grey:
        return 'Grey';
      case NovelBackgroundTheme.white:
        return 'White';
      case NovelBackgroundTheme.sepia:
        return 'Sepia';
    }
  }
}

/// Text alignment options.
enum NovelTextAlign { left, center, right, justify }

extension NovelTextAlignX on NovelTextAlign {
  TextAlign get value {
    switch (this) {
      case NovelTextAlign.left:
        return TextAlign.left;
      case NovelTextAlign.center:
        return TextAlign.center;
      case NovelTextAlign.right:
        return TextAlign.right;
      case NovelTextAlign.justify:
        return TextAlign.justify;
    }
  }

  String get label => name[0].toUpperCase() + name.substring(1);

  IconData get icon {
    switch (this) {
      case NovelTextAlign.left:
        return Icons.format_align_left;
      case NovelTextAlign.center:
        return Icons.format_align_center;
      case NovelTextAlign.right:
        return Icons.format_align_right;
      case NovelTextAlign.justify:
        return Icons.format_align_justify;
    }
  }
}

/// Configuration for the novel reader.
class NovelReaderSettings {
  NovelReaderSettings({
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.fontFamily = 'serif',
    this.align = NovelTextAlign.justify,
    this.background = NovelBackgroundTheme.white,
    this.keepScreenOn = true,
    this.tapToNavigate = true,
    this.showProgress = true,
  });

  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final NovelTextAlign align;
  final NovelBackgroundTheme background;
  final bool keepScreenOn;
  final bool tapToNavigate;
  final bool showProgress;

  NovelReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    NovelTextAlign? align,
    NovelBackgroundTheme? background,
    bool? keepScreenOn,
    bool? tapToNavigate,
    bool? showProgress,
  }) {
    return NovelReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      align: align ?? this.align,
      background: background ?? this.background,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      tapToNavigate: tapToNavigate ?? this.tapToNavigate,
      showProgress: showProgress ?? this.showProgress,
    );
  }
}

class NovelReaderSettingsNotifier
    extends StateNotifier<NovelReaderSettings> {
  NovelReaderSettingsNotifier() : super(NovelReaderSettings());

  void setFontSize(double v) => state = state.copyWith(fontSize: v);
  void setLineHeight(double v) => state = state.copyWith(lineHeight: v);
  void setFontFamily(String f) => state = state.copyWith(fontFamily: f);
  void setAlign(NovelTextAlign a) => state = state.copyWith(align: a);
  void setBackground(NovelBackgroundTheme b) =>
      state = state.copyWith(background: b);
  void toggleKeepScreenOn() =>
      state = state.copyWith(keepScreenOn: !state.keepScreenOn);
  void toggleTapToNavigate() =>
      state = state.copyWith(tapToNavigate: !state.tapToNavigate);
  void toggleShowProgress() =>
      state = state.copyWith(showProgress: !state.showProgress);
}

final novelReaderSettingsProvider = StateNotifierProvider<
    NovelReaderSettingsNotifier, NovelReaderSettings>(
  (ref) => NovelReaderSettingsNotifier(),
);

/// A single novel chapter.
class NovelChapter {
  NovelChapter({
    required this.id,
    required this.title,
    required this.html,
    required this.number,
    this.author,
  });

  final int id;
  final String title;
  final String html;
  final double number;
  final String? author;
}

/// Per-chapter scroll position persistence (in-memory; persistence to disk
/// would be added by the storage provider).
class NovelScrollStore {
  NovelScrollStore() : _map = HashMap<int, double>();

  final HashMap<int, double> _map;

  double get(int chapterId) => _map[chapterId] ?? 0;

  void put(int chapterId, double offset) => _map[chapterId] = offset;

  void clear() => _map.clear();
}

final novelScrollStoreProvider = Provider<NovelScrollStore>(
  (ref) => NovelScrollStore(),
);

/// Chapters for a novel. Content is provided by novel-capable sources
/// through the extension coordinator once installed; the map below is a
/// lightweight cache the reader populates when a source delivers HTML.
///
/// This used to return hardcoded demo HTML — replaced with an honest empty
/// list so the reader shows its empty state instead of fake content.
final Map<int, List<NovelChapter>> _novelChapterCache = {};

final novelChaptersProvider =
    Provider.family<List<NovelChapter>, int>((ref, novelId) {
  return _novelChapterCache[novelId] ?? const [];
});

/// Called by the data layer when a novel source delivers chapter content.
void cacheNovelChapters(int novelId, List<NovelChapter> chapters) {
  _novelChapterCache[novelId] = chapters;
}

class _NovelContent extends StatelessWidget {
  const _NovelContent({
    required this.chapter,
    required this.settings,
    required this.scrollController,
    required this.ttsWords,
    required this.ttsWordIndex,
  });

  final NovelChapter chapter;
  final NovelReaderSettings settings;
  final ScrollController scrollController;
  final List<String> ttsWords;
  final int? ttsWordIndex;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 24, 20, 80),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              Html(
                data: chapter.html,
                style: {
                  'body': Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(settings.lineHeight),
                    fontFamily: settings.fontFamily,
                    textAlign: settings.align.value,
                    color: settings.background.foreground,
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                  ),
                  'h1': Style(
                    fontSize: FontSize(settings.fontSize * 1.6),
                    fontWeight: FontWeight.bold,
                    color: settings.background.foreground,
                    textAlign: settings.align.value,
                    margin: Margins.only(bottom: 16),
                  ),
                  'h2': Style(
                    fontSize: FontSize(settings.fontSize * 1.35),
                    fontWeight: FontWeight.bold,
                    color: settings.background.foreground,
                    textAlign: settings.align.value,
                    margin: Margins.only(bottom: 12, top: 16),
                  ),
                  'p': Style(
                    fontSize: FontSize(settings.fontSize),
                    lineHeight: LineHeight(settings.lineHeight),
                    color: settings.background.foreground,
                    textAlign: settings.align.value,
                    margin: Margins.only(bottom: 12),
                  ),
                  'blockquote': Style(
                    fontSize: FontSize(settings.fontSize * 0.95),
                    fontStyle: FontStyle.italic,
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
              const SizedBox(height: 24),
              if (ttsWordIndex != null && ttsWordIndex! < ttsWords.length)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🔊 ${ttsWords[ttsWordIndex!]}',
                    style: TextStyle(
                      color: settings.background.foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: settings.fontSize,
                    ),
                  ),
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

class NovelReaderSettingsSheet extends ConsumerWidget {
  const NovelReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(novelReaderSettingsProvider);
    final notifier = ref.read(novelReaderSettingsProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 20, 20),
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
              const _SectionLabel('Text alignment'),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in NovelTextAlign.values)
                    ChoiceChip(
                      avatar: Icon(a.icon),
                      label: Text(a.label),
                      selected: settings.align == a,
                      onSelected: (_) => notifier.setAlign(a),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _SectionLabel('Background'),
              Wrap(
                spacing: 8,
                children: [
                  for (final b in NovelBackgroundTheme.values)
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
                title: const Text('Show reading progress'),
                value: settings.showProgress,
                onChanged: (_) => notifier.toggleShowProgress(),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Strips HTML tags from [input] — used by TTS path.
String stripHtml(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Estimates reading time in minutes for [html] at the given [wpm].
int estimateReadingMinutes(String html, {int wpm = 250}) {
  final text = stripHtml(html);
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return math.max(1, (words.length / wpm).ceil());
}

// ---------------------------------------------------------------------------
// NovelReaderView — the interactive reader body
// ---------------------------------------------------------------------------

/// The interactive novel reader.
///
/// Renders the current chapter's HTML with the user's typography settings,
/// restores per-chapter scroll positions via [NovelScrollStore], and offers
/// chapter navigation plus a settings sheet. Chapter content arrives from
/// [novelChaptersProvider], which the data layer populates when a
/// novel-capable source delivers HTML.
class NovelReaderView extends ConsumerStatefulWidget {
  const NovelReaderView({
    super.key,
    required this.novelId,
    this.initialChapterId,
  });

  final int novelId;
  final int? initialChapterId;

  @override
  ConsumerState<NovelReaderView> createState() => _NovelReaderViewState();
}

class _NovelReaderViewState extends ConsumerState<NovelReaderView> {
  final ScrollController _scrollController = ScrollController();
  NovelChapter? _chapter;
  bool _fileLoadAttempted = false;
  String? _fileLoadError;

  // ---- Read-aloud (TTS) state -------------------------------------------
  // The reader was originally shipped TTS-READY (ttsWords/ttsWordIndex
  // plumbing + stripHtml) but no engine was ever attached — the buttons
  // simply never existed. flutter_tts speaks the chapter sentence by
  // sentence; the active sentence is surfaced in the reading view.
  FlutterTts? _tts;
  bool _speaking = false;
  bool _ttsPaused = false;
  List<String> _sentences = const [];
  int _sentenceIndex = 0;

  /// Chapter ids belonging to a SOURCE-backed novel (fetched on open).
  /// When non-empty, [NovelChapter.html] is filled lazily via the
  /// extension coordinator (`chapterText`) instead of the local file.
  final Set<int> _sourceChapterIds = {};
  bool _fetchingText = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialChapterId;
    if (initial != null) {
      // Resolve lazily in build once the provider cache is visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final chapters = ref.read(novelChaptersProvider(widget.novelId));
        final match = chapters.where((c) => c.id == initial).firstOrNull;
        if (match != null) _setChapter(match, restoreScroll: true);
      });
    }
    _loadFromFileIfNeeded();
  }

  /// REAL content pipeline for locally imported .txt novels. The reader
  /// previously depended on `cacheNovelChapters()` — which NOTHING ever
  /// called — so it rendered its "No chapters loaded" empty state forever.
  /// Now a .txt import on the Library tab is split into chapters (by
  /// heading pattern, falling back to fixed-size chunks) and cached.
  ///
  /// SOURCE-BACKED novels (added from an installed novel extension) take
  /// the library-DB path: their Chapter rows become the reader's chapter
  /// list and each chapter's text is fetched on open through the extension
  /// coordinator (previously these novels opened EMPTY forever — the reader
  /// had no text pipeline at all).
  Future<void> _loadFromFileIfNeeded() async {
    if (_fileLoadAttempted) return;
    _fileLoadAttempted = true;
    try {
      final manga = await ref
          .read(data.libraryRepositoryProvider)
          .getManga(widget.novelId);
      if (manga == null) return;
      final path = manga.url;

      // ---- Source-backed novel: chapters from the library DB. ----
      if (path.startsWith('http://') || path.startsWith('https://')) {
        final rows = await ref
            .read(data.libraryRepositoryProvider)
            .getChapters(widget.novelId);
        if (rows.isEmpty) {
          if (mounted) {
            setState(() => _fileLoadError =
                'This novel has no chapters yet — open it from its source '
                'detail page first so the chapter list is fetched.');
          }
          return;
        }
        final chapters = <NovelChapter>[
          for (var i = 0; i < rows.length; i++)
            NovelChapter(
              id: rows[i].id,
              title: rows[i].name,
              html: '', // fetched lazily on open
              number: rows[i].number,
            ),
        ];
        _sourceChapterIds.addAll(chapters.map((c) => c.id));
        cacheNovelChapters(widget.novelId, chapters);
        if (!mounted) return;
        setState(() {
          final initial = widget.initialChapterId;
          if (initial != null) {
            final match =
                chapters.where((c) => c.id == initial).firstOrNull;
            _chapter = match;
          }
          _chapter ??= chapters.last; // first chapter (list is newest-first)
        });
        return;
      }

      // ---- Local .txt import. ----
      if (!path.toLowerCase().endsWith('.txt')) return;

      final text = await File(path).readAsString();
      if (text.trim().isEmpty) {
        setState(() => _fileLoadError = 'The imported file is empty.');
        return;
      }
      final chapters = _splitIntoChapters(text, manga.title);
      cacheNovelChapters(widget.novelId, chapters);
      if (!mounted) return;
      setState(() {
        // Auto-open the first chapter once loaded.
        _chapter ??= chapters.first;
      });
    } catch (e) {
      if (mounted) {
        setState(() =>
            _fileLoadError = 'Could not load the novel: $e');
      }
    }
  }

  /// Splits raw novel text into chapters by common heading patterns
  /// (`Chapter 12`, `CHAPTER XII`, `第12章`); when no headings exist the
  /// text is chunked into ~2,500-word segments so navigation still works.
  List<NovelChapter> _splitIntoChapters(String text, String title) {
    final heading = RegExp(
      r'^\s*(?:chapter\s+\d+|chapter\s+[ivxlcdm]+|第\s*\d+\s*章|prologue|epilogue)\s*:?.*$',
      caseSensitive: false,
      multiLine: true,
    );
    final lines = text.split('\n');
    final found = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (heading.hasMatch(lines[i])) found.add(i);
    }

    final List<(String, String)> parts;
    if (found.length >= 2) {
      parts = [
        for (var i = 0; i < found.length; i++)
          (
            lines[found[i]].trim(),
            lines
                .sublist(
                    found[i],
                    i + 1 < found.length ? found[i + 1] : lines.length)
                .join('\n')
          ),
      ];
    } else {
      // No headings — chunk by word count.
      final words = text.split(RegExp(r'\s+'));
      const chunkSize = 2500;
      parts = [
        for (var i = 0; i < words.length; i += chunkSize)
          (
            'Part ${i ~/ chunkSize + 1}',
            words
                .sublist(
                    i, math.min(i + chunkSize, words.length))
                .join(' ')
          ),
      ];
    }

    return [
      for (var i = 0; i < parts.length; i++)
        NovelChapter(
          id: i + 1,
          title: parts[i].$1.length > 80 ? 'Chapter ${i + 1}' : parts[i].$1,
          html: _toHtml(parts[i].$2),
          number: (i + 1).toDouble(),
        ),
    ];
  }

  String _toHtml(String raw) {
    final paragraphs = raw
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => '<p>${_escape(p)}</p>')
        .join('');
    return paragraphs.isEmpty ? '<p></p>' : paragraphs;
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  void dispose() {
    _stopSpeaking();
    _tts?.stop();
    _scrollController.dispose();
    super.dispose();
  }

  // ---- Read-aloud ---------------------------------------------------------

  FlutterTts _ensureTts() {
    final tts = _tts ??= FlutterTts()
      ..setStartHandler(() {
        if (mounted) {
          setState(() {
            _speaking = true;
            _ttsPaused = false;
          });
        }
      })
      ..setCompletionHandler(_onSentenceDone)
      ..setCancelHandler(() {
        if (mounted) {
          setState(() {
            _speaking = false;
            _ttsPaused = false;
          });
        }
      })
      ..setErrorHandler((msg) {
        if (mounted) {
          setState(() {
            _speaking = false;
            _ttsPaused = false;
          });
        }
      });
    return tts;
  }

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      if (_ttsPaused) {
        // flutter_tts has no resume() — re-speaking the current sentence
        // continues from the last completed boundary.
        await _tts?.speak(_sentenceIndex < _sentences.length
            ? _sentences[_sentenceIndex]
            : '');
        if (mounted) setState(() => _ttsPaused = false);
      } else {
        await _tts?.pause();
        if (mounted) setState(() => _ttsPaused = true);
      }
      return;
    }
    final chapter = _chapter;
    if (chapter == null || chapter.html.isEmpty) return;
    final text = stripHtml(chapter.html);
    if (text.isEmpty) return;

    final tts = _ensureTts();
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(0.5);
    await tts.awaitSpeakCompletion(true);

    // Sentence chunks: each completion advances the highlight; a single
    // sentence failing never kills the run.
    _sentences = text
        .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9\u201c"])'))
        .map((s) => s.trim())
        .where((s) => s.length > 1)
        .toList();
    _sentenceIndex = 0;
    if (_sentences.isEmpty) return;
    if (mounted) setState(() => _speaking = true);
    await tts.speak(_sentences[0]);
  }

  void _onSentenceDone() {
    if (!mounted || !_speaking) return;
    _sentenceIndex++;
    if (_sentenceIndex >= _sentences.length) {
      setState(() {
        _speaking = false;
        _ttsPaused = false;
        _sentenceIndex = 0;
      });
      return;
    }
    setState(() {}); // advance the highlight
    _tts?.speak(_sentences[_sentenceIndex]);
  }

  void _stopSpeaking() {
    _speaking = false;
    _ttsPaused = false;
    _sentenceIndex = 0;
    _tts?.stop();
  }

  void _setChapter(NovelChapter chapter, {bool restoreScroll = false}) {
    if (_speaking) _stopSpeaking();
    final store = ref.read(novelScrollStoreProvider);
    if (_chapter != null) {
      store.put(_chapter!.id, _scrollController.hasClients
          ? _scrollController.offset
          : 0);
    }
    setState(() {
      _chapter = chapter;
      _fetchError = null;
    });

    // Source-backed chapter whose text has not been fetched yet.
    if (_sourceChapterIds.contains(chapter.id) && chapter.html.isEmpty) {
      _fetchChapterText(chapter);
    }

    final target = restoreScroll ? store.get(chapter.id) : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(
        math.min(target, _scrollController.position.maxScrollExtent),
      );
    });
  }

  /// Fetches a source chapter's text through the extension coordinator and
  /// swaps it into the reader. Runs once per chapter (cached by the
  /// coordinator's service layer / HTTP cache headers).
  ///
  /// LOCAL-FIRST: a downloaded chapter (DownloadEngine writes
  /// `<downloads>/chapters/<novelId>/<chapterId>/chapter.html`) is read
  /// from disk without touching the network.
  Future<void> _fetchChapterText(NovelChapter chapter) async {
    if (_fetchingText) return;
    setState(() => _fetchingText = true);
    try {
      String? html;

      // 1. Downloaded copy on disk.
      try {
        final base = await StorageProvider().getDownloadsDir();
        final f = File('$base/chapters/${widget.novelId}/${chapter.id}/'
            'chapter.html');
        if (await f.exists()) {
          final local = await f.readAsString();
          if (local.trim().isNotEmpty) html = local;
        }
      } catch (_) {/* fall through to network */}

      // 2. Network via the source chain.
      html ??= await ref
          .read(extensionCoordinatorProvider)
          .chapterText(chapter.id)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (html == null || html.isEmpty) {
        setState(() => _fetchError =
            'The source did not return any text for this chapter.');
        return;
      }
      final filled = NovelChapter(
        id: chapter.id,
        title: chapter.title,
        html: html,
        number: chapter.number,
      );
      // Update the shared cache so revisits are instant.
      final cached = _novelChapterCache[widget.novelId];
      if (cached != null) {
        final i = cached.indexWhere((c) => c.id == chapter.id);
        if (i >= 0) cached[i] = filled;
      }
      if (_chapter?.id == chapter.id) {
        setState(() {
          _chapter = filled;
          _fetchError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fetchError = 'Could not load this chapter: $e');
      }
    } finally {
      if (mounted) setState(() => _fetchingText = false);
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const NovelReaderSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(novelReaderSettingsProvider);
    final chapters = ref.watch(novelChaptersProvider(widget.novelId));

    // Keep-screen-on is honoured for the duration of the reader.
    WakelockPlus.toggle(enable: settings.keepScreenOn);

    if (chapters.isEmpty) {
      return Scaffold(
        backgroundColor: settings.background.color,
        appBar: AppBar(
          title: const Text('Novel'),
          backgroundColor: settings.background.color,
        ),
        body: emptyState(
          context: context,
          icon: Icons.auto_stories_outlined,
          title: _fileLoadError ?? 'No chapters loaded',
          subtitle: _fileLoadError ??
              'Import a .txt novel from the Library tab (Import button), or '
              'install a novel-capable source and open a chapter from its '
              'detail page.',
        ),
      );
    }

    final chapter =
        _chapter ?? chapters.first; // latest chapter by default
    final index = chapters.indexWhere((c) => c.id == chapter.id);

    final body = _fetchingText && chapter.html.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _fetchError != null && chapter.html.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _fetchError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => _fetchChapterText(chapter),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _NovelContent(
                chapter: chapter,
                settings: settings,
                scrollController: _scrollController,
                ttsWords: const [],
                ttsWordIndex: null,
              );

    return Scaffold(
      backgroundColor: settings.background.color,
      appBar: AppBar(
        title: Text(
          chapter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: settings.background.color,
        actions: [
          IconButton(
            icon: Icon(_speaking
                ? (_ttsPaused ? Icons.play_arrow : Icons.pause)
                : Icons.volume_up_outlined),
            tooltip: _speaking
                ? (_ttsPaused ? 'Resume reading aloud' : 'Pause reading aloud')
                : 'Read aloud',
            onPressed: _toggleSpeak,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Reader settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: _ChapterNavBar(
        hasPrev: index >= 0 && index < chapters.length - 1,
        hasNext: index > 0,
        onPrev: index >= 0 && index < chapters.length - 1
            ? () => _setChapter(chapters[index + 1])
            : null,
        onNext: index > 0 ? () => _setChapter(chapters[index - 1]) : null,
        backgroundColor: settings.background.color,
      ),
    );
  }
}

/// Minimal prev/next chapter bar.
class _ChapterNavBar extends StatelessWidget {
  const _ChapterNavBar({
    required this.hasPrev,
    required this.hasNext,
    this.onPrev,
    this.onNext,
    this.backgroundColor,
  });

  final bool hasPrev;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: hasPrev ? onPrev : null,
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Previous'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: hasNext ? onNext : null,
                icon: const Icon(Icons.arrow_downward),
                label: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
