import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/remote_control_provider.dart';

/// 为遥控模式下的文本输入框创建 FocusNode。
///
/// 单行搜索框获得焦点后，EditableText 的方向键快捷键会吞掉 D-pad（当作光标
/// 移动），导致焦点困在框里出不去。给 TextField 传入本函数返回的 focusNode：
/// - 遥控模式开启时，**上/下键改走焦点遍历移出**文本框（到相邻可聚焦项），
///   左右键仍保留给光标/编辑；
/// - 遥控模式关闭时原样放行，触屏与键盘编辑行为零变化。
///
/// 使用方持有该节点并负责 dispose：
/// ```dart
/// late final FocusNode _searchFocus = remoteTextFieldFocusNode();
/// // dispose() 中 _searchFocus.dispose()
/// TextField(focusNode: _searchFocus, ...)
/// ```
/// 仅用于**单行**输入框（多行输入框的上下键是合法的光标移动，勿用）。
FocusNode remoteTextFieldFocusNode() {
  return FocusNode(
    debugLabel: 'remote_text_field',
    onKeyEvent: _handleRemoteTextFieldKey,
  );
}

KeyEventResult _handleRemoteTextFieldKey(FocusNode node, KeyEvent event) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final key = event.logicalKey;
  if (key != LogicalKeyboardKey.arrowUp && key != LogicalKeyboardKey.arrowDown) {
    return KeyEventResult.ignored;
  }
  final ctx = node.context;
  if (ctx == null) return KeyEventResult.ignored;
  if (!Provider.of<RemoteControlProvider>(ctx, listen: false).enabled) {
    return KeyEventResult.ignored;
  }

  // 移出文本框：优先按上/下方向找相邻可聚焦项，找不到退回阅读顺序，保证能离开。
  final goingDown = key == LogicalKeyboardKey.arrowDown;
  final policy =
      FocusTraversalGroup.maybeOfNode(node) ?? ReadingOrderTraversalPolicy();
  final direction =
      goingDown ? TraversalDirection.down : TraversalDirection.up;
  if (policy.inDirection(node, direction)) return KeyEventResult.handled;
  if (goingDown) {
    policy.next(node);
  } else {
    policy.previous(node);
  }
  return KeyEventResult.handled;
}
