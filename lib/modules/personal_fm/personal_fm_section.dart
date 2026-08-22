import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:provider/provider.dart';

import '../../providers/favorites_provider.dart';
import '../../providers/kugou_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/kugou_api/kugou_models.dart';
import '../../widgets/sliding_segmented_control.dart';
import '../login/login_page.dart';
import '../player/full_player_route.dart';
import 'personal_fm_page.dart';

/// 一个具名电台：把 API 的 (mode, songPoolId) 这对裸参数包成用户看得懂的一档。
///
/// 接口本身是二维的（mode ∈ normal/small/peak × songPoolId ∈ 0/1/2，共 9 种），
/// 但这两个维度对听众没有可解释的差别——发现页只需要「我现在想听哪种」。
/// 所以这里挑出 3 组有意义的组合，每组给名字、图标和一句说明；
/// 想要全部 9 种组合的走完整 FM 页（区块标题右侧的 `›`）。
class _Station {
  const _Station({
    required this.label,
    required this.icon,
    required this.mode,
    required this.songPoolId,
    required this.description,
  });

  final String label;

  /// 每段都显示，不是选中态才给：图标是「这一档是什么」的一部分。
  final IconData icon;

  final String mode;
  final int songPoolId;

  /// 选中后显示在分段控件下方的一行说明。这一行是本区块自引导的核心：
  /// 换档时用户立刻知道这一档意味着什么，不必先试听一轮。
  final String description;
}

const List<_Station> _kStations = [
  _Station(
    label: '红心',
    icon: Icons.favorite,
    mode: 'normal',
    songPoolId: 0,
    description: '贴着你标过红心的歌来',
  ),
  _Station(
    label: '探索',
    icon: Icons.explore,
    mode: 'normal',
    songPoolId: 2,
    description: '跳出常听，找点没听过的',
  ),
  _Station(
    label: '小众',
    icon: Icons.diamond,
    mode: 'small',
    songPoolId: 1,
    description: '冷门但对味的作品',
  ),
];

/// 卡片圆角：与发现页 banner 的 20 对齐，两张卡上下相邻不能是两种圆角。
const double _kCardRadius = 20.0;

/// 卡内主封面圆角。
const double _kCoverRadius = 16.0;

/// 卡内主封面边长。
///
/// 档位组和档位说明移到卡外（见 [PersonalFmSection.build]）之后，卡片只剩
/// 「正在播的一首歌」，腾出来的高度给了封面：84 → 112。总区块高度几乎没变，
/// 但封面大了三分之一，第二屏终于有一个够重的视觉锚点。
///
/// 它同时是右侧内容列的高度预算：曲目信息和两个按钮顶对齐后，
/// 112 减去那一簇的高度就是「即将播放」那一排能用的空间。
const double _kCoverSize = 112.0;

/// 主封面与右侧内容列之间的间距。
const double _kCoverGap = 12.0;

/// 即将播放封面的边长。
///
/// 48 不是随手取的：这些封面现在可点，48dp 正好是 MD3 的最小触达尺寸；
/// 同时它加上一份间距后仍能塞进「112 减去信息+按钮那一簇」剩下的高度里。
const double _kNextCoverSize = 48.0;

/// 即将播放封面的圆角，比主封面小一档，主次关系靠尺寸和圆角同时表达。
const double _kNextCoverRadius = 12.0;

/// 即将播放封面之间（以及它与上方那一簇之间）的间距。
const double _kNextCoverGap = 8.0;

/// 区块所有容器的底色。
///
/// 用 surface 系而不是 primaryContainer：MD3 给 tonal container 只配了一个
/// on 色（onPrimaryContainer），做「主文字 / 次要文字 / 占位」的层次就只能手调
/// alpha；换到 surface 系后 onSurface、onSurfaceVariant、surfaceContainerHighest
/// 三个现成角色刚好对上，一个 alpha 都不用写，暗色模式也自动成立。
/// 取 surfaceContainerLow 还让这张卡与每日推荐卡、场景卡同底。
Color _containerColor(ColorScheme cs) => cs.surfaceContainerLow;

