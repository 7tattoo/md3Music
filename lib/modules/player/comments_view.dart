import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../../providers/kugou_provider.dart';
import '../../services/kugou_api/kugou_models.dart';

/// 评论列表视图。
///
/// 在 FullPlayer 中作为 TabBarView 第三个 Tab 展示，背景为模糊封面 + 黑蒙版。
/// 由于背景永远是深色封面图，原 MD3 主题的黑色文字几乎不可见。
///
/// **智能反色**：通过 [PaletteGenerator] 从当前封面提取主色（dominantColor），
/// 根据主色亮度（[Color.computeLuminance]）决定文字颜色：
/// - 主色亮度 < 0.5（暗色封面）→ 文字反色为白色
/// - 主色亮度 >= 0.5（亮色封面）→ 文字反色为黑色
/// - 无封面或提取失败 → 默认白色（FullPlayer 背景为黑+黑蒙版）
///
/// 辅助文字（用户名、时间）在反色基础上加 70% 透明度。
///
/// **mask alpha 渐变**：列表顶部/底部各 24px 范围用 ShaderMask + BlendMode.dstIn
/// 实现 alpha 渐变（比歌词页更窄），让滚动内容从背景柔和淡入、淡出到背景，
/// 避免列表硬切边。
class CommentsView extends StatefulWidget {
  final String songHash;
  final String? albumAudioId;

  /// 封面 URL，用于提取主色驱动智能反色。
  final String? artworkUri;

  const CommentsView({
    super.key,
    required this.songHash,
    this.albumAudioId,
    this.artworkUri,
  });

  @override
  State<CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<CommentsView> {
  List<KugouComment> _comments = [];
  bool _isLoading = false;
  String? _error;

  /// 智能反色后的主文字颜色（评论正文）。
  /// null 表示尚未确定（首帧先用白色兜底，避免黑底黑字）。
  Color _primaryTextColor = Colors.white;

  /// 智能反色后的辅助文字颜色（用户名、时间戳）。
  Color _secondaryTextColor = const Color(0xB3FFFFFF); // 70% 透明白

  @override
  void initState() {
    super.initState();
    _updatePalette();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchComments();
    });
  }

  @override
  void didUpdateWidget(covariant CommentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songHash != widget.songHash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchComments();
      });
    }
    // 封面切换时重新提取主色
    if (oldWidget.artworkUri != widget.artworkUri) {
      _updatePalette();
    }
  }

  /// 从封面提取主色并设置反色后的文字颜色。
  ///
  /// 使用 [PaletteGenerator.fromImageProvider] 异步提取 dominantColor，
  /// 根据亮度选择黑/白反色。失败时降级为白色（适配 FullPlayer 深色背景）。
  Future<void> _updatePalette() async {
    final uri = widget.artworkUri;
    if (uri == null || uri.isEmpty) {
      _applyPalette(null);
      return;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(uri),
        maximumColorCount: 16,
      );
      if (!mounted) return;
      _applyPalette(palette.dominantColor?.color);
    } catch (_) {
      if (!mounted) return;
      _applyPalette(null);
    }
  }

  /// 根据主色亮度应用反色文字。
  ///
  /// - `artworkUri == null`（原版 MD3 FullPlayer 调用，未传封面 URL）：
  ///   背景是 colorScheme.surface，跟随主题色，主文字用 onSurface、辅助文字用 onSurfaceVariant。
  /// - `artworkUri != null`（AM 风格 FullPlayer 调用，传入封面 URL）：启用智能反色
  ///   - 主色为 null：默认白色（适配 AM 黑色模糊封面背景）
  ///   - 主色亮度 < 0.5：暗背景 → 文字反色为白色
  ///   - 主色亮度 >= 0.5：亮背景 → 文字反色为黑色
  /// 辅助文字 = 主文字颜色 × 70% 透明度（仅 AM 风格分支，用户原话："黑色加上70%灰色"）。
  void _applyPalette(Color? dominant) {
    // 原版 MD3 风格：未传 artworkUri，背景是 surface，跟随主题色
    if (widget.artworkUri == null) {
      final colorScheme = Theme.of(context).colorScheme;
      setState(() {
        _primaryTextColor = colorScheme.onSurface;
        _secondaryTextColor = colorScheme.onSurfaceVariant;
      });
      return;
    }
    // AM 风格：智能反色，根据封面主色亮度决定黑/白
    final bool isDarkBg =
        dominant == null ? true : dominant.computeLuminance() < 0.5;
    final Color base = isDarkBg ? Colors.white : Colors.black;
    setState(() {
      _primaryTextColor = base;
      _secondaryTextColor = base.withValues(alpha: 0.7);
    });
  }

  Future<void> _fetchComments() async {
    if (widget.songHash.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final kugouProvider = context.read<KugouProvider>();
    await kugouProvider.getComments(widget.songHash,
        albumAudioId: widget.albumAudioId);

    if (mounted) {
      setState(() {
        _isLoading = false;
        final commentList = kugouProvider.comments;
        if (commentList != null && commentList.comments.isNotEmpty) {
          _comments = commentList.comments;
        } else {
          _comments = [];
        }
        _error = kugouProvider.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: _primaryTextColor),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: _secondaryTextColor,
              ),
              const SizedBox(height: 12),
              Text(
                '加载评论失败',
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _fetchComments,
                style: TextButton.styleFrom(foregroundColor: _primaryTextColor),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.comment_outlined,
              size: 48,
              color: _secondaryTextColor,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无评论',
              style: TextStyle(color: _secondaryTextColor, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // 用 ShaderMask + BlendMode.dstIn 实现上下 alpha 渐变：
    // 顶部 24px alpha 0→1，底部 24px alpha 1→0，
    // 比 lyrics 视图更窄，让评论从背景柔和淡入、淡出到背景。
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        const double fadeHeight = 24.0;
        final double fadeRatio = (fadeHeight / bounds.height).clamp(0.0, 0.5);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [
            0.0,
            fadeRatio,
            1.0 - fadeRatio,
            1.0,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _comments.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: _secondaryTextColor.withValues(alpha: 0.2),
        ),
        itemBuilder: (context, index) {
          final comment = _comments[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _secondaryTextColor.withValues(alpha: 0.2),
                  child: Text(
                    comment.username.isNotEmpty ? comment.username[0] : '?',
                    style: TextStyle(
                      color: _primaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            comment.username,
                            style: TextStyle(
                              color: _secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatTime(comment.time),
                            style: TextStyle(
                              color: _secondaryTextColor
                                  .withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment.content,
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}月${date.day}日';
  }
}
