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
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme.dart';
import '../../../core/ui/lumina_ui.dart';
import '../../../core/ui/watermelon.dart';
import '../../../data/providers.dart' as data;
import '../../../models/models.dart' hide SubtitleTrack;
import '../../../providers/providers.dart' hide SubtitleTrack;
import '../../shared/widgets.dart';

/// The anime player screen — a professional, gesture-driven playback
/// surface built on [media_kit]:
///
///   * Gestures: single-tap toggles controls, double-tap sides seek ±10s
///     (with animated indicators), horizontal drag scrubs, vertical drag
///     on the right half adjusts volume with a HUD.
///   * Seekbar: drag-to-scrub with a floating timestamp bubble, buffered
///     indication, and commit-on-release (no seek storms while dragging).
///   * Controls: animated play/pause, prev/next episode, an episode
///     picker sheet, playback speed, quality + subtitle selectors, AniSkip
///     skip OP/ED, screen lock, and Picture-in-Picture (auto-PiP when the
///     user leaves the app while playing — the native MainActivity handles
///     the Android side).
///   * Secondary controls live in a watermelon.sh Extended Toolbar: the
///     primary set slides out and the extended set slides in.
///   * Progress memory: debounced watch-position persistence + a final
///     flush on dispose, resume-on-reopen, history/stats recording.
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

/// Netflix player accent — the anime tab's crimson, consistent with the
/// browse/home surfaces.
const Color _kPlayerAccent = Color(0xFFE50914);