/// 发现页内嵌的私人 FM 区块。
///
/// 与完整 FM 页的差异：
/// - 加载后不自动开播（发现页仅展示，点播放才出声）
/// - 不注册 onPlaylistEnd / 预取 / 同步逻辑（避免与 FM 页抢占回调）
/// - 电台档位是 3 个具名预设而非 mode × songPoolId 两个三选一
///
/// 层级划分：档位组和档位说明是**区块级**的（它们决定卡片显示什么内容，
/// 本身不是卡片的内容），所以放在卡外；卡片只承载「正在播的一首歌」。
/// 这样卡片和发现页其他歌曲卡变成同一类对象，语言统一。
///
/// 卡内布局靠形状和尺寸而非文字说明角色：
/// 左边一张大方封面 = 正在播；右边上半是曲目信息 + 收藏 / 播放，
/// 这一簇顶对齐后腾出的下半排小方封面 = 接下来会放的几首。
/// 封面都可点：大封面直接进播放详情页，小封面先把电台切到那一首再进详情页。
class PersonalFmSection extends StatefulWidget {
  const PersonalFmSection({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  /// 是否展开。折叠状态与持久化由发现页统一管理（六个区块同一套机制），
  /// 本区块只负责渲染标题行的箭头和内容的折叠动画。
  final bool isExpanded;

  /// 点击标题行（标题 + 箭头）时的折叠/展开回调。
  final VoidCallback onToggle;

  @override
  State<PersonalFmSection> createState() => _PersonalFmSectionState();
}

class _PersonalFmSectionState extends State<PersonalFmSection> {
  bool _isLoading = false;
  int _stationIndex = 0;

  _Station get _station => _kStations[_stationIndex];

  Future<void> _loadPersonalFm() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await Provider.of<KugouProvider>(context, listen: false).getPersonalFm(
        mode: _station.mode,
        songPoolId: _station.songPoolId,
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 换电台：更新档位并拉新歌单；点回当前档不做任何事。
  void _selectStation(int index) {
    if (index == _stationIndex) return;
    setState(() => _stationIndex = index);
    _loadPersonalFm();
  }

  Future<void> _playSong(KugouSongDetail song) async {
    final kugou = Provider.of<KugouProvider>(context, listen: false);
    final player = Provider.of<PlayerProvider>(context, listen: false);
    if (!kugou.personalFmSongs.any((s) => s.hash == song.hash)) return;

    kugou.moveToFirst(song);
    await player.playOnlinePlaylist(kugou.personalFmAsSongs, 0);
  }

  /// 点封面：进播放详情页，必要时先把电台切到这一首。
  ///
  /// 「必要时」按播放器的当前曲目判断而不是按封面在列表里的位置：本区块加载后
  /// 不自动开播，首屏大封面上已经有 `songs.first` 而播放器还是空的，
  /// 这时点大封面同样得先起播，否则详情页开出来是上一首甚至空的。
  ///
  /// 不 await 起播：[PlayerProvider.playOnlinePlaylist] 在第一个 await 之前
  /// 已经同步设好 currentSong 并 notifyListeners，详情页立刻就能显示这首歌，
  /// 取 URL 期间的加载态由播放页自己表现。await 的话点一下要等一个网络往返才跳页。
  void _openTrack(KugouSongDetail track) {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    if (player.currentSong?.id != track.hash) {
      _playSong(track);
    }
    _openPlayerDetail();
  }

  /// 打开播放详情页。
  ///
  /// 走 [fullPlayerRoute] 而不是 `pushNamed('/player')`：前者是 MiniPlayer 点击
  /// 展开用的同一条路由，带向下拖拽收起、与 MiniPlayer 的交叉淡入，
  /// 以及 md / AM 两套播放页的选择。栈顶已经是播放器时不重复 push。
  void _openPlayerDetail() {
    if (activePlayerRoute?.isCurrent ?? false) return;
    Navigator.of(context).push(fullPlayerRoute(context));
  }

  Future<void> _togglePlay() async {
    final player = Provider.of<PlayerProvider>(context, listen: false);
    if (player.isPlaying) {
      await player.pause();
    } else {
      await player.resume();
    }
  }

  Future<void> _handlePlayPersonalFm(
    KugouSongDetail? track,
    bool isPlaying,
  ) async {
    if (_isLoading) return;
    final kugou = Provider.of<KugouProvider>(context, listen: false);

    // 首次进入：列表为空，点击触发首次加载
    if (kugou.personalFmSongs.isEmpty) {
      await _loadPersonalFm();
      return;
    }

    if (isPlaying) {
      await _togglePlay();
    } else {
      if (track == null) return;
      await _playSong(track);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kugou = Provider.of<KugouProvider>(context);
    final player = Provider.of<PlayerProvider>(context);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isLoggedIn = kugou.isLoggedIn;
    final songs = kugou.personalFmSongs;
    final currentTrack = songs.isNotEmpty ? songs.first : null;
    final isPlaying =
        currentTrack != null &&
        player.currentSong?.id == currentTrack.hash &&
        player.isPlaying;
    final nextTracks = songs.length > 1
        ? songs.sublist(1)
        : const <KugouSongDetail>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(cs, textTheme, showMore: isLoggedIn),
        // 折叠动画与发现页其他区块同一套参数（200ms + easeInOut）。
        // 底部间距放在折叠内容内部：折叠后本区块只剩标题行，
        // 高度与其他区块的折叠态一致，不会多留一截空白。
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: widget.isExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          sizeCurve: Curves.easeInOut,
          firstChild: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLoggedIn) ...[
                  // 档位说明紧贴标题：它描述的是「这一档电台是什么」，
                  // 属于区块的 supporting text，不属于某一首歌。
                  // 放在顶部换档时视线不用下移就能看到这行字变了。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _buildStationDescription(cs, textTheme),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _buildStationGroup(),
                  ),
                  _buildRadioCard(
                    cs,
                    textTheme,
                    currentTrack,
                    nextTracks,
                    isPlaying,
                  ),
                ] else
                  _buildLoginPrompt(cs, textTheme),
              ],
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// 区块标题行：与每日推荐/热门歌单/排行榜同一个骨架（titleMedium + w600 +
  /// 可点击的折叠箭头），让私人 FM 不再是发现页里唯一没有标题、也是唯一
  /// 不能折叠的内容块。右侧 `›` 进完整 FM 页，那里才有全部 9 种
  /// mode × songPoolId 组合。
  ///
  /// 展开时底部只留 2dp（外层 0 + InkWell 内层 2）：紧接着的档位说明是这一行的
  /// supporting text，两者要读成一组而不是两个独立的元素；折叠后下方内容整体
  /// 隐去，改留 8dp 与其他区块的折叠态对齐。
  Widget _buildSectionHeader(
    ColorScheme cs,
    TextTheme textTheme, {
    required bool showMore,
  }) {
    final tight = showMore && widget.isExpanded;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, showMore ? 4 : 16, tight ? 0 : 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: widget.onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.only(top: 4, bottom: tight ? 2 : 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '私人 FM',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: widget.isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showMore)
            IconButton(
              tooltip: '打开私人 FM',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonalFmPage()),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
        ],
      ),
    );
  }

  /// 未登录时的紧凑登录引导卡片。标题已由区块标题行承担，这里只留一句行动号召。
  ///
  /// 底色与电台卡片相同：登录前后是同一个区块，不该换一张颜色不同的卡。
  /// 需要的强调放在左侧图标块上——中性卡里嵌一小块 primaryContainer，
  /// 既点出这是要动作的状态，又让正文继续用 onSurface / onSurfaceVariant 这对
  /// 现成的层次角色，不必手调 alpha。
  Widget _buildLoginPrompt(ColorScheme cs, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: _containerColor(cs),
        borderRadius: BorderRadius.circular(_kCardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const LoginPage())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: cs.primaryContainer,
                  ),
                  child: Icon(
                    Icons.radio,
                    size: 22,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '登录后开启你的专属电台',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '按你的口味不断续播',
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 电台卡片：正在播的一首歌，加上接下来会放的几首的封面。
  ///
  /// 档位组和说明已经提到卡外（区块级），所以这里不再是一个塞了四种东西的
  /// 复合容器，而是和 `_DailySongCard` 同构的一张歌曲卡。
  Widget _buildRadioCard(
    ColorScheme cs,
    TextTheme textTheme,
    KugouSongDetail? currentTrack,
    List<KugouSongDetail> nextTracks,
    bool isPlaying,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kCardRadius),
        color: _containerColor(cs),
      ),
      child: _buildNowPlayingRow(
        cs,
        textTheme,
        currentTrack,
        nextTracks,
        isPlaying,
      ),
    );
  }

  /// 电台档位：[SlidingSegmentedControl]，三段等宽，选中项由一个滑动的
  /// primary 指示器承载。
  ///
  /// 相比原先的 M3E connected button group：段宽不再随选中项变化（换档时
  /// 三段的宽度不重排），图标三段都在（不是只有当前档才有），选中态也不改字重。
  /// 换档时动的只有指示器的位置和前景色。
  Widget _buildStationGroup() {
    return SlidingSegmentedControl(
      segments: _kStations
          .map(
            (station) => SlidingSegment(
              label: station.label,
              icon: station.icon,
              semanticLabel: '${station.label}电台',
            ),
          )
          .toList(),
      selectedIndex: _stationIndex,
      onSelected: _selectStation,
      semanticLabel: '电台档位',
    );
  }

  /// 当前档位的一句说明。换档时淡入淡出，让人注意到这行字变了。
  Widget _buildStationDescription(ColorScheme cs, TextTheme textTheme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        _station.description,
        key: ValueKey(_stationIndex),
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 正在播这一行：左边大封面，右边上半是曲目信息 + 收藏 / 播放，
  /// 下半是接下来会放的几首的封面。
  ///
  /// 右侧那一簇顶对齐（[CrossAxisAlignment.start]）而不是像原来一样在 112dp 的
  /// 行高里居中：居中时它上下各留一条谁也用不上的空白，顶上去之后那两条空白
  /// 合成一块完整的区域，刚好排得下一行 48dp 的封面。卡片高度因此没变。
  Widget _buildNowPlayingRow(
    ColorScheme cs,
    TextTheme textTheme,
    KugouSongDetail? currentTrack,
    List<KugouSongDetail> nextTracks,
    bool isPlaying,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCurrentCover(cs, currentTrack),
        const SizedBox(width: _kCoverGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 信息与按钮内部仍然互相居中：曲名一行还是两行都有可能，
              // 让文字块与 48dp 的按钮对齐比让两者都贴顶稳。
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          // 空态直接说下一步该做什么，不写「暂无推荐」——
                          // 首次进入时列表本来就是空的，那不是错误状态。
                          currentTrack?.songName ?? '点播放，开启你的电台',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (currentTrack?.artistName?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 3),
                          Text(
                            currentTrack!.artistName!,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildFavoriteButton(cs, currentTrack),
                  _buildPlayButton(cs, currentTrack, isPlaying),
                ],
              ),
              if (nextTracks.isNotEmpty) ...[
                const SizedBox(height: _kNextCoverGap),
                _buildNextCoverRow(cs, nextTracks),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 正在播的大封面。点它进播放详情页。
  ///
  /// 空态（还没拉到歌）不挂点击：那时候没有「这一首」可以打开。
  Widget _buildCurrentCover(ColorScheme cs, KugouSongDetail? currentTrack) {
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(_kCoverRadius),
      child: SizedBox(
        width: _kCoverSize,
        height: _kCoverSize,
        child: currentTrack == null
            ? _buildCoverPlaceholder(cs, iconSize: 36)
            : _buildCover(cs, currentTrack, cacheSize: 336, iconSize: 36),
      ),
    );
    if (currentTrack == null) return cover;
    return _buildTappableCover(
      cover: cover,
      radius: _kCoverRadius,
      semanticLabel: '正在播放 ${currentTrack.songName}',
      tooltip: '打开播放详情',
      onTap: () => _openTrack(currentTrack),
    );
  }

  /// 接下来会放的几首的封面排，坐在曲目信息和按钮下面腾出来的那块空间里。
  ///
  /// 数量按可用宽度算而不是写死：这一排在主封面右侧，能用的宽度是屏宽减掉
  /// 页边距、卡片内边距、主封面和间距之后剩下的部分，写死三张在窄屏上会溢出。
  Widget _buildNextCoverRow(ColorScheme cs, List<KugouSongDetail> nextTracks) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 最后一张右边不需要间距，所以先补一份间距再按「封面 + 间距」整除。
        final slot = _kNextCoverSize + _kNextCoverGap;
        final fits = ((constraints.maxWidth + _kNextCoverGap) / slot).floor();
        final count = fits.clamp(0, nextTracks.length);
        if (count <= 0) return const SizedBox.shrink();
        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: _kNextCoverGap),
              _buildNextCover(cs, nextTracks[i]),
            ],
          ],
        );
      },
    );
  }

  /// 接下来会放的一张封面。点它把电台切到这一首并进播放详情页。
  ///
  /// 曲名通过语义标签和长按 tooltip 给出，不占版面。
  Widget _buildNextCover(ColorScheme cs, KugouSongDetail track) {
    return _buildTappableCover(
      cover: ClipRRect(
        borderRadius: BorderRadius.circular(_kNextCoverRadius),
        child: SizedBox(
          width: _kNextCoverSize,
          height: _kNextCoverSize,
          child: _buildCover(cs, track, cacheSize: 144, iconSize: 18),
        ),
      ),
      radius: _kNextCoverRadius,
      semanticLabel: '接下来播放 ${track.songName}',
      tooltip: '播放：${track.songName}',
      onTap: () => _openTrack(track),
    );
  }

  /// 给封面套上可点击层。
  ///
  /// 用 Stack 把「透明 Material + InkWell」叠在封面**上面**，而不是让封面当
  /// InkWell 的 child：水波纹画在它所属 Material 的表面上，Material 在下层时
  /// 会被不透明的封面整个挡住，点了完全没反馈。
  ///
  /// [MergeSemantics] 把标签和 InkWell 自带的按钮节点并成一个：不并的话读屏
  /// 会先念一遍曲名、再单独聚焦一个没名字的按钮。
  Widget _buildTappableCover({
    required Widget cover,
    required double radius,
    required String semanticLabel,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        child: Tooltip(
          message: tooltip,
          child: Stack(
            children: [
              cover,
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(radius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(onTap: onTap),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 收藏按钮：接 [FavoritesProvider]（`toggleFavorite` 走「我喜欢」歌单，
  /// 已登录时同步到服务端）。只订阅当前曲目那一个布尔值，
  /// 所以点收藏不会把带网络封面的整个区块重建一遍。
  ///
  /// 已收藏用 primary（与播放按钮同一个强调色，「这首被我挑出来了」），
  /// 未收藏用 onSurfaceVariant（和歌手名同级的次要前景），
  /// 两态的差别落在色相上而不是同一个颜色的两档透明度。
  Widget _buildFavoriteButton(ColorScheme cs, KugouSongDetail? currentTrack) {
    if (currentTrack == null) {
      return IconButton(
        tooltip: '收藏',
        onPressed: null,
        icon: const Icon(Icons.favorite_border),
        color: cs.onSurfaceVariant,
      );
    }
    return Selector<FavoritesProvider, bool>(
      selector: (_, favorites) => favorites.isFavorite(currentTrack.hash),
      builder: (context, isFavorite, _) {
        return IconButton(
          tooltip: isFavorite ? '取消收藏' : '收藏',
          onPressed: () => context.read<FavoritesProvider>().toggleFavorite(
            currentTrack.toSong(),
          ),
          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
          color: isFavorite ? cs.primary : cs.onSurfaceVariant,
        );
      },
    );
  }

  /// 播放按钮：48dp，满足 MD3 最小触达（原先是 28–36dp）。
  Widget _buildPlayButton(
    ColorScheme cs,
    KugouSongDetail? currentTrack,
    bool isPlaying,
  ) {
    return Material(
      color: cs.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handlePlayPersonalFm(currentTrack, isPlaying),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: M3ELoadingIndicator(color: cs.onPrimary),
                  )
                : Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: cs.onPrimary,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }

  /// 封面。改用 [CachedNetworkImage]（与发现页其他封面一致），
  /// 原来这里是 Image.network，每次重建都重新走网络。
  Widget _buildCover(
    ColorScheme cs,
    KugouSongDetail track, {
    required int cacheSize,
    required double iconSize,
  }) {
    final url = track.artworkUri;
    if (url == null || url.isEmpty) {
      return _buildCoverPlaceholder(cs, iconSize: iconSize);
    }
    return CachedNetworkImage(
      imageUrl: url,
      memCacheWidth: cacheSize,
      memCacheHeight: cacheSize,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, _) => _buildCoverPlaceholder(cs, iconSize: iconSize),
      errorWidget: (_, _, _) =>
          _buildCoverPlaceholder(cs, iconSize: iconSize),
    );
  }

  /// 封面占位。用 surfaceContainerHighest 而不是给前景色加透明度：
  /// 它比卡底 surfaceContainerLow 高两档，本来就是「容器里最靠上的一层」，
  /// 图没加载出来时是一块干净的浅色方块，不是一片脏掉的半透明。
  Widget _buildCoverPlaceholder(ColorScheme cs, {required double iconSize}) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: iconSize,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
