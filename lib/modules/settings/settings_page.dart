import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/custom_font_loader.dart';
import '../../core/services/desktop_lyric_service.dart';
import '../../core/services/equalizer_service.dart';
import '../../core/services/lyricon_provider_service.dart';
import '../../core/services/media_notification_service.dart';
import '../../core/services/wakelock_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion_constants.dart';
import '../../data/repositories/settings_repository.dart';
import '../onboarding/onboarding_page.dart';
import '../onboarding/user_agreement_page.dart';
import '../../providers/kugou_provider.dart';
import '../../providers/tab_config_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/kugou_server.dart';
import '../../widgets/apple_lyrics/layout/lyric_preferences.dart';
import '../../widgets/apple_lyrics/layout/lyric_preferences_panel.dart';
import '../../widgets/apple_lyrics/preview/lyrics_preview_page.dart';
import '../../widgets/seed_color_picker.dart';
import 'equalizer_settings_page.dart';
import 'license_view_page.dart';

/// CI compile-time version injection via --dart-define=APP_VERSION=X
/// Fallback display when runtime PackageInfo read fails.
const String kBuildAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '5.0.2',
);

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsRepository _settingsRepository = SettingsRepository();
  ThemeMode _themeMode = ThemeMode.system;
  String _defaultQuality = '128';
  bool _autoReceiveVip = true;
  // 本地 API 服务器重启中（在线音乐区块显示加载态）
  bool _isRestarting = false;
  bool _useDynamicColor = false;
  // Apple Music 风格播放页开关（默认关闭，开启后用 AM 风格 FullPlayer）
  bool _useAmStylePlayer = false;
  bool _useGaussianBlur = true;
  bool _useArtistPhotoBackground = false;
  int _artistPhotoInterval = 15;
  double _artistPhotoOpacity = 0.55;
  bool _useGlowEffect = true;
  bool _useFlowingBackground = true;
  bool _useDuetLayout = false;
  String _appVersion = '';
  // Lyricon 词幕推送相关状态
  bool _lyriconEnabled = false;
  bool _lyriconDisplayTranslation = true;
  bool _lyriconDisplayRoma = false;
  // 同时存在翻译和罗马音时优先推送翻译（开启后 roma 在 Dart 侧被过滤）
  bool _lyriconPreferTranslation = true;
  // 蓝牙歌词开关：通过 MediaSession 元数据替换在车机等设备显示歌词
  bool _bluetoothLyricEnabled = false;
  double _uiScale = 1.0;
  // 暂停淡入淡出开关
  bool _pauseFadeEnabled = false;
  // 播放时保持屏幕常亮开关
  bool _keepScreenOn = false;
  // 歌词双击跳转开关（默认关闭，开启后需双击歌词才能跳转位置）
  bool _lyricDoubleTapToJump = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
    _loadLyriconSettings();
    LyriconProviderService.instance.addListener(_onLyriconStateChanged);
    // 桌面歌词状态变化（设置页开关 / 播放器长按 / 通知栏按钮）→ 刷新 UI
    DesktopLyricService.instance.addListener(_onDesktopLyricChanged);
  }

  @override
  void dispose() {
    LyriconProviderService.instance.removeListener(_onLyriconStateChanged);
    DesktopLyricService.instance.removeListener(_onDesktopLyricChanged);
    super.dispose();
  }

  /// 桌面歌词开关状态变化回调：触发 UI 刷新
  void _onDesktopLyricChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Lyricon 服务状态变化回调：触发 UI 刷新
  void _onLyriconStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 从 SettingsRepository 加载 Lyricon 相关偏好
  Future<void> _loadLyriconSettings() async {
    final enabled = await _settingsRepository.getLyriconEnabled();
    final displayTranslation = await _settingsRepository
        .getLyriconDisplayTranslation();
    final displayRoma = await _settingsRepository.getLyriconDisplayRoma();
    final preferTranslation = await _settingsRepository
        .getLyriconPreferTranslation();
    if (mounted) {
      setState(() {
        _lyriconEnabled = enabled;
        _lyriconDisplayTranslation = displayTranslation;
        _lyriconDisplayRoma = displayRoma;
        _lyriconPreferTranslation = preferTranslation;
      });
    }
    // 同步推送当前已保存的偏好到原生侧（冷启动后 Service 可能已自动恢复，
    // 这里再推一次保证一致；未启用时 SDK 调用会被 try-catch 吞掉）
    if (enabled) {
      try {
        await LyriconProviderService.instance.setDisplayTranslation(
          displayTranslation,
        );
        await LyriconProviderService.instance.setDisplayRoma(displayRoma);
      } catch (_) {}
    }
  }

  /// Lyricon 连接状态 → 中文文案
  String _getLyriconStateText() {
    switch (LyriconProviderService.instance.state) {
      case LyriconConnectionState.disabled:
        return '未启用';
      case LyriconConnectionState.connecting:
        return '连接中...';
      case LyriconConnectionState.connected:
        return '已连接';
      case LyriconConnectionState.disconnected:
        return '已断开';
      case LyriconConnectionState.timeout:
        return '连接超时，请检查 Lyricon / LSPosed 配置';
    }
  }

  Future<void> _loadSettings() async {
    final themeMode = await _settingsRepository.getThemeMode();
    final quality = await _settingsRepository.getDefaultQuality();
    final autoReceiveVip = await _settingsRepository.getAutoReceiveVip();
    // 从 ThemeProvider 同步「使用系统主题色」开关状态
    final useDynamicColor = context.read<ThemeProvider>().useDynamicColor;
    // 从 ThemeProvider 同步「Apple Music 风格播放页」开关状态
    final useAmStylePlayer = context.read<ThemeProvider>().useAmStylePlayer;
    final lyricDoubleTapToJump = context
        .read<ThemeProvider>()
        .lyricDoubleTapToJump;
    final useArtistPhotoBackground = context
        .read<ThemeProvider>()
        .useArtistPhotoBackground;
    final artistPhotoInterval = context
        .read<ThemeProvider>()
        .artistPhotoInterval;
    final artistPhotoOpacity = context.read<ThemeProvider>().artistPhotoOpacity;
    // 从 ThemeProvider 同步 UI 缩放
    final uiScale = context.read<ThemeProvider>().uiScale;
    // 读取蓝牙歌词开关
    final bluetoothLyricEnabled = await _settingsRepository
        .getBluetoothLyricEnabled();
    final pauseFadeEnabled = await _settingsRepository.getPauseFadeEnabled();
    final keepScreenOn = await _settingsRepository.getKeepScreenOn();

    setState(() {
      _themeMode = themeMode;
      _defaultQuality = quality;
      _autoReceiveVip = autoReceiveVip;
      _useDynamicColor = useDynamicColor;
      _useAmStylePlayer = useAmStylePlayer;
      _lyricDoubleTapToJump = lyricDoubleTapToJump;
      _useArtistPhotoBackground = useArtistPhotoBackground;
      _artistPhotoInterval = artistPhotoInterval;
      _artistPhotoOpacity = artistPhotoOpacity;
      _useGaussianBlur = LyricPreferences.instance.useGaussianBlur;
      _useGlowEffect = LyricPreferences.instance.useGlowEffect;
      _useFlowingBackground = LyricPreferences.instance.useFlowingBackground;
      _useDuetLayout = LyricPreferences.instance.useDuetLayout;
      _uiScale = uiScale;
      _bluetoothLyricEnabled = bluetoothLyricEnabled;
      _pauseFadeEnabled = pauseFadeEnabled;
      _keepScreenOn = keepScreenOn;
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = kBuildAppVersion;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final isDark = baseTheme.brightness == Brightness.dark;

    // iOS 语义色（中性色固定，tint 用主题品牌色，浅深色自动适配）
    final bg = isDark ? const Color(0xFF000000) : Colors.white;
    final card = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final label = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final secondary =
        isDark ? const Color(0xFFAEAEB2) : const Color(0xFF8E8E93);
    final separator =
        isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5E5);
    final sliderTrack =
        isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5E5);

    final colorScheme = baseTheme.colorScheme.copyWith(
      surface: card,
      onSurface: label,
      onSurfaceVariant: secondary,
      surfaceContainerLowest: bg,
    );

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: bg,
        dividerColor: separator,
        appBarTheme: baseTheme.appBarTheme.copyWith(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
        ),
        listTileTheme: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: label,
          ),
          subtitleTextStyle: TextStyle(fontSize: 13, color: secondary),
        ),
        sliderTheme: baseTheme.sliderTheme.copyWith(
          activeTrackColor: baseTheme.colorScheme.primary,
          inactiveTrackColor: sliderTrack,
          thumbColor: baseTheme.colorScheme.primary,
        ),
      ),
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _buildSectionLabel('外观', colorScheme),
            _buildSettingsCard(
              _buildAppearanceSection(colorScheme),
              colorScheme,
              separator,
            ),
            _buildSectionLabel('播放页样式', colorScheme),
            _buildSettingsCard(
              _buildPlayerStyleSection(colorScheme),
              colorScheme,
              separator,
            ),
            _buildSectionLabel('歌词', colorScheme),
            _buildSettingsCard(
              _buildLyricSection(colorScheme),
              colorScheme,
              separator,
            ),
            _buildSectionLabel('播放', colorScheme),
            _buildSettingsCard(
              _buildPlaybackSection(colorScheme),
              colorScheme,
              separator,
            ),
            _buildSectionLabel('主页管理', colorScheme),
            _buildSettingsCard(
              _buildTabManagementSection(colorScheme),
              colorScheme,
              separator,
            ),
            _buildSectionLabel('在线音乐', colorScheme),
            _buildSettingsCard(
              _buildOnlineMusicSection(colorScheme),
              colorScheme,
              separator,
            ),
            _buildSectionLabel('缓存与数据', colorScheme),
            _buildSettingsCard(
              _buildCacheSection(colorScheme),
              colorScheme,
              separator,
            ),
            _buildSectionLabel('关于', colorScheme),
            _buildSettingsCard(
              _buildAboutSection(colorScheme),
              colorScheme,
              separator,
            ),
          ],
        ),
      ),
    );
  }

  /// iOS 风格分区小标题：小号灰色字，左缩进与卡片内文字对齐。
  Widget _buildSectionLabel(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// iOS 风格分组卡片：圆角 + 卡片底色 + 行间缩进分隔线。
  Widget _buildSettingsCard(
    List<Widget> rows,
    ColorScheme colorScheme,
    Color separator,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(Divider(
          height: 0.5,
          thickness: 0.5,
          indent: 16,
          color: separator,
        ));
      }
      children.add(rows[i]);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  /// 歌词设置 section：MD3 与 Apple Music 两种风格播放页的歌词
  /// （字号/行间距/字体）均已移入播放页右上角菜单的"歌词显示设置"入口，
  /// 设置页不再保留独立入口。
  List<Widget> _buildLyricSection(ColorScheme colorScheme) {
    return [
        // Lyricon 词幕推送主开关（开关 + 连接状态合并为一行组，避免插入分隔线）
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Lyricon 词幕推送'),
              subtitle: const Text('向 Lyricon 提供方实时推送歌词'),
              value: _lyriconEnabled,
              onChanged: (value) {
                setState(() {
                  _lyriconEnabled = value;
                });
                LyriconProviderService.instance.setEnabled(value);
                _settingsRepository.setLyriconEnabled(value);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _getLyriconStateText(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        // 次级开关：翻译歌词（主开关关闭时禁用）
        SwitchListTile(
          title: const Text('翻译歌词'),
          subtitle: const Text('在 Lyricon 设备上显示翻译文本'),
          value: _lyriconDisplayTranslation,
          onChanged: _lyriconEnabled
              ? (value) {
                  setState(() {
                    _lyriconDisplayTranslation = value;
                  });
                  LyriconProviderService.instance.setDisplayTranslation(value);
                  _settingsRepository.setLyriconDisplayTranslation(value);
                }
              : null,
        ),
        // 次级开关：罗马音歌词（主开关关闭时禁用）
        SwitchListTile(
          title: const Text('罗马音歌词'),
          subtitle: const Text('在 Lyricon 设备上显示罗马音/音译文本'),
          value: _lyriconDisplayRoma,
          onChanged: _lyriconEnabled
              ? (value) {
                  setState(() {
                    _lyriconDisplayRoma = value;
                  });
                  LyriconProviderService.instance.setDisplayRoma(value);
                  _settingsRepository.setLyriconDisplayRoma(value);
                }
              : null,
        ),
        // 次级开关：同时存在翻译和罗马音时二选一推送
        // 仅当主开关开启时可用：
        // - 开启：保留翻译，丢弃罗马音
        // - 关闭：保留罗马音，丢弃翻译
        SwitchListTile(
          title: const Text('优先翻译（同时存在时）'),
          subtitle: const Text('一行同时有翻译和罗马音时，开启推送翻译、关闭推送罗马音'),
          value: _lyriconPreferTranslation,
          onChanged: _lyriconEnabled
              ? (value) async {
                  setState(() {
                    _lyriconPreferTranslation = value;
                  });
                  await _settingsRepository.setLyriconPreferTranslation(value);
                  // 偏好变化后重新推送当前歌曲，让过滤逻辑立即生效
                  try {
                    await LyriconProviderService.instance.repushLastSong();
                  } catch (_) {}
                }
              : null,
        ),
        // 解锁桌面歌词：悬浮窗锁定后点击穿透（无法点击自身解锁），
        // 且无法下拉通知栏时，可在此一键解锁悬浮窗。
        SwitchListTile(
          title: const Text('解锁桌面歌词'),
          subtitle: Text(
            DesktopLyricService.instance.locked
                ? '悬浮窗已锁定（点击穿透），点按此开关解除锁定'
                : '悬浮窗未锁定，此开关用于锁定后无法点击时解除锁定',
          ),
          value: DesktopLyricService.instance.locked,
          onChanged: (_) async {
            await DesktopLyricService.instance.unlock();
          },
        ),
        // 蓝牙歌词：通过 MediaSession 元数据替换在车机等设备显示歌词
        SwitchListTile(
          title: const Text('蓝牙歌词'),
          subtitle: const Text('通过蓝牙在汽车主机等设备显示当前歌词（标题显示歌词，作者显示「作者 - 标题」）'),
          value: _bluetoothLyricEnabled,
          onChanged: (value) async {
            setState(() => _bluetoothLyricEnabled = value);
            await _settingsRepository.setBluetoothLyricEnabled(value);
            // 同步到歌词服务（启停定时器）和原生端（元数据替换开关）
            DesktopLyricService.instance.setBluetoothLyricEnabled(value);
            MediaNotificationService.setBluetoothLyricEnabled(value);
          },
        ),
    ];
  }

  /// 歌词字体来源中文标签（用于"歌词字体"ListTile 的 subtitle）。
  String _lyricFontSourceLabel(LyricFontSource source) {
    switch (source) {
      case LyricFontSource.system:
        return '系统默认（手机字体优先）';
      case LyricFontSource.bundled:
        return '内置 SimHei';
      case LyricFontSource.custom:
        return '自定义字体';
    }
  }

  /// 弹出歌词字体来源选择面板。
  /// 与全局字体选择解耦：歌词字体独立配置，仅作用于歌词渲染路径。
  /// 切换字体会触发 LyricPreferences.notifyListeners，
  /// AppleLyricsView 监听到后会失效行高缓存 + 模糊图片缓存并重算。
  void _showLyricFontSourceSheet(LyricPreferences prefs) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final current = prefs.fontSource;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '歌词字体来源',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  current == LyricFontSource.system
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: const Text('系统默认'),
                subtitle: const Text('使用手机系统字体（推荐）'),
                onTap: () async {
                  await prefs.setFontSource(LyricFontSource.system);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(
                  current == LyricFontSource.bundled
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: const Text('内置 SimHei'),
                subtitle: const Text('使用打包的黑体字体'),
                onTap: () async {
                  await prefs.setFontSource(LyricFontSource.bundled);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(
                  current == LyricFontSource.custom
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: const Text('自定义字体'),
                subtitle: Text(
                  prefs.customFontPath == null
                      ? '点击从设备选择 .ttf / .otf 文件'
                      : '已加载：${prefs.customFontPath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  // 立即关闭面板，避免文件选择器与 BottomSheet 重叠
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _pickAndApplyLyricCustomFont(prefs);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 调用原生 SAF 文件选择器为歌词选字体文件，成功后保存并应用。
  Future<void> _pickAndApplyLyricCustomFont(LyricPreferences prefs) async {
    final path = await CustomFontLoader.pickFontFile();
    if (path == null) {
      // 用户取消
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未选择字体文件'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 先保存路径并加载字体（_tryLoadCustomFont 内部会注册 FontLoader）
    await prefs.setCustomFontPath(path);
    // 再切换来源为 custom（即使加载失败也切换，UI 自然降级为系统字体）
    await prefs.setFontSource(LyricFontSource.custom);
    if (!mounted) return;
    final loaded = prefs.effectiveFontFamily != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loaded ? '已应用自定义字体到歌词' : '字体加载失败，已降级为系统字体'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Widget> _buildAppearanceSection(ColorScheme colorScheme) {
    final themeProvider = context.read<ThemeProvider>();
    // 仅 ThemeMode.light 时禁用 OLED 开关；dark 与 system 均可勾选。
    // system 模式下勾选后，等系统切到深色时 darkTheme 自动应用纯黑（MaterialApp 机制）。
    final canToggleOled = _themeMode != ThemeMode.light;
    return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('主题模式', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (modes) {
                    final mode = modes.first;
                    setState(() {
                      _themeMode = mode;
                    });
                    context.read<ThemeProvider>().setThemeMode(mode);
                    _settingsRepository.setThemeMode(mode);
                  },
                ),
              ),
            ],
          ),
        ),
        // app全局字体入口：点击弹出三选一面板（系统 / 内置 SimHei / 自定义 TTF）
        // 选择"自定义"时打开 Android SAF 文件选择器选 .ttf/.otf 文件
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('app全局字体'),
          subtitle: Text(_getFontSourceLabel(themeProvider.fontSource)),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _showFontSourceSheet(themeProvider),
        ),
        // 主题色入口：点击弹出 8 色预设面板。
        // 系统色开启时用 IgnorePointer 禁用点击（不灰显，色块仍显示当前 effectiveSeedColor）。
        IgnorePointer(
          ignoring: themeProvider.useDynamicColor,
          child: ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('主题色'),
            subtitle: Text(
              themeProvider.useDynamicColor ? '跟随系统壁纸取色' : '手动选择种子色',
            ),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: themeProvider.effectiveSeedColor,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outline, width: 1.5),
              ),
            ),
            onTap: () => _showSeedColorPicker(themeProvider),
          ),
        ),
        SwitchListTile(
          title: const Text('使用系统主题色'),
          subtitle: const Text('跟随系统壁纸取色（Android 12+ 莫奈色，HCT 多点量化）'),
          value: _useDynamicColor,
          onChanged: (v) {
            setState(() => _useDynamicColor = v);
            context.read<ThemeProvider>().setUseDynamicColor(v);
          },
        ),
        // OLED 纯黑开关：light 模式禁用；dark 与 system 可勾选。
        // system 模式下勾选后，系统切深色时自动生效，切浅色时不影响 lightTheme。
        SwitchListTile(
          title: const Text('OLED 纯黑深色'),
          subtitle: const Text('将深色背景改为纯黑（仅深色模式生效，节省 OLED 电量）'),
          value: themeProvider.useOledBlack,
          onChanged: canToggleOled
              ? (v) => themeProvider.setUseOledBlack(v)
              : null,
        ),
        // UI 缩放滑块（滑块 + 说明合并为一行组，避免卡片插入分隔线）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.format_size, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                      ),
                      child: Slider(
                        value: _uiScale,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: '${_uiScale.toStringAsFixed(1)}x',
                        onChanged: (v) {
                          setState(() => _uiScale = v);
                          HapticFeedback.lightImpact();
                        },
                        onChangeEnd: (v) {
                          context.read<ThemeProvider>().setUiScale(v);
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${_uiScale.toStringAsFixed(1)}x',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '调整全局界面大小（歌词界面不受影响）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  /// 播放页样式 section：播放器风格卡片选择 + 视觉特效开关。
  List<Widget> _buildPlayerStyleSection(ColorScheme colorScheme) {
    return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _buildStyleCards(colorScheme),
        ),
        SwitchListTile(
          title: const Text('歌词双击跳转'),
          subtitle: const Text('开启后需双击歌词行才能跳转播放位置'),
          value: _lyricDoubleTapToJump,
          onChanged: (v) {
            setState(() => _lyricDoubleTapToJump = v);
            context.read<ThemeProvider>().setLyricDoubleTapToJump(v);
          },
        ),
        SwitchListTile(
          title: const Text('歌手写真背景轮播'),
          subtitle: const Text('MD3 风格播放页显示歌手写真背景（仅在线歌曲）'),
          value: _useArtistPhotoBackground,
          onChanged: !_useAmStylePlayer
              ? (v) {
                  setState(() => _useArtistPhotoBackground = v);
                  context.read<ThemeProvider>().setUseArtistPhotoBackground(v);
                }
              : null,
        ),
        if (_useArtistPhotoBackground && !_useAmStylePlayer)
          ListTile(
            title: const Text('轮播间隔'),
            subtitle: Text('每 $_artistPhotoInterval 秒切换'),
            trailing: DropdownButton<int>(
              value: _artistPhotoInterval,
              items: [5, 10, 15, 20, 30, 45, 60]
                  .map((s) => DropdownMenuItem(value: s, child: Text('$s 秒')))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _artistPhotoInterval = v);
                context.read<ThemeProvider>().setArtistPhotoInterval(v);
              },
            ),
          ),
        if (_useArtistPhotoBackground && !_useAmStylePlayer)
          ListTile(
            title: const Text('写真背景透明度'),
            subtitle: Slider(
              value: _artistPhotoOpacity,
              min: 0.0,
              max: 0.95,
              divisions: 19,
              label: '${(_artistPhotoOpacity * 100).round()}%',
              onChanged: (v) {
                setState(() => _artistPhotoOpacity = v);
                context.read<ThemeProvider>().setArtistPhotoOpacity(v);
              },
            ),
            trailing: Text('${(_artistPhotoOpacity * 100).round()}%'),
          ),
        SwitchListTile(
          title: const Text('歌词高斯模糊'),
          subtitle: const Text('开启为高斯模糊渐变，高功耗，关闭为 alpha 淡出'),
          value: _useGaussianBlur,
          onChanged: _useAmStylePlayer
              ? (v) {
                  setState(() => _useGaussianBlur = v);
                  LyricPreferences.instance.setUseGaussianBlur(v);
                }
              : null,
        ),
        SwitchListTile(
          title: const Text('歌词辉光效果'),
          subtitle: const Text('持续时间较长的字触发发光缩放效果'),
          value: _useGlowEffect,
          onChanged: _useAmStylePlayer
              ? (v) {
                  setState(() => _useGlowEffect = v);
                  LyricPreferences.instance.setUseGlowEffect(v);
                }
              : null,
        ),
        SwitchListTile(
          title: const Text('背景动态流光'),
          subtitle: const Text('专辑封面色彩流动效果,高功耗 '),
          value: _useFlowingBackground,
          onChanged: _useAmStylePlayer
              ? (v) {
                  setState(() => _useFlowingBackground = v);
                  LyricPreferences.instance.setUseFlowingBackground(v);
                }
              : null,
        ),
        SwitchListTile(
          title: const Text('男女对唱歌词优化'),
          subtitle: const Text('剔除「男/女/合」标记，男左女右、合唱居中'),
          value: _useDuetLayout,
          onChanged: _useAmStylePlayer
              ? (v) {
                  setState(() => _useDuetLayout = v);
                  LyricPreferences.instance.setUseDuetLayout(v);
                }
              : null,
        ),
    ];
  }

  /// 弹出 8 色预设种子色选择面板。
  /// 选择后调用 ThemeProvider.setManualSeedColor 持久化并立即生效。
  void _showSeedColorPicker(ThemeProvider themeProvider) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SeedColorPicker(
        currentColor:
            themeProvider.manualSeedColor ?? AppTheme.defaultSeedColor,
        onSelected: (color) {
          themeProvider.setManualSeedColor(color);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  /// 字体来源中文标签。
  String _getFontSourceLabel(FontSource source) {
    switch (source) {
      case FontSource.system:
        return '系统默认（手机字体优先）';
      case FontSource.bundled:
        return '内置 SimHei';
      case FontSource.custom:
        return '自定义字体';
    }
  }

  /// 弹出字体来源选择面板。
  ///
  /// 三个选项：
  /// - 系统默认：UI 走系统字体链（Roboto + Noto Sans CJK 等）
  /// - 内置 SimHei：使用打包的 assets/fonts/simhei.ttf
  /// - 自定义字体：通过 Android SAF 选择 .ttf/.otf 文件，
  ///   原生端拷贝到 filesDir/fonts/user_custom.ttf，Dart 端用 FontLoader 注册
  void _showFontSourceSheet(ThemeProvider themeProvider) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final current = themeProvider.fontSource;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'app全局字体来源',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  current == FontSource.system
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: const Text('系统默认'),
                subtitle: const Text('使用手机系统字体（推荐）'),
                onTap: () async {
                  await themeProvider.setFontSource(FontSource.system);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(
                  current == FontSource.bundled
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: const Text('内置 SimHei'),
                subtitle: const Text('使用打包的黑体字体'),
                onTap: () async {
                  await themeProvider.setFontSource(FontSource.bundled);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(
                  current == FontSource.custom
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: const Text('自定义字体'),
                subtitle: Text(
                  themeProvider.customFontPath == null
                      ? '点击从设备选择 .ttf / .otf 文件'
                      : '已加载：${themeProvider.customFontPath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  // 立即关闭面板，避免文件选择器与 BottomSheet 重叠
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _pickAndApplyCustomFont(themeProvider);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 调用原生 SAF 文件选择器让用户选择字体文件，成功后保存并应用。
  ///
  /// 选择流程：
  /// 1. CustomFontLoader.pickFontFile() 打开系统文件选择器
  /// 2. 原生端把选中文件拷贝到 filesDir/fonts/user_custom.ttf，返回路径
  /// 3. themeProvider.setCustomFontPath(path) 持久化路径 + 立即 FontLoader 注册
  /// 4. themeProvider.setFontSource(FontSource.custom) 切换为 custom 模式
  ///
  /// 失败处理：用户取消（path=null）→ 不切换，弹提示；
  /// 加载失败 → effectiveFontFamily 自动降级为 null（system 行为），弹错误提示。
  Future<void> _pickAndApplyCustomFont(ThemeProvider themeProvider) async {
    final path = await CustomFontLoader.pickFontFile();
    if (path == null) {
      // 用户取消
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未选择字体文件'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 先保存路径并加载字体（_tryLoadCustomFont 内部会注册 FontLoader）
    await themeProvider.setCustomFontPath(path);
    // 再切换来源为 custom（即使加载失败也切换，UI 自然降级为系统字体）
    await themeProvider.setFontSource(FontSource.custom);
    if (!mounted) return;
    final loaded = themeProvider.effectiveFontFamily != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loaded ? '已应用自定义字体' : '字体加载失败，已降级为系统字体'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Widget> _buildPlaybackSection(ColorScheme colorScheme) {
    return [
        ListTile(
          title: const Text('默认音质'),
          subtitle: Text(_getQualityLabel(_defaultQuality)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showQualityDialog(),
        ),
        ListenableBuilder(
          listenable: EqualizerService.instance,
          builder: (context, _) {
            final eq = EqualizerService.instance;
            return ListTile(
              leading: Icon(
                Icons.graphic_eq,
                color: eq.enabled
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: const Text('均衡器'),
              subtitle: Text(eq.enabled ? '已开启 · ${eq.currentPreset}' : '未开启'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EqualizerSettingsPage(),
                ),
              ),
            );
          },
        ),
        SwitchListTile(
          title: const Text('自动领取VIP'),
          subtitle: const Text('每次启动自动领取每日VIP（需要登录）'),
          value: _autoReceiveVip,
          onChanged: (value) {
            setState(() {
              _autoReceiveVip = value;
            });
            _settingsRepository.setAutoReceiveVip(value);
          },
        ),
        SwitchListTile(
          title: const Text('暂停淡入淡出'),
          subtitle: const Text('暂停/播放时音量平滑过渡，避免突然出声'),
          value: _pauseFadeEnabled,
          onChanged: (value) {
            setState(() {
              _pauseFadeEnabled = value;
            });
            _settingsRepository.setPauseFadeEnabled(value);
          },
        ),
        SwitchListTile(
          title: const Text('播放时保持屏幕常亮'),
          subtitle: const Text('播放歌曲或 MV 时屏幕不会自动息屏'),
          value: _keepScreenOn,
          onChanged: (value) {
            setState(() {
              _keepScreenOn = value;
            });
            _settingsRepository.setKeepScreenOn(value);
            WakelockService.instance.setSettingEnabled(value);
          },
        ),
    ];
  }

  /// 主页管理 section：Tab 显示/隐藏开关 + 拖拽排序
  List<Widget> _buildTabManagementSection(ColorScheme colorScheme) {
    return [
        ListTile(
          leading: const Icon(Icons.tab),
          title: const Text('主页 Tab 管理'),
          subtitle: const Text('显示/隐藏、拖拽排序'),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _showTabManagementSheet(),
        ),
    ];
  }

  /// 弹出 Tab 管理面板：支持拖拽排序 + 显示/隐藏开关。
  void _showTabManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _TabManagementPanel(),
    );
  }

  List<Widget> _buildOnlineMusicSection(ColorScheme colorScheme) {
    return [
        // 本地数据接口（单元格 + 说明合并为一行组，避免插入分隔线）
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.dns, color: colorScheme.primary),
              title: const Text('本地数据接口'),
              subtitle: Text('端口：${KugouApiServer.currentPort}'),
              trailing: _isRestarting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '运行中',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
              onTap: _isRestarting ? null : _confirmRestartServer,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Text(
                '本地 Rust 服务器运行中，推荐/排行/搜索/播放/登录等数据接口均通过本地处理（点击上方可重启）',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
    ];
  }

  /// 询问是否重启本地 API 服务器，确认后重启并更新端口展示。
  Future<void> _confirmRestartServer() async {
    final port = KugouApiServer.currentPort;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重启本地 API 服务器'),
        content: Text('确定要重启本地 Rust API 服务器吗？\n当前端口：$port\n重启后将重新分配随机端口。\n如果你遇到了玄学问题，那就重启一下试试吧（）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重启'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRestarting = true);
    try {
      final ok = await KugouApiServer.restart();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? '已重启，新端口：${KugouApiServer.currentPort}'
              : '重启失败，服务器未就绪'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重启失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRestarting = false);
    }
  }

  List<Widget> _buildCacheSection(ColorScheme colorScheme) {
    return [
        ListTile(
          title: const Text('清除缓存'),
          leading: Icon(Icons.delete_outline, color: colorScheme.error),
          onTap: () => _showClearCacheDialog(),
        ),
        ListTile(
          title: const Text('数据迁移（修复数据混乱）'),
          subtitle: const Text('如果看到其他用户的信息，执行此操作'),
          leading: Icon(Icons.bug_report, color: colorScheme.tertiary),
          onTap: () => _showDataMigrationDialog(),
        ),
    ];
  }

  Future<void> _showDataMigrationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔧 数据迁移'),
        content: const Text(
          '此操作将清除旧版本的登录数据，修复可能的数据混乱问题。\n\n'
          '执行后需要重新登录。\n\n'
          '是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('执行'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final prefs = await SharedPreferences.getInstance();

        // 清除旧版本的全局键
        await prefs.remove('kugou_token');
        await prefs.remove('kugou_userid');
        await prefs.remove('kugou_vip_token');
        await prefs.remove('kugou_dfid');
        await prefs.remove('kugou_current_userid');

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 数据迁移完成，请重新登录'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );

        // 退出登录
        context.read<KugouProvider>().logout();

        // 返回上一页
        Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 数据迁移失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<Widget> _buildAboutSection(ColorScheme colorScheme) {
    return [
        ListTile(
          title: const Text('新手教程'),
          subtitle: const Text('重新查看功能引导'),
          leading: const Icon(Icons.school_outlined),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => OnboardingPage(isReview: true)),
            );
          },
        ),
        ListTile(
          title: const Text('用户协议'),
          subtitle: const Text('查看用户协议全文'),
          leading: const Icon(Icons.handshake_outlined),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserAgreementPage(
                  isFirstLaunch: false,
                  isReview: true,
                  onAgreed: () => Navigator.of(context).pop(),
                ),
              ),
            );
          },
        ),
        ListTile(
          title: const Text('免责声明'),
          subtitle: const Text('查看本软件免责声明'),
          leading: const Icon(Icons.gavel_outlined),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => UserAgreementPage.showDisclaimerDialog(context),
        ),
        ListTile(
          title: const Text('应用版本'),
          subtitle: Text(_appVersion.isEmpty ? kBuildAppVersion : _appVersion),
          leading: const Icon(Icons.info_outline),
        ),
        ListTile(
          title: const Text('更新最新版本'),
          subtitle: const Text('https://github.com/zzyoxml/md3Music/releases'),
          leading: const Icon(Icons.system_update_outlined),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _openReleasesUrl(),
        ),
        ListTile(
          title: const Text('开源许可'),
          leading: const Icon(Icons.description_outlined),
          onTap: () {
            showLicensePage(
              context: context,
              applicationName: 'MD3Music',
              applicationVersion: _appVersion.isEmpty
                  ? kBuildAppVersion
                  : _appVersion,
            );
          },
        ),
        ListTile(
          title: const Text('本应用许可证'),
          subtitle: const Text('GNU AGPL-3.0'),
          leading: const Icon(Icons.balance_outlined),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LicenseViewPage()),
            );
          },
        ),
        // 开发者入口：跳转 Apple Music 风格歌词渲染预览页（Task 22.5）
        ListTile(
          title: const Text('歌词预览（开发）'),
          subtitle: const Text('Apple Music 风格歌词渲染调试'),
          leading: const Icon(Icons.lyrics_outlined),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LyricsPreviewPage()),
            );
          },
        ),
    ];
  }

  Future<void> _openReleasesUrl() async {
    const url = 'https://github.com/zzyoxml/md3Music/releases';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _getQualityLabel(String quality) {
    switch (quality) {
      case 'standard':
      case '128':
        return '标准 128k';
      case 'hq':
        return '高品质 320k';
      case 'sq':
      case 'flac':
        return '无损 FLAC';
      case 'hires':
      case 'high':
        return 'Hi-Res 无损';
      default:
        return '高品质 320k';
    }
  }

  void _showQualityDialog() {
    final qualities = [
      ('128', '标准 128k'),
      ('hq', '高品质 320k'),
      ('flac', '无损 FLAC'),
      ('high', 'Hi-Res 无损'),
    ];

    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('默认音质'),
          children: qualities.map((q) {
            return SimpleDialogOption(
              onPressed: () {
                setState(() {
                  _defaultQuality = q.$1;
                });
                _settingsRepository.setDefaultQuality(q.$1);
                Navigator.pop(context);
              },
              child: Text(
                q.$2,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _defaultQuality == q.$1
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除缓存'),
          content: const Text('确定要清除所有缓存数据吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _doClearCache();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _doClearCache() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 1. 清图片缓存
      await DefaultCacheManager().emptyCache();
      // 2. 清 app 临时目录（Android 系统设置里的"清除缓存"也指这个）
      try {
        final dir = await getTemporaryDirectory();
        if (dir.existsSync()) {
          for (final entity in dir.listSync()) {
            try {
              if (entity is Directory) {
                entity.deleteSync(recursive: true);
              } else {
                entity.deleteSync();
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
      // 3. 清 KugouProvider 内存
      if (mounted) {
        context.read<KugouProvider>().clearMemoryCache();
      }
      // 4. 重置发现页日期标志
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('discover_last_date');
      _settingsRepository.setCacheSize(0);
    } catch (e) {
      debugPrint('Clear cache error: $e');
    }
    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('已清除缓存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 播放器风格卡片选择
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildStyleCards(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStyleCard(
          colorScheme: colorScheme,
          title: 'MD3Music',
          subtitle: 'Material 3 风格',
          isSelected: !_useAmStylePlayer,
          onTap: () {
            setState(() => _useAmStylePlayer = false);
            context.read<ThemeProvider>().setUseAmStylePlayer(false);
          },
          preview: _SettingsMd3StylePreview(colorScheme: colorScheme),
        ),
        const SizedBox(width: 16),
        _buildStyleCard(
          colorScheme: colorScheme,
          title: 'Apple Music',
          subtitle: '模糊封面 + 逐字歌词',
          isSelected: _useAmStylePlayer,
          onTap: () {
            setState(() => _useAmStylePlayer = true);
            context.read<ThemeProvider>().setUseAmStylePlayer(true);
          },
          preview: _SettingsAmStylePreview(colorScheme: colorScheme),
        ),
      ],
    );
  }

  Widget _buildStyleCard({
    required ColorScheme colorScheme,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required Widget preview,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: M3ExpressiveMotion.defaultDuration,
          curve: M3ExpressiveMotion.expressiveEasing,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isSelected ? 2.5 : 1,
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: preview,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 6),
                Icon(Icons.check_circle, size: 20, color: colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab 管理面板：支持拖拽排序 + 显示/隐藏开关。
///
/// “我的”页面不允许隐藏（保证用户始终有入口进入设置/登录）。
class _TabManagementPanel extends StatelessWidget {
  const _TabManagementPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabConfig = context.watch<TabConfigProvider>();
    final allTabs = tabConfig.allTabs;
    final hiddenTabs = tabConfig.hiddenTabs;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '主页 Tab 管理',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => tabConfig.resetToDefault(),
                    child: const Text('重置'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '拖拽排序、开关显示/隐藏（“我的”不可隐藏）',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: allTabs.length,
                onReorder: (oldIndex, newIndex) {
                  tabConfig.reorderTabs(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final tab = allTabs[index];
                  final isHidden = hiddenTabs.contains(tab.id);
                  return ListTile(
                    key: ValueKey(tab.id),
                    leading: Icon(
                      _getTabIcon(tab.id),
                      color: isHidden
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.primary,
                    ),
                    title: Text(
                      tab.label,
                      style: TextStyle(
                        color: isHidden ? colorScheme.onSurfaceVariant : null,
                      ),
                    ),
                    subtitle: !tab.isRemovable
                        ? Text(
                            '必显示',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.isRemovable)
                          Switch(
                            value: !isHidden,
                            onChanged: (_) {
                              tabConfig.toggleTabVisibility(tab.id);
                            },
                          ),
                        Icon(
                          Icons.drag_handle,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTabIcon(String tabId) {
    switch (tabId) {
      case 'discover':
        return Icons.explore;
      case 'coverflow':
        // 与主页 tab 图标保持一致（见 app.dart 的 coverflow case）
        return Icons.album;
      case 'library':
        return Icons.library_music;
      case 'favorites':
        return Icons.favorite;
      case 'fm':
        return Icons.radio;
      case 'search':
        return Icons.search;
      case 'charts':
        return Icons.leaderboard;
      case 'recognition':
        return Icons.mic;
      case 'user':
        return Icons.person;
      default:
        return Icons.circle;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// 播放器风格预览组件
// ─────────────────────────────────────────────────────────────────────

/// MD3Music 风格播放器预览：简洁的 Material 3 卡片布局。
class _SettingsMd3StylePreview extends StatelessWidget {
  final ColorScheme colorScheme;

  const _SettingsMd3StylePreview({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colorScheme.surface,
      child: Column(
        children: [
          // 顶栏
          Container(
            height: 28,
            color: colorScheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const Spacer(),
                Icon(
                  Icons.more_horiz,
                  size: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          // 封面
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.music_note,
                          size: 32,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 5,
                    width: 55,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    height: 4,
                    width: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(
                        Icons.skip_previous,
                        size: 16,
                        color: colorScheme.onSurface,
                      ),
                      Icon(
                        Icons.play_arrow,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      Icon(
                        Icons.skip_next,
                        size: 16,
                        color: colorScheme.onSurface,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Apple Music 风格播放器预览：模糊封面背景 + 逐字歌词。
class _SettingsAmStylePreview extends StatelessWidget {
  final ColorScheme colorScheme;

  const _SettingsAmStylePreview({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.primary.withValues(alpha: 0.6),
            colorScheme.surface,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: colorScheme.onSurface,
                ),
                const Spacer(),
                Icon(Icons.more_horiz, size: 12, color: colorScheme.onSurface),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLyricBar(45, colorScheme.onSurface, 0.2),
                  const SizedBox(height: 5),
                  _buildLyricBar(70, colorScheme.primary, 1.0),
                  const SizedBox(height: 5),
                  _buildLyricBar(40, colorScheme.onSurface, 0.2),
                  const SizedBox(height: 5),
                  _buildLyricBar(30, colorScheme.onSurface, 0.1),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.music_note,
                    size: 12,
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 4,
                        width: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 3,
                        width: 26,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.play_arrow, size: 16, color: colorScheme.onSurface),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricBar(double width, Color color, double opacity) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 6,
        width: width,
        decoration: BoxDecoration(
          color: color.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
