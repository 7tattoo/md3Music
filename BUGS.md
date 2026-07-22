# MD3Music Bug Report

> 扫描时间：2025-07-22 | 共发现 **111 个问题** (Flutter 23 + Node.js 88)

---

## 概览

| 严重级别 | Flutter | Node.js | 合计 |
|----------|---------|---------|------|
| Critical | 1 | 7 | 8 |
| High | 4 | 19 | 23 |
| Medium | 12 | 35 | 47 |
| Low | 6 | 27 | 33 |

---

## 一、Flutter/Dart 代码问题 (23 个)

### BUG-01 — Critical: `_audioService` 声明为 `dynamic`，丧失类型安全

- **文件**: `lib/providers/player_provider.dart:71`
- **描述**: `_audioService` 声明为 `dynamic`，所有方法调用绕过静态类型检查。如果加载的模块返回意外类型，所有调用将静默失败或抛出运行时错误。
- **修复建议**: 改为 `AudioService?` 类型，使用接口抽象支持多平台。

---

### BUG-02 — High: `AudioService` 单例从未调用 `dispose()` — 资源泄漏

- **文件**: `lib/core/services/audio_service_io.dart:12-17`, `lib/providers/player_provider.dart:1046-1055`
- **描述**: `PlayerProvider.dispose()` 取消流订阅但从未调用 `_audioService?.dispose()`。`AudioPlayer` 及其原生资源在整个应用生命周期内泄漏。
- **修复建议**: 在 `PlayerProvider.dispose()` 中调用 `_audioService?.dispose()`。

---

### BUG-03 — High: `_handlePlaybackCompleted` 并发竞态条件

- **文件**: `lib/providers/player_provider.dart:209-249`
- **描述**: `_handlingCompletion` 守卫在 `finally` 块中重置，快速切歌时第二次调用被静默丢弃。如果第一次调用失败，守卫已重置，后续完成事件可能重入。
- **修复建议**: 使用计数器或将第二次调用排队。

---

### BUG-04 — High: `_prefetchNextSongs` 修改 `_playlist` 但未调用 `notifyListeners`

- **文件**: `lib/providers/player_provider.dart:435-458`
- **描述**: 在 `.then()` 回调中修改 `_playlist[i]` 但从未调用 `notifyListeners()`。UI 显示过时数据。
- **修复建议**: 在修改后调用 `notifyListeners()`。

---

### BUG-05 — High: `DownloadManager.dispose()` 从未调用 — StreamController 泄漏

- **文件**: `lib/providers/downloads_provider.dart:28-64`
- **描述**: `DownloadsProvider` 订阅了 `DownloadManager.taskUpdates` 流，但从未在 `dispose()` 中关闭 StreamController。
- **修复建议**: 在 `DownloadsProvider.dispose()` 中调用 `_manager.dispose()`。

---

### BUG-06 — Medium: `nodejs_server.dart` 在 `Isolate.run` 中使用 FFI

- **文件**: `lib/services/nodejs_server.dart:44-73`
- **描述**: `Isolate.run()` 在新 Isolate 中打开 FFI 绑定，对父 Isolate 不可用。`_started` 在父 Isolate 设置但 Node.js 在子 Isolate 运行。
- **修复建议**: 使用 `Isolate.spawn` 配合 `ReceivePort` 或在主线程启动。

---

### BUG-07 — Medium: `_clearAvatarCache` 清除了整个图片缓存

- **文件**: `lib/providers/kugou_provider.dart:795-799`
- **描述**: `DefaultCacheManager().emptyCache()` 清除整个图片缓存而非仅头像，导致登出后图片闪烁。
- **修复建议**: 实现按前缀/类型清除或维护独立头像缓存。

---

### BUG-08 — Medium: `toggleFavorite` 快速点击时状态不一致

- **文件**: `lib/providers/favorites_provider.dart:93-136`
- **描述**: 收藏/取消收藏的本地状态更新发生在异步 API 调用完成后，快速点击时状态可能不一致。
- **修复建议**: 采用乐观更新模式。

---

