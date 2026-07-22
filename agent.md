# MD3Music - Agent Context

## Project Overview

MD3Music 是一个基于 Flutter 的 Material Design 3 音乐播放器，使用酷狗音乐 API 作为音乐源。项目采用**本地 + 云端混合架构**：App 内置 Node.js 服务器处理所有本地 API 请求，仅登录/同步功能走云端。

- **版本**: 3.3.0+10
- **Flutter SDK**: ^3.12.0
- **平台**: Android (主), Web (实验性)
- **License**: MIT

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MD3Music App                         │
│  ┌─────────────────────┐  ┌────────────────────────┐  │
│  │   Flutter UI (Dart) │  │  嵌入式 Node.js 服务器  │  │
│  └──────────┬──────────┘  └──────────┬─────────────┘  │
│             └──────────┬───────────────┘                │
│             ┌──────────▼───────────────┐                │
│             │   本地数据 / 缓存 (SQLite)│                │
│             └──────────────────────────┘                │
└─────────────────────────────────────────────────────────┘
                           │ 仅登录/同步
                           ▼
              ┌────────────────────────────┐
              │   云端 API (networkapi)     │
              │   115.29.236.96:5621       │
              └────────────────────────────┘
```

### 核心特点
- **嵌入式 Node.js**: App 启动时自动启动本地服务器 (127.0.0.1:8080)，通过 `nodejs-mobile` 实现
- **流量优化**: 仅登录/同步走云端，月流量 < 100MB
- **多架构支持**: armeabi-v7a (32位), arm64-v8a (64位), x86_64 (模拟器)

## Tech Stack

| 类别 | 技术 |
|------|------|
| UI 框架 | Flutter 3.12+ |
| 状态管理 | Provider |
| 音频播放 | just_audio |
| 网络请求 | Dio |
| 本地存储 | SharedPreferences + SQLite (sqflite) |
| 图片缓存 | cached_network_image + flutter_cache_manager |
| 嵌入式服务器 | nodejs-mobile (Node.js 18) |
| 服务器打包 | esbuild |
| 音乐源 | 酷狗音乐 API |

## Project Structure

```
md3Music/
├── lib/                        # Flutter 应用代码
│   ├── main.dart               # 应用入口
│   ├── app.dart                # 主应用组件 (MultiProvider + MaterialApp)
│   ├── core/                   # 核心模块
│   │   ├── layout/             # 响应式布局 (ResponsiveScaffold)
│   │   ├── services/           # 平台服务 (Audio, MediaNotification, DesktopLyric, Lyricon)
│   │   ├── theme/              # 主题配置 (AppTheme, SeedColor)
│   │   └── utils/              # 工具类 (Permissions)
│   ├── data/                   # 数据层
│   │   ├── models/             # 数据模型 (Song, Album, Artist, Playlist, DownloadTask)
│   │   └── repositories/       # 数据仓库 (Favorites, History, Downloads, Settings, LocalMusic, CollectedPlaylist)
│   ├── modules/                # 功能模块
│   │   ├── discover/           # 发现页
│   │   ├── charts/             # 排行榜
│   │   ├── player/             # 播放器 (FullPlayer, MiniPlayer, Lyrics, Comments)
│   │   ├── search/             # 搜索
│   │   ├── user/               # 用户中心 (Favorites, Downloads, History)
│   │   ├── library/            # 音乐库 (Songs, Albums, Artists)
│   │   ├── playlist/           # 歌单详情
│   │   ├── album/              # 专辑详情
│   │   ├── personal_fm/        # 私人 FM
│   │   ├── login/              # 登录
│   │   └── settings/           # 设置
│   ├── providers/              # 状态管理 (Player, Theme, Kugou, Favorites, Downloads, Library, PlaylistCollection)
│   ├── services/               # API 服务
│   │   ├── nodejs_server.dart  # Node.js 服务器管理
│   │   ├── kugou_api/          # 酷狗 API 客户端
│   │   ├── download_manager.dart
│   │   └── metadata_writer.dart
│   └── widgets/                # 公共组件
│       ├── apple_lyrics/       # Apple 风格歌词组件 (解析器/渲染器/动画/布局)
│       ├── player_playlist_dialog.dart
│       ├── song_list_item.dart
│       ├── album_card.dart
│       └── artist_tile.dart
├── kugou_api_server/           # 嵌入式 Node.js API 服务器
│   ├── index.js                # 入口
│   ├── app.js                  # 启动逻辑
│   ├── server.js               # HTTP 服务器
│   ├── module/                 # API 模块 (音频/评论/歌手/专辑/登录/验证码等)
│   ├── util/                   # 工具类 (请求/加密/缓存/配置)
│   └── package.json
├── networkapi/                 # 云端登录 API (Node.js)
│   ├── server.js
│   ├── module/                 # 登录/用户/VIP 相关模块
│   └── util/
├── assets/                     # 资源文件
│   ├── images/
│   ├── fonts/                  # SimHei 字体
│   └── nodejs-project/        # 打包后的服务器代码 (server_bundle.js)
├── scripts/                    # 构建脚本
├── android/                    # Android 平台配置
├── web/                        # Web 平台配置
└── pubspec.yaml
```

## Key Files

### Entry Points
- `lib/main.dart` - 应用入口，启动 Node.js 服务器，请求权限，初始化服务
- `lib/app.dart` - MaterialApp + MultiProvider，路由定义，响应式布局

### State Management (Provider)
- `PlayerProvider` - 播放器状态（播放/暂停/进度/播放列表/循环模式/音质）
- `ThemeProvider` - 主题模式 + SeedColor + OLED 黑色
- `KugouProvider` - 酷狗 API 数据（搜索/排行榜/每日推荐）
- `FavoritesProvider` - 收藏管理
- `DownloadsProvider` - 下载管理
- `LibraryProvider` - 本地音乐库
- `PlaylistCollectionNotifier` - 收藏歌单变更广播

### Data Models
- `Song` - 歌曲 (id, title, artist, album, duration, url, localPath, artworkUri, isOnline, quality)
- `Album` - 专辑
- `Artist` - 歌手
- `Playlist` - 歌单
- `DownloadTask` - 下载任务

### Services
- `NodeJsServer` - 启动/停止嵌入式 Node.js 服务器 (MethodChannel + FFI 双回退)
- `AudioService` - just_audio 封装
- `MediaNotificationService` - 通知栏控制
- `DesktopLyricService` - 桌面歌词
- `LyriconProviderService` - Lyricon 歌词扩展
- `KugouApiClient` - 酷狗 API 调用

### Node.js Server
- `kugou_api_server/` - 嵌入式 API 服务器源码
  - `module/` - API 模块 (audio, comment, artist, album, login, captcha, brush, ai_recommend 等)
  - `util/` - 工具类 (request, crypto, memory-cache, helper, config)
  - `server.js` - HTTP 服务器入口

## Navigation

底部 Tab 导航 (5 个):
1. **发现** - DiscoverPage
2. **排行** - ChartsPage
3. **我收藏** - FavoritesPage
4. **私人 FM** - PersonalFmPage
5. **我的** - UserCenterPage

路由:
- `/search` - SearchPage
- `/library` - LibraryPage
- `/settings` - SettingsPage
- `/user` - UserCenterPage
- `/player` - FullPlayer
- `/personal_fm` - PersonalFmPage
- `/playlist` - PlaylistPage (需传 Playlist 参数)

## Audio Quality

| 音质 | 格式 | 比特率 |
|------|------|--------|
| 标准 | MP3 | 128 kbps |
| 高质 | MP3 | 320 kbps |
| 无损 | FLAC | ~1000 kbps |

## Build & Run

```bash
# 安装依赖
flutter pub get

# 下载 Native 依赖 (首次)
.\setup_native.bat  # Windows
# 或 curl + unzip (macOS/Linux)

# 运行调试版
flutter run

# 构建发布版 APK (分拆包)
flutter build apk --release --split-per-abi
```

### 服务器构建
```bash
# 修改 kugou_api_server/ 后需重新打包
cd scripts
.\build_nodejs_server.bat
```

## CI/CD

GitHub Actions 自动构建:
- 推送 `v*` 标签触发
- 自动构建 3 个架构 APK
- 自动创建 GitHub Release
- 自动递增 versionCode + Changelog

## Development Notes

- Node.js 服务器通过 MethodChannel 启动，失败时回退到 dart:ffi
- 应用退出时需手动关停 Node.js 服务器释放端口
- 歌词支持 KRC/LRC/纯文本 + Lyricon 扩展格式
- 响应式布局: 手机 (NavigationBar) / 平板 (NavigationRail) / 桌面 (NavigationDrawer)
- FullPlayer 上滑时主页向上偏移 15% + 淡出 (Apple Music 风格)
- 云端 API 地址: `115.29.236.96:5621` (可配置)
