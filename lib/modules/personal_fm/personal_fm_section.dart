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

/// 一个具名电台：把 API 的 (mode, songPoolId) 这对裸参数包成用户看得懂的一档。
///
/// 接口是二维的（mode ∈ normal/small/peak × songPoolId ∈ 0/1/2，共 9 种），
/// 但这两个维度对听众没有可解释的差别，所以这里只挑 3 组有意义的组合，
/// 每组给名字、图标和一句说明；要全部 9 种的走完整 FM 页。
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

  /// 选中后显示在分段控件下方的一行说明：换档时不必先试听一轮就知道这一档是什么。
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

/// 卡片圆角。
const double _kCardRadius = 20.0;

/// 卡内主封面圆角。
const double _kCoverRadius = 16.0;

/// 卡内主封面边长，同时是右侧内容列的高度预算：曲目信息和两个按钮顶对齐后，
/// 112 减去那一簇的高度就是底排（预告封面 + 档位按钮）能用的空间。
const double _kCoverSize = 112.0;

/// 主封面与右侧内容列之间的间距。
const double _kCoverGap = 12.0;

/// 即将播放封面的边长。这些封面可点，48dp 是 MD3 的最小触达尺寸；
/// 加一份间距后仍能塞进底排剩下的高度里。
const double _kNextCoverSize = 48.0;

/// 即将播放封面的圆角，比主封面小一档，主次关系靠尺寸和圆角同时表达。
const double _kNextCoverRadius = 12.0;

/// 即将播放封面之间（以及它与上方那一簇之间）的间距。
const double _kNextCoverGap = 8.0;

/// 档位按钮的边长（卡片右下角那枚）。
///
/// 40 而不是 48：它和 48dp 的预告封面同排，比封面小一档才读得出「这是控件、
/// 不是又一张封面」，且与 [SlidingSegmentedControl] 的轨道同高。
const double _kStationButtonSize = 40.0;

/// 档位按钮右侧的补白：它和上一排 48dp 的播放按钮都靠右排，直接贴右边两个圆心
/// 会差 4dp，补上这 4dp 才落在同一条竖线上。
const double _kStationButtonRightInset = 4.0;

/// 档位抽屉的开合时长与曲线。用 MD3 emphasized 那条：抽屉是「一块面积长出来」，
/// 属于大状态转换，standard 曲线会显得它只是淡了一下。
const Duration _kDrawerDuration = Duration(milliseconds: 260);
const Curve _kDrawerCurve = Curves.easeInOutCubicEmphasized;

/// 队列里剩下的歌少于这个数就提前补货（与完整 FM 页同一条阈值）。
const int _kPrefetchThreshold = 3;

/// 卡片正面（以及未登录时那张引导卡）的底色。
///
/// 用 surface 系而不是 primaryContainer：tonal container 只配一个 on 色，
/// 做「主文字 / 次要文字 / 占位」的层次就得手调 alpha；surface 系有
/// onSurface、onSurfaceVariant、surfaceContainerHighest 三个现成角色可用。
/// 取 surfaceContainerLow 还让这张卡与页面里其他卡同底。
Color _containerColor(ColorScheme cs) => cs.surfaceContainerLow;

/// 档位抽屉那一层的底色。
///
/// 抽屉露出来的这块必须同时区别于卡面（surfaceContainerLow）和页面底色
/// （surface）。不能用 surfaceDim：深色主题下它与 surface 是同一个值
/// （本项目种子色下都是 #111418），抽屉展开后正好和页面底色一样，看起来就是
/// 「没有背景」。中性档里离卡面最远的 surfaceContainerHighest 又只比抽屉里
/// 分段控件的轨道（surfaceContainerHigh）差一档，轨道会糊掉。
///
/// secondaryContainer 在浅色和深色下都与卡面、页面底色明显不同，与轨道之间
/// 除明度差还有色相差，且自带 onSecondaryContainer；OLED 纯黑变体没动它。
Color _drawerColor(ColorScheme cs) => cs.secondaryContainer;

/// 档位抽屉里文字的前景色（配 [_drawerColor]）。
Color _onDrawerColor(ColorScheme cs) => cs.onSecondaryContainer;

