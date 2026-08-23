# AGENTS.md — MD3Music 项目约定

> 本文件供 AI Agent 和开发者快速了解项目结构、模块边界、构建流程与已知陷阱。

> **分支适用说明**：本仓库存在两个并行开发分支，正文 1~6 节全部内容仅描述当前分支 `rust-local-two`（Rust 架构）。
> 切换到 `arch-local-first`（Node.js 架构）时，请以其自带版本的 AGENTS.md 为准；两分支内容对比与切换注意事项见[第 7 节](#7-git-分支约定)。

---

## 1. 项目架构概览

MD3Music 是一款 Android 音乐播放器，采用 **Flutter 前端 + 嵌入式 Rust API 服务器** 的混合架构：

- **Flutter 前端**（Dart）：负责 UI、播放控制、本地数据管理
- **嵌入式 Rust 服务器**（Rust）：App 启动时通过 `libkugou_server.so`（JNI/MethodChannel，`dart:ffi` 兜底）在进程内启动一个 `tiny_http` HTTP 服务器，监听 `127.0.0.1` 上的**随机端口**（`[10000, 60000]`，被占用则 1s 后换下一个，最多 10 次），实际端口通过 MethodChannel/FFI 返回给 Dart 写入 `KugouEndpoints.baseUrl`。处理所有酷狗音乐 API 请求。Rust 实现取代了旧的 `libnode.so` + `server_bundle.js`（Express）方案，行为与酷狗云端等价。
- **登录接口同样走本地 Rust 服务器**：`/login/*`、`/captcha/sent`、`/register/dev` 等 16 个登录端点由 Rust `login.rs`/`misc.rs` 用本地设备身份（dfid/mid）直连酷狗上游（`login-user.kugou.com` / `loginserviceretry.kugou.com` / `login.user.kugou.com` / `gateway.kugou.com` 等），不再依赖第三方云端（旧 `networkapi/` 已退役，仅作 JS 参考）。

核心设计理念：所有音乐搜索、歌词、排行榜、登录等 API 请求都走本地 Rust 服务器转发，避免直接暴露 API 密钥在客户端。

---

## 2. 模块边界

```
md3Music/
├── lib/                          # Dart 前端（Flutter）
│   ├── main.dart                 # 入口：权限请求 → 启动本地 API 服务器 → runApp
│   ├── app.dart                  # MaterialApp 配置、主题、导航、Tab 布局
│   ├── core/                     # 核心层：主题、布局、服务（桌面歌词、均衡器、Lyricon）
│   ├── data/                     # 数据层：模型、仓库（settings_repository 等）
│   ├── modules/                  # 功能模块：discover、player、search、library、login...
│   ├── providers/                # 状态管理：PlayerProvider、KugouProvider、ThemeProvider...
│   ├── services/                 # 服务层：kugou_server.dart（MethodChannel + dart:ffi 启动服务器）
│   └── widgets/                  # 共享 UI 组件（歌词、播放器控件等）
│
├── kugou_api_server/             # 本地 API 服务器（Rust，编译为 cdylib 打包进 APK）
│   ├── rust/                     # Rust crate（crate 名 kugou_server）
│   │   ├── src/
│   │   │   ├── lib.rs            # 对外 FFI/JNI 符号：start_server/stop_server/is_server_running/
│   │   │   │                     #   get_server_port + Java_com_md3music_..._native*
│   │   │   ├── server.rs         # tiny_http 服务器：CORS、cookie、body 解析、apicache、路由分发
│   │   │   ├── modules/          # 按端点分组的 160+ 个 API 模块（search.rs、audio.rs、lyric.rs、
│   │   │   │                     #   playlist.rs、user.rs、youth.rs、pcm.rs、song_url.rs...）
│   │   │   ├── crypto.rs         # MD5/SHA1/AES/RSA（与 JS CryptoJS 行为对齐）
│   │   │   ├── request.rs        # 上游转发（ureq）、签名、响应组装
│   │   │   ├── device.rs         # dfid/mid 设备信息持久化（device_info.json）
│   │   │   ├── cache.rs / config.rs / helper.rs / util.rs / simulate.rs
│   │   │   └── ...
│   │   ├── tests/smoke.rs        # 本地冒烟测试（不依赖外网）
│   │   ├── .cargo/               # 可选的 Android 交叉编译 linker/CC 配置
│   │   └── Cargo.toml            # crate-type = ["cdylib", "rlib"]；jni 仅 Android target 依赖
│   ├── module/                   # 旧 JS 模块（200+，已被 Rust 取代，仅作参考/对照）
│   ├── util/                     # 旧 JS 工具（仅供 networkapi 参考）
│   └── server.js / bundled_entry.js / server_bundle.js   # 旧 Node 方案遗留，不再打包
│
├── networkapi/                   # 旧公网登录服务器（Node.js，已退役，仅作 JS 参考）
│   ├── server.js                 # 精简版 Express，只加载登录相关模块
│   ├── module/                   # 登录、注册、验证码等模块
│   └── util/                     # 独立的工具函数副本（与 Rust 端已分家，见 4.6）
│
├── android/                      # Android 原生层
│   ├── app/src/main/jniLibs/     # libkugou_server.so（arm64-v8a、armeabi-v7a、x86_64、x86）
│   └── app/src/main/kotlin/      # Kotlin 原生代码（MediaSession、KugouApiService、桌面歌词等）
│
├── assets/
│   ├── fonts/                    # 内置字体（simhei.ttf）
│   └── images/                   # 应用图标
│
└── scripts/                      # 构建脚本（部分为旧 Node 方案遗留）
    └── test_api.ps1              # API 测试脚本
```

### 关键边界规则

| 边界 | 说明 |
|------|------|
| `lib/` ↔ `kugou_api_server/rust/` | Dart 前端通过 HTTP `127.0.0.1:<随机端口>` 调用 API（端口由 `startServer`/`start_server` 返回，写入 `KugouEndpoints.baseUrl`）；启动/停止走 `KugouApiService` 的 MethodChannel（`com.md3music.md3music/kugou_api`：startServer/isRunning/stopServer），`dart:ffi` 直连 `start_server` 作为兜底 |
| `kugou_api_server/rust/` ↔ `networkapi/` | 两者代码完全独立，不再共享 util；networkapi 已退役（登录已改由 Rust 直连酷狗），仅作 JS 参考 |
| `kugou_api_server/module/` 等 JS 文件 | 旧 Node 方案遗留，已被 Rust 取代，**不要**再修改 JS 版模块或重新打包 |
| `android/app/src/main/jniLibs/` | 原生库目录，`libkugou_server.so` **已提交进 Git**（从 `rust/target/*/release/` 复制），无需下载 |
| `assets/nodejs-project/` | 已从 `pubspec.yaml` 移除，不再打包；旧 `server_bundle.js` 仅作参考 |

---

## 3. 构建流程

### 3.1 完整构建顺序（CI / 手动发布）

```
步骤 1: 构建 Rust 服务器 cdylib（修改 rust/src 后必须执行）
   └── cd kugou_api_server/rust
       一键脚本（推荐，自动定位 NDK、交叉编译 4 ABI 并覆盖 jniLibs）：
           ./build_android.sh
           # 可选：--no-copy 只编译；--debug 调试构建；--out=<目录> 自定义复制目标；--host 额外编译主机 release
       主机：cargo build --release
            → target/release/libkugou_server.so
       安卓（交叉编译，4 个 ABI）：
           cargo build --target aarch64-linux-android --release
           cargo build --target armv7-linux-androideabi --release
           cargo build --target i686-linux-android --release
           cargo build --target x86_64-linux-android --release
       每个 ABI 需要 NDK 链接器（见 4.1），产物：
           → target/{target}/release/libkugou_server.so

步骤 2: 复制到 jniLibs
   └── 4 个 ABI 的 .so 复制到 android/app/src/main/jniLibs/{abi}/libkugou_server.so

步骤 3: Flutter 构建
   └── flutter build apk --release --split-per-abi
       → build/app/outputs/flutter-apk/app-{abi}-release.apk
```

### 3.2 开发时快速迭代

```bash
# 只修改了 rust/src/ 下的代码时：
cd kugou_api_server/rust && cargo build --release   # 主机验证编译
# 修改安卓侧行为（JNI 符号等）后需交叉编译并复制 .so，再：
flutter run

# 只改 Dart/Android/Kotlin 代码时：
flutter run
```

### 3.3 测试

```bash
cd kugou_api_server/rust
cargo test        # 本地冒烟：404/CORS/RSA 常量解析 + 路由 dispatch 断言
cargo clippy      # 静态检查（勿引入新 error）
```

### 3.4 CI 流程（`.github/workflows/ci.yml`）

- 触发条件：push 到 main/master，或手动 workflow_dispatch
- 环境：Ubuntu + Java 17 + Flutter stable + Android SDK 36 + NDK 28
- 注意：CI 中旧 Node 流程（获取 libnode、esbuild 打包）已冗余但不会失败；`libkugou_server.so` 已入库，Flutter 构建直接可用
- 产物：三个 ABI 的 APK（arm64-v8a、armeabi-v7a、x86_64），自动创建 GitHub Release

---

## 4. 已知陷阱和注意事项

### 4.1 Android 交叉编译（ring / ureq TLS）

**问题**：`ureq` 的 TLS 依赖 `ring`，其 build script 按裸命令名找 C 编译器（`aarch64-linux-android-clang`），而 NDK 只提供带 API 级别的 `aarch64-linux-android21-clang`；且它是以 shell 包装脚本形式存在，**不能**被 symlink 到别的目录（脚本用 `dirname $0` 定位 `clang`）。

**解决**：通过环境变量显式指定 CC/AR/链接器为 NDK 完整路径（配合 `cargo build --target`）：

```bash
NDK=~/Android/Sdk/ndk/28.2.13676358
BIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
env CC_aarch64_linux_android=$BIN/aarch64-linux-android21-clang \
    AR_aarch64_linux_android=$BIN/llvm-ar \
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$BIN/aarch64-linux-android21-clang \
    cargo build --target aarch64-linux-android --release
```

- CC/AR 用小写目标名（cc-rs 读取 `CC_<target>`，target 用下划线）；cargo 的 linker 变量**必须大写**（`CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER`），小写会被静默忽略。
- 各 target 对应 linker：`aarch64-linux-android21-clang` / `armv7a-linux-androideabi21-clang` / `i686-linux-android21-clang` / `x86_64-linux-android21-clang`，AR 统一用 `llvm-ar`。
- 验证产物：`file target/{target}/release/libkugou_server.so` 应为 `for Android 21`。
- 导出符号核对：`llvm-nm -D --defined-only libkugou_server.so` 应含 `start_server`/`stop_server`/`is_server_running`/`get_server_port` + 3 个 `Java_com_md3music_md3music_KugouApiService_*`。

### 4.2 RSA PEM 常量必须能被 rsa crate 解析

**问题**：`PUBLIC_LITE_RAS_KEY`/`PUBLIC_RAS_KEY` 是单行长 base64；`rsa` crate 底层 pem-rfc7468 要求每行 ≤64 字符，直接 `from_public_key_pem` 会 panic（`Pem(Base64(InvalidEncoding))`），导致登录/注册 RSA 路径崩溃。

**解决**：`crypto.rs` 内 `rsa_raw_encrypt`/`rsa_pkcs1v15_encrypt`/`rsa_oaep_sha256_encrypt` 先经 `normalize_pem()` 按 64 字符折行。`tests/smoke.rs::rsa_keys_parse` 为回归测试。新增 RSA 使用点也必须走这几个函数。

**附加坑（SSA simulate 公钥）**：`simulate.rs` 的 `PUBLIC_KEY`（RSA-OAEP，来自 WASM 反作弊）曾把 `MIIBIjANBgkqhkiG9w0…` 误抄成 `…G09w0…`（多了个 `0`），导致 SSA 重试路径一触发就 panic。该常量虽是标准多行 PEM，但内容 corrupted，`normalize_pem` 只能折行、无法修复内容。**拷贝任何 PEM 常量后必须用 `openssl rsa -pubin -in <(echo "$PEM") -text` 或对照 JS 原串逐字符比对**；`tests/smoke.rs::simulate_rsa_key_parses` 为回归测试。

### 4.3 服务器启动时序

**问题**：Flutter UI 渲染后发现页立即请求 API，如果本地服务器还没启动完毕，请求全部失败。

**解决**：`main.dart` 中 `await KugouApiServer.start()` 在 `runApp()` 之前执行；`_waitForReady()` 会轮询实际端口最多 30 秒。冷启动时 MethodChannel 可能尚未注册（3 次重试失败），此时 `dart:ffi` 兜底直接 `start_server(0, dataDir)` 也可启动（`0` 表示随机端口），`server::start` 会检测已在运行并返回当前端口，幂等。

### 4.4 随机端口与端口冲突

**问题**：旧方案固定 8080，退出 App 时如果没有正确关停服务器，下次冷启动端口被占用导致启动失败（`Server::http` 返回 Err → `start_server` 返回 0）。

**解决**：Rust 启动时改用**随机端口**（`server::start(0, dir)` 在 `[10000, 60000]` 内随机，被占用则 sleep 1s 换下一个，最多 10 次），成功返回实际端口，`start_server`/`nativeStartNode` 以端口为返回值（0=失败），Kotlin MethodChannel `startServer` 与 dart:ffi 兜底都会把端口回传给 Dart 写入 `KugouEndpoints.baseUrl`（`KugouApiClient.updateBaseUrl`）。退出流程仍必须 `await KugouApiServer.stop()` + 等待 300ms + `exit(0)`；`MainActivity.onDestroy`/`onTrimMemory` 也会调用 `KugouApiService.stopServer()`（`nativeStopNode`）。`SystemNavigator.pop()` 不够可靠。设置页「在线音乐 → 本地数据接口」点击可确认重启服务器（`KugouApiServer.restart()`，停服→重新随机端口→`KugouEndpoints.baseUrl` 更新，dfid/mid 因 device_info.json 持久化保持不变）。

### 4.5 JNI 签名必须与 Rust 导出一致

**问题**：Rust `lib.rs` 导出的 JNI 函数签名是 `nativeStartNode(jint port, jstring dataDir)`，旧 Kotlin 声明的是 `nativeStartNode(Array<String>, String)`，参数不匹配会崩溃/调用异常。

**解决**：`KugouApiService.kt` 的 `external` 声明必须与 Rust 侧一致（见 lib.rs），改了任一侧都要同步更新另一侧，并重打包验证。

### 4.6 networkapi 与 kugou_api_server 已分家

**问题**：旧架构中两处 `util/` 各自维护副本，容易失同步。Rust 化后 kugou_api_server 已是 Rust，networkapi 仍是 Node.js。

**解决**：修改 Rust 端工具函数只影响 `rust/src/`；如需同步登录行为，以 Rust 实现为准，networkapi 单点修改即可，不再有跨目录拷贝。

### 4.6 登录已全部本地化，networkapi 已退役
- Dart 端 `kugou_api_client.dart` 曾把登录路径硬编码到 `http://115.29.236.96:5621`（`_loginPaths`），已移除——全部请求统一走本地 `KugouEndpoints.baseUrl`。

### 4.7 桌面快捷方式图标与 shrinkResources（keep.xml 位置坑）

**问题**：release 构建开启 `isShrinkResources = true`，桌面长按快捷方式图标（`ic_shortcut_*` drawable）只在 Dart 层以字符串资源名引用（`quick_actions` 的 `ShortcutItem.icon`，运行时 `getIdentifier` 查找），资源收缩器静态分析看不到 → 被当作未引用资源删除，快捷方式回退显示安卓机器人默认图标。

**解决**：`android/app/src/main/res/raw/keep.xml`（**必须是 `res/raw/` 目录下的文件**）声明 `tools:keep="@drawable/ic_shortcut_*"`。

**坑（已踩）**：2026-08-20 曾有人修复此问题却把内容直接写到了 `res/raw` **文件本身**（正确应是 `res/raw/keep.xml`），构建不报错但收缩器读不到规则，图标照样被删。任何 res 下的新资源配置前先确认目标路径是目录结构。另外通配符写法覆盖全部 13 个候选（逐个列举曾漏掉 `ic_shortcut_brush`）。

### 4.8 Android 构建配置

- `compileSdk = 36`，`targetSdk = 35`，`ndkVersion = "28.2.13676358"`
- 已移除 CMake/`externalNativeBuild`（`cpp/` 目录删除）；JNI 符号直接来自 `libkugou_server.so`
- Release 构建启用 R8 混淆（`isMinifyEnabled = true`），原生库不参与混淆；修改 JNI 后检查 `proguard-rules.pro`
- 无 `keystore.properties` 时自动使用 debug 签名

### 4.9 Dart 分析规则

- 使用 `package:flutter_lints/flutter.yaml`
- `avoid_print` 默认开启，但项目中大量使用 `print()` 做调试日志（如服务器启动日志），通过 `// ignore: avoid_print` 抑制
- 部分 `discarded_futures` 也通过 ignore 注释处理

### 4.10 `kugou_server` crate 的 release 构建参数

- `crate-type = ["cdylib", "rlib"]`，cdylib 用于导出 FFI/JNI 符号，rlib 用于测试；`jni` 依赖仅在 Android target 下引入（桌面构建不编译 JNI 符号）
- `[profile.release]`：`opt-level = 3`（性能优先，HTTP 服务器是 CPU 密集型）、`lto = true`、`panic = "abort"`（Android 端 panic 即崩溃，务必避免在请求线程 panic——4.2 曾踩坑）；**不要使用 `strip = true`**——cdylib 的动态导出符号（`start_server` / `Java_com_md3music_*` JNI 符号）可能被 strip 移除，导致 App 启动找不到符号崩溃

---

## 5. 技术栈速查

| 层 | 技术 | 版本要求 |
|----|------|----------|
| 前端框架 | Flutter | SDK ^3.12.0 |
| 状态管理 | Provider (ChangeNotifier) | ^6.1.2 |
| 音频播放 | just_audio + just_audio_background | ^0.9.34 |
| 本地存储 | sqflite + shared_preferences | 2.3.3+1 / ^2.5.0 |
| 网络请求 | dio + http | ^5.4.0 / ^1.2.1 |
| 主题 | dynamic_color + material_color_utilities | MD3 动态取色 |
| 嵌入式 API 服务器 | Rust（cdylib） + tiny_http + ureq | Rust 2021 / tiny_http 0.12 / ureq 2 |
| 加密 | rsa / aes / md-5 / sha1 / sha2 / base64（CBC + PKCS7 手动实现） | 与 JS CryptoJS 行为对齐 |
| 原生桥接 | JNI + dart:ffi | NDK 28 |
| 构建工具 | Gradle (Kotlin DSL) | Java 17 |
| 公网服务器 | 已退役（原为 Node.js + Express，登录已改由 Rust 本地直连） | — |

---

## 6. 常用命令

```bash
# Rust 服务器构建 / 测试
cd kugou_api_server/rust
cargo build                     # 编译检查
cargo test                      # 本地冒烟测试
cargo clippy                    # 静态检查
cargo build --release           # 主机 release cdylib

# 交叉编译（4 ABI，见 4.1 的完整 env 前缀）
cargo build --target aarch64-linux-android --release   # 复制到 jniLibs/arm64-v8a
cargo build --target armv7-linux-androideabi --release # jniLibs/armeabi-v7a
cargo build --target i686-linux-android --release      # jniLibs/x86
cargo build --target x86_64-linux-android --release    # jniLibs/x86_64

# 日常开发
flutter run                               # 调试运行
flutter build apk --release --split-per-abi  # 发布构建

# 测试 API（需先启动 App / 本地服务器）
powershell -File scripts\test_api.ps1     # 测试本地 API 接口

# 代码检查
flutter analyze                           # Dart 静态分析
```

---

## 7. Git 分支约定

> 本仓库的 `arch-local-first` 与 `rust-local-two` 是基于 `c7ec59b` 并行分叉的两个开发分支，各自独立演进（见 7.3）。
> **切换分支时注意**：不同分支的 AGENTS.md 内容不同（`arch-local-first` 上描述的是 Node.js 架构，`rust-local-two` 上是 Rust 架构），请以当前分支的文件为准。

**两分支快速对照**：

| 维度 | `rust-local-two`（当前） | `arch-local-first` |
|------|------|------|
| 本地 API 服务器 | Rust（`libkugou_server.so` + tiny_http + ureq） | Node.js（`libnode.so` + Express） |
| Dart 服务类 | `KugouApiServer`（`kugou_server.dart`） | `NodeJsServer`（`nodejs_server.dart`） |
| Kotlin 服务 | `KugouApiService` | `NodeJsService` |
| 服务器构建入口 | `build_android.sh`（cargo 交叉编译） | `build_nodejs_server.bat`（esbuild） |
| jniLibs | `libkugou_server.so`（4 ABI，已提交进 Git） | `libnode.so`（需 `setup_native.bat` 获取） |
| 原生层 | 无 CMake（JNI 符号来自 .so） | CMake + `cpp/` 桥接目录 |
| 前端独有变更 | apple_lyrics 重构（渲染实现改动） | apple_lyrics 性能优化、搜索结果去重等 |
| 对应文档 | 本文档正文（1~6 节） | 该分支自带版本的 AGENTS.md |

### 7.1 `rust-local-two`（Rust 化改造分支，当前所在分支）

**定位**：Rust 化改造主线（PR #35，作者 LyonHyrik）。用嵌入式 Rust API 服务器替换 Node.js 方案，本文档 1~6 节描述的即为该分支架构。

**独有提交**（`git log rust-local-two --not arch-local-first`）：

| 提交 | 说明 |
|------|------|
| `b86ec67` | feat: 用嵌入式 Rust API 服务器替换 Node.js 方案（核心变更，见下） |
| `ed96df0` | Merge pull request #35 from LyonHyrik/rust-local-two |

**核心变更内容**：

- 新增 `kugou_api_server/rust/` crate（tiny_http + ureq），编译为 `libkugou_server.so` cdylib，覆盖 160+ 酷狗 API 端点
- 修复 AES-192/256 CBC 密文错误（cbc crate 输出异常，改为在 `BlockEncrypt`/`BlockDecrypt` 上手动实现 CBC + PKCS7，与 JS CryptoJS 逐字节一致）；新增 smoke 测试中的 AES-CBC 对照回归
- 修复关注/取消关注歌手 userid 读取（`param_or_cookie_num`），Rust 与旧 Node 行为对齐
- Kotlin：`NodeJsService` → `KugouApiService`；Dart：`nodejs_server` → `kugou_server`（MethodChannel `com.md3music.md3music/kugou_api` + dart:ffi 兜底）
- jniLibs 提交 4 ABI（arm64-v8a、armeabi-v7a、x86、x86_64）的 `libkugou_server.so`；移除 `cpp/` CMake 原生构建
- 新增一键交叉编译脚本 `kugou_api_server/rust/build_android.sh`
- 附带前端改动：`apple_lyrics_view.dart` / `word_renderer.dart` 重构、`full_player.dart` 精简、登录页/收藏页小改

**相关命令**：见本文档 3、6 节；新增 API 模块统一在 `kugou_api_server/rust/src/modules/` 下实现（勿再改 `module/` 下旧 JS 模块）。

### 7.2 `arch-local-first`（Node.js 架构 + 前端优化分支）

**定位**：并行开发分支。保持 Node.js 旧架构（`libnode.so` + Express `server_bundle.js`）不变，叠加来自 zzyoxml 的前端功能与性能优化。该分支上的 AGENTS.md 是 Node.js 方案说明（构建需 `build_nodejs_server.bat`）。

**独有提交**（`git log arch-local-first --not rust-local-two`）：

| 提交 | 说明 |
|------|------|
| `384e80b` | perf(apple_lyrics): 优化上浮动画功耗与平滑度 |
| `1fa6010` | perf(apple_lyrics): 字内渐变改为行级 maskX 模型，扩大渐变范围 |
| `cb3ff95` | perf(apple_lyrics): 修复真正的卡顿瓶颈 |
| `f82f589` | revert(lyrics): 还原被禁用的文字上浮动画 |
| `1492588` | perf(lyrics): 复用辉光层 Paint 对象，消除每帧分配 |
| `fd100db` | fix(ui): 搜索结果去重 + 进度条拖动自动暂停 |
| `59aa692` | Merge branch 'zzyoxml:arch-local-first' into arch-local-first |

**核心变更内容**：

- **apple_lyrics 性能优化**：修复歌词卡顿瓶颈、字内渐变改为行级 `maskX` 模型、上浮动画功耗与平滑度优化、辉光层 `Paint` 对象复用消除每帧分配、还原被禁用的文字上浮动画
- **UI 修复**：搜索结果去重、进度条拖动自动暂停

**注意**：该分支的 `apple_lyrics_view.dart` / `word_renderer.dart` 与 7.1 分支的实现已分叉（各自独立重构），后续合流需手动合并。

### 7.3 分支关系与切换

- **remote**：`origin = https://github.com/Little-White3110/md3Music`
- **分叉点**：两分支基于 `c7ec59b` 并行分叉，后端架构（Rust vs Node.js）与前端功能各自演进；后续合流需手动处理 AGENTS.md、构建脚本、jniLibs 及歌词渲染代码的差异
- **切换分支的坑**：两分支 jniLibs 下的 `.so` 不同（`libkugou_server.so` vs `libnode.so`）；切回旧架构分支时，残留的 `libnode.so` 会以 untracked 文件形式留在工作区，可手动删除
- **其他分支**：`main`（旧主线，无 AGENTS.md，Node.js）；`feat-*` / `fix-*`（一次性功能/修复分支）；`pr/update-md3music-content`（内容更新 PR 分支）

---

## 8. 公开版（public）偏好约定（用户决策，勿违反）

> 本节记录用户在「公开库 zzyoxml/md3Music / rust-local-two」上确认的长期偏好。
> 任何同步/移植/开发都必须遵守；与私有库（premium）行为冲突时以本节为准。

### 8.1 权限（敏感权限一律不弹窗、不声明）
- ❌ **不请求「所有文件访问」权限**（`MANAGE_EXTERNAL_STORAGE`）：公开版不含下载/边听边存，无需修改公共目录文件元数据；Manifest 与 main.dart 均已移除
- ❌ **不请求「忽略电池优化」（电量无限制）权限弹窗**（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`）：启动流程不再请求
- ✅ 仅保留必需权限：通知（POST_NOTIFICATIONS）、麦克风/媒体音频（RECORD_AUDIO / READ_MEDIA_AUDIO）、悬浮窗（SYSTEM_ALERT_WINDOW，浮窗识曲用）等

### 8.2 包名与平台
- ✅ 保持 `com.md3music.md3music`（applicationId/namespace/JNI 符号 `Java_com_md3music_md3music_*`/MethodChannel 名）
- ❌ 不采用私有库的 `com.md3music.premium` 改名
- ❌ 不支持 Windows（公开版仅 Android）；不移植 `windows/`、`just_audio_windows`、`video_player_win`、`build_windows.ps1` 等

### 8.3 功能范围
- ❌ **不移植「边听边存」与「下载」功能**：stream_cache_*、download_*、downloads_*、metadata_writer 及其在 player_provider/kugou_provider/settings/playlist/song_list_item 等的嵌入点
- ✅ **浮窗识曲需要保留**（源自私有库 Aug 13 提交，用户明确要）
- ✅ 歌词字重、锁屏歌词、SuperLyric、MV 画中画、刷刷、已购页、听歌等级、多账号等已移植功能均保留

### 8.4 UI 决策
- ✅ Tab 默认配置：`LaunchPad`/`发现`/`我的` 默认显示；**封面流/我收藏/私人FM 默认关闭**；本地音乐默认开启；其余可选 Tab（搜索/排行榜/编辑精选/听歌识曲/听书/场景音乐/频道/刷刷/设置）默认隐藏
- ✅ 播放页右上角菜单**不显示分享入口**
- ✅ 发现页搜索入口为**页面顶部内嵌搜索框**（样式对齐设置页总览页搜索框：`surfaceContainerHighest` alpha 0.5、圆角 28、搜索图标 + 提示「搜索歌曲、歌手、专辑」，只读外观点击跳转搜索页）；右上角仅保留识曲图标；标题为 `发现`
- ✅ **各页搜索框统一样式**（设置页/发现页/本地音乐页/搜索页）：`surfaceContainerHighest` alpha 0.5 半透明、圆角 28，勿用实心 `surfaceContainerHigh/Highest`
- ✅ LaunchPad 标题**加粗**（titleLarge + w600，与其他一级页面一致）
- ✅ Tab 默认顺序：**`发现` 第一个（首页）、`LaunchPad` 第二个、`我的` 第三**（`kDefaultTabs`）；注意只影响新用户/重置配置，已有持久化 order 的设备不自动迁移

### 8.5 交互/UI 细节（公开版）
- ✅ 退出 App：**「再按一次返回退出」**（3 秒窗口），**不再弹确认对话框**；提示用**系统原生 Toast**（`app_toast.dart` 的 `showToast`，fluttertoast，非 SnackBar）
- ✅ 一首歌添加到歌单前**先查重**：已在目标歌单中则提示「已在歌单中」并跳过，不重复添加（MD3/AM 两套播放器均生效）
- ✅ 发现页顶部**文字/图标区域置于顶层**（opaque）：无壁纸时背景恒为不透明 surface，不与滚动内容重叠变色
- ✅ 底部导航栏（NavigationBar）与平板侧栏（NavigationRail）**都只显示图标、不显示文字**
- ✅ 播放页随机/循环按钮激活时**有圆形底色**（primaryContainer 圆底 + onPrimaryContainer 图标，v5.2.1 同款），突出强调避免看不清；未激活为透明灰图标

### 8.6 自定义背景 / 导航布局（公开版）
- ✅ 启用自定义背景图时，**发现页顶部完全透明**（`ScrollAwareAppBar` opaque 分支返回 `Colors.transparent`，与「我的收藏」等普通 AppBar 一致，壁纸透出透明度上下统一）；**搜索页/搜索结果页顶部同样完全透明**（`search_page.dart` 的 SliverAppBar 与结果 Tab 栏容器按 `useBackgroundImage` 切换，勿写死 `surface`）；**用户协议页底部勾选+按钮区**（`user_agreement_page.dart`）壁纸开启时为 surface alpha 0.2，与正文区透明度一致；MiniPlayer、底部导航栏、平板侧栏透出模糊背景图（表面 alpha 0.2，背景图清晰主导）
- ✅ 底部导航栏**高度减半、无浮动动画**（height 44，图标按钮静态切换，去掉悬浮 padding）
- ✅ 横屏侧栏改用**自定义 `CompactNavigationRail`**（不再用 NavigationRail）：宽度 34 仅容纳图标、**图标间距 6dp（M3 内置 12dp 的一半）**、**图标组垂直居中**（原 SingleChildScrollView 包裹会破坏 NavigationRail 内部 Flexible+Align 居中，图标堆顶部）、tab 过多时可滚动；背景/指示器颜色读 NavigationRailTheme（壁纸模式自动半透明）
- ✅ MiniPlayer **留白减半**：内边距 horizontal 8→4 / vertical 4→2、封面-文字间距 12→8、右侧按钮 `VisualDensity.compact`（48→40）

### 8.7 尺寸与「显示大小」（勿回退到逐元素缩放）

- ✅ **页面尺寸一律直接写 dp 设计 token**（封面 52、导航栏 44、侧栏 34…）。Flutter 的逻辑像素本身就是 DPI 无关的，**这就是适配不同 DPI 的正解**；屏幕差异交给断点（`getScreenType` / `isPadLayout`）、可用空间（LayoutBuilder）与 WindowInsets（SafeArea），原生层只负责正确提供窗口与 Insets（edgeToEdge）
- ❌ **不要再引入逐元素缩放辅助函数**（历史上的 `core/utils/ui_scale.dart` + `context.scaledSize()` / `scaledCache()`，曾散落 31 个文件 210 处调用，已于「显示大小」重写中整体删除）。它的根本缺陷：元素被乘大而可用逻辑尺寸不变，放大必然溢出，只能靠补 `NavigationBar.height` / `AppBar.toolbarHeight` 和整页 `noScaling` 豁免打补丁
- ✅ 整体缩放**只有一个点**：`core/layout/ui_density.dart` 的 `DisplayScaleScope`（挂在 `MaterialApp.builder` 最外层）。语义等同安卓系统「显示大小」：`MediaQuery` 逻辑尺寸/insets ÷ s、devicePixelRatio × s，再由 `FittedBox` 映射回物理屏。档位 0.85~1.30（键 `ui_display_scale`，旧键 `ui_scale` 已在加载时清理、不做值迁移）
- ✅ 不变量：`MediaQuery.sizeOf × MediaQuery.devicePixelRatioOf` 恒等于真实物理像素 —— "宽 × dpr = 解码宽度"（如 `app_background.dart`）之类的算法据此保持正确
- ✅ 系统「字体大小」（`MediaQuery.textScaler`）**跟随但限幅 1.30x**（下限钉 1.0，想变小走显示大小滑块）。唯二豁免点：`lyrics_view.dart`（字号是用户单独设置项，且行高缓存已按该字号预算过）与设置页的迷你预览示意图；`AppleLyricsView` 用裸 `TextPainter`，本来就不受影响
- ✅ Pad 布局判定统一走 `isPadLayout(context)`（按**有效视口**最短边 ≥ 600dp），**不要**用设备物理 dp —— 显示大小调大后原生同样会跌出 sw600dp 桶

