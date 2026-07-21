# Lyricon Provider 开发文档

> 来源：[Lyricon Provider 官方文档](https://tomakino.github.io/lyricon/zh-cn/developer/provider/)
> 整理日期：2026-07-19

---

## 1. Provider 概述

Provider 用于向词幕（Lyricon）发送歌曲、歌词、播放状态和显示配置。适用于播放器或歌词来源插件。

### 接入流程

1. 添加 Provider 依赖
2. 配置 `AndroidManifest.xml` 元数据
3. 创建 `LyriconProvider`
4. 调用 `register()` 注册
5. 通过 `provider.player` 发送数据
6. 不再使用时调用 `unregister()` 或 `destroy()`

---

## 2. 依赖

```kotlin
implementation("io.github.proify.lyricon:provider:0.1.70")
```

> **注意**：Provider Bridge 当前在 Android 8.1 以下会返回空实现。

---

## 3. 快速开始

### 3.1 添加依赖

在应用模块的 `build.gradle.kts` 中添加：

```kotlin
implementation("io.github.proify.lyricon:provider:0.1.70")
```

### 3.2 创建 Provider

```kotlin
val provider = LyriconFactory.createProvider(context)
```

如果需要自定义注册信息，可以传入更多参数：

```kotlin
val provider = LyriconFactory.createProvider(
    context = context,
    providerPackageName = context.packageName,
    playerPackageName = context.packageName,
    logo = null,
    metadata = null
)
```

### 3.3 监听连接状态

```kotlin
provider.service.addConnectionListener {
    onConnected { provider ->
        // 首次连接成功
    }
    onReconnected { provider ->
        // 断线后重新连接成功
    }
    onDisconnected { provider ->
        // 连接断开
    }
    onConnectTimeout { provider ->
        // 连接中心服务超时
    }
}
```

### 3.4 注册 Provider

```kotlin
provider.register()
```

注册成功后，Lyricon 中心服务会开始接收该 Provider 推送的数据。

### 3.5 发送纯文本歌词

```kotlin
val player = provider.player
player.setPlaybackState(true)
player.sendText("我无法只是普通朋友")
```

`sendText()` 适用于不需要时间轴控制的简单歌词展示。调用该方法会清除之前设置的歌曲信息，使播放器进入纯文本模式。

### 3.6 发送结构化歌曲

```kotlin
player.setSong(
    Song(
        id = "song-id",
        name = "普通朋友",
        artist = "陶喆",
        duration = 2000,
        lyrics = listOf(
            RichLyricLine(
                begin = 0,
                end = 1000,
                text = "我无法只是普通朋友"
            ),
            RichLyricLine(
                begin = 1000,
                end = 2000,
                text = "不想做普通朋友"
            )
        )
    )
)
player.setPosition(100)
```

### 3.7 释放资源

```kotlin
provider.unregister()
provider.destroy()
```

- `unregister()`：主动断开当前中心服务连接
- `destroy()`：释放监听器、注册回调和远端连接资源

---

## 4. Manifest 配置

Provider 应用需要在 `AndroidManifest.xml` 的 `<application>` 节点中声明 Lyricon 元数据，用于让 Lyricon 识别该应用是一个歌词提供端。

### 4.1 必需配置

```xml
<application>
    <meta-data android:name="lyricon_module" android:value="true" />
    <meta-data android:name="lyricon_module_author" android:value="your name" />
    <meta-data android:name="lyricon_module_description" android:value="module description" />
</application>
```

| 字段 | 说明 |
|---|---|
| `lyricon_module` | 标记当前应用为 Lyricon 模块 |
| `lyricon_module_author` | 模块作者名称 |
| `lyricon_module_description` | 模块说明 |

### 4.2 模块标签

模块标签用于声明插件支持的歌词能力，仅用于展示。

```xml
<meta-data android:name="lyricon_module_tags" android:resource="@array/lyricon_module_tags" />
```

在 `res/values/arrays.xml` 中声明：

```xml
<string-array name="lyricon_module_tags">
    <item>$syllable</item>
    <item>$translation</item>
</string-array>
```

支持的标签：

| Code | 含义 |
|---|---|
| `$syllable` | 支持逐字 / 动态歌词 |
| `$translation` | 支持歌词翻译显示 |

### 4.3 常见问题

- `lyricon_module` 缺失时，Lyricon 可能不会把该应用识别为模块
- 标签只表示能力声明，不会自动启用逐字歌词或翻译歌词
- 作者和描述建议使用面向用户的可读文本，避免只填写包名或内部代号

---

## 5. 连接生命周期

`LyriconProvider` 负责与 Lyricon 中心服务建立连接。Provider 需要注册到中心服务后，才能发送歌曲、歌词和播放状态。

### 5.1 注册

```kotlin
provider.register()
```

`register()` 会向中心服务发送注册请求。返回值表示请求是否成功发出，不代表业务数据已经被显示。

### 5.2 注销

```kotlin
provider.unregister()
```

`unregister()` 用于主动断开当前中心服务连接。适合播放器退出、服务停止或临时不再推送歌词的场景。

### 5.3 销毁

```kotlin
provider.destroy()
```

`destroy()` 会释放监听器、注册回调和远端连接资源。通常在应用组件最终销毁时调用。

### 5.4 连接监听

```kotlin
provider.service.addConnectionListener {
    onConnected { }
    onReconnected { }
    onDisconnected { }
    onConnectTimeout { }
}
```

| 回调 | 说明 |
|---|---|
| `onConnected` | 首次连接成功 |
| `onReconnected` | 断线后重新连接成功 |
| `onDisconnected` | 连接断开 |
| `onConnectTimeout` | 连接中心服务超时 |

### 5.5 自动同步

```kotlin
provider.autoSync = true
```

`autoSync` 控制连接或重连成功后是否自动同步最近一次缓存的播放器状态。默认行为由实现决定，通常建议保持启用，避免中心服务重启后歌词状态丢失。

### 5.6 推荐实践

- 在播放器服务或应用级组件中持有 Provider，避免频繁创建
- 注册后先同步当前歌曲，再同步播放状态和进度
- 连接超时时提示用户检查 Lyricon、LSPosed 或 LocalCentralService 状态
- 应用退出或服务停止时调用 `destroy()`

---

## 6. 播放器控制

Provider 通过 `provider.player` 获取 `RemotePlayer`，并向 Lyricon 中心服务发送播放器状态。

```kotlin
val player = provider.player
```

### 6.1 设置歌曲

```kotlin
player.setSong(song)
```

`setSong(song: Song?)` 用于设置当前播放歌曲和结构化歌词。

- `song != null`：更新当前歌曲
- `song == null`：清空当前播放

### 6.2 发送纯文本

```kotlin
player.sendText("我无法只是普通朋友")
```

`sendText(text: String?)` 用于发送无时间轴的普通文本。调用该方法会清除之前设置的歌曲信息，播放器进入纯文本模式。

### 6.3 设置播放状态

```kotlin
player.setPlaybackState(true)
```

`setPlaybackState(playing: Boolean)` 用于同步播放/暂停状态。

- `true`：播放中
- `false`：暂停

也可以使用 Android `PlaybackState`：

```kotlin
player.setPlaybackState(playbackState)
```

中心服务可根据 `PlaybackState.position`、播放速度和更新时间计算实时进度。传入 `null` 表示停止使用该模式。

### 6.4 同步播放位置

```kotlin
player.setPosition(1000)
```

`setPosition(position: Long)` 用于更新当前播放位置，单位为毫秒。它通常用于持续同步播放进度。

### 6.5 跳转播放位置

```kotlin
player.seekTo(60000)
```

`seekTo(position: Long)` 表示用户或播放器发生了主动跳转。它适合进度条拖动、切歌恢复进度等场景。

### 6.6 设置位置读取间隔

```kotlin
player.setPositionUpdateInterval(500)
```

`setPositionUpdateInterval(interval: Int)` 用于设置中心服务读取播放位置的间隔，一般无需修改。

### 6.7 翻译和罗马音

```kotlin
player.setDisplayTranslation(true)
player.setDisplayRoma(true)
```

这两个方法只控制显示状态。是否有内容可显示，取决于 `RichLyricLine` 中是否提供了翻译或罗马音数据。

### 6.8 推荐调用顺序

```kotlin
player.setSong(song)
player.setPosition(currentPosition)
player.setPlaybackState(isPlaying)
player.setDisplayTranslation(displayTranslation)
player.setDisplayRoma(displayRoma)
```

如果只是展示临时文本：

```kotlin
player.setPlaybackState(true)
player.sendText(text)
```

---

## 7. 歌词数据结构

Provider 使用 `Song`、`RichLyricLine` 和 `LyricWord` 描述歌曲和歌词。时间单位统一为毫秒。

### 7.1 Song

`Song` 表示当前歌曲。常用字段包括：

| 字段 | 说明 |
|---|---|
| `id` | 歌曲唯一标识，建议稳定且可复用 |
| `name` | 歌曲名称 |
| `artist` | 歌手名称 |
| `duration` | 歌曲总时长，单位毫秒 |
| `lyrics` | 歌词行列表 |

可以先发送只有基础信息的歌曲占位：

```kotlin
player.setSong(
    Song(
        name = "普通朋友",
        artist = "陶喆"
    )
)
```

### 7.2 行级歌词

行级歌词适合普通 LRC 场景，只包含每行的开始和结束时间。

```kotlin
player.setSong(
    Song(
        id = "song-id",
        name = "普通朋友",
        artist = "陶喆",
        duration = 2000,
        lyrics = listOf(
            RichLyricLine(
                begin = 0,
                end = 1000,
                text = "我无法只是普通朋友"
            ),
            RichLyricLine(
                begin = 1000,
                end = 2000,
                text = "不想做普通朋友"
            )
        )
    )
)
```

设置歌曲后，应同步当前播放进度：

```kotlin
player.setPosition(100)
```

### 7.3 逐字歌词

逐字歌词通过 `RichLyricLine.words` 描述每个词或字的时间范围。

```kotlin
player.setSong(
    Song(
        id = "song-id",
        name = "普通朋友",
        artist = "陶喆",
        duration = 1000,
        lyrics = listOf(
            RichLyricLine(
                begin = 0,
                end = 1000,
                text = "我无法只是普通朋友",
                words = listOf(
                    LyricWord(text = "我", begin = 0, end = 200),
                    LyricWord(text = "无法", begin = 200, end = 400),
                    LyricWord(text = "只是", begin = 400, end = 600),
                    LyricWord(text = "普通", begin = 600, end = 800),
                    LyricWord(text = "朋友", begin = 800, end = 1000)
                )
            )
        )
    )
)
```

### 7.4 翻译和次要歌词

`RichLyricLine` 可以同时携带主歌词、次要歌词和翻译歌词。

```kotlin
RichLyricLine(
    begin = 0,
    end = 1000,
    text = "我无法只是普通朋友",
    secondary = "（不想做普通朋友）",
    translation = "I can't just be a normal friend"
)
```

显示翻译需要同时满足：

- 歌词行中存在翻译内容
- Provider 调用了 `player.setDisplayTranslation(true)`
- Lyricon 展示端允许显示翻译

### 7.5 罗马音

如果歌词模型中提供了罗马音字段，可通过以下方式控制显示状态：

```kotlin
player.setDisplayRoma(true)
```

显示逻辑与翻译类似，开关只控制展示状态，不会自动生成罗马音。

### 7.6 建议

- `id` 尽量使用稳定的歌曲 ID，避免同一首歌重复创建不同状态
- `begin` 和 `end` 使用毫秒，且建议单调递增
- 逐字歌词的 `words` 时间范围应落在所在行的时间范围内
- 没有逐字数据时，提供行级时间轴即可
- 没有时间轴时，使用 `sendText()` 更简单

---

## 8. 本地测试

正常情况下，Provider 需要通过 Lyricon 在 LSPosed / Xposed 环境中激活的中心服务进行测试。如果当前设备无法使用 LSPosed，可以使用 LocalCentralService 做基础测试。

### 8.1 LocalCentralService

LocalCentralService 是一个用于测试的本地中心服务实现，提供 Lyricon 中心服务的部分能力，方便在无 LSPosed 环境下验证 Provider 接入流程。

下载地址：[LocalCentralService](https://github.com/proify/lyricon/releases/tag/localcentral)

### 8.2 测试步骤

1. 安装 LocalCentralService
2. 打开应用并激活服务
3. 授予悬浮窗权限
4. 在 Provider 创建时指定本地中心服务包名
5. 调用 `register()`
6. 推送播放状态和歌词，检查显示效果

### 8.3 Provider 配置

```kotlin
val provider = LyriconFactory.createProvider(
    context,
    centralPackageName = "io.github.lyricon.localcentralapp"
)
```

> **注意**：`centralPackageName` 指向 LocalCentralService 仅用于测试，正式发布前应删除该配置，使用默认中心服务包名。

### 8.4 测试建议

- 先使用 `sendText()` 验证连接是否正常
- 再使用 `setSong()` 验证结构化歌词
- 最后测试播放进度、翻译开关和罗马音开关
- 如果连接超时，先确认 LocalCentralService 是否已启动并授权悬浮窗权限

---

## 9. 常见问题

### 9.1 注册后为什么没有显示歌词？

可能原因：

- Lyricon 中心服务未运行
- LSPosed / Xposed 作用域未正确配置
- Provider 未调用 `register()`
- Provider 已连接但没有调用 `sendText()` 或 `setSong()`
- 使用 LocalCentralService 测试时未授予悬浮窗权限

### 9.2 `sendText()` 和 `setSong()` 有什么区别？

`sendText()` 用于发送无时间轴的普通文本，会清除之前设置的歌曲信息。

`setSong()` 用于发送结构化歌曲和歌词，适合行级歌词、逐字歌词、翻译歌词等场景。

### 9.3 什么时候用 `setPosition()`？

`setPosition()` 用于持续同步当前播放位置，例如播放器正常播放时定期更新进度。

### 9.4 什么时候用 `seekTo()`？

`seekTo()` 表示主动跳转到指定位置，例如用户拖动进度条、切歌后恢复播放位置。

### 9.5 翻译歌词为什么不显示？

需要同时满足：

- `RichLyricLine` 中提供了翻译字段
- 调用了 `player.setDisplayTranslation(true)`
- 展示端配置允许显示翻译

### 9.6 罗马音为什么不显示？

需要同时满足：

- 歌词数据中提供了罗马音内容
- 调用了 `player.setDisplayRoma(true)`
- 展示端配置允许显示罗马音

### 9.7 是否支持 Java？

Java 调用方式未经过完整验证，不保证 API 友好性或稳定性。建议使用 Kotlin 接入。

### 9.8 发布前需要检查什么？

- 删除 LocalCentralService 的 `centralPackageName` 测试配置
- 确认 `AndroidManifest.xml` 已声明 Lyricon 模块元数据
- 确认模块标签与实际能力一致
- 确认连接断开和应用退出时会释放资源

---

## 文档索引

| 章节 | 原始链接 |
|---|---|
| Provider 概览 | [index](https://tomakino.github.io/lyricon/zh-cn/developer/provider/) |
| 快速开始 | [quick-start](https://tomakino.github.io/lyricon/zh-cn/developer/provider/quick-start) |
| Manifest 配置 | [manifest](https://tomakino.github.io/lyricon/zh-cn/developer/provider/manifest) |
| 连接生命周期 | [connection](https://tomakino.github.io/lyricon/zh-cn/developer/provider/connection) |
| 播放器控制 | [player-control](https://tomakino.github.io/lyricon/zh-cn/developer/provider/player-control) |
| 歌词数据结构 | [lyrics-model](https://tomakino.github.io/lyricon/zh-cn/developer/provider/lyrics-model) |
| 本地测试 | [local-testing](https://tomakino.github.io/lyricon/zh-cn/developer/provider/local-testing) |
| 常见问题 | [faq](https://tomakino.github.io/lyricon/zh-cn/developer/provider/faq) |