import 'package:flutter/material.dart';

import '../core/utils/ui_scale.dart';
import '../data/models/artist.dart';
import 'smart_artwork_image.dart';

class ArtistTile extends StatelessWidget {
  final Artist artist;
  final VoidCallback? onTap;

  const ArtistTile({
    super.key,
    required this.artist,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      // 外框与封面同步缩放，否则放大后的封面会被 SizedBox 裁掉
      leading: SizedBox(
        width: context.scaledSize(48),
        height: context.scaledSize(48),
        child: SmartArtworkImage(
          artworkUri: artist.artworkUri,
          size: 48,
          borderRadius: 24,
        ),
      ),
      title: Text(
        artist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${artist.songCount} 首歌曲 · ${artist.albumCount} 张专辑',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
      onTap: onTap,
    );
  }
}