### BUG-09 — Medium: `KugouProvider` 缺少 `dispose()` 方法

- **文件**: `lib/providers/kugou_provider.dart:12-18`
- **描述**: `_searchCache` 和 `_dataTimestamps` map 无限增长，仅登出时清理。
- **修复建议**: 添加 `dispose()` 和 LRU 淘汰策略。

---

### BUG-10 — Medium: `_searchCache` 和 `_dataTimestamps` 无界增长

- **文件**: `lib/providers/kugou_provider.dart:139-161`
- **描述**: 每个唯一搜索关键词添加条目，长时间会话中内存线性增长。
- **修复建议**: 添加最大容量限制和 LRU 淘汰。

---

### BUG-11 — Medium: `DesktopLyricService` 缓存的 Provider 引用可能过时

- **文件**: `lib/core/services/desktop_lyric_service.dart:227-234`
- **描述**: Provider 树重建时，缓存引用指向已废弃的 `ChangeNotifier` 实例。
- **修复建议**: 每次需要时通过 `BuildContext` 获取。

---

### BUG-12 — Medium: `mini_player.dart` 使用 `markNeedsBuild()` 违反框架规则

- **文件**: `lib/modules/player/mini_player.dart:170`
- **描述**: 绕过 Flutter 响应式重建机制，可能导致框架断言错误。
- **修复建议**: 改为 `StatefulWidget` 或使用 `ValueListenableBuilder`。

---

### BUG-13 — Medium: `Playlist.fromJson` 丢失字段

- **文件**: `lib/data/models/playlist.dart:35-49`
- **描述**: 忽略 `listCreateUserid`、`listCreateListid`、`subscribedListId`，反序列化时丢失。
- **修复建议**: 在 `fromJson` 中添加缺失字段解析。

---

### BUG-14 — Medium: `MediaNotificationService` 回调被重复设置

- **文件**: `lib/core/services/desktop_lyric_service.dart:64-91`, `lib/providers/player_provider.dart:92-104`
- **描述**: 两处设置相同静态回调，最后一个执行的覆盖另一个。
- **修复建议**: 统一回调注册点。

---

### BUG-15 — Medium: `KugouApiClient` 拦截器初始化竞态

- **文件**: `lib/services/kugou_api/kugou_api_client.dart:61-116`
- **描述**: `_initCompleter` 在异步构造函数中设置，首次请求可能在令牌加载前执行。
- **修复建议**: 确保 `_initCompleter` 在构造函数第一行赋值。

---

### BUG-16 — Medium: `audio_service_web.dart` Blob URL 从未释放

- **文件**: `lib/core/services/audio_service_web.dart:139-153`
- **描述**: 每首歌创建 Blob URL 但从未释放，长时间会话泄漏浏览器内存。
- **修复建议**: 切换歌曲时释放前一首 Blob URL。

---

### BUG-17 — Low: `_cleanName` 正则表达式实际未替换任何内容

- **文件**: `lib/services/kugou_api/kugou_models.dart:957-963`
- **描述**: `replaceAll('&#\\d+;', '')` 使用字面字符串而非 `RegExp`，HTML 实体未清理。
- **修复建议**: 改为 `replaceAll(RegExp(r'&#\d+;'), '')`。

---

### BUG-18 — Low: `DownloadsProvider.downloadSong` 未按 `songId` 去重

- **文件**: `lib/providers/downloads_provider.dart:132-173`
- **描述**: 同一首歌多次下载会在 `_tasks` 中追加重复条目。
- **修复建议**: 已存在相同 `songId` 时更新而非追加。

---

### BUG-19 — Low: `DownloadManager._buildFilePath` 使用硬编码 `/`

- **文件**: `lib/services/download_manager.dart:146-166`
- **描述**: Windows 上会产生混合路径分隔符。
- **修复建议**: 使用 `Platform.pathSeparator`。

---

### BUG-20 — Low: `app.dart` 无条件导入 `dart:io`

- **文件**: `lib/app.dart:1`
- **描述**: Web 构建时 `dart:io` 不可用，导致编译错误。
- **修复建议**: 使用条件导入。

---

