import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/core/remote/remote_slider.dart';
import '../../lib/providers/remote_control_provider.dart';

/// RemoteSlider 行为测试（遥控器模式滑块包装器）。
///
/// 覆盖：
/// - 遥控模式关闭时原样返回 Slider（左右/上下键均被 Slider 传统模式吞掉，调值）
/// - 遥控模式开启 + 滑块聚焦：左右键调值，上下键**移出**滑块到相邻可聚焦项
///   （解决"滑块/进度条焦点收不回来"）
void main() {
  Future<void> pumpHarness(
    WidgetTester tester, {
    bool remoteOn = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final provider = RemoteControlProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 40),
                RemoteSlider(
                  value: 0.5,
                  onChanged: (_) {},
                ),
                const SizedBox(height: 80),
                TextButton(
                  onPressed: () {},
                  child: const Text('下方目标'),
                ),
              ],
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

  testWidgets('遥控模式关闭：Slider 原样可用，方向键不移动焦点（调值）', (tester) async {
    await pumpHarness(tester, remoteOn: false);

    // 聚焦到滑块（第一个可聚焦项）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final focusAfterDown = FocusManager.instance.primaryFocus;

    // 传统模式下方向键被 Slider 吞掉调值 → 焦点停留在滑块（下方按钮未获焦）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus,
      focusAfterDown,
      reason: '遥控关闭时保持 Flutter 默认行为：上下键被滑块消费，焦点不移动',
    );
  });

  testWidgets('遥控模式开启 + 滑块聚焦：左右键调值、上下键移出到相邻项', (tester) async {
    var value = 0.5;
    SharedPreferences.setMockInitialValues({});
    final provider = RemoteControlProvider();
    final buttonKey = GlobalKey();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 40),
                RemoteSlider(value: value, onChanged: (v) => value = v),
                const SizedBox(height: 80),
                TextButton(
                  key: buttonKey,
                  onPressed: () {},
                  child: const Text('下方目标'),
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

    // 方向键聚焦到滑块（第一个可聚焦项）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final sliderFocus = FocusManager.instance.primaryFocus;

    // 滑块聚焦时：左右键调值
    final before = value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, greaterThan(before), reason: '滑块聚焦时左右键应调值');

    // 滑块聚焦时：上下键移出滑块 → 焦点落到下方按钮
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus,
      isNot(sliderFocus),
      reason: '滑块聚焦时上下键应放行焦点遍历，移出滑块',
    );
    final buttonContext = buttonKey.currentContext!;
    final movedFocus = FocusManager.instance.primaryFocus!;
    var insideButton = false;
    movedFocus.context?.visitAncestorElements((element) {
      if (element == buttonContext) {
        insideButton = true;
        return false;
      }
      return true;
    });
    expect(insideButton, isTrue, reason: '焦点应移动到下方按钮');

    // 焦点已离开滑块：再按左右键不应改变滑块值
    final afterExit = value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, afterExit, reason: '焦点移出后左右键不应再作用于滑块');
  });
}
