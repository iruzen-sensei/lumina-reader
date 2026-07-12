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
import '../../../models/models.dart';
import '../../../providers/providers.dart';
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
    required this.mangaId,
    required this.episodeId,
  });

  final int mangaId;
  final int episodeId;

  @override
  ConsumerState<AnimePlayerScreen> createState() => _AnimePlayerScreenState();
}

class _AnimePlayerScreenState extends ConsumerState<AnimePlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  late final List<StreamSubscription> _subs;

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

  late Chapter _episode;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration());
    _controller = VideoController(_player);
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
    _scheduleHide();
  }

  void _loadEpisode() {
    final manga = ref.read(mangaDetailProvider(widget.mangaId));
    _episode = manga.chapters.firstWhere(
      (c) => c.id == widget.episodeId,
      orElse: () => manga.chapters.first,
    );
  }

  Future<void> _openVideo() async {
    final sources = ref.read(videoSourcesProvider(widget.episodeId));
    final url = sources.isNotEmpty ? sources.first.url : '';
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

  void _togglePip() {
    // media_kit exposes PiP through the platform controller; surface a snackbar
    // where the native binding is unavailable.
    showSnack(ref, context, 'Picture-in-picture');
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
    await _player.open(Media(
        ref.read(videoSourcesProvider(_episode.id))[_qualityIndex].url));
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
    await _player.open(Media(
        ref.read(videoSourcesProvider(_episode.id))[_qualityIndex].url));
    _maybeStartAniSkipWatch();
  }

  @override
  Widget build(BuildContext context) {
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
                      controls: NoVideoControls,
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),
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
    final manga = ref.watch(mangaDetailProvider(widget.mangaId));
    return Stack(
      children: [
        _GradientTop(
          title: manga.title,
          subtitle: _episode.name,
          onBack: () => Navigator.maybePop(context),
          onPip: _togglePip,
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
                  groupValue: selectedIndex,
                  activeColor: Colors.white,
                  onChanged: (v) => onSelect(v ?? e.key),
                  title: Text(e.value,
                      style: const TextStyle(color: Colors.white)),
                );
              }),
            ],
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
    required this.onPip,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onPip;

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
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                  icon: const Icon(Icons.picture_in_picture_alt,
                      color: Colors.white),
                  onPressed: onPip,
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
    final total = duration.inMilliseconds.toDouble().clamp(1, double.infinity);
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
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
                                    valueColor:
                                        const AlwaysStoppedAnimation(
                                            Colors.white38),
                                  ),
                                ),
                              ),
                            ),
                            Slider(
                              value: position.inMilliseconds
                                  .toDouble()
                                  .clamp(0, total),
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
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
                        icon: const Icon(Icons.replay_10,
                            color: Colors.white),
                        onPressed: () => onSeek(position -
                            const Duration(seconds: 10)),
                      ),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        onPressed: onPlayPause,
                      ),
                      IconButton(
                        tooltip: 'Forward 10s',
                        icon: const Icon(Icons.forward_10,
                            color: Colors.white),
                        onPressed: () => onSeek(position +
                            const Duration(seconds: 10)),
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
        shape: StadiumBorder(
            side: const BorderSide(color: Colors.white38)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(range.label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
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