### BUG-21 — Low: `_handleLyriconSongChange` 监听自身 — 潜在无限递归

- **文件**: `lib/providers/player_provider.dart:84-88`
- **描述**: 依赖外部假设不触发 `notifyListeners`，模式脆弱。
- **修复建议**: 使用独立事件总线。

---

### BUG-22 — Low: `playOnlineSong` 创建重复 `KugouApiClient` 实例

- **文件**: `lib/providers/player_provider.dart:276-293`
- **描述**: 同一单例创建两次，令人困惑。
- **修复建议**: 复用同一实例。

---

### BUG-23 — Low: `KugouApiClient._getSongUrlNew` 静默丢弃 `priv_status == 0`

- **文件**: `lib/services/kugou_api/kugou_api_client.dart:676-678`
- **描述**: 无调试日志，难以诊断 VIP 播放问题。
- **修复建议**: 添加 `debugPrint` 日志。

---

## 二、Node.js 服务器代码问题 (88 个)

### Critical (7 个)

#### C1 — `login_device_kick.js` 5 个未定义变量导致端点完全失效

- **文件**: `kugou_api_server/module/login_device_kick.js:6,13,14,16,18` + `networkapi/module/login_device_kick.js`
- **描述**: `calculateMid`, `uuid`, `dfid`, `userid`, `guid` 未声明或导入。每次调用抛出 `ReferenceError`。第 17 行还将整个 `{str, key}` 对象作为 `token` 传递而非 `encrypt.str`。

#### C2 — 硬编码微信 API 密钥

- **文件**: `kugou_api_server/util/config.json:2-6`, `networkapi/util/config.json`, `server_bundle.js:1`
- **描述**: 微信 `wx_secret` (`4efcab88b700769e376e3f6087b8abc9`) 和 `wx_lite_secret` 硬编码在源码中，且嵌入打包产物。

#### C3 — 硬编码加密签名密钥

- **文件**: `util/helper.js:11,28,46,56,74,85,99` (两个服务器)
- **描述**: 所有 API 签名密钥已提交：`NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt` 等 6 个。有仓库访问权限的人可伪造有效 API 签名。

#### C4 — Promise 反模式 + 吞没拒绝

- **文件**: `util/request.js:33` (两个服务器)
- **描述**: `new Promise(async (resolve, reject) => {...})` 包装异步代码。`response.data` 为 null 时拒绝被静默吞没，且传递普通对象而非 Error，丢失堆栈跟踪。

#### C5 — Trust proxy 伪造允许 IP 欺骗

- **文件**: `kugou_api_server/server.js:281`, `server_android.js:109`
- **描述**: `app.set('trust proxy', true)` 无代理配置，任何客户端可设置 `X-Forwarded-For` 绕过速率限制。

#### C6 — 不安全的错误处理器在非模块错误时崩溃

- **文件**: `kugou_api_server/server.js:542-568`, `server_android.js:186-192`, `networkapi/server.js:145-151`
- **描述**: catch 块访问 `e.headers` 和 `e.status`，标准 Error 对象无这些属性，导致 Express 二次错误 — 客户端无响应。

#### C7 — 隐式全局变量 `j` 导致缓存指标竞态

- **文件**: `util/apicache.js:510` (两个服务器)
- **描述**: `for (j = 0; ...)` — `j` 未声明，并发请求共享并损坏全局 `j`。

---

### High (19 个)

#### H1 — `new Buffer()` 已弃用构造函数

- **文件**: `util/apicache.js:168,260` (两个服务器)
- **描述**: 暴露未初始化内存，Node 6 起已弃用，Node 20+ 可能不存在。应改用 `Buffer.from()`。

#### H2 — Cookie 键注入导致原型链污染

- **文件**: `kugou_api_server/server.js:325-333`, `server_android.js:125-131`
- **描述**: Cookie 键从用户输入解码后直接设置，未过滤 `__proto__`、`constructor`、`prototype`。配合 `Object.assign` 可污染原型链。

#### H3 — `Object.assign` 通过 `cookie` 查询参数的原型链污染

