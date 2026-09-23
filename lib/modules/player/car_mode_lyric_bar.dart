// 车机模式底部面板「紧凑歌词条」（底部面板 10%~25% 高度档的新布局）。
//
// 用户场景（2026-09-23）：竖屏/方屏车机把底部面板压到 10%~25% 时，旧细条
// （_CarModeDockBar）封面小、控件挤在右侧、右半区大量留白。新布局：
//
//   [ 大封面 ] [ 歌名/歌手（上） + 传输键（下） ] [ 当前行 + 下一行歌词 ]
//
//   * 传输键从右侧移到歌名/歌手下方，文字上提消除竖向空白；
//   * 封面调大到与右侧内容块对齐（上限 132dp，避免大高度下面板被封面塞满）；
//   * 右侧旧控件位置让给歌词：默认「当前行 + 下一行」两行；当前行单行放不下
//     时（会换行）只显示当前行（最多两行）。
//
// 高度仍不足（<80dp：更矮的屏上 10% 被 56dp 物理下限托底）时由调用方
// （car_mode_panel.dart）回退旧细条 _CarModeDockBar，本组件不处理。
//
// 歌词管线与 DesktopLyricService 同源：本地内嵌歌词（LocalLyricLoader）→
// KugouProvider（在线/搜索兜底）→ parseLyricOffMainThread 解析成统一
// LyricLine，二分定位当前行；positionNotifier（~200ms）驱动滚动定位。
// 面板独立维护歌词状态，不依赖桌面歌词/锁屏歌词开关。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/desktop_lyric_service.dart'
    show parseLyricOffMainThread;
import '../../core/utils/local_lyric_loader.dart';
import '../../data/models/song.dart';
import '../../providers/kugou_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/apple_lyrics/models/lyric_line.dart';
import '../../widgets/smart_artwork_image.dart';
import 'full_player_route.dart';

/// 紧凑歌词条：底部面板 10%~25% 高度档的新布局（见文件头注释）。
class CarModeLyricBar extends StatefulWidget {
  const CarModeLyricBar({super.key, required this.height});

  /// 面板内容高度（已扣除 dock 避让区），调用方保证 >= 80。
  final double height;

  @override
  State<CarModeLyricBar> createState() => _CarModeLyricBarState();
}

class _CarModeLyricBarState extends State<CarModeLyricBar> {
  KugouProvider? _kugou;
  PlayerProvider? _player;

  List<LyricLine> _lines = const [];
  int _fetchToken = 0;
  String _loadedLyricKey = '';

