import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/layout/responsive_layout.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/kugou_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/downloads_provider.dart';
import '../../services/kugou_api/kugou_api_client.dart';
import '../../services/kugou_api/kugou_models.dart';
import 'comments_view.dart';
import 'lyrics_view.dart';
import '../../utils/landscape_immersive.dart';
import '../../widgets/player_playlist_dialog.dart';

const List<AudioQuality> _audioQualities = [
  AudioQuality.standard,
  AudioQuality.high,
  AudioQuality.flac,
];

class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final GlobalKey<LyricsViewState> _lyricsKey = GlobalKey<LyricsViewState>();
  String _lyrics = '';
  bool _isLoadingLyrics = false;
  String? _lastSongId;

  // Pad 模式：左侧已有封面，隐藏"封面"Tab，只保留 2 个 Tab
  bool _isPadMode = false;
  int _currentTabLength = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    // 进入播放器时根据当前方向应用沉浸模式
    applyImmersiveForOrientation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPadMode();
      final song = context.read<PlayerProvider>().currentSong;
      if (song != null) {
        _fetchLyrics(song);
      }
      context.read<PlayerProvider>().addListener(_onPlayerSongChanged);
    });
  }

  /// 检测是否为 Pad 模式（宽度 >= 600），并动态调整 TabController
  void _checkPadMode() {
    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    final shouldBePadMode = width >= 600;
    final newTabLength = shouldBePadMode ? 2 : 3;

    if (_currentTabLength != newTabLength) {
      final currentIndex = _tabController.index.clamp(0, newTabLength - 1);
      _tabController.dispose();
      _currentTabLength = newTabLength;
      _tabController = TabController(
        length: newTabLength,
        vsync: this,
        initialIndex: shouldBePadMode && currentIndex == 0 ? 0 : currentIndex,
      );
      _isPadMode = shouldBePadMode;
      setState(() {});
    } else {
      _isPadMode = shouldBePadMode;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPadMode();
  }

  @override
  void didChangeMetrics() {
    // 用户旋转设备时重新应用沉浸模式
    applyImmersiveForOrientation();
  }

  void _onPlayerSongChanged() {
    if (!mounted) return;
    final song = context.read<PlayerProvider>().currentSong;
    if (song != null && song.id != _lastSongId) {
      _fetchLyrics(song);
    }
  }

  @override
  void didUpdateWidget(covariant FullPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final song = context.read<PlayerProvider>().currentSong;
    if (song != null && song.id != _lastSongId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchLyrics(song);
      });
    }
  }

  @override
  void dispose() {
    try {
      context.read<PlayerProvider>().removeListener(_onPlayerSongChanged);
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    // 退出播放器时恢复系统栏显示
    restoreSystemUi();
    super.dispose();
  }

  Future<void> _fetchLyrics(dynamic song) async {
    final songId = song.id as String;
    if (songId == _lastSongId) return;
    _lastSongId = songId;

    setState(() {
      _isLoadingLyrics = true;
      _lyrics = '';
    });

    try {
      final kugouProvider = context.read<KugouProvider>();
      await kugouProvider.getLyric(songId, songName: song.title);

      if (mounted) {
        setState(() {
          _isLoadingLyrics = false;
          final lyric = kugouProvider.lyric;
          _lyrics = lyric?.displayLyric ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLyrics = false;
          _lyrics = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = context.watch<PlayerProvider>();
    final currentSong = playerProvider.currentSong;
    final colorScheme = Theme.of(context).colorScheme;

    if (currentSong == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('暂无播放')),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: ResponsiveLayout(
        compact: (_) =>
            _buildCompactLayout(playerProvider, currentSong, colorScheme),
        medium: (_) =>
            _buildLandscapeLayout(playerProvider, currentSong, colorScheme),
        expanded: (_) =>
            _buildExpandedLayout(playerProvider, currentSong, colorScheme),
      ),
    );
  }

  Widget _buildCompactLayout(
    PlayerProvider playerProvider,
    dynamic currentSong,
    ColorScheme colorScheme,
  ) {
    // 竖屏 edgeToEdge 模式：保持默认 padding
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                GestureDetector(
                  onTap: () => _tabController.animateTo(1),
                  behavior: HitTestBehavior.opaque,
                  child: _buildArtworkView(
                    playerProvider,
                    currentSong,
                    colorScheme,
                    isExpanded: true,
                  ),
                ),
                GestureDetector(
                  onTap: () => _tabController.animateTo(0),
                  behavior: HitTestBehavior.translucent,
                  child: _isLoadingLyrics
                      ? const Center(child: CircularProgressIndicator())
                      : LyricsView(
                          key: _lyricsKey,
                          lyrics: _lyrics,
                          position: playerProvider.position,
                          onSeek: (position) {
                            playerProvider.seek(position);
                          },
                        ),
                ),
                CommentsView(
                  songHash: currentSong.id,
                  albumAudioId: currentSong.albumAudioId,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildControls(playerProvider, colorScheme),
          ),
        ],
      ),
    );
  }

  /// 手机横屏 / 小尺寸宽屏布局：左侧封面，右侧信息+歌词/评论+控制栏
  Widget _buildLandscapeLayout(
    PlayerProvider playerProvider,
    dynamic currentSong,
    ColorScheme colorScheme,
  ) {
    // 横屏/竖屏 edgeToEdge 模式：保持默认 padding
    return SafeArea(
      bottom: false,
      child: Row(
        children: [
          // ── 左侧：封面 + 歌曲信息 ──
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 横屏时封面最大不超过可用宽度，保持正方形
                  final size = constraints.maxWidth.clamp(120.0, 300.0);
                  return Stack(
                    children: [
                      // 封面居中
                      Center(
                        child: SizedBox(
                          width: size,
                          height: size,
                          child: AnimatedScale(
                            scale: playerProvider.isPlaying ? 1.0 : 0.85,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutBack,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: currentSong.artworkUri != null
                                  ? CachedNetworkImage(
                                      imageUrl: currentSong.artworkUri!,
                                      fit: BoxFit.cover,
                                      placeholder: (_, _) => Container(
                                        color: colorScheme.surfaceContainerHighest,
                                        child: Icon(Icons.music_note,
                                          size: 48, color: colorScheme.onSurfaceVariant),
                                      ),
                                      errorWidget: (_, _, _) => Container(
                                        color: colorScheme.surfaceContainerHighest,
                                        child: Icon(Icons.music_note,
                                          size: 48, color: colorScheme.onSurfaceVariant),
                                      ),
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(Icons.music_note,
                                        size: 48, color: colorScheme.onSurfaceVariant),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      // 歌曲信息：垂直方向 80% 位置，水平居中
                      Positioned(
                        top: constraints.maxHeight * 0.8,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            Text(
                              currentSong.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentSong.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              currentSong.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // ── 右侧：TopBar + Tab + 内容 + 控制 ──
          Expanded(
            flex: 6,
            child: Column(
              children: [
                _buildTopBar(),

                // 内容区（歌词 / 评论，Pad 模式下无封面 Tab）
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      if (!_isPadMode)
                        GestureDetector(
                          onTap: () => _tabController.animateTo(1),
                          behavior: HitTestBehavior.opaque,
                          child: _buildSongInfo(playerProvider, currentSong, colorScheme),
                        ),
                      _isLoadingLyrics
                          ? const Center(child: CircularProgressIndicator())
                          : LyricsView(
                              key: _lyricsKey,
                              lyrics: _lyrics,
                              position: playerProvider.position,
                              onSeek: (position) {
                                playerProvider.seek(position);
                              },
                            ),
                      CommentsView(
                        songHash: currentSong.id,
                        albumAudioId: currentSong.albumAudioId,
                      ),
                    ],
                  ),
                ),

                // 控制区：底部 padding 包含导航栏高度
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildControls(playerProvider, colorScheme, isExpanded: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedLayout(
    PlayerProvider playerProvider,
    dynamic currentSong,
    ColorScheme colorScheme,
  ) {
    // 横屏/竖屏 edgeToEdge 模式：保持默认 padding
    return SafeArea(
      bottom: false,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxSize = (constraints.maxWidth - 32).clamp(0.0, 380.0);
                  return Stack(
                    children: [
                      // 封面居中
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxSize,
                            maxHeight: maxSize,
                          ),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: AnimatedScale(
                              scale: playerProvider.isPlaying ? 1.0 : 0.85,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutBack,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: currentSong.artworkUri != null
                                    ? CachedNetworkImage(
                                        imageUrl: currentSong.artworkUri!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => Container(
                                          color: colorScheme.surfaceContainerHighest,
                                          child: Icon(Icons.music_note,
                                            size: 48, color: colorScheme.onSurfaceVariant),
                                        ),
                                        errorWidget: (_, _, _) => Container(
                                          color: colorScheme.surfaceContainerHighest,
                                          child: Icon(Icons.music_note,
                                            size: 48, color: colorScheme.onSurfaceVariant),
                                        ),
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Icon(Icons.music_note,
                                          size: 48, color: colorScheme.onSurfaceVariant),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 歌曲信息：垂直方向 80% 位置，水平居中
                      Positioned(
                        top: constraints.maxHeight * 0.8,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            Text(
                              currentSong.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentSong.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              currentSong.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      if (!_isPadMode)
                        _buildSongInfo(playerProvider, currentSong, colorScheme),
                      _isLoadingLyrics
                          ? const Center(child: CircularProgressIndicator())
                          : LyricsView(
                              lyrics: _lyrics,
                              position: playerProvider.position,
                              onSeek: (position) {
                                playerProvider.seek(position);
                              },
                            ),
                      CommentsView(
                        songHash: currentSong.id,
                        albumAudioId: currentSong.albumAudioId,
                      ),
                    ],
                  ),
                ),
                // 底部 padding 包含导航栏高度
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildControls(playerProvider, colorScheme, isExpanded: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final tabs = _isPadMode
        ? const [Tab(text: '歌词'), Tab(text: '评论')]
        : const [Tab(text: '封面'), Tab(text: '歌词'), Tab(text: '评论')];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: TabBar(
              controller: _tabController,
              tabs: tabs,
              labelStyle: Theme.of(context).textTheme.labelMedium,
              indicatorSize: TabBarIndicatorSize.label,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMoreMenu(context),
          ),
        ],
      ),
    );
  }

  Widget _buildArtworkView(
    PlayerProvider playerProvider,
    dynamic currentSong,
    ColorScheme colorScheme, {
    bool isExpanded = false,
  }) {
    final horizontalPadding = isExpanded ? 16.0 : 32.0;
    final verticalPadding = isExpanded ? 8.0 : 16.0;
    final textSpacing = isExpanded ? 8.0 : 24.0;
    final iconSize = isExpanded ? 48.0 : 64.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isExpanded) const Spacer(),
          if (isExpanded) ...[
            const Spacer(),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxSize = (constraints.maxWidth - 32).clamp(0.0, 380.0);
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxSize,
                    maxHeight: maxSize,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    // 暂停缩放动画（与 AM 风格统一：播放 1.0 / 暂停 0.85 带回弹）
                    child: AnimatedScale(
                      scale: playerProvider.isPlaying ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: currentSong.artworkUri != null
                            ? CachedNetworkImage(
                                imageUrl: currentSong.artworkUri!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.music_note,
                                    size: iconSize,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                errorWidget: (_, _, _) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.music_note,
                                    size: iconSize,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.music_note,
                                  size: iconSize,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Spacer(),
          ] else
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                // 暂停缩放动画（与 AM 风格统一：播放 1.0 / 暂停 0.85 带回弹）
                child: AnimatedScale(
                  scale: playerProvider.isPlaying ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: currentSong.artworkUri != null
                        ? CachedNetworkImage(
                            imageUrl: currentSong.artworkUri!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.music_note,
                                size: iconSize,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.music_note,
                                size: iconSize,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.music_note,
                              size: iconSize,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          SizedBox(height: textSpacing),
          Text(
            currentSong.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isExpanded
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            currentSong.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (!isExpanded) const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSongInfo(
    PlayerProvider playerProvider,
    dynamic currentSong,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentSong.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              currentSong.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              currentSong.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(
    PlayerProvider playerProvider,
    ColorScheme colorScheme, {
    bool isExpanded = false,
  }) {
    final duration = playerProvider.duration ?? Duration.zero;
    final position = playerProvider.position;
    final horizontalPadding = isExpanded ? 16.0 : 24.0;
    final verticalSpacing = isExpanded ? 4.0 : 8.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressBar(playerProvider, position, duration, colorScheme),
          SizedBox(height: verticalSpacing),
          _buildMainControls(
            playerProvider,
            colorScheme,
            isExpanded: isExpanded,
          ),
          SizedBox(height: verticalSpacing),
          _buildSecondaryControls(
            playerProvider,
            colorScheme,
            isExpanded: isExpanded,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    PlayerProvider playerProvider,
    Duration position,
    Duration duration,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            _formatDuration(position),
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Slider(
            value: duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  )
                : 0.0,
            onChanged: (value) {
              final newPosition = Duration(
                milliseconds: (duration.inMilliseconds * value).round(),
              );
              playerProvider.seek(newPosition);
              _lyricsKey.currentState?.forceScrollToPosition(newPosition);
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            _formatDuration(duration),
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildMainControls(
    PlayerProvider playerProvider,
    ColorScheme colorScheme, {
    bool isExpanded = false,
  }) {
    final spacing = isExpanded ? 4.0 : 8.0;
    final skipIconSize = isExpanded ? 28.0 : 36.0;
    final playIconSize = isExpanded ? 40.0 : 48.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            playerProvider.shuffleEnabled
                ? Icons.shuffle
                : Icons.shuffle_outlined,
            color: playerProvider.shuffleEnabled
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          onPressed: () => playerProvider.toggleShuffle(),
        ),
        SizedBox(width: spacing),
        IconButton(
          iconSize: skipIconSize,
          icon: const Icon(Icons.skip_previous),
          onPressed: () => playerProvider.previous(),
        ),
        SizedBox(width: spacing),
        IconButton.filled(
          iconSize: playIconSize,
          icon: Icon(playerProvider.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            if (playerProvider.isPlaying) {
              playerProvider.pause();
            } else {
              playerProvider.resume();
            }
          },
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
        ),
        SizedBox(width: spacing),
        IconButton(
          iconSize: skipIconSize,
          icon: const Icon(Icons.skip_next),
          onPressed: () => playerProvider.next(),
        ),
        SizedBox(width: spacing),
        IconButton(
          icon: Icon(
            _getLoopModeIcon(playerProvider.loopMode),
            color: playerProvider.loopMode != AppLoopMode.off
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          onPressed: () => playerProvider.toggleLoopMode(),
        ),
      ],
    );
  }

  Widget _buildSecondaryControls(
    PlayerProvider playerProvider,
    ColorScheme colorScheme, {
    bool isExpanded = false,
  }) {
    final song = playerProvider.currentSong;
    final isFavorited =
        song != null && context.watch<FavoritesProvider>().isFavorite(song.id);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                isFavorited ? Icons.favorite : Icons.favorite_border,
                color: isFavorited
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
              onPressed: song != null
                  ? () => context.read<FavoritesProvider>().toggleFavorite(song)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: song != null ? () => _downloadSong(song) : null,
            ),
            IconButton(
              icon: const Icon(Icons.volume_up),
              onPressed: () => _showVolumeDialog(playerProvider),
            ),
          ],
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => _showSpeedDialog(playerProvider),
                child: Text(
                  '${playerProvider.speed}x',
                  style: TextStyle(fontSize: isExpanded ? 12 : 14),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _showQualityDialog(playerProvider),
                child: Text(
                  playerProvider.audioQualityLabel,
                  style: TextStyle(fontSize: isExpanded ? 12 : 14),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.playlist_play),
          onPressed: () => _showPlaylist(playerProvider),
        ),
      ],
    );
  }

  void _showVolumeDialog(PlayerProvider playerProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: StatefulBuilder(
                builder: (context, setState) {
                  final volume = playerProvider.volume;
                  final percent = (volume * 100).round();
                  final icon = volume <= 0
                      ? Icons.volume_off
                      : volume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: volume,
                        onChanged: (value) {
                          playerProvider.setVolume(value);
                          setState(() {});
                        },
                      ),
                      Text(
                        '$percent%',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSpeedDialog(PlayerProvider playerProvider) {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // 找到当前速度对应的索引
            int currentIndex = speeds.indexOf(playerProvider.speed);
            if (currentIndex == -1) currentIndex = 3; // 默认 1.0x

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题 + 当前倍速
                      Text(
                        '播放速度',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${speeds[currentIndex]}x',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 横条滑块
                      Slider(
                        value: currentIndex.toDouble(),
                        min: 0,
                        max: (speeds.length - 1).toDouble(),
                        divisions: speeds.length - 1,
                        label: '${speeds[currentIndex]}x',
                        onChanged: (value) {
                          setState(() {
                            currentIndex = value.round();
                          });
                          playerProvider.setSpeed(speeds[currentIndex]);
                        },
                      ),
                      // 节点标签
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: speeds.map((s) {
                          final isSelected = s == speeds[currentIndex];
                          return Text(
                            s == 1.0 ? '1x' : '${s}x',
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // 关闭按钮
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQualityDialog(PlayerProvider playerProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Center(child: Text('音质选择')),
          children: _audioQualities.map((quality) {
            return SimpleDialogOption(
              onPressed: () {
                playerProvider.setAudioQuality(quality);
                Navigator.pop(context);
              },
              child: Text(
                quality.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: playerProvider.audioQuality == quality
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  fontWeight: playerProvider.audioQuality == quality
                      ? FontWeight.bold
                      : null,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  IconData _getLoopModeIcon(AppLoopMode mode) {
    switch (mode) {
      case AppLoopMode.off:
        // 不循环：空心箭头
        return Icons.repeat_outlined;
      case AppLoopMode.one:
        // 单曲循环：带数字1
        return Icons.repeat_one;
      case AppLoopMode.all:
        // 列表循环：实心箭头，播完回到第一首
        return Icons.repeat;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _downloadSong(dynamic song) {
    final downloadsProvider = context.read<DownloadsProvider>();
    final isDownloaded = downloadsProvider.isDownloaded(song.id);
    final isDownloading = downloadsProvider.isDownloading(song.id);

    if (isDownloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已下载: ${song.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在下载: ${song.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 弹出音质选择对话框
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('下载: ${song.displayName ?? song.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(song.artist ?? '', style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text('选择音质', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildDownloadQualityOption(ctx, '标准音质 (128kbps)', '128', song, downloadsProvider),
            _buildDownloadQualityOption(ctx, '高音质 (320kbps)', '320', song, downloadsProvider),
            _buildDownloadQualityOption(ctx, '无损音质 (FLAC)', 'flac', song, downloadsProvider),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadQualityOption(
    BuildContext context,
    String label,
    String quality,
    dynamic song,
    DownloadsProvider provider,
  ) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.music_note, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: () {
        Navigator.pop(context);
        final displayName = song.displayName ?? song.title;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('开始下载: $displayName'),
            duration: const Duration(seconds: 2),
          ),
        );
        provider.downloadSong(song, quality: quality);
      },
    );
  }

  void _showMoreMenu(BuildContext context) {
    final song = context.read<PlayerProvider>().currentSong;
    if (song == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('添加到歌单'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddToPlaylistDialog(context, song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 实现分享功能
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('分享功能开发中')));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, dynamic song) async {
    final api = KugouApiClient();
    if (!api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先登录'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return FutureBuilder<Map<String, dynamic>?>(
          future: api.getUserPlaylist(pagesize: 50),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('加载歌单中...'),
                  ],
                ),
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
              return AlertDialog(
                title: const Text('错误'),
                content: const Text('获取歌单失败'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'),
                  ),
                ],
              );
            }

            final data = snapshot.data!['data'];
            List<dynamic> rawPlaylists = [];
            if (data is List) {
              rawPlaylists = data;
            } else if (data is Map) {
              rawPlaylists =
                  data['info'] ?? data['list'] ?? data['special_list'] ?? [];
            }

            // 使用 KugouPlaylistBrief 模型解析，确保字段名映射正确
            // 只显示用户自己创建的歌单 (type=0)
            final playlists = <Map<String, dynamic>>[];
            for (final item in rawPlaylists) {
              final json = item as Map<String, dynamic>;
              final brief = KugouPlaylistBrief.fromJson(json);
              if (brief.type != 0) continue;
              // 将模型数据转回 Map 以便 UI 使用（包含正确的字段值）
              playlists.add({
                'name': brief.name,
                'songCount': brief.songCount,
                'listid': brief.listId.isEmpty ? brief.id : brief.listId,
                'specialid': brief.id,
                'global_collection_id': brief.globalCollectionId,
                'type': brief.type,
                // 保留原始 JSON 用于 API 调用
                ...json,
              });
            }

            if (playlists.isEmpty) {
              return AlertDialog(
                title: const Text('我的歌单'),
                content: const Text('暂无歌单，请先创建歌单'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: const Text('添加到歌单'),
              content: SizedBox(
                width: 300,
                height: 400,
                child: ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final name =
                        (playlist['name'] ?? playlist['specialname'] ?? '未知歌单')
                            .toString();
                    // 优先使用模型解析后的 songCount，再尝试原始字段
                    final songCount =
                        playlist['songCount'] ??
                        playlist['songcount'] ??
                        playlist['song_count'] ??
                        playlist['count'] ??
                        0;

                    return ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(name),
                      subtitle: Text('$songCount 首'),
                      onTap: () async {
                        Navigator.pop(dialogContext);
                        await _addSongToPlaylist(context, song, playlist);
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addSongToPlaylist(
    BuildContext context,
    dynamic song,
    Map<String, dynamic> playlist,
  ) async {
    final api = KugouApiClient();
    final listid =
        playlist['listid']?.toString() ?? playlist['list_id']?.toString() ?? '';

    if (listid.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('歌单ID无效'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 乐观更新：立即显示成功，后台同步到酷狗服务器
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加到「${playlist['name']}」'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // 构造歌曲数据 — 酷狗API要求的格式：歌名|hash|albumId|albumAudioId
    final songData =
        '${song.title}|${song.id}|${song.albumId ?? 0}|${int.tryParse(song.albumAudioId ?? '') ?? 0}';

    // 后台同步，不阻塞 UI
    api
        .addPlaylistTracks(listid, songData)
        .then((result) {
          // 同步失败时提示用户（静默失败，不影响已显示的乐观更新）
          if (result == null) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('同步到服务器失败，将在下次启动时重试'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        })
        .catchError((_) {
          // 网络错误等，同样静默处理
        });
  }

  void _showPlaylist(PlayerProvider playerProvider) {
    showDialog(
      context: context,
      // 透明 barrier：横屏时点击左半边不关闭对话框（仍可操作播放器）
      barrierColor: Colors.transparent,
      builder: (dialogContext) => const PlayerPlaylistDialog(
        useDisplayName: false, // MD3 风格用 title
      ),
    );
  }
}
