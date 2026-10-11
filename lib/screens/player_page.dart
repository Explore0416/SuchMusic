import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final AudioPlayerService _audioPlayer = AudioPlayerService();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<SongModel?>? _currentSongSub;
  StreamSubscription<PlayMode>? _playModeSub;
  StreamSubscription<bool>? _fmModeSub;
  bool _isFmMode = false;
  final ValueNotifier<PlayMode> _playModeNotifier =
      ValueNotifier<PlayMode>(PlayMode.loop);
  bool _isPlaying = false;
  bool _coverCollapsed = false;
  String? _currentCoverUrl;
  Uint8List? _coverBytes;
  String? _fetchingUrl;

  @override
  void initState() {
    super.initState();
    _isPlaying = _audioPlayer.isPlaying;
    _playModeNotifier.value = _audioPlayer.playMode;
    _isFmMode = _audioPlayer.isFmMode;
    _loadCover();

    _stateSub = _audioPlayer.onStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _currentSongSub = _audioPlayer.onCurrentSongChanged.listen((song) {
      if (!mounted) return;
      if (song != null) {
        // 切歌时保留上一首封面继续显示，新封面加载完成后再替换
        _loadCover();
      } else {
        // 完全无歌曲时才清空封面，显示占位图
        _currentCoverUrl = null;
        _coverBytes = null;
        _fetchingUrl = null;
      }
      setState(() {});
    });

    _playModeSub = _audioPlayer.onPlayModeChanged.listen((mode) {
      if (mounted) {
        _playModeNotifier.value = mode;
      }
    });

    _fmModeSub = _audioPlayer.onFmModeChanged.listen((isFm) {
      if (mounted) {
        setState(() {
          _isFmMode = isFm;
        });
      }
    });
  }

  void _loadCover() {
    final song = _audioPlayer.currentSong;
    if (song?.coverUrl == null) {
      // 新歌没有封面：保留上一首封面继续显示，不退回占位图
      _fetchingUrl = null;
      return;
    }
    final newUrl = song!.coverUrl!;
    if (newUrl == _currentCoverUrl && _coverBytes != null) return;
    _currentCoverUrl = newUrl;
    final cached = AudioPlayerService.cachedCover(_currentCoverUrl!);
    if (cached != null) {
      _coverBytes = cached;
      _fetchingUrl = null;
    } else if (_fetchingUrl != newUrl) {
      _fetchingUrl = newUrl;
      _fetchCover(_currentCoverUrl!);
    }
  }

  Future<void> _fetchCover(String url) async {
    await AudioPlayerService.preFetchCover(url);
    if (!mounted) return;
    if (_currentCoverUrl != url) return; // 已切到其他歌，丢弃过期结果
    final bytes = AudioPlayerService.cachedCover(url);
    if (bytes != null) {
      setState(() {
        _coverBytes = bytes;
        _fetchingUrl = null;
      });
    } else {
      if (_fetchingUrl == url) {
        _fetchingUrl = null;
      }
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _currentSongSub?.cancel();
    _playModeSub?.cancel();
    _fmModeSub?.cancel();
    _playModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 深色页面：系统栏用浅色图标，避免 ColorOS 手势条自动垫浅色背景
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBlurredBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 34),
                _buildCoverAndSongInfo(),
                // 大歌词区域：出现时上移淡入，收起时下移淡出（与封面动画同步 200ms）
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
                      );
                    },
                    child: _coverCollapsed
                        ? FullLyricDisplay(
                            key: const ValueKey('lyrics'),
                          )
                        : const SizedBox.expand(
                            key: ValueKey('lyrics_empty'),
                          ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: _coverCollapsed
                      ? const SizedBox(
                          width: double.infinity,
                          key: ValueKey('song_info_empty'),
                        )
                      : Column(
                          key: const ValueKey('song_info_visible'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 25),
                              child: _buildSongInfo(collapsed: false),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ),
                ),
                Transform.translate(
                offset: const Offset(0, -12),
                child: const ProgressBar(),
              ),
                const SizedBox(height: 0),
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: _buildControls(),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBlurredBackground() {
    final defaultBg = Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: const Color(0xFF1A1A2E),
          child: Image.asset(
            'assets/images/Such_Music_Logo.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            color: Colors.black.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
    if (_coverBytes == null) return defaultBg;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          _coverBytes!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            color: Colors.black.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 16, top: 4, bottom: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/images/svg/Down.svg',
                  width: 22,
                  height: 22,
                  colorFilter: const ColorFilter.mode(
                      Colors.white, BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                const Text(
                  '返回',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildCoverAndSongInfo() {
    final screenWidth = MediaQuery.of(context).size.width;
    final coverSize = screenWidth - 50;
    const collapsedSize = 70.0;
    final collapsedHeight = collapsedSize + 8.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: coverSize,
      height: _coverCollapsed ? collapsedHeight : coverSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 4.0,
            left: collapsedSize + 12.0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              opacity: _coverCollapsed ? 1.0 : 0.0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                // 与小封面同步：上移浮现
                offset:
                    _coverCollapsed ? Offset.zero : const Offset(0, 0.4),
                child: _buildSongInfo(collapsed: true),
              ),
            ),
          ),
          // 大封面：收起时下移淡出
          Positioned(
            top: -8.0,
            left: 0,
            child: IgnorePointer(
              ignoring: _coverCollapsed,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                opacity: _coverCollapsed ? 0.0 : 1.0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  offset:
                      _coverCollapsed ? const Offset(0, 0.3) : Offset.zero,
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _coverCollapsed = true),
                    child: Container(
                      width: coverSize,
                      height: coverSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _coverImage(coverSize),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 小封面：收起时上移浮现
          Positioned(
            top: -8.0,
            left: 0,
            child: IgnorePointer(
              ignoring: !_coverCollapsed,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                opacity: _coverCollapsed ? 1.0 : 0.0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  offset:
                      _coverCollapsed ? Offset.zero : const Offset(0, 0.4),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _coverCollapsed = false),
                    child: Container(
                      width: collapsedSize,
                      height: collapsedSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: _coverImage(collapsedSize),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 封面图片（大小共用同一份字节缓存）
  Widget _coverImage(double size) {
    return _coverBytes != null
        ? Image.memory(
            _coverBytes!,
            key: ValueKey(_currentCoverUrl),
            width: size,
            height: size,
            fit: BoxFit.cover,
          )
        : _buildDefaultCover(size);
  }

  Widget _buildDefaultCover(double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF1A1A2E),
        child: Image.asset(
          'assets/images/Such_Music_Logo.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildSongInfo({required bool collapsed}) {
    final song = _audioPlayer.currentSong;

    if (song == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '暂无播放歌曲',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '快去挑一首喜欢的歌吧',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      );
    }

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(height: 8),
          const LyricDisplay(),
        ],
      ],
    );
    if (collapsed) return child;
    return child;
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_isFmMode)
            Opacity(
              opacity: 0.3,
              child: SvgPicture.asset(
                'assets/images/svg/Play_cycle.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                    Colors.white, BlendMode.srcIn),
              ),
            )
          else
            GestureDetector(
              onTap: () => _audioPlayer.togglePlayMode(),
              child: ValueListenableBuilder<PlayMode>(
                valueListenable: _playModeNotifier,
                builder: (_, mode, _) {
                  final icon = switch (mode) {
                    PlayMode.loop => 'assets/images/svg/Play_cycle.svg',
                    PlayMode.single => 'assets/images/svg/play-once.svg',
                    PlayMode.shuffle => 'assets/images/svg/shuffle-one.svg',
                  };
                  return SvgPicture.asset(
                    icon,
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(
                        Colors.white, BlendMode.srcIn),
                  );
                },
              ),
            ),
          GestureDetector(
            onTap: _isFmMode ? null : () => _audioPlayer.playPrevious(),
            child: Opacity(
              opacity: _isFmMode ? 0.3 : 1.0,
              child: SvgPicture.asset(
                'assets/images/svg/Previous.svg',
                width: 32,
                height: 32,
                colorFilter: const ColorFilter.mode(
                    Colors.white, BlendMode.srcIn),
              ),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () => _audioPlayer.togglePlayPause(),
              icon: _isPlaying
                  ? SvgPicture.asset(
                      'assets/images/svg/Pause.svg',
                      width: 48,
                      height: 48,
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn),
                    )
                  : SvgPicture.asset(
                      'assets/images/svg/Play.svg',
                      width: 48,
                      height: 48,
                      colorFilter: const ColorFilter.mode(
                          Colors.white, BlendMode.srcIn),
                    ),
            ),
          ),
          GestureDetector(
            onTap: () => _audioPlayer.playNext(),
            child: SvgPicture.asset(
              'assets/images/svg/Next.svg',
              width: 32,
              height: 32,
              colorFilter: const ColorFilter.mode(
                  Colors.white, BlendMode.srcIn),
            ),
          ),
          if (_isFmMode)
            GestureDetector(
              onTap: () => _audioPlayer.fmTrash(),
              child: SvgPicture.asset(
                'assets/images/svg/thumb_down.svg',
                width: 28,
                height: 28,
                colorFilter: const ColorFilter.mode(
                    Colors.white, BlendMode.srcIn),
              ),
            )
          else
            GestureDetector(
              onTap: () => _showPlaylistSheet(context),
              child: SvgPicture.asset(
                'assets/images/svg/Playlist_Alternate.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                    Colors.white, BlendMode.srcIn),
              ),
            ),
        ],
      ),
    );
  }

  void _showPlaylistSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final playlist = _audioPlayer.playlist;
            final currentIndex = _audioPlayer.currentIndex;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '播放列表 (${playlist.length})',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          if (playlist.isNotEmpty)
                            GestureDetector(
                              onTap: () async {
                                await _audioPlayer.clearPlaylist();
                                if (!ctx.mounted) return;
                                setSheetState(() {});
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(
                                  '清空',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close,
                                color: Colors.black54, size: 22),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                Expanded(
                  child: playlist.isEmpty
                      ? const Center(
                          child: Text(
                            '播放列表为空',
                            style: TextStyle(color: Colors.black38),
                          ),
                        )
                      : ListView.builder(
                          itemCount: playlist.length,
                          itemBuilder: (ctx, index) {
                            final song = playlist[index];
                            final isCurrent = index == currentIndex;
                            return ListTile(
                              leading: isCurrent
                                  ? const Icon(Icons.equalizer,
                                      color: Color(0xFF2F84FE), size: 22)
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: Colors.black38,
                                        fontSize: 14,
                                      ),
                                    ),
                              title: Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent
                                      ? const Color(0xFF2F84FE)
                                      : Colors.black87,
                                  fontSize: 14,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.black38,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: GestureDetector(
                                onTap: () async {
                                  await _audioPlayer.removeFromPlaylist(index);
                                  if (!ctx.mounted) return;
                                  setSheetState(() {});
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.close,
                                      color: Colors.black38, size: 18),
                                ),
                              ),
                              onTap: () async {
                                await _audioPlayer.playAtIndex(index);
                                if (!ctx.mounted) return;
                                setSheetState(() {});
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ProgressBar extends StatefulWidget {
  const ProgressBar({super.key});

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  final AudioPlayerService _audioPlayer = AudioPlayerService();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _position = _audioPlayer.position;
    _duration = _audioPlayer.duration;
    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted && !_isSeeking) {
        setState(() {
          _position = pos;
        });
      }
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _duration = dur;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = screenWidth - 50;
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        children: [
          SizedBox(
            width: barWidth,
            height: 20,
            child: GestureDetector(
              onTapUp: (details) {
                final pos =
                    (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                final seekPos = Duration(
                  milliseconds: (pos * _duration.inMilliseconds).round(),
                );
                setState(() {
                  _position = seekPos;
                });
                _audioPlayer.seek(seekPos);
              },
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _isSeeking = true;
                  final pos =
                      (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                  _position = Duration(
                    milliseconds:
                        (pos * _duration.inMilliseconds).round(),
                  );
                });
              },
              onHorizontalDragEnd: (_) {
                _isSeeking = false;
                _audioPlayer.seek(_position);
              },
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    width: barWidth,
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2.5),
                      color: Colors.white24,
                    ),
                  ),
                  Container(
                    width: barWidth * progress.clamp(0.0, 1.0),
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2.5),
                      color: Colors.white,
                    ),
                  ),
                  Positioned(
                    left: barWidth * progress.clamp(0.0, 1.0) - 5,
                    top: 5,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: barWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LyricDisplay extends StatefulWidget {
  const LyricDisplay({super.key});

  @override
  State<LyricDisplay> createState() => _LyricDisplayState();
}

class _LyricDisplayState extends State<LyricDisplay> {
  final AudioPlayerService _audioPlayer = AudioPlayerService();
  StreamSubscription<String>? _lyricSub;
  String _currentLyric = '';

  @override
  void initState() {
    super.initState();
    _currentLyric = _audioPlayer.currentLyric;
    _lyricSub = _audioPlayer.onLyricChanged.listen((lyric) {
      if (mounted) {
        setState(() {
          _currentLyric = lyric;
        });
      }
    });
  }

  @override
  void dispose() {
    _lyricSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              ...previousChildren,
              ?currentChild,
            ],
          );
        },
        transitionBuilder: (Widget child, Animation<double> animation) {
          final isNew = child.key == ValueKey(_currentLyric);
          final offset = isNew
              ? Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
              : Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.5));
          final curve = isNew
              ? const Interval(0.4, 1.0, curve: Curves.easeInOut)
              : Curves.easeInOut;
          return ClipRect(
            child: SlideTransition(
              position: offset.animate(CurvedAnimation(
                parent: animation,
                curve: curve,
              )),
              child: FadeTransition(
                opacity: isNew
                    ? CurvedAnimation(parent: animation, curve: curve)
                    : animation,
                child: child,
              ),
            ),
          );
        },
        child: Text(
          _currentLyric,
          key: ValueKey<String>(_currentLyric),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, color: Colors.white54),
        ),
      ),
    );
  }
}