- **文件**: `kugou_api_server/server.js:462`, `server_android.js:168`
- **描述**: `?cookie[__proto__][isAdmin]=true` 可污染 Object.prototype。

#### H4 — `app.js` 缺少 `await` on `startService()`

- **文件**: `kugou_api_server/app.js:5`
- **描述**: 返回 Promise 但未 await，拒绝（如端口占用）成为未处理拒绝。

#### H5 — 静默 `catch` 吞没模块加载错误

- **文件**: `server_entry.js:50-52`, `modules_index.js:168-172` (两个服务器)
- **描述**: `catch (e) { // Skip }` 静默丢弃模块加载错误，关键模块语法错误静默 404。

#### H6 — 非 async `app.listen()` 回调中的 `await`

- **文件**: `kugou_api_server/server.js:630-632`
- **描述**: `await registerDeviceAndGetDfid()` 在非 async 回调中，设备注册错误静默丢失。

#### H7 — CORS 允许任意来源 + 凭证

- **文件**: `kugou_api_server/server.js:299-305`, `server_android.js:113-119`, `networkapi/server.js:70-81`
- **描述**: 任何网站可进行经过认证的跨域请求并读取响应。

#### H8 — 硬编码明文 HTTP 登录端点 (5+ 文件)

- **文件**: `captcha_sent.js:10`, `login_cellphone.js:43`, `login_qr_check.js:8`, `login_qr_key.js:6`, `login_token.js:49`
- **描述**: 所有使用 `http://115.29.236.96:5621` — 登录凭证、令牌、手机号通过未加密 HTTP 发送。

#### H9 — 硬编码 AES 加密密钥/IV

- **文件**: `login_token.js:4-5,7-8`, `login_cellphone.js:4-7`, `login_openplat.js:7-10` (两个服务器)
- **描述**: AES 密钥硬编码在源码中，有仓库访问权限可解密所有令牌负载。

#### H10 — 微信密钥通过 URL 查询字符串发送

- **文件**: `kugou_api_server/module/login_wx_create.js:8`, `networkapi/module/login_wx_create.js:8`
- **描述**: `secret` 作为 GET 参数发送，出现在服务器日志、代理日志和 Referer 头中。

#### H11 — 变量遮蔽覆盖函数参数

- **文件**: `login_wx_create.js:32` (两个服务器)
- **描述**: `const params = {...}` 遮蔽了函数参数 `params`，后续引用获取错误对象。

#### H12 — `login_qr_create.js` 未处理 Promise 拒绝

- **文件**: `login_qr_create.js:14` (两个服务器)
- **描述**: `await qrcode.toDataURL(url)` 无 try/catch，错误成为未处理拒绝。

#### H13 — `Math.random()` 用于安全敏感值

- **文件**: `util/util.js:15,28,102` (两个服务器)
- **描述**: 用于服务器设备 ID、GUID、AES 临时密钥，可预测。

#### H14 — `everyday_friend.js` 完全硬编码 — 忽略用户输入

- **文件**: `kugou_api_server/module/everyday_friend.js:8`
- **描述**: 请求体包含硬编码 `user_id: 853927886` 和固定 `mixsong_ids`，`params` 参数完全忽略。

#### H15 — `everyday_style_recommend.js` 计算数据未发送

- **文件**: `kugou_api_server/module/everyday_style_recommend.js:2-4,10`
- **描述**: `dataMap` 构建但第 10 行发送 `data: {}` 而非 `data: dataMap`。

#### H16 — `fm_songs.js` singername 始终为空

- **文件**: `kugou_api_server/module/fm_songs.js:11`
- **描述**: `.split(',')` 产生字符串，`.map(s => s.singername)` 访问字符串属性始终 undefined。

#### H17 — HTTP 明文传输携带凭证的 API 调用

- **文件**: `album.js:26`, `audio.js:24`, `artist_honour.js:4` (kugou_api_server)
- **描述**: POST 到 `http://kmr.service.kugou.com`，`token` 和 `userid` 明文传输。

#### H18 — `login_openplat.js` 空引用解引用 `body.data`

