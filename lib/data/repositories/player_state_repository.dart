import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// 播放器状态持久化：保存/恢复当前歌曲、播放列表、播放位置、循环模式等。
///
/// 冷启动时 PlayerProvider 从此处读取上次状态，恢复播放位置并准备就绪。
class PlayerStateRepository {
  static const _keyCurrentSong = 'player_current_song';
  static const _keyPlaylist = 'player_playlist';
  static const _keyCurrentIndex = 'player_current_index';
  static const _keyPosition = 'player_position';
  static const _keyLoopMode = 'player_loop_mode';
  static const _keyShuffleEnabled = 'player_shuffle_enabled';
  // 音量记忆：保存/恢复 app 音量（普通播放与 USB 独占 DAC 各一份）
  static const _keyVolume = 'player_volume';
  static const _keyDacVolume = 'player_dac_volume';

  /// 保存当前播放状态。
  Future<void> saveState({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required Duration position,
    required String loopMode,
    required bool shuffleEnabled,
    required double volume,
    required double dacVolume,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (currentSong != null) {
      await prefs.setString(_keyCurrentSong, jsonEncode(currentSong.toJson()));
    } else {
      await prefs.remove(_keyCurrentSong);
    }

    final jsonList = playlist.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_keyPlaylist, jsonList);
    await prefs.setInt(_keyCurrentIndex, currentIndex);
    await prefs.setInt(_keyPosition, position.inMilliseconds);
    await prefs.setString(_keyLoopMode, loopMode);
    await prefs.setBool(_keyShuffleEnabled, shuffleEnabled);
    await prefs.setDouble(_keyVolume, volume);
    await prefs.setDouble(_keyDacVolume, dacVolume);
  }

  /// 恢复上次的播放状态。
  Future<PlayerState?> restoreState() async {
    final prefs = await SharedPreferences.getInstance();

    final songJson = prefs.getString(_keyCurrentSong);
    if (songJson == null) return null;

    Song currentSong;
    try {
      currentSong = Song.fromJson(jsonDecode(songJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }

    final jsonList = prefs.getStringList(_keyPlaylist);
    final playlist = jsonList
        ?.map((str) {
          try {
            return Song.fromJson(jsonDecode(str) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();
    if (playlist == null || playlist.isEmpty) return null;

    final currentIndex = prefs.getInt(_keyCurrentIndex) ?? 0;
    final positionMs = prefs.getInt(_keyPosition) ?? 0;
    final loopMode = prefs.getString(_keyLoopMode) ?? 'off';
    final shuffleEnabled = prefs.getBool(_keyShuffleEnabled) ?? false;
    final volume = prefs.getDouble(_keyVolume) ?? 1.0;
    final dacVolume = prefs.getDouble(_keyDacVolume) ?? 0.1;

    return PlayerState(
      currentSong: currentSong,
      playlist: playlist,
      currentIndex: currentIndex.clamp(0, playlist.length - 1),
      position: Duration(milliseconds: positionMs),
      loopMode: loopMode,
      shuffleEnabled: shuffleEnabled,
      volume: volume,
      dacVolume: dacVolume,
    );
  }

  /// 清除保存的状态。
  Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentSong);
    await prefs.remove(_keyPlaylist);
    await prefs.remove(_keyCurrentIndex);
    await prefs.remove(_keyPosition);
    await prefs.remove(_keyLoopMode);
    await prefs.remove(_keyShuffleEnabled);
    await prefs.remove(_keyVolume);
    await prefs.remove(_keyDacVolume);
  }
}

class PlayerState {
  final Song currentSong;
  final List<Song> playlist;
  final int currentIndex;
  final Duration position;
  final String loopMode;
  final bool shuffleEnabled;
  final double volume;
  final double dacVolume;

  const PlayerState({
    required this.currentSong,
    required this.playlist,
    required this.currentIndex,
    required this.position,
    required this.loopMode,
    required this.shuffleEnabled,
    required this.volume,
    required this.dacVolume,
  });
}
