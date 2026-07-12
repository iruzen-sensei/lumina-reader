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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../shared/widgets.dart';

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

/// Seed novel chapters — in a real build these come from an extension.
final novelChaptersProvider =
    Provider.family<List<NovelChapter>, int>((ref, novelId) {
  return List.generate(8, (i) {
    final chapter = (i + 1).toDouble();
    return NovelChapter(
      id: novelId * 1000 + i,
      title: 'Chapter $chapter',
      number: chapter,
      author: 'Lumina Demo',
      html: _demoHtml(i),
    );
  });
});

String _demoHtml(int index) {
  return '''
<h1>Chapter ${index + 1}</h1>
<p>The morning sun crested the eastern ridge, casting long shadows across the
valley floor. <em>Serah</em> pulled her cloak tighter against the chill,
watching as the village below stirred to life. Smoke rose from a hundred
chimneys, weaving together into a single grey ribbon that climbed toward the
peaks.</p>
<p>She had been walking since dawn, and her legs ached with every step. But
there was no time to rest — not yet. The road ahead was long, and the
message she carried was heavier than any pack upon her shoulders.</p>
<blockquote>"The mountain remembers what the river forgets."</blockquote>
<p>Her grandfather's words echoed in her mind. He had spoken them the
night before he died, his hand clasped around hers, eyes fixed on something
far beyond the candle-lit room. She had not understood then. She was
beginning to understand now.</p>
<p>The path steepened, climbing through a forest of silver birch. Birdsong
filled the air, and somewhere distant a woodpecker drummed against a hollow
trunk. The world felt <strong>impossibly alive</strong>, and Serah found
herself pausing, just for a moment, to breathe it in.</p>
<p>By noon she had reached the lookout. Below, the kingdom spread out like
a tapestry — patchwork fields, glinting rivers, the distant smudge of the
capital against the horizon. Somewhere down there, in a tower she had
never seen, a council was meeting to decide her fate.</p>
<p>She tightened her grip on the scroll, and began her descent.</p>
<p>The rest is, as they say, history — but the histories never tell you
how heavy the first step feels, or how cold the wind becomes when you
walk it alone.</p>
''';
}

// ---------------------------------------------------------------------------
// NovelReaderView
// ---------------------------------------------------------------------------

/// The novel reader view.
///
/// Renders HTML chapter content via [flutter_html] with adjustable font
/// size, alignment and background theme. Supports auto-scroll with speed
/// control, TTS playback (with word highlighting through [flutter_tts]),
/// per-chapter scroll position persistence, prev/next chapter navigation,
/// reading progress tracking, and tap-zone page navigation.
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