- **文件**: `login_openplat.js:59-66`, `login.js:32,35`, `login_cellphone.js:59-64`, `login_token.js:59-66` (两个服务器)
- **描述**: 检查 `body?.data?.secu_params` 但未验证 `body.data` 非 null，API 返回 `data: null` 时崩溃。

#### H19 — `memory-cache.js` 键覆盖时定时器泄漏

- **文件**: `util/memory-cache.js:6-23` (两个服务器)
- **描述**: `add()` 覆盖已有键时旧 `setTimeout` 未清除，过期定时器删除新条目导致数据损坏。

---

### Medium (35 个)

| # | 文件 | 行号 | 描述 |
|---|------|------|------|
| M1 | `server.js` | 38,51 | `fs.appendFileSync` 在每次 `console.log` 调用时阻塞事件循环 |
| M2 | `server.js` | 469 | 日志记录 Authorization 头（令牌/用户ID） |
| M3 | `device_config.js` | 4-9,29-41 | 模块级共享可变状态竞态条件 |
| M4 | `util/runtime.js` | 51 | CLI 平台参数被 `'lite'` 覆盖 |
| M5 | `util/memory-cache.js` | 1-54 | 无最大大小限制，内存无限增长 |
| M6 | `util/request.js` | 159-160 | 错误对象丢失堆栈跟踪 |
| M7 | `util/crypto.js` | 264-270 | RSA 使用 PKCS1 v1.5 而非 OAEP |
| M8 | `util/util.js` | 82-84 | `decodeLyrics` 空 catch 吞没错误 |
| M9 | `util/util.js` | 51-59 | Cookie 值在 `=` 处被截断 |
| M10 | `util/request.js` | 127-134 | URL 参数未编码，可注入 |
| M11 | `util/request.js` | 82,110,124 | 签名计算与实际发送数据不一致 |
| M12 | `networkapi/server.js` | 64 | 无效 PORT 环境变量产生 NaN |
| M13 | `playlist_add/del.js` 等 | 多处 | 缺少 `params.cookie` 可选链 |
| M14 | `lastest_songs_listen.js` | 11 | 缺少 `params` 可选链 |
| M15 | `playlist_del.js` | 46-49 | catch 块 resolve 而非 reject |
| M16 | `lyric.js` | 37-43 | 吞没原始错误详情 |
| M17 | `login_openplat.js` | 71-76 | 日志记录敏感令牌数据 |
| M18 | `login_qr_check.js` | 17-23 | 日志记录令牌详情 |
| M19 | 10+ 模块文件 | 多处 | Promise 构造器反模式 |
| M20 | `util/apicache.js` | 357-377 | `parseDuration` 空引用 |
| M21 | `ip_zone.js` | 3-30 | 不必要的 Promise 包装 |
| M22 | `ip_zone.js` | 12 | 松散相等 `==` 而非 `===` |
| M23 | `comment_count.js` | 9-13 | 缺少输入验证 |
| M24 | `audio_accompany_matching.js` 等 | 多处 | 缺少可选链 |
| M25 | `artist_lists.js` | 5 | `sextypes` 拼写错误应为 `sextype` |
| M26 | `artist_unfollow.js` | 4,6 | 类型强制不一致 |
| M27 | `captcha_sent.js` | 5 | 模板字面量将 undefined 转为字符串 `"undefined"` |
| M28 | `register_dev.js` | 108 | 不必要的 Promise 包装 |
| M29 | `server.js` | 249 | 同步 `require()` 阻塞启动 |
| M30 | `disable_proxy_v2.js` | 1-95 | 自修改源代码，正则替换脆弱 |
| M31 | `util/memory-cache.js` | 36-38 | 过期条目读取时未清理 |
| M32 | `util/runtime.js` | 80-127 | 代理缓存永不失效 |
| M33 | `fm_songs.js` | 15-17 | 数字类型参数 `.split()` 崩溃 |
| M34 | `krm_audio.js` 等 | 多处 | `Number('')` = 0 发送无效 ID |
| M35 | `longaudio_album_audios.js` | 7 | 缺少 `album_id` 可选链 |

