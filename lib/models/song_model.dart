import 'package:netease_music_api/netease_music_api.dart';

class SongModel {
  final String id;
  final String name;
  final String artist;
  final String album;
  final String? coverUrl;
  final int? duration;

  const SongModel({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    this.coverUrl,
    this.duration,
  });

  /// 从库的 Song 类型创建
  factory SongModel.fromNeteaseSong(Song song) {
    final artistNames = song.artists
            ?.map((a) => a.name ?? '')
            .where((n) => n.isNotEmpty)
            .join(' / ') ??
        '';

    return SongModel(
      id: song.id,
      name: song.name ?? '',
      artist: artistNames,
      album: song.album?.name ?? '',
      coverUrl: song.album?.picUrl,
      duration: song.duration,
    );
  }

  /// 从每日推荐接口的 Song2 类型创建
  factory SongModel.fromSong2(Song2 song) {
    final artistNames = song.ar
            ?.map((a) => a.name ?? '')
            .where((n) => n.isNotEmpty)
            .join(' / ') ??
        '';

    return SongModel(
      id: song.id,
      name: song.name ?? '',
      artist: artistNames,
      album: song.al.name ?? '',
      coverUrl: song.al.picUrl,
      duration: song.dt,
    );
  }

  /// 创建副本并覆盖字段
  SongModel copyWith({
    String? id,
    String? name,
    String? artist,
    String? album,
    String? coverUrl,
    int? duration,
  }) {
    return SongModel(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: duration ?? this.duration,
    );
  }

  /// 从原始 JSON 创建（兼容旧接口）
  factory SongModel.fromJson(Map<String, dynamic> json) {
    final artists = json['ar'] as List<dynamic>? ?? [];
    final artistNames = artists
        .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
        .join(' / ');

    return SongModel(
      id: (json['id'] as dynamic).toString(),
      name: json['name'] as String? ?? '',
      artist: artistNames,
      album: (json['al'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      coverUrl: (json['al'] as Map<String, dynamic>?)?['picUrl'] as String?,
      duration: json['dt'] as int?,
    );
  }

  String get durationText {
    if (duration == null) return '';
    final totalSeconds = duration! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'album': album,
      'coverUrl': coverUrl,
      'duration': duration,
    };
  }

  factory SongModel.fromStorage(Map<String, dynamic> json) {
    return SongModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      coverUrl: json['coverUrl'] as String?,
      duration: json['duration'] as int?,
    );
  }
}

class PlaylistModel {
  final String id;
  final String name;
  final String? coverUrl;
  final String? description;
  final int? trackCount;
  final String? creatorName;
  final int? playCount;

  const PlaylistModel({
    required this.id,
    required this.name,
    this.coverUrl,
    this.description,
    this.trackCount,
    this.creatorName,
    this.playCount,
  });

  factory PlaylistModel.fromNeteaseTopList(TopList topList) {
    return PlaylistModel(
      id: topList.id,
      name: topList.name ?? '',
      coverUrl: topList.coverImgUrl,
      description: topList.description,
      trackCount: topList.trackCount,
      playCount: topList.playCount,
    );
  }

  factory PlaylistModel.fromNeteasePlay(Play play) {
    return PlaylistModel(
      id: play.id,
      name: play.name ?? '',
      coverUrl: play.coverImgUrl,
      description: play.description,
      trackCount: play.trackCount,
      creatorName: play.creator?.nickname,
      playCount: play.playCount,
    );
  }
}