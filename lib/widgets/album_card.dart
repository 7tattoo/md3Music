import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/widgets/no_text_shadow.dart';
import '../data/models/album.dart';
import 'smart_artwork_image.dart';

/// 文字信息块的最小高度：单行标题 + 上下 padding。
/// 封面在高度不足时按这个值让位，保证文字永远不被挤掉。
const double _kInfoMinHeight = 40.0;

class AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback? onTap;

  const AlbumCard({
    super.key,
    required this.album,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: onTap,
          // 封面尺寸由卡片自己算，不用 Expanded。
          //
          // 原来是 Expanded：封面高度 = 卡高 - 文字块，宽度 = 卡宽，两者不相等，
          // 于是正方形的歌单封面被拉成竖矩形，BoxFit.cover 上下裁掉一截。
          // 方向反了——应该让封面决定高度，不是剩余空间决定封面。
          //
          // 用 LayoutBuilder 而不是 AspectRatio(1)，是因为 PinchableGridView 的
          // cell 高度由 childAspectRatio 固定，Pad 上捏合改列数时 cell 会变窄，
          // 硬取正方形会连文字块一起溢出。这里取「正方形」和「可用高度减文字块」
          // 里的较小值：够方就方，不够就让位，两种情况都不溢出。
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverSize = constraints.maxHeight.isFinite
                  ? math.min(
                      constraints.maxWidth,
                      constraints.maxHeight - _kInfoMinHeight,
                    )
                  : constraints.maxWidth;
              return Column(
                children: [
                  SizedBox(
                    width: constraints.maxWidth,
                    height: math.max(coverSize, 0),
                    child: SmartArtworkImage(
                      artworkUri: album.artworkUri,
                      size: double.infinity,
                      borderRadius: 0,
                    ),
                  ),
                  // 卡片整体是实色 Material，文字块那截看不到壁纸：去掉全局文字阴影
                  Expanded(
                    child: NoTextShadow(
                      child: _buildInfo(colorScheme, textTheme),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfo(ColorScheme colorScheme, TextTheme textTheme) {
    final hasArtist = album.artist.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // titleSmall 而不是 labelMedium：label 系是按钮和标签的角色，
              // 卡片标题该用 title 系。与 _DailySongCard、主题歌单卡、
              // SongListItem 统一到同一档。
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            // 无副标题（如热门歌单 artist 为空）时不渲染空行，避免文字下方留大片空白
            if (hasArtist) ...[
              const SizedBox(height: 2),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
