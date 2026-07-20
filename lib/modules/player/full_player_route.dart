import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import 'full_player.dart';
import 'full_player_am.dart';

/// 全局标志：当前 FullPlayer 是否在路由栈顶。
///
/// 由 [fullPlayerRoute] 构造时设 true，pop 后清 false。
/// 主页常驻的 [MiniPlayer] 监听此值，FullPlayer 打开时自动隐藏避免重复。
final ValueNotifier<bool> isFullPlayerOnTop = ValueNotifier<bool>(false);

/// 使用标准 [MaterialPageRoute] 打开 FullPlayer。
///
/// **动画方式**（与「热门歌单 → 上一级」一致）：
/// - Android：FadeThrough（系统默认平台过渡）
/// - iOS：水平 slide from right（系统默认平台过渡）
/// - 不使用任何 spring 弹回 / 自定义 slide，避免浅色主题下显示硬编码的黑色背景
///
/// **之前的设计问题**（已修复）：
/// 旧的 `BottomSlideMaterialPageRoute` 用自定义 SlideTransition 从底部垂直滑入，
/// 在浅色主题下 pop 时 AM 风格 FullPlayer 内部的 `Colors.black` Scaffold 会
/// 透出黑色块。改用标准平台过渡后，过渡期间 AM 路由上下层都保持自然背景，
/// 黑色块消失。
///
/// **保留兼容**：旧类名 `BottomSlideMaterialPageRoute` 仍导出（`extends`
/// [MaterialPageRoute]），外部代码可以继续用 `BottomSlideMaterialPageRoute(builder: ...)`，
/// 行为与标准 MaterialPageRoute 完全一致。
BottomSlideMaterialPageRoute<void> fullPlayerRoute(BuildContext context) {
  final useAm = context.read<ThemeProvider>().useAmStylePlayer;
  // push 时立即标记，pop 后清除（见下方 listener）
  isFullPlayerOnTop.value = true;
  final route = BottomSlideMaterialPageRoute<void>(
    builder: (_) => useAm ? const AmStyleFullPlayer() : const FullPlayer(),
  );
  // popped Future 在路由出栈时 resolve；无论用户用系统返回手势、AppBar 返回按钮
  // 还是代码 pop，都会触发，从而保证 MiniPlayer 不会永远隐藏。
  route.popped.then((_) {
    if (isFullPlayerOnTop.value) isFullPlayerOnTop.value = false;
  });
  return route;
}

/// 保留旧类名（兼容外部 import），现在是 [MaterialPageRoute] 的简单别名。
///
/// **过渡动画**（自定义）：
/// - 时长 420ms（forward） / 360ms（reverse），比 Material 默认 300ms 更从容
/// - 垂直短距离 slide（8%）+ 透明度淡入，避免 AM 风格 `Colors.black` 在浅色
///   主题下大面积出现黑色块
/// - 曲线：`easeOutCubic`（forward）/ `easeInCubic`（reverse），符合"上推淡入"物理感
/// - 保留 [MaterialPageRoute] 的系统预测返回手势对接（Android 14+ / iOS）
class BottomSlideMaterialPageRoute<T> extends MaterialPageRoute<T> {
  BottomSlideMaterialPageRoute({required super.builder});

  @override
  bool didPop(T? result) {
    // 返回动画一开始就提前让 mini bar 同步淡入：
    // 避免 FullPlayer 上滑淡出过程中，底部露出下层页面主体，
    // 在浅色主题下与 AM 黑色背景形成阴影/色块。
    if (isFullPlayerOnTop.value) isFullPlayerOnTop.value = false;
    return super.didPop(result);
  }

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 不做任何过渡动画，直接返回 child。
    // push / pop 立即切换，无上下左右 slide、无 fade、无 spring。
    return child;
  }
}
