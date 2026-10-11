import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import '../models/song_model.dart';
import 'audio_player_service.dart';

MediaItem _songToMediaItem(SongModel song, {String? filePath}) {
  Uri? artUri;
  if (filePath != null) {
    artUri = Uri.file(filePath);
  } else {
    var coverUrl = song.coverUrl;
    if (coverUrl != null && coverUrl.startsWith('http://')) {
      coverUrl = coverUrl.replaceFirst('http://', 'https://');
    }
    if (coverUrl != null && coverUrl.isNotEmpty) {
      try {
        artUri = Uri.parse(coverUrl);
      } catch (_) {
        artUri = null;
      }
    }
  }
  final duration = song.duration;
  return MediaItem(
    id: song.id,
    album: song.album,
    title: song.name,
    artist: song.artist,
    duration: duration != null ? Duration(milliseconds: duration) : null,
    artUri: artUri,
  );
}

class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayerService _service = AudioPlayerService();

  AudioPlayerHandler() {
    _service.onStateChanged.listen(_onStateChanged);
    _service.onPositionChanged.listen(_onPositionChanged);
    _service.onDurationChanged.listen(_onDurationChanged);
    _service.onCurrentSongChanged.listen(_onCurrentSongChanged);
    _service.onPlaylistChanged.listen(_onPlaylistChanged);
    _service.onFmModeChanged.listen((_) => _emitPlaybackState());

    _emitCurrentState();
  }

  void _emitCurrentState() {
    final song = _service.currentSong;
    if (song != null) {
      mediaItem.add(_songToMediaItem(song));
    }
    final playlist = _service.playlist;
    if (playlist.isNotEmpty) {
      queue.add(playlist.map(_songToMediaItem).toList());
    }
    _emitPlaybackState();
  }

  void _emitPlaybackState() {
    final controls = _buildControls();
    final state = PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices:
          controls.length >= 3 ? [0, 1, 2] : List.generate(controls.length, (i) => i),
      processingState: _toAudioProcessingState(_service.state),
      playing: _service.isPlaying,
      updatePosition: _service.position,
      bufferedPosition: Duration.zero,
      speed: 1.0,
    );
    debugPrint(
        '[AudioPlayerHandler] emitPlaybackState: playing=${_service.isPlaying}, state=${_service.state}, controls=${controls.map((c) => c.label).toList()}');
    playbackState.add(state);
  }

  void _onStateChanged(PlayerState state) {
    _emitPlaybackState();
  }

  void _onPositionChanged(Duration position) {
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
    ));
  }

  void _onDurationChanged(Duration duration) {
    if (mediaItem.value != null) {
      mediaItem.add(mediaItem.value!.copyWith(duration: duration));
    }
  }

  void _onCurrentSongChanged(SongModel? song) {
    if (song != null) {
      mediaItem.add(_songToMediaItem(song));
      _updateMediaItemWithCover(song);
    }
    _emitPlaybackState();
  }

  void _updateMediaItemWithCover(SongModel song) async {
    final coverUrl = song.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) return;
    await AudioPlayerService.preFetchCover(coverUrl);
    final filePath = AudioPlayerService.coverFileUri(coverUrl);
    if (filePath != null) {
      mediaItem.add(_songToMediaItem(song, filePath: filePath));
    }
  }

  void _onPlaylistChanged(List<SongModel> playlist) {
    queue.add(playlist.map(_songToMediaItem).toList());
    _emitPlaybackState();
  }

  List<MediaControl> _buildControls() {
    final isFm = _service.isFmMode;
    final isPlaying = _service.isPlaying;

    final playPause = isPlaying ? MediaControl.pause : MediaControl.play;

    if (isFm) {
      return [playPause, MediaControl.skipToNext];
    }
    return [
      MediaControl.skipToPrevious,
      playPause,
      MediaControl.skipToNext,
    ];
  }

  AudioProcessingState _toAudioProcessingState(PlayerState state) {
    switch (state) {
      case PlayerState.idle:
        return AudioProcessingState.idle;
      case PlayerState.loading:
        return AudioProcessingState.buffering;
      case PlayerState.playing:
        return AudioProcessingState.ready;
      case PlayerState.paused:
        return AudioProcessingState.ready;
      case PlayerState.error:
        return AudioProcessingState.error;
    }
  }

  @override
  Future<void> play() => _service.resume();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> stop() async {
    await _service.clearPlaylist();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> skipToNext() => _service.playNext();

  @override
  Future<void> skipToPrevious() => _service.playPrevious();
}