---

### Low (27 个)

| # | 文件 | 行号 | 描述 |
|---|------|------|------|
| L1 | `server.js` | 274 | `consturctServer` 拼写错误 |
| L2 | `server_entry.js` | 72-78 | 未使用的 imports |
| L3 | `album.js`, `audio.js` | 9,8 | Token 默认值为数字 `0` 而非字符串 `''` |
| L4 | `ip_dateil.js` | 文件名 | 文件名拼写错误应为 `ip_detail.js` |
| L5 | `everyday_friend.js` | 11 | 硬编码 PID header |
| L6 | `fm_image.js` | 5-6 | `userid` 缺少默认值 |
| L7 | `playhistory_upload.js` | 6 | `Number(undefined)` 发送 `mxid: NaN` |
| L8 | `login_cellphone.js` | 12 | 手机号掩码对短号码脆弱 |
| L9 | `login.js` | 13 | 未验证用户名是否提供 |
| L10 | `login_qr_create.js` | 6 | 缺少 `params.key` 可选链 |
| L11 | `login_device.js` | 5 | 缺少 `params.token` 可选链 |
| L12 | `lyric.js` | 27 | 未验证 base64 内容 |
| L13 | `login_qr_check.js` | 11 | 空 QR key 发送到 API |
| L14 | `playlist_del.js` | 43 | 响应体视为 Buffer 无类型检查 |
| L15 | `server_android.js` | 211 | 自引用 HTTP 进行设备注册 |
| L16 | `networkapi/server.js` | 86 | Cookie 解析器 `=` 边界情况 |
| L17 | `networkapi/server.js` | 148,150 | 错误响应缺少一致 Content-Type |
| L18 | `networkapi/login_qr_create.js` | 6 | `params.key` 无空检查 |
| L19 | `album.js`, `audio.js` | 26,24 | HTTP (非 HTTPS) API 调用 |
| L20 | `artist_honour.js` | 4 | HTTP (非 HTTPS) API 调用 |
| L21 | `ip_zone.js` | 12 | 松散相等 `==` |
| L22 | `comment_count.js` | 9-13 | 缺少必需参数验证 |
| L23 | `longaudio_album_detail.js` | 2 | 缺少 `album_id` 可选链 |
| L24 | `longaudio_album_audios.js` | 7 | 缺少 `album_id` 可选链 |
| L25 | `krm_audio_mv.js` | 4 | `Number('')` = 0 |
| L26 | `apicache.js` | 67,283 | `index` 未初始化 |
| L27 | `apicache.js` | 168,260 | `new Buffer()` 已弃用 |

---

## 三、关键修复优先级

### P0 — 立即修复 (安全漏洞)
1. **C2/C3** 硬编码密钥 — 轮换所有密钥，迁移至环境变量
2. **C5** Trust proxy IP 伪造 — 移除或正确配置
3. **H7** CORS Origin 反射 — 使用 `CORS_ALLOW_ORIGIN` 环境变量
4. **H2/H3** 原型链污染 — 过滤危险 Cookie 键
5. **C1** `login_device_kick.js` 完全失效 — 修复未定义变量
6. **H8** HTTP 明文凭证 — 切换 HTTPS
7. **H9** 硬编码 AES 密钥 — 迁移至环境变量

### P1 — 尽快修复 (崩溃/数据损坏)
8. **C4** Promise 反模式 — 项目范围重构为 async 函数
9. **C6** 不安全错误处理器 — 添加类型检查
10. **H18** 空引用解引用 — 添加 null 检查
11. **H19** 内存缓存定时器泄漏 — 覆盖时清除旧定时器
12. **BUG-01** `_audioService` dynamic 类型
13. **BUG-02/05** 资源泄漏
14. **BUG-03** 播放完成竞态

### P2 — 计划修复
15. **M1** 同步文件 I/O 阻塞
16. **M7** RSA PKCS1 → OAEP
17. **H13** Math.random → crypto.randomBytes
18. **BUG-06-16** 其余 Medium 问题

### P3 — 后续优化
19. 所有 Low 级别问题
