import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/remote/focus_highlight.dart';
import '../data/models/song.dart';
import '../modules/player/comments_view.dart';
import '../modules/player/mv_player_page.dart';
import '../providers/favorites_provider.dart';
import '../providers/local_favorites_provider.dart';
import '../providers/player_provider.dart';
import 'playing_spectrum_indicator.dart';
import 'smart_artwork_image.dart';

class SongListItem extends StatefulWidget {
  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onMoreTap;
  final bool showDuration;
  final bool forceFavorited;

  /// 多选模式：显示圆形复选框替代封面，点击切换选中而非播放。
  final bool isSelectMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;

  /// 遥控模式下「菜单键」回调覆盖。默认弹出更多菜单；
  /// 歌单/收藏/云音乐等页面可重定向为进入多选/管理模式。
  final VoidCallback? onContextMenuOverride;

  const SongListItem({
    super.key,
    required this.song,
    this.onTap,
    this.onMoreTap,
    this.showDuration = true,
    this.forceFavorited = false,
    this.isSelectMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectToggle,
    this.onContextMenuOverride,
  });

  @override
  State<SongListItem> createState() => _SongListItemState();
}

class _SongListItemState extends State<SongListItem> {
  /// 整行 InkWell 的焦点节点：`canRequestFocus: false` 禁用其自身焦点，
  /// 焦点收归外层 RemoteFocusHighlight（提供聚焦视觉 + 菜单键），
  /// 避免与整行 wrapper 双重触发；同时 `descendantsAreFocusable: true`
  /// 保留行内图标的独立焦点。
  final FocusNode _rowFocusNode = FocusNode()
    ..debugLabel = 'song_list_item_row'
    ..canRequestFocus = false;

  Song get song => widget.song;

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(song.displayName),
              subtitle: Text(song.artist),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('下一首播放'),
              onTap: () {
                Navigator.pop(ctx);
                final player = context.read<PlayerProvider>();
                player.insertAfterCurrent([song]);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已加入下一首'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.comment_outlined),
              title: const Text('看评论'),
              onTap: () {
                Navigator.pop(ctx);
                showSongCommentsSheet(context, song);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 遥控模式菜单键回调：优先用页面覆盖，多选模式切选中，否则弹更多菜单。
  VoidCallback? _buildContextMenuAction(BuildContext context) {
    if (widget.onContextMenuOverride != null) {
      return widget.onContextMenuOverride;
    }
    if (widget.isSelectMode) {
      return widget.onSelectToggle;
    }
    return () => _showMoreMenu(context);
  }

  @override
  void dispose() {
    _rowFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 关键：用 context.select 只订阅本条目关心的字段，避免在播放进度等
    // 高频 notifyListeners（PlayerProvider 每次 position 更新都会通知）下
    // 整行重建——大量可见行同时重建会导致滚动空白、停一下才显示。
    final isCurrentSong = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.id == song.id,
    );
    final isPlaying =
        context.select<PlayerProvider, bool>((p) => p.isPlaying);
    final isFavorited = widget.forceFavorited
        ? true
        : song.isOnline
            ? context.select<FavoritesProvider, bool>(
                (f) => f.isFavorite(song.id),
              )
            : context.select<LocalFavoritesProvider, bool>(
                (f) => f.isFavorite(song.id),
              );
    // 操作回调用 read，不建立订阅（避免跟随进度刷新）
    final favoritesProvider = context.read<FavoritesProvider>();
    final localFavoritesProvider = context.read<LocalFavoritesProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    const imgSize = 52.0; // 正方形封面，不被 ListTile 压缩

    final VoidCallback? rowTap =
        widget.isSelectMode ? widget.onSelectToggle : widget.onTap;
    final VoidCallback? contextMenuAction = _buildContextMenuAction(context);

    final rowBody = InkWell(
      focusNode: _rowFocusNode,
      onTap: rowTap,
      onLongPress: widget.onLongPress,
      child: Container(
        color: widget.isSelectMode && widget.isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            // 多选模式：圆形复选框；普通模式：封面图
            if (widget.isSelectMode)
              _buildCheckbox(colorScheme, imgSize)
            else
              // 封面图：智能选择 Image.network（在线/content://）或 LocalArtworkImage（文件路径）
              SmartArtworkImage(
                artworkUri: song.artworkUri,
                fallbackFilePath: song.localPath,
                size: imgSize,
                borderRadius: 8,
              ),
            const SizedBox(width: 12),

            // 标题 + 副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isCurrentSong ? colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.artist} - ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: isCurrentSong
                          ? colorScheme.primary.withValues(alpha: 0.7)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // 右侧操作区：多选模式下不显示
            if (!widget.isSelectMode)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (isCurrentSong)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      // 频谱动画标识：3 根粒度柱 sin 波动
                      // 暂停时 isPlaying=false → ticker 停止，保留最后一帧
                      // 继续播放时 isPlaying=true → ticker 恢复，动画继续
                      child: PlayingSpectrumIndicator(
                        color: colorScheme.primary,
                        size: 14,
                        isPlaying: isPlaying,
                      ),
                    ),
                  if (widget.showDuration)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(song.displayDuration, style: textTheme.labelSmall),
                    ),
                  // 收藏
                  RemoteFocusHighlight(
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    scale: 1.2,
                    onTap: () => song.isOnline
                        ? favoritesProvider.toggleFavorite(song)
                        : localFavoritesProvider.toggleFavorite(song.id),
                    onContextMenu: contextMenuAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                      child: Icon(
                        isFavorited ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: isFavorited ? colorScheme.error : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // MV（仅在线歌曲）
                  if (song.isOnline)
                    RemoteFocusHighlight(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      scale: 1.2,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => MvPlayerPage(song: song)),
                      ),
                      onContextMenu: contextMenuAction,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        child: Icon(Icons.music_video_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  // 更多
                  RemoteFocusHighlight(
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    scale: 1.2,
                    onTap: () => _showMoreMenu(context),
                    onContextMenu: contextMenuAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      child: Icon(Icons.more_vert, size: 18, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );

    // 遥控模式：整行提供单一焦点入口 + 菜单键。
    // descendantsAreFocusable: true 保留行内图标的独立焦点；
    // InkWell 自身焦点已通过 _rowFocusNode.canRequestFocus = false 禁用。
    return RemoteFocusHighlight(
      scale: 1.0,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      descendantsAreFocusable: true,
      onTap: rowTap,
      onContextMenu: contextMenuAction,
      child: rowBody,
    );
  }

  /// 多选模式下的圆形复选框，与封面同等大小。
  Widget _buildCheckbox(ColorScheme colorScheme, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: widget.isSelected
            ? Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary,
                ),
                child: Icon(
                  Icons.check,
                  color: colorScheme.onPrimary,
                  size: 28,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
              ),
      ),
    );
  }
}
