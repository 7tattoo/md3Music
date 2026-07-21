import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 根据当前屏幕方向启用或禁用全屏沉浸模式。
///
/// - 横屏（landscape）：启用 [SystemUiMode.immersiveSticky]，隐藏状态栏和导航栏。
///   用户可从屏幕边缘滑入临时显示系统栏，松手后自动隐藏，适合沉浸式播放场景。
/// - 竖屏（portrait）：启用 [SystemUiMode.edgeToEdge]，恢复系统栏显示。
///
/// 调用时机：
/// - 全屏播放器 initState 时首次调用
/// - didChangeMetrics 回调中调用（用户旋转设备时响应）
/// - 全屏播放器 dispose 时调 [restoreSystemUi] 恢复
void applyImmersiveForOrientation() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final isLandscape = view.physicalSize.width > view.physicalSize.height;
  if (isLandscape) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

/// 退出全屏播放器时恢复系统栏显示。
void restoreSystemUi() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
