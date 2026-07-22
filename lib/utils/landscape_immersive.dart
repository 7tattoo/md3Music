import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 根据当前屏幕方向启用或禁用全屏沉浸模式。
///
/// - 横屏（landscape）：启用 [SystemUiMode.immersiveSticky]，隐藏状态栏和导航栏。
/// - 竖屏（portrait）：启用 [SystemUiMode.edgeToEdge]，导航栏透明，内容延伸到导航栏后面。
///
/// 调用时机：
/// - 全屏播放器 initState 时首次调用
/// - didChangeMetrics 回调中调用（用户旋转设备时响应）
/// - 全屏播放器 dispose 时调 [restoreSystemUi] 恢复
void applyImmersiveForOrientation() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final isLandscape = view.physicalSize.width > view.physicalSize.height;
  if (isLandscape) {
    // 横屏：完全沉浸，隐藏状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    // 竖屏：edgeToEdge，导航栏透明，内容延伸到导航栏后面
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }
}

/// 退出全屏播放器时恢复系统栏显示，根据当前主题设置导航栏颜色。
void restoreSystemUi({Color? navigationBarColor, Brightness? statusBarBrightness}) {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarIconBrightness: statusBarBrightness ?? Brightness.dark,
    systemNavigationBarColor: navigationBarColor ?? const Color(0x00000000),
    systemNavigationBarIconBrightness: statusBarBrightness ?? Brightness.dark,
  ));
}
