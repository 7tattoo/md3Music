import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../lib/widgets/apple_lyrics/controllers/lyric_scroll_controller.dart';
import '../../../../lib/widgets/apple_lyrics/layout/lyric_layout.dart';

/// LyricScrollController 弹簧参数缓存（P1-D）的单元测试。
///
/// 覆盖 PR12 引入的 _applySpringParams 输入缓存：
/// 三个输入（isSeeking / intervalMs / isInterludeActive）未变时直接早退，
/// 跳过 math.pow（posYNormalStiffness）与 setParams，参数保持稳定。
void main() {
  group('LyricScrollController P1-D 弹簧参数缓存', () {
    test('相同参数重复 setCurrentLine 不重算弹簧参数', () {
      final controller = LyricScrollController();
      controller.setViewportSize(const Size(400, 600));
      // seeking 模式固定参数 (90, 15)
      controller.setCurrentLine(0, isSeeking: true, lineHeight: 40);
      expect(controller.currentStiffness, closeTo(90, 1e-9));
      expect(controller.currentDamping, closeTo(15, 1e-9));

      // 相同输入重复调用：缓存命中，参数保持不变（不重算 pow）
      controller.setCurrentLine(0, isSeeking: true, lineHeight: 40);
      expect(controller.currentStiffness, closeTo(90, 1e-9));
      expect(controller.currentDamping, closeTo(15, 1e-9));

      // 切换普通模式（intervalMs 变化）→ 触发重算并更新缓存
      controller.setCurrentLine(
        0,
        isSeeking: false,
        lineHeight: 40,
        intervalMs: 200,
      );
      final double stiffness = controller.currentStiffness;
      expect(stiffness, closeTo(LyricLayout.posYNormalStiffness(200), 1e-9));
      // 再次相同：缓存命中，值保持
      controller.setCurrentLine(
        0,
        isSeeking: false,
        lineHeight: 40,
        intervalMs: 200,
      );
      expect(controller.currentStiffness, closeTo(stiffness, 1e-9));
      controller.dispose();
    });

    test('间奏模式参数切换后缓存跟随更新', () {
      final controller = LyricScrollController();
      controller.setViewportSize(const Size(400, 600));
      // 普通模式
      controller.setCurrentLine(
        0,
        isSeeking: false,
        lineHeight: 40,
        intervalMs: 200,
      );
      final double normalStiffness = controller.currentStiffness;
      // 间奏模式（isInterludeActive=true）→ 柔和弹簧 (40, 10)
      controller.setCurrentLine(
        0,
        isSeeking: false,
        lineHeight: 40,
        intervalMs: 200,
        isInterludeActive: true,
      );
      expect(controller.currentStiffness, closeTo(40, 1e-9));
      expect(controller.currentDamping, closeTo(10, 1e-9));
      // 回到普通模式 → 恢复并缓存更新
      controller.setCurrentLine(
        0,
        isSeeking: false,
        lineHeight: 40,
        intervalMs: 200,
        isInterludeActive: false,
      );
      expect(controller.currentStiffness, closeTo(normalStiffness, 1e-9));
      controller.dispose();
    });
  });
}
