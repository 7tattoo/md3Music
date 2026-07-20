import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/widgets/apple_lyrics/layout/lyric_layout.dart';
import 'package:md3music/widgets/apple_lyrics/models/lyric_line.dart';
import 'package:md3music/widgets/apple_lyrics/renderers/word_renderer.dart';

/// WordRenderer 单元测试
///
/// 覆盖：初始状态、tick 推进、isActive 切换、scale 联动、
/// 指数衰减、reset、空 words 不崩溃。
///
/// 主要验证状态逻辑（alpha 计算与 tick 推进），不验证绘制像素。
/// paintLine 涉及 Canvas 绘制，构造一个写入 PictureRecorder 的 canvas
/// 以触发内部绑定逻辑与 TextPainter 调用，但不验证像素。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WordRenderer renderer;
  late LyricLine line;

  setUp(() {
    renderer = WordRenderer();
    line = const LyricLine(
      startTime: 0,
      duration: 4000,
      text: '运命的华',
      words: [
        LyricWord(startTime: 0, duration: 1000, text: '运'),
        LyricWord(startTime: 1000, duration: 1000, text: '命'),
        LyricWord(startTime: 2000, duration: 1000, text: '的'),
        LyricWord(startTime: 3000, duration: 1000, text: '华'),
      ],
    );
  });

  /// 构造一个可绘制的 Canvas（写入 PictureRecorder，不实际显示）。
  /// 用 ui 前缀访问 dart:ui 的 Canvas / PictureRecorder / Offset，
  /// 避免与 flutter/widgets.dart 重导出的同名类冲突。
  ui.Canvas makeCanvas() {
    final recorder = ui.PictureRecorder();
    return ui.Canvas(recorder);
  }

  group('初始状态', () {
    test('非当前行（scale=0.97）：所有 word alpha 初始为 dynamicDarkAlpha=0.2', () {
      renderer.setLineState(
          isActive: false, scale: LyricLayout.inactiveScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      final alphas = renderer.wordAlphas;
      expect(alphas.length, 4);
      for (final a in alphas.values) {
        expect(a, closeTo(0.2, 1e-9));
      }
    });

    test('当前行（scale=1.0）：所有 word alpha 初始为 dynamicDarkAlpha=0.4', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      final alphas = renderer.wordAlphas;
      expect(alphas.length, 4);
      for (final a in alphas.values) {
        expect(a, closeTo(0.4, 1e-9));
      }
    });
  });

  group('tick 后状态推进', () {
    test('progress=0.25：word 0 已播趋向 1.0，word 1/2/3 未播趋向 0.4', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);

      // progress=0.25 时：wordPos = 0.25 * 4 = 1.0，currentIdx = 1
      // word 0: index=0 < 1 → 已播 → bright=1.0
      // word 1: index=1 == 1, wp=0 → 当前字起点 → dark=0.4
      // word 2,3: 未播 → dark=0.4
      for (int i = 0; i < 100; i++) {
        renderer.tick(0.016, 0.25);
      }
      expect(renderer.wordAlphas[0]!, closeTo(1.0, 0.01));
      expect(renderer.wordAlphas[1]!, closeTo(0.4, 0.01));
      expect(renderer.wordAlphas[2]!, closeTo(0.4, 0.01));
      expect(renderer.wordAlphas[3]!, closeTo(0.4, 0.01));
    });

    test('progress 推进到 1.0：所有 word 已播，alpha 趋向 1.0', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);

      // 先到 progress=0.5 让前两字变亮
      for (int i = 0; i < 100; i++) {
        renderer.tick(0.016, 0.5);
      }
      // 再推进到 1.0：wordPos=4.0, currentIdx=4，所有字已播 → bright=1.0
      for (int i = 0; i < 200; i++) {
        renderer.tick(0.016, 1.0);
      }
      for (int i = 0; i < 4; i++) {
        expect(renderer.wordAlphas[i]!, closeTo(1.0, 0.01),
            reason: 'word $i 应趋向 brightAlpha=1.0');
      }
    });
  });

  group('isActive 切换', () {
    test('从非当前行切到当前行，alpha 从 0.2 渐变到 0.4', () {
      // 初始非当前行：scale=0.97, factor=0, dynamicDarkAlpha=0.2
      renderer.setLineState(
          isActive: false, scale: LyricLayout.inactiveScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      for (final a in renderer.wordAlphas.values) {
        expect(a, closeTo(0.2, 1e-9));
      }

      // 切到当前行：scale=1.0, factor=1, dynamicDarkAlpha=0.4
      // progress=0 时所有字未播，目标 = dynamicDarkAlpha = 0.4
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      for (int i = 0; i < 100; i++) {
        renderer.tick(0.016, 0.0);
      }
      for (final a in renderer.wordAlphas.values) {
        expect(a, closeTo(0.4, 0.01));
      }
    });

    test('从当前行切到非当前行，alpha 从 0.4 渐变回 0.2', () {
      // 初始当前行：所有字 alpha=0.4
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      for (final a in renderer.wordAlphas.values) {
        expect(a, closeTo(0.4, 1e-9));
      }

      // 切到非当前行：scale=0.97, factor=0, dynamicDarkAlpha=0.2
      // 非当前行 SOLID 模式，所有字目标 = 0.2
      renderer.setLineState(
          isActive: false, scale: LyricLayout.inactiveScale);
      for (int i = 0; i < 200; i++) {
        renderer.tick(0.016, 0.5);
      }
      for (final a in renderer.wordAlphas.values) {
        expect(a, closeTo(0.2, 0.01));
      }
    });
  });

  group('scale 联动', () {
    test('scale=0.97 时 factor=0，dynamicDarkAlpha=0.2，dynamicBrightAlpha=0.2', () {
      renderer.setLineState(
          isActive: false, scale: LyricLayout.inactiveScale);
      expect(renderer.factor, closeTo(0.0, 1e-9));
      expect(renderer.dynamicDarkAlpha, closeTo(0.2, 1e-9));
      expect(renderer.dynamicBrightAlpha, closeTo(0.2, 1e-9));
    });

    test('scale=1.0 时 factor=1，dynamicDarkAlpha=0.4，dynamicBrightAlpha=1.0', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      expect(renderer.factor, closeTo(1.0, 1e-9));
      expect(renderer.dynamicDarkAlpha, closeTo(0.4, 1e-9));
      expect(renderer.dynamicBrightAlpha, closeTo(1.0, 1e-9));
    });

    test('scale=0.985 时 factor=0.5，dynamicDarkAlpha=0.3，dynamicBrightAlpha=0.6', () {
      renderer.setLineState(isActive: true, scale: 0.985);
      expect(renderer.factor, closeTo(0.5, 1e-9));
      expect(renderer.dynamicDarkAlpha, closeTo(0.3, 1e-9));
      expect(renderer.dynamicBrightAlpha, closeTo(0.6, 1e-9));
    });

    test('scale 越界保护：< 0.97 时 factor 钳制为 0', () {
      renderer.setLineState(isActive: false, scale: 0.5);
      expect(renderer.factor, closeTo(0.0, 1e-9));
    });

    test('scale 越界保护：> 1.0 时 factor 钳制为 1', () {
      renderer.setLineState(isActive: true, scale: 1.5);
      expect(renderer.factor, closeTo(1.0, 1e-9));
    });
  });

  group('指数衰减', () {
    test('连续 tick 多次后，alpha 接近目标值（误差 < 0.01）', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);

      // progress=0.5: wordPos=2.0, currentIdx=2
      // word 0,1: 已播 → bright=1.0
      // word 2: 当前 wp=0 → dark=0.4
      // word 3: 未播 → dark=0.4
      for (int i = 0; i < 200; i++) {
        renderer.tick(0.016, 0.5);
      }
      expect(renderer.wordAlphas[0]!, closeTo(1.0, 0.01));
      expect(renderer.wordAlphas[1]!, closeTo(1.0, 0.01));
      expect(renderer.wordAlphas[2]!, closeTo(0.4, 0.01));
      expect(renderer.wordAlphas[3]!, closeTo(0.4, 0.01));
    });

    test('ATTACK 速度比 RELEASE 快：相同帧数下变亮幅度大于变暗幅度', () {
      // 变亮：从 dark(0.4) 到 bright(1.0)
      final upRenderer = WordRenderer()
        ..setLineState(isActive: true, scale: LyricLayout.activeScale);
      upRenderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      for (int i = 0; i < 5; i++) {
        upRenderer.tick(0.016, 1.0); // progress=1.0：所有字已播，目标=1.0
      }
      final double upAlpha = upRenderer.wordAlphas[0]!;

      // 变暗：从 bright(1.0) 到 dark(0.4)
      final downRenderer = WordRenderer()
        ..setLineState(isActive: true, scale: LyricLayout.activeScale);
      downRenderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      // 先把 alpha 推到接近 1.0
      for (int i = 0; i < 200; i++) {
        downRenderer.tick(0.016, 1.0);
      }
      // 然后切到 progress=0（目标 0.4）tick 5 次
      for (int i = 0; i < 5; i++) {
        downRenderer.tick(0.016, 0.0);
      }
      final double downAlpha = downRenderer.wordAlphas[0]!;

      // 5 帧内：变亮残差（距 1.0 的差）应小于变暗残差（距 0.4 的差）
      // 即 ATTACK 比 RELEASE 快
      expect(1.0 - upAlpha, lessThan(downAlpha - 0.4));
    });

    test('阈值收敛：alphaEpsilon=0.001 内的差值直接吸附到目标', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      // 大量 tick 让 alpha 充分收敛
      for (int i = 0; i < 500; i++) {
        renderer.tick(0.016, 1.0);
      }
      // 应完全等于目标 1.0（无残差）
      expect(renderer.wordAlphas[0]!, equals(1.0));
    });
  });

  group('reset', () {
    test('reset 后 alpha map 清空，状态归零', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      for (int i = 0; i < 50; i++) {
        renderer.tick(0.016, 0.5);
      }
      expect(renderer.wordAlphas, isNotEmpty);

      renderer.reset();
      expect(renderer.wordAlphas, isEmpty);
      expect(renderer.isActive, isFalse);
      expect(renderer.currentLineProgress, 0.0);
      // factor 也应回到 inactive (0)
      expect(renderer.factor, closeTo(0.0, 1e-9));
    });

    test('reset 后重新 paintLine 应重新绑定并初始化', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      for (int i = 0; i < 50; i++) {
        renderer.tick(0.016, 0.5);
      }
      renderer.reset();

      // 重新设置并绑定
      renderer.setLineState(
          isActive: false, scale: LyricLayout.inactiveScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      for (final a in renderer.wordAlphas.values) {
        expect(a, closeTo(0.2, 1e-9));
      }
    });
  });

  group('空 words 列表', () {
    test('paintLine 不崩溃，alpha map 为空', () {
      const emptyLine = LyricLine(
        startTime: 0,
        duration: 1000,
        text: '空行',
        words: [],
      );
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, emptyLine, 24);
      expect(renderer.wordAlphas, isEmpty);
    });

    test('tick 在空 words 时不崩溃', () {
      const emptyLine = LyricLine(
        startTime: 0,
        duration: 1000,
        text: '空行',
        words: [],
      );
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, emptyLine, 24);
      renderer.tick(0.016, 0.5);
      expect(renderer.wordAlphas, isEmpty);
    });

    test('空 text + 空 words 也不崩溃', () {
      const emptyLine = LyricLine(
        startTime: 0,
        duration: 1000,
        text: '',
        words: [],
      );
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, emptyLine, 24);
      expect(renderer.wordAlphas, isEmpty);
    });

    test('hasWordTiming=false 的行触发 SOLID 降级绘制不崩溃', () {
      const lrcLine = LyricLine(
        startTime: 0,
        duration: 1000,
        text: '这是一行 LRC 歌词',
        words: [],
      );
      expect(lrcLine.hasWordTiming, isFalse);
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, lrcLine, 24);
      // 降级绘制不写入 _wordAlphas（无 word index）
      expect(renderer.wordAlphas, isEmpty);
    });
  });

  group('line 切换重置 alpha map', () {
    test('切换到不同 line 时 alpha map 重新初始化', () {
      renderer.setLineState(isActive: true, scale: LyricLayout.activeScale);
      renderer.paintLine(makeCanvas(), ui.Offset.zero, line, 24);
      // 推进动画让 alpha 偏离初始值
      for (int i = 0; i < 50; i++) {
        renderer.tick(0.016, 1.0);
      }
      expect(renderer.wordAlphas[0]!, closeTo(1.0, 0.01));

      // 切换到新 line（不同引用）
      const newLine = LyricLine(
        startTime: 1000,
        duration: 2000,
        text: '新行',
        words: [
          LyricWord(startTime: 1000, duration: 500, text: '新'),
          LyricWord(startTime: 1500, duration: 500, text: '行'),
        ],
      );
      renderer.paintLine(makeCanvas(), ui.Offset.zero, newLine, 24);
      // alpha map 应重新初始化为新 line 的 word 数量，值为 dynamicDarkAlpha=0.4
      expect(renderer.wordAlphas.length, 2);
      for (final a in renderer.wordAlphas.values) {
        expect(a, closeTo(0.4, 1e-9));
      }
    });
  });
}
