import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 全屏播放器竖屏下的系统栏样式。
///
/// **重要**：[AmStyleFullPlayer._buildFullLayout] 中 AnnotatedRegion 的 value
/// 必须引用本常量，确保 applyImmersiveForOrientation 与 AnnotatedRegion
/// 使用同一引用——否则 SystemUiOverlayStyle 未重写 ==，引用不等会触发
/// 平台 channel 真实调用，导致系统栏反复重设（视觉闪烁）。
const SystemUiOverlayStyle kPlayerOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarDividerColor: Color(0x00000000),
  // 关掉系统对比度增强，否则 Android 10+ 会给透明导航条铺一层半透明遮罩，
  // 小横条区域无法真正透出播放器背景
  systemNavigationBarContrastEnforced: false,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// 主页面（非播放器）系统栏样式：surface 背景 + 主题亮度图标。
///
/// 供全屏播放器拖拽展开期间使用：展开完成前保持主页面外观，
/// 避免系统栏提前切换成播放器的透明 + 浅色图标样式造成闪烁。
SystemUiOverlayStyle mainPageOverlayStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: scheme.surface,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: scheme.surface,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
  );
}

/// 根据当前屏幕方向启用或禁用全屏沉浸模式。
///
/// - 横屏（landscape）：启用 [SystemUiMode.immersiveSticky]，隐藏状态栏和导航栏。
/// - 竖屏（portrait）：启用 [SystemUiMode.edgeToEdge]，导航栏透明，内容延伸到导航栏后面。
///
/// 调用时机：
/// - 全屏播放器 initState 时首次调用
/// - didChangeMetrics 回调中调用（用户旋转设备时响应）
/// - 全屏播放器 dispose 时调 [restoreSystemUi] 恢复（确保从横屏沉浸模式正确退出）
void applyImmersiveForOrientation() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final isLandscape = view.physicalSize.width > view.physicalSize.height;
  if (isLandscape) {
    // 横屏：完全沉浸，隐藏状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    // 竖屏：edgeToEdge，导航栏透明，内容延伸到导航栏后面。
    // 先强制恢复系统栏显示：从 immersiveSticky（zen/横屏）切到 edgeToEdge 时，
    // 部分设备状态栏不会自动重新显示，必须先 manual 显式 show 再切 edgeToEdge。
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 引用公共 const，与 AnnotatedRegion 共用同一实例
    // 避免引用不等触发平台 channel 真实调用导致闪烁
    SystemChrome.setSystemUIOverlayStyle(kPlayerOverlayStyle);
  }
}

/// 退出全屏播放器时恢复系统栏显示。
///
/// 先 [SystemUiMode.manual] 显式 show（确保从横屏 immersiveSticky 退出时
/// 系统栏一定重新出现），再切回主界面的 [SystemUiMode.edgeToEdge]
/// —— 状态栏与底部导航条透明悬浮，与 `_SystemUiUpdater` 保持一致。
void restoreSystemUi({Color? navigationBarColor, Brightness? statusBarBrightness}) {
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarIconBrightness: statusBarBrightness ?? Brightness.dark,
    systemNavigationBarColor: navigationBarColor ?? const Color(0x00000000),
    systemNavigationBarDividerColor: const Color(0x00000000),
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: statusBarBrightness ?? Brightness.dark,
  ));
}
