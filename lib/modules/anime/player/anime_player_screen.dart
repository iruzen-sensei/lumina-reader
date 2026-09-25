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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme.dart';
import '../../../data/providers.dart' as data;
import '../../../models/models.dart' hide SubtitleTrack;
import '../../../providers/providers.dart' hide SubtitleTrack;
import '../../shared/widgets.dart';

/// The anime player screen.
///
/// Built on top of [media_kit]'s [Video] widget, this screen layers a custom
/// Material 3 control overlay on top of the video surface: play/pause, a
/// draggable seekbar with buffered indication, volume, a quality selector, a
/// subtitle selector, an AniSkip button that jumps past openings/endings,
/// picture-in-picture, playback speed and prev/next episode navigation.
class AnimePlayerScreen extends ConsumerStatefulWidget {
  const AnimePlayerScreen({
    super.key,
    required this.episodeId,
  });

  /// The episode to play. The parent anime is resolved from the database
  /// so deep links (`/animePlayer/:episodeId`) work from history / updates.
  final int episodeId;

  @override
  ConsumerState<AnimePlayerScreen> createState() => _AnimePlayerScreenState();
}

class _AnimePlayerScreenState extends ConsumerState<AnimePlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  late final List<StreamSubscription<dynamic>> _subs;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _seeking = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double _volume = 1.0;
  double _speed = 1.0;
  int _qualityIndex = 0;
  int _subtitleIndex = 0;
  bool _isLoading = true;
  SkipRange? _activeSkip;
  StreamSubscription<Duration>? _positionSub;

  // ---- Watch-progress persistence (mirrors the manga reader's _flush) ----
  DateTime _sessionStart = DateTime.now();
  Timer? _progressSaver;
  bool _completedHandled = false;
  bool _incognito = false;

  /// Nullable: assigned by the async _loadEpisode resolve after the first
  /// frame — every access must be guarded (the previous `late` variant
  /// crashed the overlay build with LateInitializationError on first open).
  Chapter? _episode;

  Manga? _manga;
  bool _notFound = false;

  /// Episode the player is currently bound to. Differs from
  /// [widget.episodeId] after a next/prev switch; the build watch follows
  /// this so the auto-open logic targets the CURRENT episode's sources.
  late int _currentEpisodeId = widget.episodeId;

  /// Episode id whose sources were already opened — prevents re-opening on
  /// every rebuild while still allowing a fresh open after a switch.
  int? _openedEpisodeId;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration());
    _controller = VideoController(_player);
    _loadEpisode();
    _subs = [
      _player.stream.position.listen((p) {
        if (!_seeking && mounted) setState(() => _position = p);
        _scheduleProgressSave();
      }),
      _player.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      _player.stream.buffering.listen((b) {
        if (mounted) setState(() => _isLoading = b);
      }),
      _player.stream.buffer.listen((d) {
        if (mounted) setState(() => _buffered = d);
      }),
      _player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = v);
      }),
      _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          showSnack(ref, context, 'Episode finished');
          // REAL completion: mark watched + persist history/stats
          // (previously the player never recorded anything, so the anime
          // library's watched checkmarks and Continue-watching could never
          // come from actually watching an episode).
          _handleEpisodeComplete();
        }
      }),
    ];
    _scheduleHide();
    _incognito = ref.read(incognitoModeProvider);
    _sessionStart = DateTime.now();
  }

  /// Debounced progress write — at most one DB write every 5 s while
  /// playing (mirrors the manga reader's throttled saveChapterProgress).
  void _scheduleProgressSave() {
    _progressSaver?.cancel();
    _progressSaver = Timer(const Duration(seconds: 5), _flushProgress);
  }

  Future<void> _flushProgress() async {
    final episode = _episode;
    if (episode == null || _incognito) return;
    if (_duration.inMilliseconds <= 0) return;
    final seconds = _position.inSeconds;
    // Skip meaningless writes (nothing watched yet).
    if (seconds <= 0) return;
    try {
      await ref.read(data.libraryRepositoryProvider).saveChapterProgress(
            episode.id,
            lastPageRead: seconds,
            pageCount: _duration.inSeconds,
            isRead: seconds >= _duration.inSeconds - 30,
          );
    } catch (_) {
      // Progress persistence must never interrupt playback.
    }
  }

  /// Marks the episode watched and records history + a stats session.
  Future<void> _handleEpisodeComplete() async {
    final episode = _episode;
    final manga = _manga;
    if (episode == null || manga == null || _completedHandled) return;
    _completedHandled = true;
    if (_incognito) return;
    try {
      await ref.read(data.libraryRepositoryProvider).saveChapterProgress(
            episode.id,
            isRead: true,
            lastPageRead: _duration.inSeconds,
            pageCount: _duration.inSeconds,
          );
      await ref.read(data.historyRepositoryProvider).recordRead(
            mangaId: manga.id,
            chapterId: episode.id,
            chapterName: episode.name,
            chapterNumber: episode.number,
            mangaTitle: manga.title,
            mangaCover: manga.thumbnailUrl,
            isAnime: true,
            progress: 1.0,
          );
      final watched = DateTime.now().difference(_sessionStart).inSeconds;
      await ref.read(data.statsRepositoryProvider).recordSession(
            mangaId: manga.id,
            chapterId: episode.id,
            pagesRead: 0,
            durationSeconds: watched.clamp(1, 60 * 60 * 3),
          );
    } catch (_) {
      // Best-effort — playback already finished.
    }
  }

  Future<void> _loadEpisode() async {
    final repo = ref.read(data.libraryRepositoryProvider);
    final (manga, episode) = await repo.resolveChapter(widget.episodeId);
    if (!mounted) return;
    if (manga == null || episode == null) {
      setState(() => _notFound = true);
      return;
    }
    setState(() {
      _manga = manga;
      _episode = episode;
    });
    // _openVideo is driven by the build method once video sources arrive.
  }

  /// Called from build when sources are available (and not yet opened).
  void _tryOpenVideo(List<VideoQuality> sources) {
    if (_notFound || sources.isEmpty) return;
    if (_openedEpisodeId == _currentEpisodeId) return;
    _openedEpisodeId = _currentEpisodeId;
    _openVideo();
  }

  Future<void> _openVideo() async {
    final sources = ref.read(videoSourcesProvider(_currentEpisodeId));
    final url = sources.isNotEmpty ? sources.first.url : '';
    if (url.isEmpty) return;
    await _player.open(Media(url));
    await _player.setRate(_speed);
    await _player.setVolume(_volume);
    await _resumeFromSavedPosition();
    _applyDefaultSubtitle();
    _maybeStartAniSkipWatch();
  }

  /// Applies the persisted "Default subtitle" preference (Settings →
  /// Player) — previously the option was stored but never consumed, so
  /// every episode started with subtitles off regardless of the choice.
  void _applyDefaultSubtitle() {
    final pref = ref.read(appSettingsProvider).defaultSubtitle;
    if (pref == 'Off') return;
    final tracks = ref.read(subtitleTracksProvider(_currentEpisodeId));
    for (var i = 0; i < tracks.length; i++) {
      final label = tracks[i].label.toLowerCase();
      final lang = pref.toLowerCase();
      if (label.contains(lang) ||
          (lang.startsWith('eng') && label.contains('english')) ||
          (lang.contains('spanish') && label.contains('espa'))) {
        _setSubtitle(i);
        return;
      }
    }
  }

  /// REAL resume: jump to the saved watch position when it is meaningful
  /// (previously every open restarted at 0:00 even mid-episode).
  Future<void> _resumeFromSavedPosition() async {
    final episode = _episode;
    if (episode == null) return;
    final saved = episode.lastPageRead; // seconds watched
    // Only resume when at least 10 s were watched and 30 s remain.
    if (saved <= 10) return;
    if (_duration.inSeconds > 0 && saved >= _duration.inSeconds - 30) return;
    try {
      await _player.seek(Duration(seconds: saved));
    } catch (_) {}
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionSub?.cancel();
    _progressSaver?.cancel();
    // Flush the final watch position so Continue-watching resumes here.
    unawaited(_flushProgress());
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
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
      if (mounted && !_seeking) {
        setState(() => _controlsVisible = false);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  Future<void> _seekTo(Duration position) async {
    await _player.seek(position);
    if (mounted) setState(() => _position = position);
  }

  Future<void> _togglePlay() async {
    await _player.playOrPause();
    _scheduleHide();
  }

  Future<void> _setVolume(double v) async {
    await _player.setVolume(v);
    setState(() => _volume = v);
  }

  Future<void> _setSpeed(double s) async {
    _speed = s;
    await _player.setRate(s);
    setState(() {});
  }

  /// Maps the persisted default-quality label (e.g. '720p') to an index
  /// in the available sources; 0 when nothing matches.
  int _defaultQualityIndex(List<VideoQuality> sources) {
    final pref = ref.read(appSettingsProvider).defaultVideoQuality;
    if (pref == 'Auto') return 0;
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].label.toLowerCase() == pref.toLowerCase()) return i;
    }
    return 0;
  }

  Future<void> _setQuality(int index) async {
    final sources = ref.read(videoSourcesProvider(widget.episodeId));
    if (index < 0 || index >= sources.length) return;
    final wasPlaying = _player.state.playing;
    final pos = _position;
    setState(() {
      _qualityIndex = index;
      _isLoading = true;
    });
    await _player.open(Media(sources[index].url));
    await _player.seek(pos);
    if (wasPlaying) await _player.play();
  }

  Future<void> _setSubtitle(int index) async {
    setState(() => _subtitleIndex = index);
    final tracks = ref.read(subtitleTracksProvider(widget.episodeId));
    if (index >= 0 && index < tracks.length && tracks[index].url.isNotEmpty) {
      // media_kit loads external subtitle tracks via the platform-specific API.
      // The setSubtitleTrack call is intentionally wrapped so a missing native
      // binding (e.g. on desktop test harnesses) does not crash the UI.
      try {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(tracks[index].url, title: tracks[index].label),
        );
      } on Object {
        // no-op: subtitle backend unavailable
      }
    } else {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    }
  }

  void _maybeStartAniSkipWatch() {
    // Honour Settings -> Player -> AniSkip: when disabled, no skip button
    // is ever surfaced (the toggle previously had no effect at all).
    if (!ref.read(appSettingsProvider).aniSkipEnabled) return;
    final ranges = ref.read(aniSkipProvider(widget.episodeId));
    if (ranges.isEmpty) return;
    _positionSub?.cancel();
    _positionSub = _player.stream.position.listen((pos) {
      for (final r in ranges) {
        if (pos >= r.start && pos < r.end) {
          if (_activeSkip != r) setState(() => _activeSkip = r);
          return;
        }
      }
      if (_activeSkip != null) setState(() => _activeSkip = null);
    });
  }

  Future<void> _skipCurrent() async {
    if (_activeSkip == null) return;
    await _seekTo(_activeSkip!.end);
    setState(() => _activeSkip = null);
  }

  Future<void> _skipOp() async {
    final ranges = ref.read(aniSkipProvider(widget.episodeId));
    final op = ranges.where((r) => r.type == 'op').firstOrNull;
    if (op != null) await _seekTo(op.end);
  }

  Future<void> _skipEd() async {
    final ranges = ref.read(aniSkipProvider(widget.episodeId));
    final ed = ranges.where((r) => r.type == 'ed').firstOrNull;
    if (ed != null) {
      await _seekTo(ed.start);
    } else {
      await _seekTo(_duration - const Duration(seconds: 90));
    }
  }

  Future<void> _nextEpisode() async {
    final manga = _manga;
    final episode = _episode;
    if (manga == null || episode == null) return;
    final idx = manga.chapters.indexWhere((c) => c.id == episode.id);
    if (idx <= 0) {
      showSnack(ref, context, 'No next episode');
      return;
    }
    await _switchToEpisode(manga.chapters[idx - 1]);
  }

  Future<void> _prevEpisode() async {
    final manga = _manga;
    final episode = _episode;
    if (manga == null || episode == null) return;
    final idx = manga.chapters.indexWhere((c) => c.id == episode.id);
    if (idx >= manga.chapters.length - 1) {
      showSnack(ref, context, 'No previous episode');
      return;
    }
    await _switchToEpisode(manga.chapters[idx + 1]);
  }

  /// Loads the target episode's sources (awaiting the async notifier — the
  /// old code read the provider synchronously so it ALWAYS saw the empty
  /// initial state and refused to switch), then rebinds the player.
  Future<void> _switchToEpisode(Chapter target) async {
    showSnack(ref, context, 'Loading ${target.name}…');
    final notifier = ref.read(videoSourcesProvider(target.id).notifier);
    await notifier.reload();
    final sources = ref.read(videoSourcesProvider(target.id));
    if (!mounted) return;
    if (sources.isEmpty) {
      showSnack(ref, context, 'No stream available for this episode');
      return;
    }
    setState(() {
      _episode = target;
      _currentEpisodeId = target.id;
      _isLoading = true;
      // First open honours the persisted default quality (Settings ->
      // Player); episode switches keep the user's in-session choice.
      if (_qualityIndex == 0) {
        _qualityIndex = _defaultQualityIndex(sources);
      }
      _qualityIndex = _qualityIndex.clamp(0, sources.length - 1);
    });
    _openedEpisodeId = target.id;
    _completedHandled = false;
    _sessionStart = DateTime.now();
    await _player.open(Media(sources[_qualityIndex].url));
    await _resumeFromSavedPosition();
    _maybeStartAniSkipWatch();
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Episode')),
        body: emptyState(
          context: context,
          icon: Icons.search_off,
          title: 'Episode not found',
          subtitle: 'This episode is no longer in your library.',
        ),
      );
    }

    // Open the video as soon as the (auto-loaded) sources arrive for the
    // episode the player is currently bound to.
    final sources = ref.watch(videoSourcesProvider(_currentEpisodeId));
    if (sources.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryOpenVideo(sources);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Center(
                  child: SizedBox(
                    width: orientation == Orientation.landscape
                        ? double.infinity
                        : MediaQuery.of(context).size.width,
                    child: Video(
                      controller: _controller,
                      fit: BoxFit.contain,
                      // `NoVideoControls` is `const null` in media_kit_video
                      // (inferred `dynamic`, rejected by strict-casts) — pass
                      // `null` directly; same effect: no built-in controls.
                      controls: null,
                    ),
                  ),
                ),
              ),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
              if (_activeSkip != null)
                _SkipButton(range: _activeSkip!, onSkip: _skipCurrent),
              if (_controlsVisible) _buildOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverlay() {
    final manga = _manga;
    return Stack(
      children: [
        _GradientTop(
          title: manga?.title ?? '',
          subtitle: _episode?.name ?? '',
          onBack: () => Navigator.maybePop(context),
        ),
        // Center play/pause button
        Center(
          child: IconButton(
            iconSize: 64,
            icon: Icon(
              _player.state.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            onPressed: _togglePlay,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _GradientBottom(
            position: _position,
            duration: _duration,
            buffered: _buffered,
            volume: _volume,
            speed: _speed,
            qualityLabel: _qualityLabel(),
            subtitleLabel: _subtitleLabel(),
            onSeek: (d) => _seekTo(d),
            onSeekStart: () {
              _seeking = true;
              _hideTimer?.cancel();
            },
            onSeekEnd: () {
              _seeking = false;
              _scheduleHide();
            },
            onPlayPause: _togglePlay,
            onPrevEpisode: _prevEpisode,
            onNextEpisode: _nextEpisode,
            onVolume: _setVolume,
            onSpeed: _setSpeed,
            onQuality: () => _showSelector(
              title: 'Quality',
              items: ref
                  .read(videoSourcesProvider(widget.episodeId))
                  .map((q) => q.label)
                  .toList(),
              selectedIndex: _qualityIndex,
              onSelect: (i) {
                _setQuality(i);
                Navigator.pop(context);
              },
            ),
            onSubtitles: () => _showSelector(
              title: 'Subtitles',
              items: ref
                  .read(subtitleTracksProvider(widget.episodeId))
                  .map((s) => s.label)
                  .toList(),
              selectedIndex: _subtitleIndex,
              onSelect: (i) {
                _setSubtitle(i);
                Navigator.pop(context);
              },
            ),
            onAniSkip: _skipOp,
            onAniSkipEd: _skipEd,
          ),
        ),
      ],
    );
  }

  String _qualityLabel() {
    final sources = ref.read(videoSourcesProvider(widget.episodeId));
    if (sources.isEmpty || _qualityIndex >= sources.length) return 'Auto';
    return sources[_qualityIndex].label;
  }

  String _subtitleLabel() {
    final tracks = ref.read(subtitleTracksProvider(widget.episodeId));
    if (tracks.isEmpty || _subtitleIndex >= tracks.length) return 'Off';
    return tracks[_subtitleIndex].label;
  }

  void _showSelector({
    required String title,
    required List<String> items,
    required int selectedIndex,
    required ValueChanged<int> onSelect,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          // Flutter 3.32+: group value / change handling moved from each
          // RadioListTile to the [RadioGroup] ancestor.
          child: RadioGroup<int>(
            groupValue: selectedIndex,
            onChanged: (v) => onSelect(v ?? 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                ...items.asMap().entries.map((e) {
                  return RadioListTile<int>(
                    value: e.key,
                    activeColor: Colors.white,
                    title: Text(e.value,
                        style: const TextStyle(color: Colors.white)),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GradientTop extends StatelessWidget {
  const _GradientTop({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack,
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
                      Text(subtitle,
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

class _GradientBottom extends StatelessWidget {
  const _GradientBottom({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.volume,
    required this.speed,
    required this.qualityLabel,
    required this.subtitleLabel,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onPlayPause,
    required this.onPrevEpisode,
    required this.onNextEpisode,
    required this.onVolume,
    required this.onSpeed,
    required this.onQuality,
    required this.onSubtitles,
    required this.onAniSkip,
    required this.onAniSkipEd,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double volume;
  final double speed;
  final String qualityLabel;
  final String subtitleLabel;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevEpisode;
  final VoidCallback onNextEpisode;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onSpeed;
  final VoidCallback onQuality;
  final VoidCallback onSubtitles;
  final VoidCallback onAniSkip;
  final VoidCallback onAniSkipEd;

  @override
  Widget build(BuildContext context) {
    final total =
        duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
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
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seek bar with buffered indicator
              Row(
                children: [
                  Text(formatDuration(position),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // buffered track
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: buffered.inMilliseconds
                                            .toDouble()
                                            .clamp(0, total) /
                                        total,
                                    minHeight: 4,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation(
                                        Colors.white38),
                                  ),
                                ),
                              ),
                            ),
                            Slider(
                              value: position.inMilliseconds
                                  .toDouble()
                                  .clamp(0, total)
                                  .toDouble(),
                              min: 0,
                              max: total,
                              onChangeStart: (_) => onSeekStart(),
                              onChanged: (v) =>
                                  onSeek(Duration(milliseconds: v.round())),
                              onChangeEnd: (_) => onSeekEnd(),
                              activeColor:
                                  Theme.of(context).colorScheme.primary,
                              inactiveColor: Colors.transparent,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Text(formatDuration(duration),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              // Main control row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous episode',
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white),
                        onPressed: onPrevEpisode,
                      ),
                      IconButton(
                        tooltip: 'Rewind 10s',
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        onPressed: () =>
                            onSeek(position - const Duration(seconds: 10)),
                      ),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        onPressed: onPlayPause,
                      ),
                      IconButton(
                        tooltip: 'Forward 10s',
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        onPressed: () =>
                            onSeek(position + const Duration(seconds: 10)),
                      ),
                      IconButton(
                        tooltip: 'Next episode',
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: onNextEpisode,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Volume
                      IconButton(
                        tooltip: 'Volume',
                        icon: Icon(
                            volume <= 0
                                ? Icons.volume_off
                                : volume < 0.5
                                    ? Icons.volume_down
                                    : Icons.volume_up,
                            color: Colors.white),
                        onPressed: () => onVolume(volume > 0 ? 0 : 1),
                      ),
                      SizedBox(
                        width: 70,
                        child: Slider(
                          value: volume,
                          min: 0,
                          max: 1,
                          onChanged: onVolume,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Secondary row: speed, quality, subtitles, AniSkip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _PillButton(
                      label: '${speed}x',
                      icon: Icons.speed,
                      onPressed: () => _showSpeedSheet(context),
                    ),
                    const SizedBox(width: 8),
                    _PillButton(
                      label: qualityLabel,
                      icon: Icons.hd_outlined,
                      onPressed: onQuality,
                    ),
                    const SizedBox(width: 8),
                    _PillButton(
                      label: subtitleLabel,
                      icon: Icons.subtitles_outlined,
                      onPressed: onSubtitles,
                    ),
                    const SizedBox(width: 8),
                    _PillButton(
                      label: 'Skip OP',
                      icon: Icons.fast_forward,
                      onPressed: onAniSkip,
                    ),
                    const SizedBox(width: 8),
                    _PillButton(
                      label: 'Skip ED',
                      icon: Icons.fast_rewind,
                      onPressed: onAniSkipEd,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context) {
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Playback speed',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: speeds
                    .map((s) => ChoiceChip(
                          label: Text('${s}x'),
                          selected: s == speed,
                          onSelected: (_) {
                            onSpeed(s);
                            Navigator.pop(context);
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
        shape: const StadiumBorder(side: BorderSide(color: Colors.white38)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.range, required this.onSkip});
  final SkipRange range;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      right: 16,
      child: Material(
        color: LuminaTheme.seed,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onSkip,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(range.label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                const Icon(Icons.fast_forward, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
