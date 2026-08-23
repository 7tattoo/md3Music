import 'dart:io';

import 'package:flutter/material.dart';

import 'local_artwork_image.dart';

/// 智能封面图组件：根据 artworkUri 类型选择不同的加载策略。
///
/// 支持：
/// - **http(s)://** 在线封面：使用 [Image.network]，加载失败时回退 fallbackFilePath / 占位符
/// - **content://** MediaStore 封面：通过 fallbackFilePath 读内嵌封面
/// - **local://<filePath>** 本地文件：使用 [LocalArtworkCache] 懒加载
/// - **null** 或未知：显示占位符
///
/// [size] 为 `double.infinity` 时由所在 cell（网格）决定尺寸。
class SmartArtworkImage extends StatefulWidget {
  final String? artworkUri;
  final String? fallbackFilePath;
  final double size;
  final double borderRadius;

  /// 歌曲 ID（保留参数以兼容调用方；公开库无流缓存兜底）。
  final String? songId;

  const SmartArtworkImage({
    super.key,
    this.artworkUri,
    this.fallbackFilePath,
    required this.size,
    this.borderRadius = 8,
    this.songId,
  });

  @override
  State<SmartArtworkImage> createState() => _SmartArtworkImageState();
}

class _SmartArtworkImageState extends State<SmartArtworkImage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final uri = widget.artworkUri;
    final size = widget.size;
    final radius = widget.borderRadius;

    Widget child;
    if (uri == null) {
      // URI 为空：尝试用 fallbackFilePath 读内嵌封面，否则显示占位符
      if (widget.fallbackFilePath != null) {
        child = LocalArtworkImage(
          filePath: widget.fallbackFilePath!,
          size: widget.size,
          borderRadius: widget.borderRadius,
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        );
      } else {
        child = _placeholder(colorScheme);
      }
    } else if (uri.startsWith('local://')) {
      // local:// 占位符：从文件路径读取内嵌封面
      final filePath = uri.substring('local://'.length);
      child = LocalArtworkImage(
        filePath: filePath,
        size: widget.size,
        borderRadius: widget.borderRadius,
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      );
    } else if (uri.startsWith('content://')) {
      // content:// URI 无法被 Image.network 加载（非 HTTP 协议），
      // 直接用 fallbackFilePath 走 LocalArtworkImage 懒加载内嵌封面
      if (widget.fallbackFilePath != null) {
        child = LocalArtworkImage(
          filePath: widget.fallbackFilePath!,
          size: widget.size,
          borderRadius: widget.borderRadius,
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        );
      }
      child = _placeholder(colorScheme);
    } else if (uri.startsWith('http://') ||
        uri.startsWith('https://')) {
      // http(s):// 在线封面用 Image.network
      final isFill = widget.size == double.infinity;
      child = Image.network(
        uri,
        width: isFill ? double.infinity : size,
        height: isFill ? double.infinity : size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          if (widget.fallbackFilePath != null) {
            return LocalArtworkImage(
              filePath: widget.fallbackFilePath!,
              size: widget.size,
              borderRadius: widget.borderRadius,
            );
          }
          return _placeholder(colorScheme);
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: isFill ? double.infinity : size,
            height: isFill ? double.infinity : size,
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.hourglass_empty,
              size: isFill ? 40 : size * 0.4,
              color: colorScheme.onSurfaceVariant,
            ),
          );
        },
      );
    } else if (uri.startsWith('file://')) {
      // file:// 本地文件（云盘提取的内嵌封面等）
      final isFill = widget.size == double.infinity;
      final file = File.fromUri(Uri.parse(uri));
      if (file.existsSync()) {
        child = Image.file(
          file,
          width: isFill ? double.infinity : size,
          height: isFill ? double.infinity : size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(colorScheme),
        );
      } else {
        child = _placeholder(colorScheme);
      }
    } else {
      // 兜底：当作普通 URL 处理
      child = Image.network(
        uri,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(colorScheme),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }

  Widget _placeholder(ColorScheme colorScheme) {
    final size = widget.size;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(
          widget.borderRadius,
        ),
      ),
      child: Icon(
        Icons.music_note,
        size: size * 0.4,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
