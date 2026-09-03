import java.util.Properties
import java.io.FileInputStream
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Compose 编译器插件（Kotlin 2.x 内置，版本随 Kotlin）
    id("org.jetbrains.kotlin.plugin.compose")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}

// ============================================================
// 多包名发布支持
// ------------------------------------------------------------
// applicationId 可被覆盖，用于同一份代码打出多个互不冲突的安装包
// （车机白名单场景：不同车机识别不同包名）。优先级：
//   环境变量 APP_ID  >  Gradle 属性 -PappId  >  默认 cn.kuwo.kwmusiccar
//
// namespace 必须保持 cn.kuwo.kwmusiccar 不变：
// Kotlin 包名与 cpp 里的 JNI 符号 Java_cn_kuwo_kwmusiccar_* 都绑定 namespace，
// 改动会导致 UnsatisfiedLinkError。
// ============================================================
val resolvedApplicationId: String =
    providers.environmentVariable("APP_ID").orNull
        ?: (findProperty("appId") as String?)
        ?: "cn.kuwo.kwmusiccar"

// ============================================================
// versionCode 按构建时间生成：(YY-20)MMDDHHmm
// ------------------------------------------------------------
// 例：2026-09-03 17:44 → 609031744（单调递增，便于回溯构建时刻）
//
// 注意：versionCode 是 Int32，上限 2147483647。完整的 YYMMDDHHmm
// （如 2609031744）会溢出，因此去掉世纪位，该编码可用到 2040 年底。
//
// CI 传 -PbuildVersionCode / -PbuildVersionName 统一所有并行 job 的版本号，
// 避免各 job 各自取时间导致同一 Release 里版本号不一致。
// ============================================================
val resolvedVersionCode: Int =
    (findProperty("buildVersionCode") as String?)?.toIntOrNull()
        ?: providers.environmentVariable("BUILD_VERSION_CODE").orNull?.toIntOrNull()
        ?: LocalDateTime.now()
            .format(DateTimeFormatter.ofPattern("yyMMddHHmm"))
            .toLong().minus(2_000_000_000L).toInt()

// versionName 覆盖值（为空时在 defaultConfig 里回退 flutter.versionName —
// flutter 扩展在 android 块内取值最稳，不在顶层作用域引用）
val overrideVersionName: String? =
    (findProperty("buildVersionName") as String?)
        ?: providers.environmentVariable("BUILD_VERSION_NAME").orNull

android {
    namespace = "cn.kuwo.kwmusiccar"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = resolvedApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = resolvedVersionCode
        versionName = overrideVersionName ?: flutter.versionName
        // USB 独占输出 C++ 驱动：只编译与 jniLibs 相同的 4 个 ABI
        externalNativeBuild {
            cmake {
                abiFilters("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
            }
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Use the persistent release signing config (if keystore.properties exists)
            // Falls back to debug signing when keystore.properties is missing (CI / first build)
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        debug {
            // Disable symbol stripping for Gradle 9.x compatibility
            ndk {
                debugSymbolLevel = "none"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        // MiuixDiscoverActivity 使用 Compose + miuix 组件
        compose = true
    }
}

// 注：多包名并行构建的产物重命名在 CI 里做（mv），不改 AGP outputFileName。
// 原因：flutter build apk 会按固定名 app-<abi>-release.apk 从 build/app/outputs/apk
// 复制到 build/app/outputs/flutter-apk，改 AGP 输出名会让该复制步骤找不到文件。

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.media:media:1.6.0")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("io.github.proify.lyricon:provider:0.1.70")
    implementation("io.github.proify.lyricon.lyric:model:0.1.70")
    // SuperLyricApi：基于 Binder 的系统级实时歌词 API（jnitpack，settings.gradle.kts 已声明）
    implementation("com.github.HChenX:SuperLyricApi:3.4")
    // JAudioTagger 社区分叉（支持 MP3/FLAC/Ogg/M4A 等格式的 ID3v2 / VorbisComment 标签读写，
    // 用于在下载完成后向音频文件嵌入标题/艺术家/专辑/封面/歌词）。
    // JitPack 上 AdrienPoupa 分叉仅有 2.2.3（无 2.2.5）。
    implementation("com.github.AdrienPoupa:jaudiotagger:2.2.3")
    // 方案B阶段1：app 侧 Kotlin 引用 androidx.media3.common 类型（UnstableApi、Player 等）。
    // media3-common 为单一 maven 源（fork 同版本 1.4.1），此处显式依赖以便编译期可见
    // （fork 用 implementation 隐藏了传递依赖）。session/exoplayer 仍是 fork 本地源码，勿加 maven。
    implementation("androidx.media3:media3-common:1.4.1")

    // ==================== Miuix 风格测试页（原生 Compose） ====================
    // miuix-android 0.8.8：Kotlin 2.3.20 + Compose Foundation 1.10.3 编译，
    // minCompileSdk=36，与当前工程（compileSdk 36 / Kotlin 2.3.20）完全匹配
    implementation("top.yukonga.miuix.kmp:miuix-android:0.8.8")
    // Compose 宿主（ComposeView）+ 图片加载（Coil）
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("io.coil-kt:coil-compose:2.7.0")
}

// MD3Music fork: 全局强制 media3 版本与本地 just_audio fork 的 exoplayer 源码一致（1.4.1）。
// video_player 等库声明更高版本（1.9.2），若不强制会出现重复类（本地源码 vs maven 1.9.2）。
// media3-exoplayer 的 maven 版本全局排除——由 just_audio fork 内的本地源码提供。
configurations.all {
    exclude(group = "androidx.media3", module = "media3-exoplayer")
    resolutionStrategy {
        force(
            "androidx.media3:media3-common:1.4.1",
            "androidx.media3:media3-container:1.4.1",
            "androidx.media3:media3-database:1.4.1",
            "androidx.media3:media3-datasource:1.4.1",
            "androidx.media3:media3-decoder:1.4.1",
            "androidx.media3:media3-exoplayer-dash:1.4.1",
            "androidx.media3:media3-exoplayer-hls:1.4.1",
            "androidx.media3:media3-exoplayer-rtsp:1.4.1",
            "androidx.media3:media3-exoplayer-smoothstreaming:1.4.1",
            "androidx.media3:media3-extractor:1.4.1"
        )
    }
}

flutter {
    source = "../.."
}
