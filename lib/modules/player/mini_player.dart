import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/desktop_lyric_service.dart';
import '../../core/services/media_notification_service.dart';
import '../../providers/player_provider.dart';
import 'full_player_route.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.watch<PlayerProvider>();
    final currentSong = playerProvider.currentSong;

    if (currentSong == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final duration = playerProvider.duration ?? Duration.zero;
    final position = playerProvider.position;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: () {
        // 使用 BottomSlideMaterialPageRoute（MaterialPageRoute 子类）：
        // - 继承 MaterialPageRoute 保留与系统预测返回手势的对接
        // - 重写 buildTransitions 用 animation 驱动 SlideTransition
        //   push 时从底部滑入，预测返回时系统驱动 animation 反向播放，
        //   页面自然跟随手势向下平移（而非默认的整页缩小）
        // fullPlayerRoute 根据 ThemeProvider.useAmStylePlayer 开关
        // 选择 AM 风格或原版 MD3 风格 FullPlayer widget
        Navigator.of(context).push(fullPlayerRoute(context));
      },
      child: Container(
        // Container 在外提供整体背景色与顶部 border：
        // 颜色会自然填充 SafeArea 在底部留出的系统手势条区域，
        // 避免手势条区域露出 Scaffold 背景色与主体形成颜色断层
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
          ),
        ),
        child: SafeArea(
          // 仅吸收底部系统手势条/Home Indicator 高度
          top: false,
          bottom: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 2,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: currentSong.artworkUri != null
                            ? CachedNetworkImage(
                                imageUrl: currentSong.artworkUri!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.music_note,
                                    size: 20,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                errorWidget: (_, _, _) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.music_note,
                                    size: 20,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.music_note,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentSong.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            currentSong.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        playerProvider.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      onPressed: () {
                        if (playerProvider.isPlaying) {
                          playerProvider.pause();
                        } else {
                          playerProvider.resume();
                        }
                      },
                    ),
                    IconButton(
                      tooltip: DesktopLyricService.instance.enabled
                          ? '关闭桌面歌词'
                          : '开启桌面歌词',
                      icon: Icon(
                        DesktopLyricService.instance.enabled
                            ? Icons.lyrics
                            : Icons.lyrics_outlined,
                        color: DesktopLyricService.instance.enabled
                            ? colorScheme.primary
                            : null,
                      ),
                      onPressed: () async {
                        await DesktopLyricService.instance.toggle();
                        if (context.mounted) {
                          (context as Element).markNeedsBuild();
                          // 同步通知栏"桌面歌词"按钮状态
                          final player = context.read<PlayerProvider>();
                          final song = player.currentSong;
                          await MediaNotificationService.updateNotification(
                            title: song?.title ?? '',
                            artist: song?.artist ?? '',
                            artUrl: song?.artworkUri,
                            isPlaying: player.isPlaying,
                            position: player.position,
                            duration: player.duration ?? Duration.zero,
                            desktopLyricEnabled:
                                DesktopLyricService.instance.enabled,
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: () {
                        playerProvider.next();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ), // SafeArea
      ), // Container
    );
  }
}
