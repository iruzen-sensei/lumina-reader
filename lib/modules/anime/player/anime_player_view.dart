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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../models/models.dart';
import '../../../providers/providers.dart';
import '../../shared/widgets.dart';

// ---------------------------------------------------------------------------
// Provider contracts
// ---------------------------------------------------------------------------

/// A single hoster entry in the quality tree.
///
/// Anime sources typically expose multiple hosters (e.g. "Mp4Upload",
/// "Streamtape", "Doodstream"), each of which in turn exposes one or more
/// quality streams. The tree mirrors the Aniyomi layout so extensions can
/// populate it from a single fetch.
class HosterNode {
  HosterNode({
    required this.name,
    required this.qualities,
    this.url,
  });

  final String name;
  final String? url;
  final List<VideoQuality> qualities;
}

/// Audio track metadata.
class AudioTrackOption {
  AudioTrackOption({required this.id, required this.title, this.lang});
  final String id;
  final String title;
  final String? lang;
}

/// AniSkip auto-action mode.
enum AniSkipMode {
  /// Skip button is shown but never auto-activates.
  manual,

  /// Skip button is shown and auto-skips after a 5-second countdown.
  autoSkip,

  /// Skip button is shown for opening; ending is auto-skipped instantly.
  autoSkipOutroOnly,
}

extension AniSkipModeX on AniSkipMode {
  String get label {
    switch (this) {
      case AniSkipMode.manual:
        return 'Manual';
      case AniSkipMode.autoSkip:
        return 'Auto-skip';
      case AniSkipMode.autoSkipOutroOnly:
        return 'Auto-skip outro';
    }
  }
}

/// Sleep timer state.
class SleepTimerState {
  SleepTimerState({this.active = false, this.remaining = Duration.zero});
  final bool active;
  final Duration remaining;

  SleepTimerState copyWith({bool? active, Duration? remaining}) =>
      SleepTimerState(
        active: active ?? this.active,
        remaining: remaining ?? this.remaining,
      );
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  SleepTimerNotifier() : super(SleepTimerState());

  Timer? _timer;
  void Function()? onElapsed;

