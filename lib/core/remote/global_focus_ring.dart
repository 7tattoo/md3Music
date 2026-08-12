import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/remote_control_provider.dart';
import 'focus_highlight.dart';

/// 遥控模式全局聚焦框（覆盖所有 Material 可聚焦控件）。
///
/// 单个 [RemoteFocusHighlight] 只能包住显式包装的控件；列表行（ListTile /
/// SwitchListTile 等）等大量未包装控件靠 Material 默认焦点高亮太淡，电视上
/// 看不清。GlobalFocusRing 挂在 App 顶层，监听 [FocusManager] 的
/// primaryFocus，把统一的聚焦环画在**任意**获得焦点的控件上。
///
/// 职责：
/// - **全局聚焦环**：跟随 primaryFocus，画主题色描边 + 对比 keyline + 光晕
///   （与 [RemoteFocusRing.focusDecoration] 视觉一致）。焦点已落在带局部环的
///   RemoteFocusHighlight / RemoteSlider 上时不重复叠加。
/// - **自动滚动**：焦点切换时调用 [Scrollable.ensureVisible]，让长列表里
///   D-pad 移出屏幕的项自动滚入视野（解决设置页"焦点卡在屏下缘下不去"）。
///
/// 遥控模式关闭时纯透传 child，零行为变化。
class GlobalFocusRing extends StatefulWidget {
  const GlobalFocusRing({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalFocusRing> createState() => _GlobalFocusRingState();
}

class _GlobalFocusRingState extends State<GlobalFocusRing> {
  /// 遥控模式开关（didChangeDependencies 同步，供每帧 _update 用，避免
  /// postFrame 回调里反复 context.read）。
  bool _remoteOn = false;

  /// 聚焦框在自身 Stack 坐标系中的位置（null = 不显示）。
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = context.watch<RemoteControlProvider>().enabled;
    if (on != _remoteOn) {
      _remoteOn = on;
      _scheduleUpdate();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_remoteOn) return;
    // 焦点切换：自动滚动到可见 + 重新定位环
    _scheduleUpdate(ensureVisible: true);
  }

  void _scheduleUpdate({bool ensureVisible = false}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _update(ensureVisible: ensureVisible);
    });
  }

  void _update({bool ensureVisible = false}) {
    if (!mounted) return;
    final node = FocusManager.instance.primaryFocus;
    final active = _remoteOn && node != null && node.hasFocus && node.context != null;

    if (!active) {
      if (_rect != null) setState(() => _rect = null);
      return;
    }

    final ctx = node.context!;

    // 焦点切换后把聚焦项滚入视野（居中，上下导航对称可预测）。
    // 对已可见项 / 无 Scrollable 祖先时是无操作。
    if (ensureVisible) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }

    // 已带局部聚焦环（RemoteFocusHighlight / RemoteSlider）的不再叠加全局环，
    // 避免双重描边。
    var hasLocalRing = false;
    ctx.visitAncestorElements((element) {
      if (element.widget is RemoteFocusRing) {
        hasLocalRing = true;
        return false;
      }
      return true;
    });
    if (hasLocalRing) {
      if (_rect != null) setState(() => _rect = null);
      return;
    }

    final render = ctx.findRenderObject();
    final stackRender = context.findRenderObject();
    if (render is RenderBox && render.attached && stackRender is RenderBox) {
      final local = render.localToGlobal(Offset.zero, ancestor: stackRender);
      final newRect = local & render.size;
      if (newRect != _rect) setState(() => _rect = newRect);
    }

    // 持续跟踪：滚动动画 / 布局变化时聚焦框跟随，直到环消失或遥控关闭。
    // 只在环可见时维持循环，避免空转。
    if (_rect != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      clipBehavior: Clip.hardEdge,
      children: [
        widget.child,
        if (_rect != null)
          Positioned.fromRect(
            rect: _rect!,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('__global_focus_ring__'),
                decoration: RemoteFocusRing.focusDecoration(context),
              ),
            ),
          ),
      ],
    );
  }
}
