import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/core/theme/app_theme.dart';
import 'package:md3music/data/models/song.dart';
import 'package:md3music/modules/personal_fm/personal_fm_section.dart';
import 'package:md3music/providers/favorites_provider.dart';
import 'package:md3music/providers/kugou_provider.dart';
import 'package:md3music/providers/player_provider.dart';
import 'package:md3music/services/kugou_api/kugou_api_client.dart';
import 'package:md3music/services/kugou_api/kugou_models.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 发现页私人 FM 区块的卡片状态与右侧两枚按钮的对齐。
///
/// 覆盖的两个 bug：
/// 1. 电台自己续到下一首时，卡片仍渲染列表第一首（封面/曲名/预告都停在上一首），
///    并且因为「当前曲目 != songs.first」把播放态判成没在放；
/// 2. 档位按钮（40dp）与播放按钮（48dp）都靠右排，圆心差 4dp。
class _FakeKugou extends KugouProvider {
  _FakeKugou(this.songs);

  final List<KugouSongDetail> songs;

  /// 记录 [moveToFirst] 被调用的曲目——用来验证「暂停后点播放」不重排电台列表。
  final List<String> movedToFirst = [];

  @override
  bool get isLoggedIn => true;

  @override
  List<KugouSongDetail> get personalFmSongs => songs;

  @override
  List<Song> get personalFmAsSongs => songs.map((e) => e.toSong()).toList();

  @override
  void moveToFirst(KugouSongDetail song) => movedToFirst.add(song.hash);
}

class _FakePlayer extends PlayerProvider {
  Song? _song;
  bool _playing = false;

  int resumeCalls = 0;
  int pauseCalls = 0;
  int playPlaylistCalls = 0;
  int nextCalls = 0;

  @override
  Song? get currentSong => _song;

  @override
  bool get isPlaying => _playing;

  /// 模拟播放器状态变化（起播 / 续到下一首 / 暂停）。
  void simulate({Song? song, bool playing = false}) {
    _song = song;
    _playing = playing;
    notifyListeners();
  }

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> playOnlinePlaylist(List<Song> songs, int startIndex) async =>
      playPlaylistCalls++;

  @override
  Future<void> next({bool autoPlay = true}) async => nextCalls++;
}

class _FakeFavorites extends FavoritesProvider {
  @override
  Future<void> loadFavorites() async {}

  @override
  bool isFavorite(String songId) => false;
}

const List<KugouSongDetail> _songs = [
  KugouSongDetail(hash: 'h0', songName: 'song 0', artistName: 'a0'),
  KugouSongDetail(hash: 'h1', songName: 'song 1', artistName: 'a1'),
  KugouSongDetail(hash: 'h2', songName: 'song 2', artistName: 'a2'),
  KugouSongDetail(hash: 'h3', songName: 'song 3', artistName: 'a3'),
];