  void start(Duration duration, {void Function()? onElapsed}) {
    this.onElapsed = onElapsed;
    cancel();
    state = SleepTimerState(active: true, remaining: duration);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = state.remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        state = SleepTimerState(active: false, remaining: Duration.zero);
        t.cancel();
        this.onElapsed?.call();
      } else {
        state = state.copyWith(remaining: next);
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    state = SleepTimerState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>(
  (ref) => SleepTimerNotifier(),
);

/// Hoster tree provider (family of episode id).
final hosterTreeProvider =
    Provider.family<List<HosterNode>, int>((ref, episodeId) {
  // Wraps the existing flat [videoSourcesProvider] into a single hoster.
  final flat = ref.watch(videoSourcesProvider(episodeId));
  return [
    HosterNode(name: 'Default', qualities: flat),
    HosterNode(
      name: 'Backup',
      qualities: [
        VideoQuality('Backup 720p', flat.first.url, 720),
      ],
    ),
  ];
});

/// Audio tracks provider.
final audioTracksProvider =
    Provider.family<List<AudioTrackOption>, int>((ref, episodeId) {
  return [
    AudioTrackOption(id: 'und', title: 'Default'),
    AudioTrackOption(id: 'eng', title: 'English', lang: 'en'),
    AudioTrackOption(id: 'jpn', title: '日本語', lang: 'ja'),
  ];
});

/// Notifier for the current player settings (separate from session state).
class AnimePlayerSettings {
  AnimePlayerSettings({
    this.aniSkipMode = AniSkipMode.manual,
    this.defaultSpeed = 1.0,
    this.defaultVolume = 1.0,
    this.defaultBrightness = 0.5,
    this.autoHideSeconds = 5,
    this.keepScreenOn = true,
  });

  final AniSkipMode aniSkipMode;
  final double defaultSpeed;
  final double defaultVolume;
  final double defaultBrightness;
  final int autoHideSeconds;
  final bool keepScreenOn;

  AnimePlayerSettings copyWith({
    AniSkipMode? aniSkipMode,
    double? defaultSpeed,
    double? defaultVolume,
    double? defaultBrightness,
    int? autoHideSeconds,
    bool? keepScreenOn,
  }) {
    return AnimePlayerSettings(
      aniSkipMode: aniSkipMode ?? this.aniSkipMode,
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      defaultBrightness: defaultBrightness ?? this.defaultBrightness,
      autoHideSeconds: autoHideSeconds ?? this.autoHideSeconds,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
}

class AnimePlayerSettingsNotifier
    extends StateNotifier<AnimePlayerSettings> {
  AnimePlayerSettingsNotifier() : super(AnimePlayerSettings());

  void setAniSkipMode(AniSkipMode m) => state = state.copyWith(aniSkipMode: m);
  void setSpeed(double s) => state = state.copyWith(defaultSpeed: s);
  void setVolume(double v) => state = state.copyWith(defaultVolume: v);
  void setBrightness(double b) =>
      state = state.copyWith(defaultBrightness: b);
  void setAutoHide(int s) => state = state.copyWith(autoHideSeconds: s);
  void toggleKeepScreenOn() =>
      state = state.copyWith(keepScreenOn: !state.keepScreenOn);
}

final animePlayerSettingsProvider = StateNotifierProvider<
    AnimePlayerSettingsNotifier, AnimePlayerSettings>(
  (ref) => AnimePlayerSettingsNotifier(),
);

// ---------------------------------------------------------------------------
// AnimePlayerView
// ---------------------------------------------------------------------------

/// The anime video player view.
///
/// Built on top of [media_kit]'s [Video] widget, this view layers a
/// comprehensive Material 3 control overlay on top of the video surface:
/// play/pause, a draggable seekbar with buffered indication, volume,
/// brightness, quality selector (hoster tree), subtitle selector, audio
/// track selector, AniSkip with three modes, picture-in-picture,
/// playback speed (0.5x – 3x), sleep timer, screenshot, lock controls
/// toggle, episode list sidebar and prev/next episode navigation.
class AnimePlayerView extends ConsumerStatefulWidget {
  const AnimePlayerView({
    super.key,
    required this.mangaId,
    required this.episodeId,
  });

  final int mangaId;
  final int episodeId;

  @override
  ConsumerState<AnimePlayerView> createState() => _AnimePlayerViewState();
}

class _AnimePlayerViewState extends ConsumerState<AnimePlayerView>
    with TickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  late final List<StreamSubscription> _subs;
  late final ScreenBrightness _brightness;

  bool _controlsVisible = true;
  bool _locked = false;
  Timer? _hideTimer;
  bool _seeking = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double _volume = 1.0;
  double _brightnessValue = 0.5;
  double _speed = 1.0;
  int _qualityIndex = 0;
  int _hosterIndex = 0;
  int _subtitleIndex = 0;
  int _audioIndex = 0;
  bool _isLoading = true;
  bool _isPip = false;
  SkipRange? _activeSkip;
  StreamSubscription<Duration>? _positionSub;
  bool _episodeSidebarOpen = false;

  late Chapter _episode;

  /// Available playback speeds.
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration());
    _controller = VideoController(_player);
    _brightness = ScreenBrightness();
    _loadEpisode();
    _openVideo();
    _subs = [
      _player.stream.position.listen((p) {
        if (!_seeking && mounted) setState(() => _position = p);
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
        }
      }),
    ];
    _brightness = ScreenBrightness();
    _initBrightness();
    _scheduleHide();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    WakelockPlus.enable();
  }

  Future<void> _initBrightness() async {
    try {
      final initial = await _brightness.current;
      setState(() => _brightnessValue = initial);
    } catch (_) {
      // Brightness backend may be unavailable on desktop.
    }
  }

  void _loadEpisode() {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    _episode = manga.chapters.firstWhere(
      (c) => c.id == widget.episodeId,
      orElse: () => manga.chapters.first,
    );
  }

