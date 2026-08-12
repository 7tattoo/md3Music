import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/remote_control_provider.dart';

/// 菜单键意图：遥控器「菜单」键 / 键盘 Context Menu 键触发的操作菜单意图。
///
/// 由 [RemoteFocusHighlight] 内部局部 Shortcuts 把
/// `LogicalKeyboardKey.contextMenu` 映射到此意图，避免全局注册表的
/// focus/unfocus 竞态。
class ContextMenuIntent extends Intent {
  const ContextMenuIntent();
}

/// 遥控模式统一的聚焦视觉环。
///
/// 缩放 + 主题色描边 + **对比色 keyline** + 光晕（150ms easeOutCubic）。
/// keyline 是紧贴描边外沿的细环（深色背景用白、浅色背景用黑），
/// 保证在浅色/深色、纯黑 OLED、封面图等任意背景下焦点都清晰可辨。
///
/// 由 [RemoteFocusHighlight]（按键交互）与 [RemoteSlider]（滑块）共用，
/// 两者聚焦表现完全一致。
class RemoteFocusRing extends StatelessWidget {
  /// 聚焦高亮/缩放动画时长。
  static const Duration highlightDuration = Duration(milliseconds: 150);

  /// 聚焦高亮/缩放缓动曲线。
  static const Curve highlightCurve = Curves.easeOutCubic;

  /// 当前是否聚焦（驱动描边/缩放）。
  final bool focused;

  /// 聚焦时的缩放比例。列表整行/卡片建议 1.0，图标建议 1.1~1.2。
  final double scale;

  /// 聚焦描边/光晕的圆角半径。
  final BorderRadius borderRadius;

  /// 描边/光晕与子组件之间的内边距。
  final EdgeInsets padding;

  final Widget child;

  const RemoteFocusRing({
    super.key,
    required this.focused,
    this.scale = 1.05,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  /// 统一的聚焦环装饰：主题色描边 + 对比色 keyline + 光晕。
  ///
  /// 由 [RemoteFocusRing]（局部环）与全局聚焦框（GlobalFocusRing）共用，
  /// 保证任意控件聚焦表现一致。keyline 深色背景用白、浅色背景用黑，
  /// 紧贴描边外侧，让环在任意背景下与内容分离。
  static BoxDecoration focusDecoration(
    BuildContext context, {
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyline = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.28);
    return BoxDecoration(
      borderRadius: borderRadius,
      border: Border.all(color: colorScheme.primary, width: 3),
      boxShadow: [
        // keyline：blurRadius 0 的锐利细环，最上层
        BoxShadow(color: keyline, blurRadius: 0, spreadRadius: 1.5),
        // 主题色光晕：底层柔光
        BoxShadow(
          color: colorScheme.primary.withValues(alpha: 0.35),
          blurRadius: 14,
          spreadRadius: 2,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: focused ? scale : 1.0,
      duration: highlightDuration,
      curve: highlightCurve,
      child: AnimatedContainer(
        duration: highlightDuration,
        curve: highlightCurve,
        decoration: focused
            ? RemoteFocusRing.focusDecoration(context, borderRadius: borderRadius)
            : null,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 遥控模式下的统一焦点包装器。
///
/// 职责：
/// - 遥控模式开启时，给任意 child 提供**单一焦点入口**（D-pad 可到达），
///   并叠加聚焦视觉反馈：[RemoteFocusRing]（缩放 + 主题色描边 + keyline + 光晕）。
/// - OK/Enter/Space 键激活 → [onTap]；菜单键 → [onContextMenu]。
/// - 遥控模式关闭时**原样返回 child**，触屏行为零变化。
///
/// 关键约定：
/// - 默认 [descendantsAreFocusable] 为 false，把激活权完全收归本包装器的
///   FocusNode（[onTap] 转发子组件原逻辑），避免内层 InkWell/IconButton 与
///   外层包装器双重触发。
/// - 列表整行/卡片建议传 [scale] 1.0 避免布局位移；图标级轻交互传 1.1~1.2。
class RemoteFocusHighlight extends StatefulWidget {
  /// 被包装的子组件（原控件树，视觉结构不变）。
  final Widget child;

  /// OK/Enter/Space 激活时回调，转发到子组件原激活逻辑。
  final VoidCallback? onTap;

  /// 菜单键回调，打开当前项操作菜单（长按交互的遥控替代）。
  final VoidCallback? onContextMenu;

  /// 外部提供的焦点节点；缺省时由内部管理。
  final FocusNode? focusNode;

  /// 是否在首次布局时自动获得焦点。
  final bool autofocus;

  /// 是否允许子组件自身参与焦点遍历。
  /// 默认 false：子组件自有焦点被禁用，避免与外层包装器双重触发。
  final bool descendantsAreFocusable;

  /// 聚焦描边/光晕的圆角半径。
  final BorderRadius borderRadius;

  /// 聚焦时的缩放比例。列表整行/卡片建议 1.0，图标建议 1.1~1.2。
  final double scale;

  /// 描边/光晕与子组件之间的内边距。
  final EdgeInsets padding;

  /// 无障碍语义标签（默认沿用子组件自身语义）。
  final String? semanticsLabel;

  const RemoteFocusHighlight({
    super.key,
    required this.child,
    this.onTap,
    this.onContextMenu,
    this.focusNode,
    this.autofocus = false,
    this.descendantsAreFocusable = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.scale = 1.05,
    this.padding = EdgeInsets.zero,
    this.semanticsLabel,
  });

  @override
  State<RemoteFocusHighlight> createState() => _RemoteFocusHighlightState();
}

class _RemoteFocusHighlightState extends State<RemoteFocusHighlight> {
  /// 当前是否聚焦（由 FocusableActionDetector.onFocusChange 驱动）。
  bool _focused = false;

  @override
  void dispose() {
    // 若使用了内部自建的 FocusNode，这里应释放；外部传入的不由本组件管理。
    super.dispose();
  }

  void _handleFocusChange(bool focused) {
    if (_focused == focused) return;
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final remoteOn = context.watch<RemoteControlProvider>().enabled;
    final hasAction = widget.onTap != null || widget.onContextMenu != null;

    // 遥控模式关闭、或无需键盘交互时：原样返回 child，触屏行为零变化。
    if (!remoteOn || !hasAction) return widget.child;

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticsLabel,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        descendantsAreFocusable: widget.descendantsAreFocusable,
        onFocusChange: _handleFocusChange,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
          ContextMenuIntent: CallbackAction<ContextMenuIntent>(
            onInvoke: (_) {
              widget.onContextMenu?.call();
              return null;
            },
          ),
        },
        shortcuts: {
          // 遥控器菜单键 / 键盘 Context Menu 键 → 打开当前项操作菜单
          LogicalKeySet(LogicalKeyboardKey.contextMenu): ContextMenuIntent(),
        },
        child: RemoteFocusRing(
          focused: _focused,
          scale: widget.scale,
          borderRadius: widget.borderRadius,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}