/// 发现页内嵌的私人 FM 区块。
///
/// 与完整 FM 页的差异：
/// - 加载后不自动开播（发现页仅展示，点播放才出声）
/// - 不做 FM 页那套「列表顺序反向同步回播放器」的逻辑
/// - 电台档位是 3 个具名预设而非 mode × songPoolId 两个三选一
///
/// 起播之后同样是无限电台：队列快见底时补货，见 [_PersonalFmSectionState
/// ._appendMorePersonalFm]。
///
/// 区块没有标题行——卡片本身（大封面 + 曲名 + 播放）已经说明了它是什么。
/// 登录后是电台卡，未登录是登录引导卡。
///
/// 卡内布局靠形状和尺寸表达角色：左边一张大方封面 = 正在播；右边上半是曲目信息
/// + 收藏 / 播放，这一簇顶对齐后腾出的下半排小方封面 = 接下来会放的几首，
/// 那一排的最右端是档位按钮，点开才拉出档位选择（见 [_buildStationDrawer]）。
/// 封面都可点：大封面直接进播放详情页，小封面先把电台切到那一首再进详情页。
class PersonalFmSection extends StatefulWidget {
  const PersonalFmSection({super.key});

  @override
  State<PersonalFmSection> createState() => _PersonalFmSectionState();
}

class _PersonalFmSectionState extends State<PersonalFmSection> {
  bool _isLoading = false;
  int _stationIndex = 0;

  /// 正在补货。补货有两条触发路径（提前补货、队列播完），不能同时跑。
  bool _isAppending = false;

  /// 上一次提前补货时的播放下标，避免停在同一首上反复请求。
  int _lastPrefetchIndex = -1;

  /// 监听中的播放器，dispose 时要摘掉监听。
  PlayerProvider? _player;

  /// 档位抽屉是否展开。默认收起：进发现页第一眼该是「在播什么」，
  /// 不是「先选一个档位」。
  bool _isStationDrawerOpen = false;

  _Station get _station => _kStations[_stationIndex];

