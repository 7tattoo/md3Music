import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/core/remote/focus_highlight.dart';
import '../../lib/providers/remote_control_provider.dart';

/// RemoteFocusHighlight 行为测试（遥控器模式核心包装器）。
///
/// 覆盖：
/// - 遥控模式关闭时原样返回 child，OK/菜单键无响应（触屏零行为变化）
/// - 遥控模式开启 + 聚焦后，Enter/OK（ActivateIntent）触发 onTap
/// - 遥控模式开启后，菜单键（LogicalKeyboardKey.contextMenu）触发 onContextMenu
void main() {
  /// 搭建测试 harness：RemoteControlProvider + MaterialApp 包裹一个
  /// autofocus 的 RemoteFocusHighlight（仅一个按钮，避免焦点歧义）。
  Future<void> pumpHarness(
    WidgetTester tester, {
    bool remoteOn = true,
    VoidCallback? onTap,
    VoidCallback? onContextMenu,
  }) async {
    // 遥控模式默认开启；remoteOn=false 用例显式写入 false 偏好以模拟关闭
    SharedPreferences.setMockInitialValues({
      if (!remoteOn) 'settings_remote_control_enabled': false,
    });
    final provider = RemoteControlProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: RemoteFocusHighlight(
                autofocus: true,
                onTap: onTap,
                onContextMenu: onContextMenu,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (remoteOn) {
      provider.setEnabled(true);
      await tester.pump();
    }
  }

  testWidgets('遥控模式关闭时：OK/菜单键均不触发回调', (tester) async {
    var tapped = false;
    var menuOpened = false;
    await pumpHarness(
      tester,
      remoteOn: false,
      onTap: () => tapped = true,
      onContextMenu: () => menuOpened = true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();

    expect(tapped, isFalse, reason: '遥控关闭时不应响应 OK 键');
    expect(menuOpened, isFalse, reason: '遥控关闭时不应响应菜单键');
  });

  testWidgets('遥控模式开启 + 聚焦：Enter 触发 onTap', (tester) async {
    var tapped = false;
    await pumpHarness(tester, onTap: () => tapped = true);

    // wrapper autofocus 后获得焦点，Enter（→ ActivateIntent）应触发 onTap
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tapped, isTrue, reason: 'Enter 应触发 onTap');
  });

  testWidgets('遥控模式开启：菜单键触发 onContextMenu', (tester) async {
    var menuOpened = false;
    await pumpHarness(tester, onContextMenu: () => menuOpened = true);

    // 菜单键经 wrapper 内部 Shortcuts → ContextMenuIntent → onContextMenu
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();

    expect(menuOpened, isTrue, reason: '菜单键应触发 onContextMenu');
  });

  testWidgets('回归: MaterialApp.shortcuts 必须展开默认表, 方向键/select/Enter 均可用', (tester) async {
    // 曾经踩过坑：MaterialApp.shortcuts 是【整体替换】而非【合并】默认快捷键表，
    // 若只传 {select: ActivateIntent}，方向键/Enter/Tab 等默认映射会被清空，
    // 表现为"键盘完全没反应"。修复方式：...WidgetsApp.defaultShortcuts 展开后再追加。
    final taps = <String>[];
    SharedPreferences.setMockInitialValues({});
    final provider = RemoteControlProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            LogicalKeySet(LogicalKeyboardKey.select): ActivateIntent(),
          },
          home: Scaffold(
            body: Column(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: RemoteFocusHighlight(
                      onTap: () => taps.add('item$i'),
                      onContextMenu: () => taps.add('menu$i'),
                      child: Center(child: Text('item $i')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    provider.setEnabled(true);
    await tester.pump();

    // 无 autofocus：方向键从路由 FocusScope 进入列表并移动到第二项
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // select（TV OK 键）激活当前聚焦项
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, ['item1'], reason: 'select 应激活 item1');

    // Enter 同样触发 ActivateIntent
    taps.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, ['item1'], reason: 'Enter 应触发 ActivateIntent');

    // 菜单键
    taps.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(taps, ['menu1'], reason: '菜单键应触发 onContextMenu');

    // 上方向键回到顶部
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    taps.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, ['item0'], reason: '两个上方向键应回到 item0 并激活');
  });
}