class _AnimePlayerScreenState extends ConsumerState<AnimePlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  late final List<StreamSubscription<dynamic>> _subs;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _seeking = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;

  /// media_kit volume is 0.0–100.0. The previous code treated it as 0–1,
  /// so playback ran at 1% volume — effectively SILENT (the "audio is
  /// broken" bug). Everything here is on the 0–100 scale.
  double _volume = 100.0;
  double _speed = 1.0;
  int _qualityIndex = 0;
  int _subtitleIndex = 0;
  bool _isLoading = true;
  SkipRange? _activeSkip;
  StreamSubscription<Duration>? _positionSub;

  /// Picture-in-Picture state (Android; auto-PiP when the user leaves the
  /// app mid-playback — driven by the native MainActivity channel).
  bool _inPip = false;
  static const _pipChannel = MethodChannel('lumina/pip');

  /// Controls lock (landscape one-hand use): when locked, all overlay
  /// controls are suppressed except the lock button itself.
  bool _locked = false;

  // ---- Gesture state ----
  /// Horizontal drag scrub preview: target position while dragging.
  Duration _scrubTarget = Duration.zero;
  bool _scrubbing = false;

  /// Double-tap seek feedback (side, direction, active).
  int _doubleTapSide = 0; // -1 left, 1 right, 0 none

  /// Vertical volume drag: start volume + drag delta → HUD.
  double _volumeDragStart = 0;
  bool _volumeDragging = false;

  // ---- Playback failure state ----
  String? _playerError;

  /// One-shot resume target: applied when the duration stream first reports
  /// a real duration (seeking before mpv knows the duration is a no-op).
  int? _pendingResumeSeconds;

  // ---- Watch-progress persistence ----
  DateTime _sessionStart = DateTime.now();
  Timer? _progressSaver;
  bool _completedHandled = false;
  bool _incognito = false;

  Chapter? _episode;
  Manga? _manga;
  bool _notFound = false;

  late int _currentEpisodeId = widget.episodeId;
  int? _openedEpisodeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        _applyPendingResume(d);
      }),
      _player.stream.buffering.listen((b) {
        if (mounted && _playerError == null) setState(() => _isLoading = b);
      }),
      _player.stream.buffer.listen((d) {
        if (mounted) setState(() => _buffered = d);
      }),
      _player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = v.clamp(0.0, 100.0));
      }),
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() {}); // play/pause icon refresh
        // Auto-PiP: only ask the OS to shrink when actually playing.
        if (Platform.isAndroid) {
          _pipChannel.invokeMethod(
              'setAutoOnLeave', {'enabled': playing && !_inPip});
        }
      }),
      _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          _handleEpisodeComplete();
          _autoNext();
        }
      }),
      _player.stream.error.listen((e) {
        debugPrint('media_kit error: $e');
        if (!mounted) return;
        setState(() {
          _playerError = 'Playback failed. The stream may be offline or '
              'blocked — check your connection and retry.';
          _isLoading = false;
        });
      }),
    ];
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged' && mounted) {
        setState(() => _inPip = (call.arguments as bool?) ?? false);
      }
    });
    _scheduleHide();
    _incognito = ref.read(incognitoModeProvider);
    _sessionStart = DateTime.now();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) {
      _pipChannel.invokeMethod('setAutoOnLeave', {'enabled': false});
    }
    _hideTimer?.cancel();
    _positionSub?.cancel();
    _progressSaver?.cancel();
    unawaited(_flushProgress());
    _recordPartialWatchSession();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Progress / history / stats
  // ---------------------------------------------------------------------------

  void _scheduleProgressSave() {
    _progressSaver?.cancel();
    _progressSaver = Timer(const Duration(seconds: 5), _flushProgress);
  }

  Future<void> _flushProgress() async {
    final episode = _episode;
    if (episode == null || _incognito) return;
    if (_duration.inMilliseconds <= 0) return;
    final seconds = _position.inSeconds;
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

  void _recordPartialWatchSession() {
    if (_incognito || _completedHandled) return;
    final manga = _manga;
    final episode = _episode;
    if (manga == null || episode == null) return;
    final watched = DateTime.now().difference(_sessionStart).inSeconds;
    if (watched < 30) return;
    unawaited(() async {
      try {
        await ref.read(data.statsRepositoryProvider).recordSession(
              mangaId: manga.id,
              chapterId: episode.id,
              pagesRead: 0,
              durationSeconds: watched.clamp(1, 60 * 60 * 3),
            );
      } catch (_) {}
    }());
  }

  // ---------------------------------------------------------------------------
  // Episode + stream loading
  // ---------------------------------------------------------------------------

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
  }

  void _tryOpenVideo(EpisodeMediaState media) {
    if (_notFound || media.sources.isEmpty) return;
    if (_openedEpisodeId == _currentEpisodeId) return;
    _openedEpisodeId = _currentEpisodeId;
    _openVideo();
  }

  void _applyPendingResume(Duration duration) {
    final target = _pendingResumeSeconds;
    if (target == null || duration.inSeconds <= 0) return;
    _pendingResumeSeconds = null;
    if (target <= 10 || target >= duration.inSeconds - 30) return;
    unawaited(_player.seek(Duration(seconds: target)));
  }

  Future<void> _openVideo() async {
    final media = ref.read(videoSourcesProvider(_currentEpisodeId));
    if (media.sources.isEmpty) return;
    final quality = media.sources[_qualityIndex.clamp(0, media.sources.length - 1)];
    try {
      _playerError = null;
      await _player.open(Media(quality.url, httpHeaders: quality.headers));
    } catch (e) {
      debugPrint('player open failed: $e');
      if (mounted) {
        setState(() {
          _playerError = 'Could not open the stream. Retry in a moment.';
          _isLoading = false;
        });
      }
      return;
    }
    await _player.setRate(_speed);
    await _player.setVolume(_volume);
    _queueResumeFromSavedPosition();
    _applyDefaultSubtitle();
    _maybeStartAniSkipWatch();
  }

  Future<void> _retryOpen() async {
    setState(() {
      _playerError = null;
      _isLoading = true;
    });
    final notifier = ref.read(videoSourcesProvider(_currentEpisodeId).notifier);
    await notifier.reload();
    if (!mounted) return;
    _openedEpisodeId = null;
    _tryOpenVideo(ref.read(videoSourcesProvider(_currentEpisodeId)));
  }

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

  void _queueResumeFromSavedPosition() {
    final episode = _episode;
    if (episode == null) return;
    final saved = episode.lastPageRead; // seconds watched
    if (saved <= 10) return;
    _pendingResumeSeconds = saved;
    _applyPendingResume(_duration);
  }

  // ---------------------------------------------------------------------------
  // Controls / gestures
  // ---------------------------------------------------------------------------

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
      if (mounted && !_seeking && !_scrubbing) {
        setState(() => _controlsVisible = false);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  Future<void> _seekTo(Duration position) async {
    // Duration has no clamp() — bound manually (and never into the void
    // before the duration is known).
    var target = position;
    if (target < Duration.zero) target = Duration.zero;
    final max = _duration > Duration.zero
        ? _duration
        : const Duration(days: 1);
    if (target > max) target = max;
    await _player.seek(target);
    if (mounted) setState(() => _position = target);
  }

  Future<void> _togglePlay() async {
    await _player.playOrPause();
    _scheduleHide();
  }

  Future<void> _setVolume(double v) async {
    final nv = v.clamp(0.0, 100.0);
    await _player.setVolume(nv);
    setState(() => _volume = nv);
  }

  Future<void> _setSpeed(double s) async {
    _speed = s;
    await _player.setRate(s);
    setState(() {});
  }

  /// Double-tap on the left/right third seeks ∓/±10s with an animated
  /// indicator (YouTube/Netflix pattern).
  Future<void> _doubleTapSeek(int side) async {
    setState(() => _doubleTapSide = side);
    await _seekTo(_position + Duration(seconds: side * 10));
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _doubleTapSide = 0);
    });
    _scheduleHide();
  }

  int _defaultQualityIndex(List<VideoQuality> sources) {
    final pref = ref.read(appSettingsProvider).defaultVideoQuality;
    if (pref == 'Auto') return 0;
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].label.toLowerCase() == pref.toLowerCase()) return i;
    }
    return 0;
  }

  Future<void> _setQuality(int index) async {
    final sources = ref.read(videoSourcesProvider(_currentEpisodeId)).sources;
    if (index < 0 || index >= sources.length) return;
    final wasPlaying = _player.state.playing;
    final pos = _position;
    setState(() {
      _qualityIndex = index;
      _isLoading = true;
      _playerError = null;
    });
    try {
      await _player.open(Media(sources[index].url,
          httpHeaders: sources[index].headers));
    } catch (e) {
      debugPrint('quality switch open failed: $e');
      if (mounted) {
        setState(() {
          _playerError = 'Could not switch quality. Retry?';
          _isLoading = false;
        });
      }
      return;
    }
    await _player.seek(pos);
    if (wasPlaying) await _player.play();
  }

  Future<void> _setSubtitle(int index) async {
    setState(() => _subtitleIndex = index);
    final tracks = ref.read(subtitleTracksProvider(_currentEpisodeId));
    if (index >= 0 && index < tracks.length && tracks[index].url.isNotEmpty) {
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
    if (!ref.read(appSettingsProvider).aniSkipEnabled) return;
    final ranges = ref.read(aniSkipProvider(_currentEpisodeId));
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
    final ranges = ref.read(aniSkipProvider(_currentEpisodeId));
    final op = ranges.where((r) => r.type == 'op').firstOrNull;
    if (op != null) await _seekTo(op.end);
  }

  Future<void> _skipEd() async {
    final ranges = ref.read(aniSkipProvider(_currentEpisodeId));
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

  /// Auto-advance to the next episode when one finishes (binge flow).
  void _autoNext() {
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final manga = _manga;
      final episode = _episode;
      if (manga == null || episode == null) return;
      final idx = manga.chapters.indexWhere((c) => c.id == episode.id);
      if (idx > 0) {
        _switchToEpisode(manga.chapters[idx - 1]);
      }
    });
  }

  Future<void> _switchToEpisode(Chapter target) async {
    showSnack(ref, context, 'Loading ${target.name}…');
    final notifier = ref.read(videoSourcesProvider(target.id).notifier);
    await notifier.reload();
    if (!mounted) return;
    var media = ref.read(videoSourcesProvider(target.id));
    if (media.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
    }
    media = ref.read(videoSourcesProvider(target.id));
    if (media.sources.isEmpty) {
      if (!mounted) return;
      showSnack(
          ref,
          context,
          media.error ??
              'No stream available for this episode yet');
      return;
    }
    setState(() {
      _episode = target;
      _currentEpisodeId = target.id;
      _isLoading = true;
      _playerError = null;
      if (_qualityIndex == 0) {
        _qualityIndex = _defaultQualityIndex(media.sources);
      }
      _qualityIndex = _qualityIndex.clamp(0, media.sources.length - 1);
    });
    _openedEpisodeId = target.id;
    _completedHandled = false;
    _sessionStart = DateTime.now();
    try {
      await _player.open(Media(media.sources[_qualityIndex].url,
          httpHeaders: media.sources[_qualityIndex].headers));
    } catch (e) {
      debugPrint('episode switch open failed: $e');
      if (mounted) {
        setState(() {
          _playerError = 'Could not open ${target.name}. Retry?';
          _isLoading = false;
        });
      }
      return;
    }
    _queueResumeFromSavedPosition();
    _maybeStartAniSkipWatch();
  }

  Future<void> _enterPip() async {
    if (!Platform.isAndroid) {
      showSnack(ref, context, 'Picture-in-Picture needs Android');
      return;
    }
    try {
      await _pipChannel.invokeMethod('enter');
    } catch (_) {
      if (mounted) {
        showSnack(ref, context, 'Picture-in-Picture is unavailable');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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

    final media = ref.watch(videoSourcesProvider(_currentEpisodeId));
    if (media.sources.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryOpenVideo(media);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: _PlayerGestures(
        // Gesture layer UNDER the controls overlay: taps on visible control
        // buttons hit the buttons (they are front-most in the Stack), taps
        // on the video hit this layer.
        onSingleTap: _locked ? _revealLockUi : _toggleControls,
        onDoubleTapSide: (side) {
          if (side != 0) _doubleTapSeek(side);
        },
        onHorizontalDragStart: () {
          setState(() {
            _scrubbing = true;
            _scrubTarget = _position;
          });
          _hideTimer?.cancel();
        },
        onHorizontalDragUpdate: (dx) {
          // ~1.2 screen widths = full seek span (comfortable precision).
          final width = MediaQuery.of(context).size.width;
          final span =
              _duration.inMilliseconds.toDouble().clamp(1, double.infinity);
          final delta = dx / (width * 1.2) * span;
          setState(() {
            _scrubTarget = Duration(
                milliseconds:
                    (_scrubTarget.inMilliseconds + delta).clamp(0, span).round());
          });
        },
        onHorizontalDragEnd: () {
          final target = _scrubTarget;
          setState(() => _scrubbing = false);
          unawaited(_seekTo(target));
          _scheduleHide();
        },
        onVerticalDragStart: () {
          setState(() {
            _volumeDragging = true;
            _volumeDragStart = _volume;
          });
          _hideTimer?.cancel();
        },
        onVerticalDragUpdate: (dy) {
          // Full height drag = 0→100% volume (right-half drags only).
          final height = MediaQuery.of(context).size.height;
          _setVolume(_volumeDragStart - dy / height * 100);
        },
        onVerticalDragEnd: () {
          setState(() => _volumeDragging = false);
          _scheduleHide();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Video(
                controller: _controller,
                fit: BoxFit.contain,
                controls: null,
              ),
            ),
            if (_isLoading && _playerError == null && !_inPip)
              const Center(child: CircularProgressIndicator()),
            if (_playerError != null ||
                (!media.loading && media.sources.isEmpty))
              _PlayerErrorCard(
                message: _playerError ??
                    media.error ??
                    'No stream available for this episode.',
                onRetry: _retryOpen,
              ),
            // Indicators — purely visual, never intercept touches.
            IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DoubleTapIndicator(side: _doubleTapSide),
                  if (_volumeDragging) _VolumeHud(volume: _volume),
                  if (_scrubbing)
                    _ScrubBubble(target: _scrubTarget, duration: _duration),
                ],
              ),
            ),
            if (_activeSkip != null && !_locked)
              _SkipButton(range: _activeSkip!, onSkip: _skipCurrent),
            // Controls overlay — ON TOP of the gesture layer so its
            // buttons always win the gesture arena.
            if (_controlsVisible && !_inPip)
              ..._buildOverlay(),
            if (_locked && !_inPip) _buildLockBadge(),
          ],
        ),
      ),
    );
  }

  void _revealLockUi() {
    // Tapping the screen while locked only reveals the lock button.
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Widget _buildLockBadge() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      right: 16,
      child: _PlayerIconButton(
        icon: Icons.lock_rounded,
        onTap: () {
          setState(() {
            _locked = false;
            _controlsVisible = true;
          });
          _scheduleHide();
        },
      ),
    );
  }

  List<Widget> _buildOverlay() {
    if (_locked) {
      // While locked: only the top bar title + the unlock button.
      return [
        _GradientTop(
          title: _manga?.title ?? '',
          subtitle: _episode?.name ?? '',
          onBack: () => Navigator.maybePop(context),
          locked: true,
          onUnlock: () => setState(() {
            _locked = false;
            _controlsVisible = true;
          }),
        ),
      ];
    }
    return [
      _GradientTop(
        title: _manga?.title ?? '',
        subtitle: _episode?.name ?? '',
        onBack: () => Navigator.maybePop(context),
      ),
      // Netflix center cluster: rewind-10 | play/pause | forward-10.
      Center(
        child: _CenterCluster(
          playing: _player.state.playing,
          onPlayPause: _togglePlay,
          onRewind: () =>
              _seekTo(_position - const Duration(seconds: 10)),
          onForward: () =>
              _seekTo(_position + const Duration(seconds: 10)),
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
          onSpeed: _setSpeed,
          onQuality: () => _showSelector(
            title: 'Quality',
            items: ref
                .read(videoSourcesProvider(_currentEpisodeId))
                .sources
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
                .read(subtitleTracksProvider(_currentEpisodeId))
                .map((s) => s.label)
                .toList(),
            selectedIndex: _subtitleIndex,
            onSelect: (i) {
              _setSubtitle(i);
              Navigator.pop(context);
            },
          ),
          onEpisodes: _showEpisodeSheet,
          onNextEpisode: _nextEpisode,
          onAniSkip: _skipOp,
          onAniSkipEd: _skipEd,
          onPip: _enterPip,
          onLock: () => setState(() {
            _locked = true;
            _controlsVisible = false;
          }),
        ),
      ),
    ];
  }

  String _qualityLabel() {
    final sources = ref.read(videoSourcesProvider(_currentEpisodeId)).sources;
    if (sources.isEmpty || _qualityIndex >= sources.length) return 'Auto';
    return sources[_qualityIndex].label;
  }

  String _subtitleLabel() {
    final tracks = ref.read(subtitleTracksProvider(_currentEpisodeId));
    if (tracks.isEmpty || _subtitleIndex >= tracks.length) return 'Off';
    return tracks[_subtitleIndex].label;
  }

  void _showEpisodeSheet() {
    final manga = _manga;
    if (manga == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Episodes',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: manga.chapters.length,
                  itemBuilder: (context, i) {
                    final ch = manga.chapters[i];
                    final current = ch.id == _currentEpisodeId;
                    final watched = ch.isRead;
                    final progress =
                        ch.totalPages > 0 ? ch.lastPageRead / ch.totalPages : 0.0;
                    return ListTile(
                      dense: true,
                      selected: current,
                      selectedColor: LuminaTheme.seed,
                      leading: watched
                          ? const Icon(Icons.check_circle_rounded,
                              color: Colors.white54, size: 20)
                          : progress > 0.05
                              ? Icon(Icons.play_circle_fill_rounded,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  size: 20)
                              : const Icon(Icons.circle_outlined,
                                  color: Colors.white30, size: 16),
                      title: Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: current
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.85),
                          fontWeight:
                              current ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      trailing: current
                          ? const Icon(Icons.graphic_eq_rounded,
                              color: Colors.white70, size: 18)
                          : progress > 0.05 && progress < 1
                              ? SizedBox(
                                  width: 42,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: progress.clamp(0.0, 1.0),
                                      minHeight: 3,
                                      backgroundColor: Colors.white24,
                                      valueColor:
                                          const AlwaysStoppedAnimation(
                                              Colors.white70),
                                    ),
                                  ),
                                )
                              : null,
                      onTap: current
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              _switchToEpisode(ch);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (context) {
        return SafeArea(
          child: RadioGroup<int>(
            groupValue: selectedIndex,
            onChanged: (v) => onSelect(v ?? 0),
            child: SingleChildScrollView(
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
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Gesture layer — sits above the video, below the controls:
//   * single tap → toggle controls
//   * double tap (left/right third) → seek -10s / +10s with ripple
//   * horizontal drag → scrub preview (commit on release)
//   * vertical drag (right half) → volume with HUD
// ---------------------------------------------------------------------------

class _PlayerGestures extends StatefulWidget {
  const _PlayerGestures({
    required this.child,
    required this.onSingleTap,
    required this.onDoubleTapSide,
    required this.onHorizontalDragStart,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final Widget child;
  final VoidCallback onSingleTap;
  final ValueChanged<int> onDoubleTapSide;
  final VoidCallback onHorizontalDragStart;
  final ValueChanged<double> onHorizontalDragUpdate;
  final VoidCallback onHorizontalDragEnd;
  final VoidCallback onVerticalDragStart;
  final ValueChanged<double> onVerticalDragUpdate;
  final VoidCallback onVerticalDragEnd;

  @override
  State<_PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends State<_PlayerGestures> {
  Offset? _dragStart;
  Offset? _lastPosition;
  bool _horizontal = false;
  bool _vertical = false;
  bool _rightHalf = false;
  int _doubleSide = 0;

  void _reset() {
    _dragStart = null;
    _lastPosition = null;
    _horizontal = false;
    _vertical = false;
    _rightHalf = false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Single tap toggles controls; double tap on the outer thirds seeks
      // ±10s. Flutter's built-in tap disambiguation handles the delay —
      // no manual timers (and no missed taps on control buttons, which
      // live ABOVE this layer in the Stack and win the arena themselves).
      onTap: widget.onSingleTap,
      onDoubleTapDown: (d) {
        _doubleSide = d.globalPosition.dx < size.width / 3
            ? -1
            : d.globalPosition.dx > size.width * 2 / 3
                ? 1
                : 0;
      },
      onDoubleTap: () {
        widget.onDoubleTapSide(_doubleSide);
        _doubleSide = 0;
      },
      onPanStart: (d) {
        _reset();
        _dragStart = d.globalPosition;
        _lastPosition = d.globalPosition;
        _rightHalf = d.globalPosition.dx > size.width / 2;
      },
      onPanUpdate: (d) {
        final start = _dragStart;
        final last = _lastPosition;
        if (start == null || last == null) return;
        final dx = d.globalPosition.dx - start.dx;
        final dy = d.globalPosition.dy - start.dy;
        if (!_horizontal && !_vertical) {
          // Direction lock after 12px. Vertical volume drags only start on
          // the right half (the left half stays free for future brightness).
          if (dx.abs() > 12 && dx.abs() >= dy.abs()) {
            _horizontal = true;
            widget.onHorizontalDragStart();
          } else if (dy.abs() > 12 && dy.abs() > dx.abs() && _rightHalf) {
            _vertical = true;
            widget.onVerticalDragStart();
          }
        }
        if (_horizontal) {
          widget.onHorizontalDragUpdate(d.globalPosition.dx - last.dx);
        } else if (_vertical) {
          widget.onVerticalDragUpdate(d.globalPosition.dy - start.dy);
        }
        _lastPosition = d.globalPosition;
      },
      onPanEnd: (_) {
        if (_horizontal) {
          widget.onHorizontalDragEnd();
        } else if (_vertical) {
          widget.onVerticalDragEnd();
        }
        _reset();
      },
      onPanCancel: () {
        if (_horizontal) {
          widget.onHorizontalDragEnd();
        } else if (_vertical) {
          widget.onVerticalDragEnd();
        }
        _reset();
      },
      child: widget.child,
    );
  }
}

/// The animated ±10s ripple indicator (YouTube style): a dark circle with
/// the replay/forward icon that pops + fades on the tapped side.
class _DoubleTapIndicator extends StatelessWidget {
  const _DoubleTapIndicator({required this.side});

  final int side; // -1 left, 0 none, 1 right

  @override
  Widget build(BuildContext context) {
    final show = side != 0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: show
          ? Align(
              key: const ValueKey('ripple'),
              alignment:
                  side < 0 ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 42),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        side < 0
                            ? Icons.replay_10_rounded
                            : Icons.forward_10_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      Text(
                        '${side < 0 ? '-' : '+'}10s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Volume HUD shown while vertically dragging (right half): icon + level
/// bar, floats on the right edge.
class _VolumeHud extends StatelessWidget {
  const _VolumeHud({required this.volume});

  final double volume; // 0..100

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                volume <= 1
                    ? Icons.volume_off_rounded
                    : volume < 50
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  width: 4,
                  height: 96,
                  child: LinearProgressIndicator(
                    value: (volume / 100).clamp(0.0, 1.0),
                    minHeight: 96,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${volume.round()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrub preview bubble: target timestamp + delta while dragging.
class _ScrubBubble extends StatelessWidget {
  const _ScrubBubble({required this.target, required this.duration});

  final Duration target;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatDuration(target),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 4),
            Text(
              duration > Duration.zero
                  ? 'of ${formatDuration(duration)}'
                  : 'seek',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay chrome
// ---------------------------------------------------------------------------

class _GradientTop extends StatelessWidget {
  const _GradientTop({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.onUnlock,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onUnlock;
  final bool locked;

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
                if (locked && onUnlock != null)
                  _PlayerIconButton(
                      icon: Icons.lock_rounded, onTap: onUnlock!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerIconButton extends StatefulWidget {
  const _PlayerIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<_PlayerIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child:
              Icon(widget.icon, size: 19, color: Colors.white.withValues(alpha: 0.92)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Center cluster (Netflix): rewind-10 | play/pause | forward-10 — big,
// round, high-contrast. The play button is a white circle with a dark
// glyph (Netflix grammar); the 10s circles are translucent white.
// ---------------------------------------------------------------------------

class _CenterCluster extends StatelessWidget {
  const _CenterCluster({
    required this.playing,
    required this.onPlayPause,
    required this.onRewind,
    required this.onForward,
  });

  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onRewind;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleSeekButton(
          icon: Icons.replay_10_rounded,
          size: 52,
          onTap: onRewind,
        ),
        const SizedBox(width: 28),
        _NetflixPlayButton(
          playing: playing,
          onTap: onPlayPause,
        ),
        const SizedBox(width: 28),
        _CircleSeekButton(
          icon: Icons.forward_10_rounded,
          size: 52,
          onTap: onForward,
        ),
      ],
    );
  }
}

class _CircleSeekButton extends StatefulWidget {
  const _CircleSeekButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  State<_CircleSeekButton> createState() => _CircleSeekButtonState();
}

class _CircleSeekButtonState extends State<_CircleSeekButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon,
              size: widget.size * 0.52,
              color: Colors.white.withValues(alpha: 0.95)),
        ),
      ),
    );
  }
}

/// The big white play/pause disc (Netflix center button grammar).
class _NetflixPlayButton extends StatelessWidget {
  const _NetflixPlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: heroAnimationsEnabled
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: child,
        ),
        child: Container(
          key: ValueKey(playing),
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 46,
            color: Colors.black.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar (Netflix): full-width scrubber with drag bubble, time row,
// then the watermelon.sh Extended Toolbar as the button row —
// [Episodes | Next Ep | PiP | Lock] morphing to
// [Speed | Quality | Subs | Skip OP | Skip ED] with the chevron.
// The old three-row stack (an M3 volume slider + icon row + toolbar) was
// cramped and clipped at the screen edge; volume is a gesture
// (right-half vertical drag) with a HUD, like every streaming app.
// ---------------------------------------------------------------------------

class _GradientBottom extends StatefulWidget {
  const _GradientBottom({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.speed,
    required this.qualityLabel,
    required this.subtitleLabel,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onSpeed,
    required this.onQuality,
    required this.onSubtitles,
    required this.onEpisodes,
    required this.onNextEpisode,
    required this.onAniSkip,
    required this.onAniSkipEd,
    required this.onPip,
    required this.onLock,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double speed;
  final String qualityLabel;
  final String subtitleLabel;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final ValueChanged<double> onSpeed;
  final VoidCallback onQuality;
  final VoidCallback onSubtitles;
  final VoidCallback onEpisodes;
  final VoidCallback onNextEpisode;
  final VoidCallback onAniSkip;
  final VoidCallback onAniSkipEd;
  final VoidCallback onPip;
  final VoidCallback onLock;

  @override
  State<_GradientBottom> createState() => _GradientBottomState();
}

class _GradientBottomState extends State<_GradientBottom> {
  double? _dragValue;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    final shown = _dragging
        ? (_dragValue ?? 0)
        : widget.position.inMilliseconds
            .toDouble()
            .clamp(0.0, total)
            .toDouble();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0.0, 0.72, 1.0],
          colors: [
            Colors.black.withValues(alpha: 0.88),
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- Scrubber (full width, Netflix red, fat thumb) ----
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _ScrubBar(
                    value: shown / total,
                    buffered: widget.buffered.inMilliseconds
                            .toDouble()
                            .clamp(0, total) /
                        total,
                    onDragStart: () {
                      setState(() {
                        _dragging = true;
                        _dragValue = shown.toDouble();
                      });
                      widget.onSeekStart();
                    },
                    onDragUpdate: (fraction) {
                      setState(() => _dragValue = fraction * total);
                    },
                    onDragEnd: (fraction) {
                      setState(() => _dragging = false);
                      widget.onSeekEnd();
                      widget.onSeek(Duration(
                          milliseconds: (fraction * total).round()));
                    },
                  ),
                  // Floating bubble above the thumb while scrubbing.
                  if (_dragging)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 26,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            formatDuration(Duration(
                                milliseconds: _dragValue?.round() ?? 0)),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // ---- Time row (current left, duration right) ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      formatDuration(_dragging
                          ? Duration(
                              milliseconds: _dragValue?.round() ?? 0)
                          : widget.position),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  Text(formatDuration(widget.duration),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                ],
              ),
              const SizedBox(height: 10),
              // ---- Button row: speed picker + Extended Toolbar ----
              // Speed is a watermelon.sh Quick Option Picker (pill -> tray,
              // no modal sheet); the toolbar is the dark labeled Netflix
              // cluster with Next Ep for binge flow.
              Row(
                children: [
                  WmQuickOptionPicker<double>(
                    hint: 'Speed',
                    trayAbove: false,
                    value: widget.speed,
                    options: [
                      for (final s in const [
                        0.25,
                        0.5,
                        0.75,
                        1.0,
                        1.25,
                        1.5,
                        1.75,
                        2.0
                      ])
                        WmPickerOption(
                          value: s,
                          label: s == 1.0 ? '1.0× Normal' : '${s.toStringAsFixed(2)}×',
                          icon: Icons.speed_rounded,
                        ),
                    ],
                    onChanged: widget.onSpeed,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: WmExtendedToolbar(
                        dark: true,
                        showLabels: true,
                        primary: [
                          WmToolItem(
                              icon: Icons.list_rounded,
                              label: 'Episodes',
                              onTap: widget.onEpisodes),
                          WmToolItem(
                              icon: Icons.skip_next_rounded,
                              label: 'Next Ep',
                              onTap: widget.onNextEpisode),
                          WmToolItem(
                              icon: Icons.picture_in_picture_alt_rounded,
                              label: 'PiP',
                              onTap: widget.onPip),
                          WmToolItem(
                              icon: Icons.lock_outline_rounded,
                              label: 'Lock',
                              onTap: widget.onLock),
                        ],
                        secondary: [
                          WmToolItem(
                              icon: Icons.hd_outlined,
                              label: widget.qualityLabel,
                              onTap: widget.onQuality),
                          WmToolItem(
                              icon: Icons.subtitles_outlined,
                              label: widget.subtitleLabel,
                              onTap: widget.onSubtitles),
                          WmToolItem(
                              icon: Icons.fast_forward_rounded,
                              label: 'Skip OP',
                              onTap: widget.onAniSkip),
                          WmToolItem(
                              icon: Icons.fast_rewind_rounded,
                              label: 'Skip ED',
                              onTap: widget.onAniSkipEd),
                        ],
                      ),
                    ),
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

/// The scrub bar: a fat translucent track with buffered fill + a draggable
/// thumb. Drag events are normalized to fractions; the PARENT commits the
/// seek on release (no seek-storms while dragging HLS).
class _ScrubBar extends StatefulWidget {
  const _ScrubBar({
    required this.value,
    required this.buffered,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double value; // 0..1 current
  final double buffered; // 0..1 buffered
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  @override
  State<_ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<_ScrubBar> {
  bool _dragging = false;
  double? _dragFraction;

  double _fraction(Offset local, BoxConstraints c) =>
      (local.dx / c.maxWidth).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final fraction = _dragging ? (_dragFraction ?? widget.value) : widget.value;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          setState(() {
            _dragging = true;
            _dragFraction =
                _fraction(d.localPosition, constraints);
          });
          widget.onDragStart();
          widget.onDragUpdate(_dragFraction!);
        },
        onHorizontalDragUpdate: (d) {
          setState(() =>
              _dragFraction = _fraction(d.localPosition, constraints));
          widget.onDragUpdate(_dragFraction!);
        },
        onHorizontalDragEnd: (_) {
          final f = _dragFraction ?? widget.value;
          setState(() => _dragging = false);
          widget.onDragEnd(f);
        },
        onHorizontalDragCancel: () {
          setState(() => _dragging = false);
          widget.onDragEnd(widget.value);
        },
        onTapDown: (d) {
          final f = _fraction(d.localPosition, constraints);
          widget.onDragStart();
          widget.onDragEnd(f);
        },
        child: Container(
          height: 26,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Buffered fill
              FractionallySizedBox(
                widthFactor: widget.buffered.clamp(0.0, 1.0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Progress fill (Netflix red)
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  height: _dragging ? 5 : 4,
                  decoration: BoxDecoration(
                    color: _kPlayerAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Thumb (grows on grab — Material 3 scrub pattern)
              Positioned(
                left: (fraction.clamp(0.0, 1.0)) *
                    (constraints.maxWidth - 14),
                child: Container(
                  width: _dragging ? 14 : 12,
                  height: _dragging ? 14 : 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kPlayerAccent,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Playback-failure card: replaces the eternal buffering spinner with the
/// actual reason + a Retry action.
class _PlayerErrorCard extends StatelessWidget {
  const _PlayerErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: Colors.white70, size: 36),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
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
      bottom: 190,
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