class _NovelReaderViewState extends ConsumerState<NovelReaderView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late NovelChapter _chapter;
  late List<NovelChapter> _chapters;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _autoScrollTimer;
  double _autoScrollSpeed = 0.5; // 0..1
  bool _autoScrolling = false;
  double _readingProgress = 0;

  // TTS
  late final FlutterTts _tts;
  bool _ttsPlaying = false;
  double _ttsSpeed = 1.0;
  int? _ttsWordIndex;
  List<String> _ttsWords = const [];
  StreamSubscription? _ttsProgressSub;
  StreamSubscription? _ttsCompleteSub;

  @override
  void initState() {
    super.initState();
    _chapters = ref.read(novelChaptersProvider(widget.novelId));
    _chapter = _chapters.firstWhere(
      (c) => c.id == widget.initialChapterId,
      orElse: () => _chapters.first,
    );
    _tts = FlutterTts();
    _initTts();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScrollPosition();
      if (ref.read(novelReaderSettingsProvider).keepScreenOn) {
        WakelockPlus.enable();
      }
    });
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_ttsSpeedToFlutter(_ttsSpeed));
      _tts.setProgressHandler((text, start, end, word) {
        if (mounted) setState(() => _ttsWordIndex = word);
      });
      _tts.setCompletionHandler(() {
        if (mounted) {
          setState(() {
            _ttsPlaying = false;
            _ttsWordIndex = null;
          });
        }
      });
    } catch (_) {
      // TTS backend unavailable (e.g. desktop test harness).
    }
  }

  double _ttsSpeedToFlutter(double s) {
    // flutter_tts uses 0..1 speech rate (0.5 normal, 1.0 fastest).
    return (s - 0.5) / 2.5;
  }

  void _restoreScrollPosition() {
    final store = ref.read(novelScrollStoreProvider);
    final offset = store.get(_chapter.id);
    if (_scrollController.hasClients && offset > 0) {
      _scrollController.jumpTo(offset);
    }
  }

  void _persistScrollPosition() {
    if (!_scrollController.hasClients) return;
    ref.read(novelScrollStoreProvider).put(
          _chapter.id,
          _scrollController.offset,
        );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    final progress = max <= 0 ? 0 : (offset / max).clamp(0.0, 1.0);
    if ((progress - _readingProgress).abs() > 0.01) {
      setState(() => _readingProgress = progress);
    }
    _persistScrollPosition();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _autoScrollTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _ttsProgressSub?.cancel();
    _ttsCompleteSub?.cancel();
    _tts.stop();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _goToChapter(NovelChapter next) async {
    _persistScrollPosition();
    _stopAutoScroll();
    await _tts.stop();
    setState(() {
      _chapter = next;
      _ttsPlaying = false;
      _ttsWordIndex = null;
      _readingProgress = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScrollPosition();
    });
  }

  Future<void> _nextChapter() async {
    final idx = _chapters.indexWhere((c) => c.id == _chapter.id);
    if (idx <= 0) {
      showSnack(ref, context, 'Already at the first chapter');
      return;
    }
    await _goToChapter(_chapters[idx - 1]);
  }

  Future<void> _prevChapter() async {
    final idx = _chapters.indexWhere((c) => c.id == _chapter.id);
    if (idx >= _chapters.length - 1) {
      showSnack(ref, context, 'Already at the last chapter');
      return;
    }
    await _goToChapter(_chapters[idx + 1]);
  }

  // -- Auto scroll ----------------------------------------------------------

  void _startAutoScroll() {
    if (_autoScrolling) return;
    setState(() => _autoScrolling = true);
    _autoScrollTimer =
        Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) return;
      final offset = _scrollController.offset;
      final max = _scrollController.position.maxScrollExtent;
      if (offset >= max) {
        _stopAutoScroll();
        return;
      }
      _scrollController.jumpTo(offset + _autoScrollSpeed * 2);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (mounted) setState(() => _autoScrolling = false);
  }

  void _setAutoScrollSpeed(double v) {
    setState(() => _autoScrollSpeed = v);
  }

  // -- TTS ------------------------------------------------------------------

  Future<void> _ttsToggle() async {
    if (_ttsPlaying) {
      await _tts.stop();
      setState(() {
        _ttsPlaying = false;
        _ttsWordIndex = null;
      });
      return;
    }
    final words = _plainText().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    setState(() {
      _ttsWords = words;
      _ttsPlaying = true;
      _ttsWordIndex = 0;
    });
    try {
      await _tts.speak(_plainText());
    } catch (_) {
      if (mounted) {
        setState(() => _ttsPlaying = false);
        showSnack(ref, context, 'TTS unavailable');
      }
    }
  }

  Future<void> _ttsPause() async {
    await _tts.stop();
    setState(() => _ttsPlaying = false);
  }

  Future<void> _ttsStop() async {
    await _tts.stop();
    setState(() {
      _ttsPlaying = false;
      _ttsWordIndex = null;
    });
  }

  Future<void> _ttsSetSpeed(double s) async {
    setState(() => _ttsSpeed = s);
    await _tts.setSpeechRate(_ttsSpeedToFlutter(s));
    if (_ttsPlaying) {
      await _tts.stop();
      await _tts.speak(_plainText());
    }
  }

  String _plainText() {
    // Strip HTML tags — flutter_tts cannot consume HTML directly.
    return _chapter.html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // -- Page tap navigation --------------------------------------------------

  void _onTapZone(TapZone zone) {
    if (!_scrollController.hasClients) return;
    final settings = ref.read(novelReaderSettingsProvider);
    if (!settings.tapToNavigate) {
      _toggleControls();
      return;
    }
    final viewport = _scrollController.position.viewportDimension;
    final offset = _scrollController.offset;
    switch (zone) {
      case TapZone.left:
        _scrollController.animateTo(
          math.max(offset - viewport * 0.85, 0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
        break;
      case TapZone.right:
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          math.min(offset + viewport * 0.85, max),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
        break;
      case TapZone.center:
        _toggleControls();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(novelReaderSettingsProvider);
    return Scaffold(
      backgroundColor: settings.background.color,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) {
                final w = MediaQuery.of(context).size.width;
                final x = details.globalPosition.dx;
                if (x < w / 3) {
                  _onTapZone(TapZone.left);
                } else if (x > w * 2 / 3) {
                  _onTapZone(TapZone.right);
                } else {
                  _onTapZone(TapZone.center);
                }
              },
              child: _NovelContent(
                chapter: _chapter,
                settings: settings,
                scrollController: _scrollController,
                ttsWords: _ttsWords,
                ttsWordIndex: _ttsWordIndex,
              ),
            ),
            if (_controlsVisible) _buildTopBar(settings),
            if (_controlsVisible) _buildBottomBar(settings),
            if (_autoScrolling) _buildAutoScrollIndicator(),
            if (_ttsPlaying) _buildTtsIndicator(settings),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(NovelReaderSettings settings) {
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
                  icon: Icon(Icons.arrow_back, color: settings.background.foreground),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: settings.background.foreground,
                              fontWeight: FontWeight.w600)),
                      if (_chapter.author != null)
                        Text(_chapter.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: settings.background.foreground
                                    .withValues(alpha: 0.7),
                                fontSize: 12)),
                    ],
                  ),
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

  Widget _buildBottomBar(NovelReaderSettings settings) {
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
                if (settings.showProgress)
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
                    IconButton(
                      tooltip: 'Auto-scroll',
                      icon: Icon(
                        _autoScrolling
                            ? Icons.pause_circle_filled
                            : Icons.auto_mode,
                        color: settings.background.foreground,
                      ),
                      onPressed: _autoScrolling ? _stopAutoScroll : _startAutoScroll,
                    ),
                    IconButton(
                      tooltip: _ttsPlaying ? 'Stop TTS' : 'Play TTS',
                      icon: Icon(
                        _ttsPlaying
                            ? Icons.stop_circle_outlined
                            : Icons.record_voice_over_outlined,
                        color: settings.background.foreground,
                      ),
                      onPressed: _ttsToggle,
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
                        inactiveColor:
                            settings.background.foreground.withValues(alpha: 0.1),
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
                if (_autoScrolling)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text('Speed',
                            style: TextStyle(
                                color: settings.background.foreground,
                                fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: _autoScrollSpeed,
                            min: 0.1,
                            max: 1.0,
                            onChanged: _setAutoScrollSpeed,
                            activeColor: Theme.of(context).colorScheme.primary,
                            inactiveColor: settings.background.foreground
                                .withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_ttsPlaying)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text('TTS speed',
                            style: TextStyle(
                                color: settings.background.foreground,
                                fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: _ttsSpeed,
                            min: 0.5,
                            max: 3.0,
                            divisions: 25,
                            onChanged: _ttsSetSpeed,
                            activeColor: Theme.of(context).colorScheme.primary,
                            inactiveColor: settings.background.foreground
                                .withValues(alpha: 0.1),
                          ),
                        ),
                        Text('${_ttsSpeed.toStringAsFixed(1)}x',
                            style: TextStyle(
                                color: settings.background.foreground,
                                fontSize: 12)),
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

  Widget _buildAutoScrollIndicator() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 64,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.auto_mode, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text('Auto-scroll',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTtsIndicator(NovelReaderSettings settings) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 64,
      left: 16,
      right: 80,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _ttsWordIndex != null && _ttsWordIndex! < _ttsWords.length
              ? _ttsWords[_ttsWordIndex!]
              : 'Speaking…',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const NovelReaderSettingsSheet(),
    ).then((_) {
      if (mounted) {
        setState(() => _controlsVisible = true);
        _scheduleHide();
      }
    });
  }
}

enum TapZone { left, center, right }

// ---------------------------------------------------------------------------
// Novel content renderer
// ---------------------------------------------------------------------------

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
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 80),
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