  @override
  void initState() {
    super.initState();
    // initState 里还不能读 provider，放到首帧之后再挂监听。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _player = Provider.of<PlayerProvider>(context, listen: false)
        ..addListener(_onPlayerChanged);
    });
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayerChanged);
    super.dispose();
  }

  /// 队列快见底时提前补货。
  ///
  /// [PlayerProvider] 一次只把一首歌灌进 audio_service（切歌全在 Dart 端做），
  /// 队列末尾没有预加载，等播完最后一首才去要新歌会断一下；提前补也让卡片上的
  /// 预告封面不至于空着。
  ///
  /// 只管本区块起播的队列：完整 FM 页起播时会把 [PlayerProvider.onPlaylistEnd]
  /// 抢过去，那边有自己的补货逻辑。
  void _onPlayerChanged() {
    final player = _player;
    if (player == null || player.onPlaylistEnd != _continueAfterQueueEnd) {
      return;
    }
    final index = player.currentIndex;
    if (index < 0) return;
    if (player.playlist.length - index > _kPrefetchThreshold) return;
    if (index == _lastPrefetchIndex) return;
    _lastPrefetchIndex = index;
    _appendMorePersonalFm();
  }

  Future<void> _loadPersonalFm() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await Provider.of<KugouProvider>(
        context,
        listen: false,
      ).getPersonalFm(mode: _station.mode, songPoolId: _station.songPoolId);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 换电台：更新档位并拉新歌单；点回当前档不做任何事。
  ///
  /// 换完不自动收抽屉：档位说明就在控件下面，换一档看一眼那句话是这里的常见
  /// 动作，替用户把抽屉关掉会让人得再点一次才能对比下一档。
  void _selectStation(int index) {
    if (index == _stationIndex) return;
    setState(() => _stationIndex = index);
    _loadPersonalFm();
  }

  /// 开合档位抽屉。
  void _toggleStationDrawer() {
    setState(() => _isStationDrawerOpen = !_isStationDrawerOpen);
  }

  Future<void> _playSong(KugouSongDetail song) async {
    final kugou = Provider.of<KugouProvider>(context, listen: false);
    final player = Provider.of<PlayerProvider>(context, listen: false);
    if (!kugou.personalFmSongs.any((s) => s.hash == song.hash)) return;

    kugou.moveToFirst(song);
    // 队列由本区块起播，补货就归本区块。这是播放器上的单个槽位，完整 FM 页
    // 起播时同样会把它抢过去——谁起播的队列谁负责补货。
    player.onPlaylistEnd = _continueAfterQueueEnd;
    _lastPrefetchIndex = -1;
    await player.playOnlinePlaylist(kugou.personalFmAsSongs, 0);
  }

  /// 队列播完了：补一批新歌，然后接着放下去。
  ///
  /// 必须由这里推一把 [PlayerProvider.next]。播放器在最后一首播完时只会 await
  /// 这个回调（player_provider.dart 的 `_handlePlaybackCompleted`），自己不再切歌；
  /// 而它给 audio_service 的永远只有当前这一首，所以光把歌接到 Dart 端的队列上
  /// 是不会自动播下去的。
  Future<void> _continueAfterQueueEnd() async {
    if (!await _appendMorePersonalFm()) return;
    if (!mounted) return;
    await Provider.of<PlayerProvider>(context, listen: false).next();
  }

  /// 向电台列表和播放队列各接一批新歌，返回是否真的接上了。
  ///
  /// 接口一次只发 5 首左右，[PlayerProvider.playOnlinePlaylist] 又是一次性把
  /// 这几首灌进队列，不补货的话本区块起播的电台放完就停了。
  ///
  /// 取新歌用列表最后一首当游标（与 FM 页一致：hash + songId + action=play），
  /// 带游标失败就退回不带游标再要一次。
  Future<bool> _appendMorePersonalFm() async {
    if (_isAppending || !mounted) return false;
    final kugou = Provider.of<KugouProvider>(context, listen: false);
    final player = Provider.of<PlayerProvider>(context, listen: false);
    final songs = kugou.personalFmSongs;
    if (songs.isEmpty) return false;

    // 回调是常驻的单槽位，队列可能已经不是本电台的了（用户从别处起播了别的
    // 歌单）：那时候补货只会把电台的歌塞进别人的队列。
    final playingId = player.currentSong?.id;
    if (playingId == null || !songs.any((s) => s.hash == playingId)) {
      return false;
    }

    _isAppending = true;
    try {
      final cursor = songs.last;
      List<KugouSongDetail>? result;
      try {
        result = await kugou.apiClient.getPersonalFm(
          mode: _station.mode,
          songPoolId: _station.songPoolId,
          hash: cursor.hash,
          songId: cursor.songId,
          action: 'play',
        );
      } catch (_) {
        result = await kugou.apiClient.getPersonalFm(
          mode: _station.mode,
          songPoolId: _station.songPoolId,
          action: 'play',
        );
      }
      if (result == null || result.isEmpty || !mounted) return false;

      final fresh = result
          .where((s) => !kugou.personalFmSongs.any((c) => c.hash == s.hash))
          .toList();
      if (fresh.isEmpty) return false;
      kugou.appendFmSongs(fresh);
      await player.appendPlaylist(fresh.map((e) => e.toSong()).toList());
      return true;
    } catch (_) {
      return false;
    } finally {
      _isAppending = false;
    }
  }

  /// 点封面：进播放详情页，必要时先把电台切到这一首。
  ///
  /// 「必要时」按播放器的当前曲目判断而不是按封面在列表里的位置：本区块加载后
  /// 不自动开播，那时大封面上已经有 `songs.first` 而播放器还是空的，点它同样
  /// 得先起播。
  ///
  /// 不 await 起播：[PlayerProvider.playOnlinePlaylist] 在第一个 await 之前就
  /// 同步设好了 currentSong 并 notifyListeners，详情页立刻能显示这首歌；
  /// await 的话点一下要等一个网络往返才跳页。
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

  /// 点卡片上的播放按钮：播放器停在本电台的某一首上就切播放/暂停，否则起播 [track]。
  ///
  /// 判断依据是播放器的当前曲目，而不是按钮画的是播放还是暂停——暂停在第三首时
  /// 按钮画的是播放，但那时要的是 resume，走 [_playSong] 会把这首从头重放，
  /// 还会把它挪到列表最前面。判断在点的那一刻现取，不吃 build 时的快照。
  Future<void> _handlePlayPersonalFm(KugouSongDetail? track) async {
    if (_isLoading) return;
    final kugou = Provider.of<KugouProvider>(context, listen: false);
    final player = Provider.of<PlayerProvider>(context, listen: false);

    // 首次进入：列表为空，点击触发首次加载
    if (kugou.personalFmSongs.isEmpty) {
      await _loadPersonalFm();
      return;
    }

    final playingId = player.currentSong?.id;
    final isOnThisStation =
        playingId != null &&
        kugou.personalFmSongs.any((s) => s.hash == playingId);
    if (isOnThisStation) {
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

    // 卡片跟着播放器走，而不是永远渲染 songs.first：电台自己续到下一首时列表
    // 顺序没变（[KugouProvider.moveToFirst] 只在用户主动点某一首时才重排），
    // 变的只有播放器的当前曲目。按 songs.first 渲染会让封面 / 曲名 / 预告都停在
    // 上一首，还会因为「当前曲目 == songs.first」不成立而把在放显示成没在放。
    //
    // 找不到（还没起播，或播放器在放别处的歌）就退回列表第一首——那是
    // 「点播放会从这首开始」的预告。
    final playingId = player.currentSong?.id;
    final playingIndex = playingId == null
        ? -1
        : songs.indexWhere((s) => s.hash == playingId);
    final currentIndex = playingIndex >= 0 ? playingIndex : 0;
    final currentTrack = songs.isEmpty ? null : songs[currentIndex];
    final isPlaying = playingIndex >= 0 && player.isPlaying;
    final nextTracks = songs.isEmpty
        ? const <KugouSongDetail>[]
        : songs.sublist(currentIndex + 1);

    // 上下留白由本区块自己给：卡片是发现页顶栏下的第一个元素，8 / 16 保持它与
    // 下方每日推荐区块原来的间距关系。
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: isLoggedIn
          ? _buildRadioCard(cs, textTheme, currentTrack, nextTracks, isPlaying)
          : _buildLoginPrompt(cs, textTheme),
    );
  }

  /// 未登录时的紧凑登录引导卡片。
  ///
  /// 底色与电台卡片相同（登录前后是同一个区块），强调只放在左侧那一小块
  /// primaryContainer 图标底上，正文继续用 onSurface / onSurfaceVariant。
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

  /// 电台卡片：两层叠着——上面是常驻的「正在播」面板，下面是档位抽屉。
  ///
  /// 抽屉不是面板里长出来的一段，而是面板底下另一张换了颜色的托盘
  /// （[_drawerColor]）：收起时托盘高度正好等于面板，一点也露不出来；展开时
  /// 托盘在面板下方长出一块。面板保留四个圆角并给 1 级高度，下沿压在托盘上、
  /// 阴影落进托盘里，「谁在上、谁在下」不靠文字说明；托盘的裁剪会把外溢的阴影
  /// 收掉，所以收起状态下卡片的样子和没有抽屉时一样。
  Widget _buildRadioCard(
    ColorScheme cs,
    TextTheme textTheme,
    KugouSongDetail? currentTrack,
    List<KugouSongDetail> nextTracks,
    bool isPlaying,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: _drawerColor(cs),
        borderRadius: BorderRadius.circular(_kCardRadius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          // stretch：两层的宽度都钉在卡片宽度上，不随各自内容变。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: _containerColor(cs),
              // 面板的底色是选定的角色，不要 M3 的高度着色再往上叠一层色。
              surfaceTintColor: Colors.transparent,
              elevation: 1,
              borderRadius: BorderRadius.circular(_kCardRadius),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildNowPlayingRow(
                  cs,
                  textTheme,
                  currentTrack,
                  nextTracks,
                  isPlaying,
                ),
              ),
            ),
            _buildStationDrawer(cs, textTheme),
          ],
        ),
      ),
    );
  }

  /// 档位抽屉：收起时高度为 0，展开时从面板下方拉出档位控件和当前档的说明。
  /// 它铺在托盘那一层上（见 [_buildRadioCard]），内边距由自己给：左右 16 与面板
  /// 对齐，底 16 是卡片下沿的留白。
  ///
  /// 用 `heightFactor` + [ClipRect] 而不是 [AnimatedCrossFade]：抽屉要的是
  /// 「内容钉在顶边不动、容器高度自己长出来」，交叉淡入会让内容跟着一起缩放。
  /// 收起时内容仍在树里但被裁成零高度，换档时的滑动指示器不用每次重建；
  /// 零高度下没有可命中的区域，透明度归零也让读屏跳过它（[Opacity] 在 alpha
  /// 为 0 时不下发语义）。
  Widget _buildStationDrawer(ColorScheme cs, TextTheme textTheme) {
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topLeft,
        heightFactor: _isStationDrawerOpen ? 1.0 : 0.0,
        duration: _kDrawerDuration,
        curve: _kDrawerCurve,
        child: AnimatedOpacity(
          opacity: _isStationDrawerOpen ? 1.0 : 0.0,
          duration: _kDrawerDuration,
          curve: Curves.easeInOut,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStationGroup(),
                const SizedBox(height: 8),
                _buildStationDescription(cs, textTheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 档位按钮，坐在卡片右下角。
  ///
  /// 图标取当前档位的图标（红心 / 探索 / 小众）：抽屉收起时这枚图标是「现在是
  /// 哪一档」的唯一线索，换成通用的 tune / more 图标就把这个信息丢了。
  /// 展开时底色翻成 primary，与抽屉里那条 primary 指示器对上。
  Widget _buildStationButton(ColorScheme cs) {
    final open = _isStationDrawerOpen;
    return MergeSemantics(
      child: Semantics(
        button: true,
        expanded: open,
        label: '电台档位：${_station.label}',
        excludeSemantics: true,
        child: Tooltip(
          message: open ? '收起电台档位' : '电台档位：${_station.label}',
          child: Material(
            color: open ? cs.primary : cs.surfaceContainerHigh,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _toggleStationDrawer,
              child: SizedBox(
                width: _kStationButtonSize,
                height: _kStationButtonSize,
                child: Center(
                  child: Icon(
                    _station.icon,
                    size: 20,
                    color: open ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 电台档位：[SlidingSegmentedControl]，三段等宽，选中项由一个滑动的
  /// primary 指示器承载。换档时布局不动，只有指示器的位置和前景色在变。
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
  /// 它直接落在抽屉那一层上，所以前景取 [_onDrawerColor]。
  Widget _buildStationDescription(ColorScheme cs, TextTheme textTheme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        _station.description,
        key: ValueKey(_stationIndex),
        style: textTheme.bodySmall?.copyWith(color: _onDrawerColor(cs)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 正在播这一行：左边大封面，右边上半是曲目信息 + 收藏 / 播放，
  /// 下半是接下来会放的几首的封面，那一排最右端是档位按钮。
  ///
  /// 右侧那一簇顶对齐而不是在 112dp 的行高里居中：居中时它上下各留一条用不上的
  /// 空白，顶上去之后那两条空白合成一块，刚好排得下一行 48dp 的封面。
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
              // 底排不看有没有预告封面：档位按钮是这张卡上唯一的档位入口，
              // 首次进入（一首都还没拉到）时也必须在。
              const SizedBox(height: _kNextCoverGap),
              _buildBottomRow(cs, nextTracks),
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

  /// 卡片底排：左边是接下来会放的几首的封面，右端是档位按钮。
  ///
  /// 封面数量按可用宽度算而不是写死：这一排在主封面右侧，能用的宽度是屏宽减掉
  /// 页边距、卡片内边距、主封面和间距之后剩下的部分，再扣掉右端常驻的档位按钮
  /// （连它的对齐补白）和它左边的一份间距——不扣的话窄屏上封面会顶到按钮身上。
  Widget _buildBottomRow(ColorScheme cs, List<KugouSongDetail> nextTracks) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 最后一张右边不需要间距，所以先补一份间距再按「封面 + 间距」整除。
        final slot = _kNextCoverSize + _kNextCoverGap;
        final available =
            constraints.maxWidth -
            _kStationButtonSize -
            _kStationButtonRightInset -
            _kNextCoverGap;
        final fits = ((available + _kNextCoverGap) / slot).floor();
        final count = fits.clamp(0, nextTracks.length);
        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: _kNextCoverGap),
              _buildNextCover(cs, nextTracks[i]),
            ],
            // Spacer 而不是紧挨着排：档位按钮的位置是「卡片右下角」，
            // 不该随预告封面的数量左右浮动。
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: _kStationButtonRightInset),
              child: _buildStationButton(cs),
            ),
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

  /// 收藏按钮：接 [FavoritesProvider]，只订阅当前曲目那一个布尔值，所以点收藏
  /// 不会把带网络封面的整个区块重建一遍。
  ///
  /// 已收藏用 primary（与播放按钮同一个强调色），未收藏用 onSurfaceVariant，
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

  /// 播放按钮：48dp 触达区，不带底色。强调由图标本身承担——用 primary
  /// （onPrimary 是给深色底用的，落在卡面上看不见），尺寸 28 让它压得住旁边
  /// 同排的 24dp 收藏图标。
  Widget _buildPlayButton(
    ColorScheme cs,
    KugouSongDetail? currentTrack,
    bool isPlaying,
  ) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handlePlayPersonalFm(currentTrack),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: M3ELoadingIndicator(color: cs.primary),
                  )
                : Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: cs.primary,
                    size: 28,
                  ),
          ),
        ),
      ),
    );
  }

  /// 封面。走 [CachedNetworkImage]（与发现页其他封面一致），不用 Image.network，
  /// 后者每次重建都重新走网络。
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
      errorWidget: (_, _, _) => _buildCoverPlaceholder(cs, iconSize: iconSize),
    );
  }

  /// 封面占位：用 surfaceContainerHighest 而不是给前景色加透明度，图没加载出来时
  /// 是一块干净的方块，不是一片脏掉的半透明。
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