  @override
  void initState() {
    super.initState();
    _player = context.read<PlayerProvider>();
    _player!.addListener(_onPlayerChanged);
    _kugou = context.read<KugouProvider>();
    _loadLyricFor(_player!.currentSong);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Provider 可能在依赖树变化后重建：保持引用最新并补一次切歌检测。
    final player = context.read<PlayerProvider>();
    if (!identical(player, _player)) {
      _player?.removeListener(_onPlayerChanged);
      _player = player..addListener(_onPlayerChanged);
      _loadLyricFor(player.currentSong);
    }
    final kugou = context.read<KugouProvider>();
    if (!identical(kugou, _kugou)) _kugou = kugou;
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayerChanged);
    _fetchToken++; // 使在途解析结果作废
    super.dispose();
  }

  void _onPlayerChanged() {
    final song = _player?.currentSong;
    final key = _lyricKeyOf(song);
    if (key == _loadedLyricKey) return;
    _loadLyricFor(song);
  }

  String _lyricKeyOf(Song? song) {
    if (song == null) return '';
    return '${song.id}|${song.title}|${song.artist}';
  }

  Future<void> _loadLyricFor(Song? song) async {
    final token = ++_fetchToken;
    final key = _lyricKeyOf(song);
    _loadedLyricKey = key;
    if (song == null || key.isEmpty) {
      if (mounted && token == _fetchToken) setState(() => _lines = const []);
      return;
    }
    try {
      String? text;
      String? translation;
      // 1) 本地歌曲：优先读内嵌歌词
      if (!song.isOnline) {
        var path = song.localPath;
        if (path != null && path.isNotEmpty) {
          if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
          final embedded = await LocalLyricLoader.loadForAudioAsync(path);
          if (embedded != null && embedded.isNotEmpty) text = embedded;
        }
      }
      // 2) 酷狗（在线 hash / 搜索兜底）
      if (text == null) {
        final searchName = song.artist != '未知艺术家'
            ? '${song.title} ${song.artist}'
            : song.title;
        final lyric = await _kugou?.getLyric(
          song.isOnline ? song.id : '',
          songName: searchName,
          fmt: 'lrc',
        );
        text = lyric?.displayLyric;
        translation = lyric?.translatedContent;
      }
      if (text == null || text.isEmpty) {
        if (mounted && token == _fetchToken) setState(() => _lines = const []);
        return;
      }
      final lines = await parseLyricOffMainThread(
        text,
        translationText: translation,
      );
      // isolate 解析期间可能已切歌/面板已销毁：迟到结果丢弃
      if (!mounted || token != _fetchToken) return;
      if (_lyricKeyOf(_player?.currentSong) != key) return;
      setState(() => _lines = lines);
    } catch (_) {
      if (mounted && token == _fetchToken) setState(() => _lines = const []);
    }
  }

  // —— 行定位 ——
  // 二分查找 _findLineIndex 定义在 _LyricPane（唯一消费方）。

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;
    final colorScheme = Theme.of(context).colorScheme;

    final transport = _TransportControls(
      player: player,
      tight: widget.height < 96,
    );

    // 窄容器自适应：宽屏车机封面/文字列放大，手机竖屏（若手动开车机模式）
    // 按比例收缩，保证右侧歌词条 Expanded 至少 ~110dp 不被挤没。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final artSize = math.min(
          math.min(widget.height - 12.0, width * 0.22),
          132.0,
        );
        final textColumnWidth = (math.min(
          240.0,
          width * 0.30,
        )).clamp(120.0, 240.0);
        // 紧凑档：面板高 <96dp（10% 档小屏）时压掉垂直余量，防两行文字 +
        // 传输键在 1.1x 文字缩放下溢出（86dp: 22+18+1+2+32+8 ≈ 83 < 86 ✓）。
        final tight = widget.height < 96;

        return Material(
          color: colorScheme.surface,
          child: InkWell(
            onTap: song == null ? null : () => openFullPlayer(context),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: tight ? 4 : 6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // —— 左：大封面 ——
                  SizedBox(
                    width: artSize,
                    height: artSize,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: song == null
                          ? ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                            )
                          : SmartArtworkImage(
                              artworkUri: song.artworkUri,
                              size: artSize,
                              borderRadius: 12,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // —— 中：歌名/歌手 + 传输键（控件移到文字下方） ——
                  SizedBox(
                    width: textColumnWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song?.displayName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (song != null &&
                            song.artist.isNotEmpty &&
                            song.artist != '未知艺术家') ...[
                          const SizedBox(height: 1),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                        // 歌名/歌手上提后传输键紧跟其下，不留多余空白。
                        const SizedBox(height: 2),
                        transport,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // —— 右：歌词（当前行 + 下一行） ——
                  Expanded(
                    child: _LyricPane(
                      lines: _lines,
                      player: player,
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 紧凑档传输键：36x36 触控区 + 22dp 图标（旧细条 44dp 键在 86dp 面板里
/// 与两行文字叠加放不下，压缩一档）。
class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.player, this.tight = false});

  final PlayerProvider player;

  /// 紧凑档（面板高 <96dp）：触控高 32dp，防垂直溢出。
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final playing = player.isPlaying;
    final hasSong = player.currentSong != null;
    final color = Theme.of(context).colorScheme.onSurface;

    IconData centerIcon;
    VoidCallback? centerTap;
    if (!hasSong) {
      centerIcon = Icons.play_arrow_rounded;
    } else if (playing) {
      centerIcon = Icons.pause_rounded;
      centerTap = player.pause;
    } else {
      centerIcon = Icons.play_arrow_rounded;
      centerTap = player.resume;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _key(
          icon: Icons.skip_previous_rounded,
          onTap: hasSong ? player.previous : null,
          color: color,
        ),
        _key(icon: centerIcon, onTap: centerTap, color: color),
        _key(
          icon: Icons.skip_next_rounded,
          onTap: hasSong ? player.next : null,
          color: color,
        ),
      ],
    );
  }

  Widget _key({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      color: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: 38, height: tight ? 32 : 34),
    );
  }
}

/// 右侧歌词：默认「当前行 + 下一行」；当前行单行放不下时只显示当前行
/// （最多两行后省略）。空态/加载态显示占位符。
class _LyricPane extends StatelessWidget {
  const _LyricPane({
    required this.lines,
    required this.player,
    required this.colorScheme,
  });

  final List<LyricLine> lines;
  final PlayerProvider player;
  final ColorScheme colorScheme;

  // —— 行定位（与 DesktopLyricService._findLineIndex 同法） ——

  /// 二分定位：最后一个 startTime <= posMs 的行；无命中返回 -1。
  static int _findLineIndex(List<LyricLine> lines, int posMs) {
    int lo = 0;
    int hi = lines.length - 1;
    int idx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].startTime <= posMs) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return idx;
  }

  bool _currentLineOverflows(String text, double maxWidth, TextStyle style) {
    if (text.isEmpty || maxWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '♪',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurfaceVariant.withAlpha(120)),
        ),
      );
    }

    final currentStyle =
        Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ) ??
        TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface);
    final nextStyle =
        Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: colorScheme.onSurfaceVariant.withAlpha(200)) ??
        TextStyle(color: colorScheme.onSurfaceVariant);

    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (context, position, _) {
        final posMs = position.inMilliseconds;
        final idx = _findLineIndex(lines, posMs);
        final current = idx >= 0 ? lines[idx].text.trim() : '';
        final next = idx >= 0 && idx + 1 < lines.length
            ? lines[idx + 1].text.trim()
            : '';
        if (current.isEmpty) {
          // 间奏期：显示下一行（淡色），不显示空行占位。
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              next,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: nextStyle,
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final showNext = !_currentLineOverflows(
              current,
              constraints.maxWidth,
              currentStyle,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  current,
                  maxLines: showNext ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: currentStyle,
                ),
                if (showNext && next.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    next,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nextStyle,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
