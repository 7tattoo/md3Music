import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/widgets/apple_lyrics/renderers/interlude_dots.dart';

/// 间奏点（节奏点）动画时钟相关的单元测试。
///
/// 覆盖 PR12 引入的：
/// - [InterludeDots.setInterlude] 的 `forceReset`（seek 回跳场景强制重置时钟）
/// - [InterludeDots.alignToRealTime]（Ticker mute 恢复后对齐真实窗口进度）
/// - [InterludeDots.shouldRealignTo]（时钟漂移检测）
void main() {
  group('InterludeDots', () {
    group('setInterlude forceReset（seek 回跳场景）', () {
      test('forceReset=true 时相同间奏也重置动画时钟', () {
        final dots = InterludeDots();
        // 间奏时长 6000ms（end - start）
        dots.setInterlude(1000, 7000);
        dots.tick(0.016);
        // 推进动画时钟超过间奏总时长：此时动画已结束
        dots.tick(7.0);
        // 普通重复调用：幂等保护不重置，动画时钟仍超时（paintAtLineY 会隐藏圆点）
        dots.setInterlude(1000, 7000);
        expect(dots.shouldRender, isTrue);
        // forceReset：强制重置动画时钟，重新从 0 开始入场
        dots.setInterlude(1000, 7000, forceReset: true);
        expect(dots.shouldRender, isTrue);
        expect(dots.isInterlude(3000), isTrue);
      });

      test('setInterlude(null, null) 清除间奏', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        expect(dots.shouldRender, isTrue);
        dots.setInterlude(null, null);
        expect(dots.shouldRender, isFalse);
        expect(dots.startTime, isNull);
        expect(dots.endTime, isNull);
      });
    });

    group('alignToRealTime（Ticker mute 恢复对齐）', () {
      test('对齐到窗口内真实偏移', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000); // 间奏时长 6000ms
        dots.tick(0.016);
        // 帧时钟推进 2s（模拟 mute 前）
        dots.tick(2.0);
        expect(dots.animationTimeMs, closeTo(2016, 0.1));

        // 真实播放位置 5000ms → 窗口内偏移 = 5000-1000 = 4000
        dots.alignToRealTime(5000);
        expect(dots.animationTimeMs, closeTo(4000, 0.1));
      });

      test('超出窗口时 clamp 到 [0, 间奏时长]', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000); // 时长 6000ms
        dots.tick(0.016);
        // 窗口前（早于 gapStart）
        dots.alignToRealTime(500);
        expect(dots.animationTimeMs, closeTo(0, 0.1));
        // 窗口后（晚于 gapEnd）
        dots.alignToRealTime(10000);
        expect(dots.animationTimeMs, closeTo(6000, 0.1));
      });

      test('未激活间奏时调用无副作用', () {
        final dots = InterludeDots();
        dots.alignToRealTime(5000);
        expect(dots.shouldRender, isFalse);
        expect(dots.animationTimeMs, closeTo(0, 0.1));
      });
    });

    group('shouldRealignTo（时钟漂移检测）', () {
      test('正常播放（偏差小于阈值）不触发对齐', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000); // 时长 6000ms
        dots.tick(0.016);
        dots.tick(1.0); // 帧时钟 ≈ 1016ms
        // 真实位置 2000ms → 窗口偏移 1000ms，与帧时钟几乎同步
        expect(dots.shouldRealignTo(2000), isFalse);
      });

      test('帧时钟滞后（页面重建 / mute）时触发对齐', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        dots.tick(0.016);
        dots.tick(1.0); // 帧时钟 ≈ 1016ms
        // 真实位置 5000ms → 窗口偏移 4000ms，偏差 ≈ 3000ms > 阈值
        expect(dots.shouldRealignTo(5000), isTrue);
        // 对齐后偏差归零，不再触发
        dots.alignToRealTime(5000);
        expect(dots.shouldRealignTo(5000), isFalse);
      });

      test('未激活间奏时不触发', () {
        final dots = InterludeDots();
        expect(dots.shouldRealignTo(5000), isFalse);
      });
    });
  });
}
