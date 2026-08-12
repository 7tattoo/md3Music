import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/core/remote/global_focus_ring.dart';
import '../../lib/providers/remote_control_provider.dart';

/// GlobalFocusRing 行为测试（遥控模式全局聚焦框）。
///
/// 覆盖：
/// - 遥控模式开启：未包装的 ListTile 获得焦点时出现全局聚焦环（覆盖任意控件）
/// - 遥控模式开启：焦点移到屏外项时列表自动滚动到可见（解决长列表"卡住下不去"）
/// - 遥控模式关闭：不画环、不滚动，零行为变化
void main() {
  const ringKey = ValueKey('__global_focus_ring__');

  Future<RemoteControlProvider> pumpHarness(
    WidgetTester tester, {
    bool remoteOn = true,
    ScrollController? scrollController,
  }) async {
    // 遥控模式默认开启；remoteOn=false 用例显式写入 false 偏好以模拟关闭
    SharedPreferences.setMockInitialValues({
      if (!remoteOn) 'settings_remote_control_enabled': false,
    });
    final provider = RemoteControlProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: GlobalFocusRing(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 200,
                child: ListView(
                  controller: scrollController,
                  children: [
                    for (var i = 0; i < 30; i++)
                      ListTile(
                        onTap: () {},
                        title: Text('item $i'),
                      ),
                  ],
                ),
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
    return provider;
  }

  testWidgets('遥控模式开启：未包装 ListTile 获得焦点时出现全局聚焦环', (tester) async {
    final provider = await pumpHarness(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(); // postFrame 定位环

    expect(find.byKey(ringKey), findsOneWidget, reason: '焦点应落在未包装 ListTile 上并画全局环');

    // 环应覆盖住聚焦项（item 0 的中心落在环内）
    final ringRect = tester.getRect(find.byKey(ringKey));
    final itemCenter = tester.getCenter(find.text('item 0'));
    expect(
      ringRect.contains(itemCenter),
      isTrue,
      reason: '全局环应跟随聚焦项位置',
    );

    provider.setEnabled(false);
    await tester.pump();
    await tester.pump();
  });

  testWidgets('遥控模式开启：焦点移到屏外项时列表自动滚动到可见', (tester) async {
    final scrollController = ScrollController();
    final provider = await pumpHarness(
      tester,
      scrollController: scrollController,
    );

    // 连续向下导航，跨越屏内项进入屏外区域；每次焦点切换自动滚动到可见
    for (var i = 0; i < 14; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    // 推进 ensureVisible 滚动动画
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      scrollController.offset,
      greaterThan(0),
      reason: '焦点进入屏外区域时列表应自动滚动',
    );
    // 环仍可见且落在屏内聚焦项上
    expect(find.byKey(ringKey), findsOneWidget, reason: '滚动后全局环仍应可见');

    provider.setEnabled(false);
    await tester.pump();
    await tester.pump();
  });

  testWidgets('遥控模式关闭：不画环、不自动滚动', (tester) async {
    final scrollController = ScrollController();
    await pumpHarness(tester, remoteOn: false, scrollController: scrollController);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(ringKey), findsNothing, reason: '遥控关闭时不画全局环');
    expect(scrollController.offset, 0, reason: '遥控关闭时不自动滚动');
  });
}