class FullLyricDisplay extends StatefulWidget {
  const FullLyricDisplay({super.key});

  @override
  State<FullLyricDisplay> createState() => _FullLyricDisplayState();
}

class _FullLyricDisplayState extends State<FullLyricDisplay> {
  final AudioPlayerService _audioPlayer = AudioPlayerService();
  StreamSubscription<String>? _lyricSub;
  StreamSubscription<List<LyricLine>>? _lyricsSub;
  StreamSubscription<Duration>? _positionSub;
  List<LyricLine> _lyrics = [];
  int _currentIndex = -1;
  late final ScrollController _scrollController;
  bool _userScrolling = false;
  Timer? _scrollResumeTimer;
  final Map<int, GlobalKey> _itemKeys = {};
  static const double _topPadding = 200.0;
  static const double _bottomPadding = 500.0;

  void _afterLayout(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  @override
  void initState() {
    super.initState();
    _lyrics = _audioPlayer.lyrics;
    _currentIndex = _audioPlayer.currentLyricIndex;
    _scrollController = ScrollController();
    _afterLayout(_doScroll);

    _lyricsSub = _audioPlayer.onLyricsChanged.listen((lyrics) {
      if (mounted) {
        setState(() {
          _lyrics = lyrics;
          _currentIndex = _audioPlayer.currentLyricIndex;
        });
        if (!_userScrolling) _doScroll();
      }
    });

    _lyricSub = _audioPlayer.onLyricChanged.listen((_) {
      if (mounted) {
        setState(() {
          _currentIndex = _audioPlayer.currentLyricIndex;
        });
        if (!_userScrolling) _doScroll();
      }
    });

    _positionSub = _audioPlayer.onPositionChanged.listen((_) {
      if (mounted) {
        final newIndex = _audioPlayer.currentLyricIndex;
        if (newIndex != _currentIndex) {
          setState(() {
            _currentIndex = newIndex;
          });
          if (!_userScrolling) _doScroll();
        }
      }
    });
  }

  // 区分用户拖动与程序自动滚动：只有带 dragDetails（手指触摸拖动）的
  // 滚动通知才算用户操作；程序 animateTo 产生的通知 dragDetails 为 null
  void _onUserDragStart() {
    _userScrolling = true;
    _scrollResumeTimer?.cancel();
  }

  void _onUserDragEnd() {
    if (!_userScrolling) return;
    _scrollResumeTimer?.cancel();
    // 用户停手3秒后恢复自动跟随；若当前行仍在可视区域内则不打断浏览
    _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _userScrolling = false;
        if (!_isCurrentLineVisible()) _doScroll();
      }
    });
  }

  // 当前行是否完整在可视区域内
  bool _isCurrentLineVisible() {
    if (_currentIndex < 0) return false;
    final ctx = _itemKeys[_currentIndex]?.currentContext;
    if (ctx == null || !ctx.mounted) return false; // 未构建 = 不可见
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final revealTop =
        RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
    final itemH = box.size.height;
    final offset = _scrollController.offset;
    final viewportH = _scrollController.position.viewportDimension;
    return revealTop >= offset && revealTop + itemH <= offset + viewportH;
  }

  // 自动滚动到当前高亮歌词行（行顶精确停靠在视口 28% 高度处，在顶部渐隐区之下）
  void _doScroll() {
    if (_currentIndex < 0 || _lyrics.isEmpty) return;
    if (!_scrollController.hasClients) return;
    final anchorY = _scrollController.position.viewportDimension * 0.28;
    final key = _itemKeys[_currentIndex];

    if (key != null && key.currentContext != null) {
      // 情况1：当前歌词行已构建，按其真实渲染位置精确计算目标偏移
      _scrollToLine(key.currentContext!, anchorY,
          const Duration(milliseconds: 300));
    } else {
      // 情况2：目标行被懒加载回收：按已构建行的平均高度估算粗滚，
      // 行构建出来后再做一次精确定位
      double sum = 0;
      int count = 0;
      _itemKeys.forEach((_, k) {
        final c = k.currentContext;
        if (c != null && c.mounted) {
          final b = c.findRenderObject() as RenderBox?;
          if (b != null && b.hasSize) {
            sum += b.size.height;
            count++;
          }
        }
      });
      final estimatedItemHeight = count > 0 ? sum / count : 46.0;
      final targetOffset =
          _currentIndex * estimatedItemHeight + _topPadding - anchorY;
      final clampedOffset = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ).then((_) {
        // 第二步：item构建完成后精确停靠
        _afterLayout(() {
          if (!mounted) return;
          final key = _itemKeys[_currentIndex];
          if (key != null && key.currentContext != null) {
            _scrollToLine(key.currentContext!, anchorY,
                const Duration(milliseconds: 150));
          }
        });
      });
    }
  }

  // 用目标行的真实渲染位置计算滚动偏移，保证每行停靠位置一致
  void _scrollToLine(BuildContext ctx, double anchorY, Duration duration) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final viewport = RenderAbstractViewport.of(box);
    final target = (viewport.getOffsetToReveal(box, 0.0).offset - anchorY)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(target, duration: duration, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _lyricSub?.cancel();
    _lyricsSub?.cancel();
    _positionSub?.cancel();
    _scrollResumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 没有歌词时不显示任何占位内容
    if (_lyrics.isEmpty) {
      return const SizedBox.shrink();
    }

    // 上下渐隐遮罩：歌词靠近边缘时淡出，避免生硬截断
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0.0, 0.22, 0.85, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification) {
            if (n.dragDetails != null) _onUserDragStart();
          } else if (n is ScrollUpdateNotification) {
            if (n.dragDetails != null) _onUserDragStart();
          } else if (n is ScrollEndNotification) {
            _onUserDragEnd();
          }
          return false;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(
          top: _topPadding,
          bottom: _bottomPadding,
        ),
        itemCount: _lyrics.length,
        itemBuilder: (context, index) {
          final isCurrent = index == _currentIndex;
          final lyric = _lyrics[index];

          if (!_itemKeys.containsKey(index)) {
            _itemKeys[index] = GlobalKey();
          }

          final distance = (index - _currentIndex).abs();
          final scale = isCurrent ? 1.0 : 0.8;
          final opacity = isCurrent
              ? 1.0
              : distance <= 2
                  ? 0.6
                  : distance <= 5
                      ? 0.35
                      : 0.15;

          return GestureDetector(
            key: _itemKeys[index],
            onTap: () {
              _audioPlayer.seek(lyric.timestamp);
              _userScrolling = false;
              _scrollResumeTimer?.cancel();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  opacity: opacity,
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  child: Text(
                    lyric.text,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                    fontSize: isCurrent ? 30 : 24,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: Colors.white,
                    height: 1.4,
                    shadows: isCurrent
                        ? const [Shadow(color: Colors.white38, blurRadius: 16)]
                        : null,
                  ),
                ),
              ),
            ),
          ),
          );
        },
      ),
      ),
      ),
    );
  }
}