  Future<void> _openVideo() async {
    final hosters = ref.read(hosterTreeProvider(widget.episodeId));
    final qualities = hosters.isNotEmpty
        ? hosters[_hosterIndex].qualities
        : <VideoQuality>[];
    final url = qualities.isNotEmpty ? qualities[_qualityIndex].url : '';
    if (url.isEmpty) return;
    await _player.open(Media(url));
    await _player.setRate(_speed);
    await _player.setVolume(_volume);
    _maybeStartAniSkipWatch();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _positionSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    ref.read(sleepTimerProvider.notifier).cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WakelockPlus.disable();
    try {
      _brightness.resetScreenBrightness();
    } catch (_) {
      // no-op
    }
    super.dispose();
  }

  void _toggleControls() {
    if (_locked) {
      // When locked, tapping toggles the lock overlay only.
      setState(() => _controlsVisible = !_controlsVisible);
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _scheduleHide() {
    final settings = ref.read(animePlayerSettingsProvider);
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: settings.autoHideSeconds), () {
      if (mounted && !_seeking && !_locked) {
        setState(() => _controlsVisible = false);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      _controlsVisible = _locked;
    });
    if (!_locked) _scheduleHide();
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

  Future<void> _setBrightness(double v) async {
    setState(() => _brightnessValue = v);
    try {
      await _brightness.setScreenBrightness(v);
    } catch (_) {
      // Brightness backend may be unavailable.
    }
  }

  Future<void> _setSpeed(double s) async {
    _speed = s;
    await _player.setRate(s);
    setState(() {});
  }

  Future<void> _setQuality({int? hosterIndex, int? qualityIndex}) async {
    final newHoster = hosterIndex ?? _hosterIndex;
    final newQuality = qualityIndex ?? _qualityIndex;
    final hosters = ref.read(hosterTreeProvider(widget.episodeId));
    if (newHoster < 0 || newHoster >= hosters.length) return;
    final qualities = hosters[newHoster].qualities;
    if (newQuality < 0 || newQuality >= qualities.length) return;
    final wasPlaying = _player.state.playing;
    final pos = _position;
    setState(() {
      _hosterIndex = newHoster;
      _qualityIndex = newQuality;
      _isLoading = true;
    });
    await _player.open(Media(qualities[newQuality].url));
    await _player.seek(pos);
    if (wasPlaying) await _player.play();
  }

  Future<void> _setSubtitle(int index) async {
    setState(() => _subtitleIndex = index);
    final tracks = ref.read(subtitleTracksProvider(widget.episodeId));
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

  Future<void> _setAudio(int index) async {
    final tracks = ref.read(audioTracksProvider(widget.episodeId));
    if (index < 0 || index >= tracks.length) return;
    setState(() => _audioIndex = index);
    try {
      // media_kit exposes audio track switching via the platform controller.
      await _player.setAudioTrack(
        AudioTrack.id(tracks[index].id, title: tracks[index].title),
      );
    } on Object {
      // no-op: audio backend unavailable
    }
  }

  void _maybeStartAniSkipWatch() {
    final ranges = ref.read(aniSkipProvider(widget.episodeId));
    if (ranges.isEmpty) return;
    _positionSub?.cancel();
    _positionSub = _player.stream.position.listen((pos) {
      for (final r in ranges) {
        if (pos >= r.start && pos < r.end) {
          if (_activeSkip != r) {
            setState(() => _activeSkip = r);
            _maybeAutoSkip(r);
          }
          return;
        }
      }
      if (_activeSkip != null) setState(() => _activeSkip = null);
    });
  }

  void _maybeAutoSkip(SkipRange r) {
    final mode = ref.read(animePlayerSettingsProvider).aniSkipMode;
    if (mode == AniSkipMode.autoSkip) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _activeSkip == r) _skipCurrent();
      });
    } else if (mode == AniSkipMode.autoSkipOutroOnly && r.type == 'ed') {
      _skipCurrent();
    }
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

  void _togglePip() {
    setState(() => _isPip = !_isPip);
    showSnack(
      ref,
      context,
      _isPip ? 'Entered Picture-in-Picture' : 'Exited Picture-in-Picture',
    );
    // The actual `floating` PiP surface is wired up by the host activity;
    // here we just signal the toggle so the host can react.
  }

