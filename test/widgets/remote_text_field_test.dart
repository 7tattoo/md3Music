import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/core/remote/remote_text_field.dart';
import '../../lib/providers/remote_control_provider.dart';

/// remoteTextFieldFocusNode 行为测试（遥控模式文本框焦点释放）。
///
/// 覆盖：
/// - 遥控模式关闭：TextField 上下键仍被编辑层消费，焦点不移动（零行为变化）
/// - 遥控模式开启 + 文本框聚焦：上下键改走焦点遍历移出文本框
void main() {
  testWidgets('遥控模式关闭：TextField 上下键不移动焦点（保持编辑行为）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = RemoteControlProvider();
    final textFocus = remoteTextFieldFocusNode();
    final controller = TextEditingController();
    addTearDown(() {
      textFocus.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: textFocus, controller: controller),
                const SizedBox(height: 40),
                TextButton(
                  onPressed: () {},
                  child: const Text('下方结果'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    textFocus.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, textFocus, reason: 'TextField 应获得焦点');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus,
      textFocus,
      reason: '遥控关闭时保持默认行为：方向键被编辑层消费，焦点留在文本框',
    );
  });

  testWidgets('遥控模式开启：TextField 聚焦时上下键移出到相邻项', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = RemoteControlProvider();
    final textFocus = remoteTextFieldFocusNode();
    final controller = TextEditingController();
    final buttonKey = GlobalKey();
    addTearDown(() {
      textFocus.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: textFocus, controller: controller),
                const SizedBox(height: 40),
                TextButton(
                  key: buttonKey,
                  onPressed: () {},
                  child: const Text('下方结果'),
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

    textFocus.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, textFocus, reason: 'TextField 应获得焦点');

    // 上下键移出文本框 → 焦点落到下方按钮
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus,
      isNot(textFocus),
      reason: '遥控开启时上下键应把焦点移出文本框',
    );
    final moved = FocusManager.instance.primaryFocus!;
    var insideButton = false;
    moved.context?.visitAncestorElements((element) {
      if (element == buttonKey.currentContext) {
        insideButton = true;
        return false;
      }
      return true;
    });
    expect(insideButton, isTrue, reason: '焦点应移出到下方按钮');
  });
}
