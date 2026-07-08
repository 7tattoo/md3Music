import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:io' show Platform;
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/desktop_lyric_service.dart';
import 'core/services/media_notification_service.dart';
import 'services/nodejs_server.dart';

const String _kBatteryPromptShownKey = 'battery_prompt_shown';

/// 顶级 Navigator 的 GlobalKey，预留供后续扩展使用。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  // 注册通知栏/悬浮窗回调（悬浮窗内按钮 → DesktopLyricService；通知栏桌面歌词按钮 → toggle）
  MediaNotificationService.initCallbacks();
  DesktopLyricService.instance.registerNativeCallbacks();
  // 权限请求包裹 try/catch：在部分设备/早期阶段 permission_handler 可能抛
  // "Unable to detect current Android Activity"，不能让它中断启动流程。
  try {
    await _requestPermissions();
  } catch (e) {
    print('Request permissions error (ignored): $e');
  }

  // 先启动本地 Node.js API 服务器，确保就绪后再运行 App
  // 否则发现页 post-frame callback 发出的请求会因服务器未启动而全部失败
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await NodeJsServer.start();
    } catch (e) {
      print('Node.js server start error: $e');
    }
  }

  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  // Web 平台不支持 permission_handler，跳过所有权限请求
  if (kIsWeb) return;

  // Android 13+ 通知权限
  if (await Permission.notification.isDenied) {
    try {
      await Permission.notification.request();
    } catch (e) {
      print('Notification permission request failed: $e');
    }
  }
  // Android 14+ 媒体权限
  if (await Permission.audio.isDenied) {
    try {
      await Permission.audio.request();
    } catch (e) {
      print('Audio permission request failed: $e');
    }
  }
  // 忽略电池优化：只弹一次（不管用户选什么都标记为已弹）
  try {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_kBatteryPromptShownKey) ?? false;
    if (!alreadyShown) {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
      await prefs.setBool(_kBatteryPromptShownKey, true);
    }
  } catch (_) {}
}