void main() {
  /// [KugouProvider] 的构造函数会发一次 registerDevice 请求。请求前的拦截器要等
  /// 本地 API 服务器就绪（测试里永远不会），那个 `timeout(8s)` 会留下待触发的
  /// timer；直接标记「已就绪」让它跳过等待。
  setUpAll(KugouApiClient.markServerReady);

  /// 启动请求失败后仍会留下 dio 的计时器，不放掉它测试结束时会因 pending timer 失败。
  Future<void> drainProviderStartup(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  Future<void> pumpSection(
    WidgetTester tester, {
    required _FakeKugou kugou,
    required _FakePlayer player,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KugouProvider>.value(value: kugou),
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<FavoritesProvider>(
            create: (_) => _FakeFavorites(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.defaultSeedColor,
              brightness: brightness,
            ),
          ),
          home: const Scaffold(body: PersonalFmSection()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('电台续到列表第二首：卡片换成那一首，播放态不翻成暂停', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final kugou = _FakeKugou(_songs);
    final player = _FakePlayer();
    await pumpSection(tester, kugou: kugou, player: player);

    player.simulate(song: _songs[0].toSong(), playing: true);
    await tester.pump();
    expect(find.text('song 0'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // 电台自己续到下一首：列表顺序不变，只有播放器的当前曲目变了。
    player.simulate(song: _songs[1].toSong(), playing: true);
    await tester.pump();

    expect(find.text('song 1'), findsOneWidget, reason: '卡片该换成正在播的这首');
    expect(find.text('song 0'), findsNothing, reason: '不该停在上一首');
    expect(find.byIcon(Icons.pause), findsOneWidget, reason: '仍在播，按钮是暂停');
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(
      find.byTooltip('播放：song 2'),
      findsOneWidget,
      reason: '预告该从正在播的下一首开始',
    );
    expect(find.byTooltip('播放：song 1'), findsNothing, reason: '正在播的不再是预告');

    await drainProviderStartup(tester);
  });

  testWidgets('暂停在电台某一首上：点播放是 resume，不从头重放也不重排列表', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final kugou = _FakeKugou(_songs);
    final player = _FakePlayer();
    await pumpSection(tester, kugou: kugou, player: player);

    player.simulate(song: _songs[1].toSong(), playing: false);
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(player.resumeCalls, 1);
    expect(player.playPlaylistCalls, 0, reason: '不该把这首从头重放');
    expect(kugou.movedToFirst, isEmpty, reason: '不该重排电台列表');

    await drainProviderStartup(tester);
  });

  testWidgets('播放器不在本电台上：点播放从列表第一首起播', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final kugou = _FakeKugou(_songs);
    final player = _FakePlayer();
    await pumpSection(tester, kugou: kugou, player: player);

    expect(find.text('song 0'), findsOneWidget, reason: '没起播时预告列表第一首');
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(player.playPlaylistCalls, 1);
    expect(player.resumeCalls, 0);

    await drainProviderStartup(tester);
  });

  testWidgets('起播时挂上补货回调，队列快放完能续上（无限电台）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final kugou = _FakeKugou(_songs);
    final player = _FakePlayer();
    await pumpSection(tester, kugou: kugou, player: player);

    expect(player.onPlaylistEnd, isNull, reason: '没起播前不该占着回调槽位');
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(player.onPlaylistEnd, isNotNull, reason: '本区块起播的队列由本区块补货');

    await drainProviderStartup(tester);
  });

  testWidgets('队列已经不是本电台的：补货回调直接返回，不去要新歌', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final kugou = _FakeKugou(_songs);
    final player = _FakePlayer();
    await pumpSection(tester, kugou: kugou, player: player);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    // 用户从别处起播了别的歌，回调还挂着。
    player.simulate(
      song: const Song(
        id: 'other',
        title: '别处的歌',
        artist: 'x',
        album: '',
        duration: Duration(seconds: 60),
      ),
      playing: true,
    );
    await tester.pump();
    await player.onPlaylistEnd!();
    await tester.pump();

    // 走到发请求就会留下 dio 的计时器 / 报错；这里应该在守卫处就返回了。
    expect(kugou.personalFmSongs.length, _songs.length);
    expect(player.nextCalls, 0, reason: '不是本电台的队列，不该推它切歌');

    await drainProviderStartup(tester);
  });

  testWidgets('档位按钮与播放按钮横向居中对齐', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final kugou = _FakeKugou(_songs);
    final player = _FakePlayer();
    await pumpSection(tester, kugou: kugou, player: player);

    player.simulate(song: _songs[0].toSong(), playing: true);
    await tester.pump();

    expect(
      tester.getCenter(find.byTooltip('电台档位：红心')).dx,
      tester.getCenter(find.byIcon(Icons.pause)).dx,
    );

    await drainProviderStartup(tester);
  });

  /// 抽屉展开后露出来的那一层必须同时区别于卡面和页面底色，否则展开看起来
  /// 「没有背景」——深色主题下 surfaceDim 与 surface 同值就踩过这个坑。
  for (final brightness in Brightness.values) {
    testWidgets('抽屉那一层的底色与卡面、页面底色都不同（$brightness）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final kugou = _FakeKugou(_songs);
      final player = _FakePlayer();
      await pumpSection(
        tester,
        kugou: kugou,
        player: player,
        brightness: brightness,
      );

      final section = find.byType(PersonalFmSection);
      final cs = Theme.of(tester.element(section)).colorScheme;
      // 区块里第一个 Material 就是抽屉那一层（卡面是它的子级）。
      final drawerLayer = tester.widget<Material>(
        find.descendant(of: section, matching: find.byType(Material)).first,
      );

      expect(drawerLayer.color, isNotNull);
      expect(drawerLayer.color, isNot(cs.surface), reason: '与页面底色同色就看不出抽屉');
      expect(
        drawerLayer.color,
        isNot(cs.surfaceContainerLow),
        reason: '与卡面同色就没有层级',
      );

      await drainProviderStartup(tester);
    });
  }
}