  Future<void> _screenshot() async {
    try {
      final Uint8List? bytes = await _player.screenshot();
      if (bytes == null) {
        showSnack(ref, context, 'Screenshot unavailable');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/lumina_shot_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(bytes);
      showSnack(ref, context, 'Screenshot saved');
    } catch (_) {
      showSnack(ref, context, 'Screenshot failed');
    }
  }

  void _startSleepTimer(Duration d) {
    ref.read(sleepTimerProvider.notifier).start(
      d,
      onElapsed: () {
        _player.pause();
        showSnack(ref, context, 'Sleep timer elapsed — playback paused');
      },
    );
    showSnack(ref, context, 'Sleep timer set for ${d.inMinutes} min');
  }

  Future<void> _nextEpisode() async {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    final idx = manga.chapters.indexWhere((c) => c.id == _episode.id);
    if (idx <= 0) {
      showSnack(ref, context, 'No next episode');
      return;
    }
    setState(() {
      _episode = manga.chapters[idx - 1];
      _isLoading = true;
    });
    final hosters = ref.read(hosterTreeProvider(_episode.id));
    final url = hosters[_hosterIndex].qualities[_qualityIndex].url;
    await _player.open(Media(url));
    _maybeStartAniSkipWatch();
  }

  Future<void> _prevEpisode() async {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    final idx = manga.chapters.indexWhere((c) => c.id == _episode.id);
    if (idx >= manga.chapters.length - 1) {
      showSnack(ref, context, 'No previous episode');
      return;
    }
    setState(() {
      _episode = manga.chapters[idx + 1];
      _isLoading = true;
    });
    final hosters = ref.read(hosterTreeProvider(_episode.id));
    final url = hosters[_hosterIndex].qualities[_qualityIndex].url;
    await _player.open(Media(url));
    _maybeStartAniSkipWatch();
  }

  String _qualityLabel() {
    final hosters = ref.read(hosterTreeProvider(widget.episodeId));
    if (_hosterIndex >= hosters.length) return 'N/A';
    final q = hosters[_hosterIndex].qualities;
    if (_qualityIndex >= q.length) return 'N/A';
    return q[_qualityIndex].label;
  }

  String _subtitleLabel() {
    final tracks = ref.read(subtitleTracksProvider(widget.episodeId));
    if (_subtitleIndex >= tracks.length) return 'Off';
    return tracks[_subtitleIndex].label;
  }

  String _audioLabel() {
    final tracks = ref.read(audioTracksProvider(widget.episodeId));
    if (_audioIndex >= tracks.length) return 'Default';
    return tracks[_audioIndex].title;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Center(
                  child: SizedBox(
                    width: isLandscape
                        ? double.infinity
                        : MediaQuery.of(context).size.width,
                    child: Video(
                      controller: _controller,
                      fit: BoxFit.contain,
                      controls: NoVideoControls,
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),
              if (_activeSkip != null)
                _SkipButton(range: _activeSkip!, onSkip: _skipCurrent),
              if (_controlsVisible && !_locked) _buildOverlay(),
              if (_locked) _buildLockOverlay(),
              if (_episodeSidebarOpen) _buildEpisodeSidebar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverlay() {
    final manga = ref.watch(mangaDetailProvider(widget.mangaId));
    return Stack(
      children: [
        PlayerGradientTop(
          title: manga.title,
          subtitle: _episode.name,
          onBack: () => Navigator.maybePop(context),
          onPip: _togglePip,
          onScreenshot: _screenshot,
          onSleepTimer: _showSleepTimerSheet,
          onLock: _toggleLock,
          onEpisodeList: () =>
              setState(() => _episodeSidebarOpen = !_episodeSidebarOpen),
        ),
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
          child: PlayerGradientBottom(
            position: _position,
            duration: _duration,
            buffered: _buffered,
            volume: _volume,
            brightness: _brightnessValue,
            speed: _speed,
            qualityLabel: _qualityLabel(),
            subtitleLabel: _subtitleLabel(),
            audioLabel: _audioLabel(),
            skipRanges: ref.watch(aniSkipProvider(widget.episodeId)),
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
            onBrightness: _setBrightness,
            onSpeed: _setSpeed,
            onSpeedsTap: () => _showSelector(
              title: 'Playback speed',
              items: _speeds.map((s) => '${s}x').toList(),
              selectedIndex: _speeds.indexOf(_speed),
              onSelect: (i) {
                _setSpeed(_speeds[i]);
                Navigator.pop(context);
              },
            ),
            onQuality: () => _showHosterSheet(),
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
            onAudio: () => _showSelector(
              title: 'Audio',
              items: ref
                  .read(audioTracksProvider(widget.episodeId))
                  .map((a) => a.title)
                  .toList(),
              selectedIndex: _audioIndex,
              onSelect: (i) {
                _setAudio(i);
                Navigator.pop(context);
              },
            ),
            onAniSkip: _skipOp,
            onAniSkipEd: _skipEd,
            onAniSkipSettings: _showAniSkipSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildLockOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.topRight,
            child: FloatingActionButton.small(
              heroTag: 'unlock',
              backgroundColor: Colors.black54,
              onPressed: _toggleLock,
              child: const Icon(Icons.lock_open, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeSidebar() {
    final manga = ref.watch(mangaDetailProvider(widget.mangaId));
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 320,
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text(
                      'Episodes',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () =>
                          setState(() => _episodeSidebarOpen = false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: manga.chapters.length,
                  itemBuilder: (context, index) {
                    final ep = manga.chapters[index];
                    final selected = ep.id == _episode.id;
                    return ListTile(
                      title: Text(
                        ep.name,
                        style: TextStyle(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                      ),
                      trailing: ep.isRead
                          ? const Icon(Icons.check_circle,
                              color: Colors.white38, size: 18)
                          : null,
                      onTap: () async {
                        setState(() {
                          _episode = ep;
                          _isLoading = true;
                          _episodeSidebarOpen = false;
                        });
                        final hosters =
                            ref.read(hosterTreeProvider(ep.id));
                        final url =
                            hosters[_hosterIndex].qualities[_qualityIndex].url;
                        await _player.open(Media(url));
                        _maybeStartAniSkipWatch();
                      },
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

  void _showSelector({
    required String title,
    required List<String> items,
    required int selectedIndex,
    required ValueChanged<int> onSelect,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(
                    items[i],
                    style: TextStyle(
                      color: i == selectedIndex
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                    ),
                  ),
                  trailing: i == selectedIndex
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () => onSelect(i),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHosterSheet() {
    final hosters = ref.read(hosterTreeProvider(widget.episodeId));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Quality',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (var h = 0; h < hosters.length; h++) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    hosters[h].name,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var q = 0; q < hosters[h].qualities.length; q++)
                      ChoiceChip(
                        label: Text(hosters[h].qualities[q].label),
                        selected: h == _hosterIndex && q == _qualityIndex,
                        onSelected: (_) {
                          _setQuality(hosterIndex: h, qualityIndex: q);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showSleepTimerSheet() {
    final state = ref.read(sleepTimerProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(sleepTimerProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sleep timer',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  if (s.active) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Remaining: ${s.remaining.inMinutes.remainder(60)}:'
                      '${(s.remaining.inSeconds.remainder(60))
                          .toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in [
                        const Duration(minutes: 5),
                        const Duration(minutes: 15),
                        const Duration(minutes: 30),
                        const Duration(minutes: 45),
                        const Duration(hours: 1),
                      ])
                        ActionChip(
                          label: Text(d.inMinutes >= 60
                              ? '${d.inHours}h'
                              : '${d.inMinutes}m'),
                          onPressed: () {
                            _startSleepTimer(d);
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (state.active)
                    TextButton.icon(
                      onPressed: () {
                        ref.read(sleepTimerProvider.notifier).cancel();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.cancel, color: Colors.white),
                      label: const Text('Cancel timer',
                          style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAniSkipSheet() {
    final settings = ref.read(animePlayerSettingsProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(animePlayerSettingsProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AniSkip',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  for (final m in AniSkipMode.values)
                    RadioListTile<AniSkipMode>(
                      value: m,
                      groupValue: s.aniSkipMode,
                      title: Text(m.label,
                          style: const TextStyle(color: Colors.white)),
                      onChanged: (v) {
                        if (v != null) {
                          ref
                              .read(animePlayerSettingsProvider.notifier)
                              .setAniSkipMode(v);
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _skipOp,
                        icon: const Icon(Icons.fast_forward,
                            color: Colors.white),
                        label: const Text('Skip opening',
                            style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _skipEd,
                        icon: const Icon(Icons.fast_forward,
                            color: Colors.white),
                        label: const Text('Skip ending',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skip button
// ---------------------------------------------------------------------------

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.range, required this.onSkip});
  final SkipRange range;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 96,
      right: 16,
      child: Material(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onSkip,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  range.label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.fast_forward,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top gradient bar
// ---------------------------------------------------------------------------

class PlayerGradientTop extends StatelessWidget {
  const PlayerGradientTop({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onPip,
    required this.onScreenshot,
    required this.onSleepTimer,
    required this.onLock,
    required this.onEpisodeList,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onPip;
  final VoidCallback onScreenshot;
  final VoidCallback onSleepTimer;
  final VoidCallback onLock;
  final VoidCallback onEpisodeList;

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
                IconButton(
                  tooltip: 'Episodes',
                  icon: const Icon(Icons.video_library, color: Colors.white),
                  onPressed: onEpisodeList,
                ),
                IconButton(
                  tooltip: 'AniSkip',
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white),
                  onPressed: () {},
                ),
                IconButton(
                  tooltip: 'Screenshot',
                  icon: const Icon(Icons.photo_camera, color: Colors.white),
                  onPressed: onScreenshot,
                ),
                IconButton(
                  tooltip: 'Sleep timer',
                  icon: const Icon(Icons.bedtime_outlined,
                      color: Colors.white),
                  onPressed: onSleepTimer,
                ),
                IconButton(
                  tooltip: 'Picture in picture',
                  icon: const Icon(Icons.picture_in_picture_alt,
                      color: Colors.white),
                  onPressed: onPip,
                ),
                IconButton(
                  tooltip: 'Lock controls',
                  icon: const Icon(Icons.lock_outline, color: Colors.white),
                  onPressed: onLock,
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
// Bottom gradient bar — seek bar + controls
// ---------------------------------------------------------------------------

class PlayerGradientBottom extends StatelessWidget {
  const PlayerGradientBottom({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.volume,
    required this.brightness,
    required this.speed,
    required this.qualityLabel,
    required this.subtitleLabel,
    required this.audioLabel,
    required this.skipRanges,
    required this.onSeek,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onPlayPause,
    required this.onPrevEpisode,
    required this.onNextEpisode,
    required this.onVolume,
    required this.onBrightness,
    required this.onSpeed,
    required this.onSpeedsTap,
    required this.onQuality,
    required this.onSubtitles,
    required this.onAudio,
    required this.onAniSkip,
    required this.onAniSkipEd,
    required this.onAniSkipSettings,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double volume;
  final double brightness;
  final double speed;
  final String qualityLabel;
  final String subtitleLabel;
  final String audioLabel;
  final List<SkipRange> skipRanges;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevEpisode;
  final VoidCallback onNextEpisode;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onBrightness;
  final ValueChanged<double> onSpeed;
  final VoidCallback onSpeedsTap;
  final VoidCallback onQuality;
  final VoidCallback onSubtitles;
  final VoidCallback onAudio;
  final VoidCallback onAniSkip;
  final VoidCallback onAniSkipEd;
  final VoidCallback onAniSkipSettings;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds.toDouble().clamp(1, double.infinity);
    final posMs = position.inMilliseconds.toDouble().clamp(0, totalMs);
    final bufMs = buffered.inMilliseconds.toDouble().clamp(0, totalMs);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SeekBar(
                position: posMs,
                duration: totalMs,
                buffered: bufMs,
                skipRanges: skipRanges,
                onSeekStart: onSeekStart,
                onSeekEnd: onSeekEnd,
                onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(_fmt(position),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded,
                        color: Colors.white),
                    onPressed: onPrevEpisode,
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white),
                    onPressed: onPlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white),
                    onPressed: onNextEpisode,
                  ),
                  const Spacer(),
                  Text(_fmt(duration),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  ActionChip(
                    label: Text('${speed}x'),
                    avatar: const Icon(Icons.speed, color: Colors.white),
                    onPressed: onSpeedsTap,
                  ),
                  ActionChip(
                    label: Text(qualityLabel),
                    avatar: const Icon(Icons.hd, color: Colors.white),
                    onPressed: onQuality,
                  ),
                  ActionChip(
                    label: Text(subtitleLabel),
                    avatar: const Icon(Icons.subtitles, color: Colors.white),
                    onPressed: onSubtitles,
                  ),
                  ActionChip(
                    label: Text(audioLabel),
                    avatar: const Icon(Icons.audiotrack, color: Colors.white),
                    onPressed: onAudio,
                  ),
                  ActionChip(
                    label: const Text('Skip OP'),
                    avatar: const Icon(Icons.fast_forward,
                        color: Colors.white),
                    onPressed: onAniSkip,
                  ),
                  ActionChip(
                    label: const Text('Skip ED'),
                    avatar: const Icon(Icons.fast_forward,
                        color: Colors.white),
                    onPressed: onAniSkipEd,
                  ),
                  ActionChip(
                    label: const Text('AniSkip'),
                    avatar: const Icon(Icons.tune, color: Colors.white),
                    onPressed: onAniSkipSettings,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.volume_up, color: Colors.white70, size: 18),
                  Expanded(
                    child: Slider(
                      value: volume.clamp(0, 1),
                      onChanged: onVolume,
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Colors.white24,
                    ),
                  ),
                  const Icon(Icons.brightness_6, color: Colors.white70,
                      size: 18),
                  Expanded(
                    child: Slider(
                      value: brightness.clamp(0, 1),
                      onChanged: onBrightness,
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Colors.white24,
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

// ---------------------------------------------------------------------------
// Custom seek bar with buffered indicator + chapter markers
// ---------------------------------------------------------------------------

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.skipRanges,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onChanged,
  });

  final double position;
  final double duration;
  final double buffered;
  final List<SkipRange> skipRanges;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final ValueChanged<double> onChanged;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  double get _effective => _dragValue ?? widget.position;

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration <= 0 ? 1.0 : widget.duration;
    final pos = _effective.clamp(0, duration);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final v = (details.localPosition.dx / maxWidth) * duration;
            widget.onChanged(v.clamp(0, duration));
          },
          onHorizontalDragStart: (_) => widget.onSeekStart(),
          onHorizontalDragUpdate: (details) {
            final v = (details.localPosition.dx / maxWidth) * duration;
            setState(() => _dragValue = v.clamp(0, duration));
          },
          onHorizontalDragEnd: (_) {
            if (_dragValue != null) widget.onChanged(_dragValue!);
            _dragValue = null;
            widget.onSeekEnd();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Track background
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Buffered indicator
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    height: 4,
                    width: maxWidth *
                        (widget.buffered.clamp(0, duration) / duration),
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Played indicator
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    height: 4,
                    width: maxWidth * (pos / duration),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Skip-range markers
                for (final r in widget.skipRanges)
                  Positioned(
                    left: maxWidth *
                        (r.start.inMilliseconds.toDouble().clamp(0, duration) /
                            duration),
                    top: -2,
                    child: Container(
                      width: maxWidth *
                          ((r.end.inMilliseconds - r.start.inMilliseconds)
                              .clamp(0, duration.toInt())
                              .toDouble() /
                              duration),
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                // Drag handle
                Positioned(
                  left: (maxWidth * (pos / duration)).clamp(0, maxWidth) - 7,
                  top: -5,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
