import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/remote_control_provider.dart';
import 'focus_highlight.dart';

/// 遥控模式下的滑块包装器（解决「滑块/进度条焦点收不回来」）。
///
/// Flutter 自带的 [Slider] 默认（traditional 导航模式）把**四个方向键全部**
/// 映射为调值（_AdjustSliderIntent），D-pad 一旦落到滑块上方向键就被吞掉，
/// 无法移出 → 表现为"返回不了"。
///
/// [RemoteSlider] 在遥控模式下用 [MediaQuery] 把子树覆盖为
/// [NavigationMode.directional]：Slider 内置的 _directionalNavShortcutMap
/// 只消费左右键（调值），上下键**放行**到焦点遍历，由 D-pad 自然移出滑块。
///
/// 同时叠加 [RemoteFocusRing] 聚焦环，让滑块与其它控件聚焦表现一致
/// （浅色/深色背景下都可辨），解决"看不清焦点在哪"。
///
/// 遥控模式关闭时**原样返回 Slider**（不注入 FocusNode），触屏行为零变化。
class RemoteSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final Color? activeColor;
  final Color? inactiveColor;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const RemoteSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  State<RemoteSlider> createState() => _RemoteSliderState();
}

class _RemoteSliderState extends State<RemoteSlider> {
  /// 仅用于跟踪 Slider 是否聚焦（驱动聚焦环），不拦截按键；
  /// 按键由 Slider 自身的 directional 映射处理。
  final FocusNode _focusNode = FocusNode(debugLabel: 'remote_slider');

  /// 当前是否聚焦（驱动聚焦环）。
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  Widget _buildSlider({FocusNode? focusNode}) {
    return Slider(
      focusNode: focusNode,
      value: widget.value,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      label: widget.label,
      activeColor: widget.activeColor,
      inactiveColor: widget.inactiveColor,
      onChanged: widget.onChanged,
      onChangeStart: widget.onChangeStart,
      onChangeEnd: widget.onChangeEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteOn = context.watch<RemoteControlProvider>().enabled;

    // 遥控模式关闭：原样返回，触屏行为零变化。
    if (!remoteOn) return _buildSlider();

    // 遥控模式开启：
    // 1) 子树覆盖为 directional 导航 → 左右调值、上下移出滑块；
    // 2) 叠加聚焦环，scale 保持 1.0 避免进度条/滑块聚焦时缩放造成布局位移。
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(navigationMode: NavigationMode.directional),
      child: RemoteFocusRing(
        focused: _focused,
        scale: 1.0,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: _buildSlider(focusNode: _focusNode),
      ),
    );
  }
}
