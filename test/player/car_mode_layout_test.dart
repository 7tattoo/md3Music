import 'package:flutter_test/flutter_test.dart';

import 'package:md3music/modules/player/car_mode_layout.dart';

void main() {
  group('resolveCarModePanelWidth', () {
    test('默认 30%：1280 屏 → 384', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 1280, ratio: 0.30),
        closeTo(384.0, 0.001),
      );
    });

    test('下限 20%：1280 屏 → 256', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 1280, ratio: 0.20),
        closeTo(256.0, 0.001),
      );
    });

    test('上限 50%：1280 屏 → 640', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 1280, ratio: 0.50),
        closeTo(640.0, 0.001),
      );
    });

    test('占比越界向下：0.05 按 20% 计', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 1280, ratio: 0.05),
        closeTo(256.0, 0.001),
      );
    });

    test('占比越界向上：0.80 按 50% 计', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 1280, ratio: 0.80),
        closeTo(640.0, 0.001),
      );
    });

    test('窄屏被物理下限托底：800 屏 20% → 196 而不是 160', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 800, ratio: 0.20),
        closeTo(kCarModePanelMinWidth, 0.001),
      );
    });

    test('物理下限不得突破 50% 上限：300 屏 → 150', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 300, ratio: 0.50),
        closeTo(150.0, 0.001),
      );
    });

    test('占比 NaN 回落到默认 30%', () {
      expect(
        resolveCarModePanelWidth(screenWidth: 1280, ratio: double.nan),
        closeTo(384.0, 0.001),
      );
    });

    test('屏幕宽度 0 / 负数不抛异常', () {
      expect(resolveCarModePanelWidth(screenWidth: 0, ratio: 0.30), 0.0);
      expect(resolveCarModePanelWidth(screenWidth: -10, ratio: 0.30), 0.0);
    });
  });

  group('CarModePanelSide.fromIndex', () {
    test('null / 越界一律回落到左侧', () {
      expect(CarModePanelSide.fromIndex(null), CarModePanelSide.left);
      expect(CarModePanelSide.fromIndex(-1), CarModePanelSide.left);
      expect(CarModePanelSide.fromIndex(2), CarModePanelSide.left);
    });

    test('1 → 右侧', () {
      expect(CarModePanelSide.fromIndex(1), CarModePanelSide.right);
    });
  });

  group('resolveCarModeRatioDelta', () {
    test('左侧停靠：向右拖 = 面板变宽', () {
      expect(
        resolveCarModeRatioDelta(
          deltaX: 128,
          screenWidth: 1280,
          side: CarModePanelSide.left,
        ),
        closeTo(0.10, 0.001),
      );
    });

    test('右侧停靠：向右拖 = 面板变窄（位移取反）', () {
      expect(
        resolveCarModeRatioDelta(
          deltaX: 128,
          screenWidth: 1280,
          side: CarModePanelSide.right,
        ),
        closeTo(-0.10, 0.001),
      );
    });

    test('向左拖为负增量（夹取由上层负责）', () {
      expect(
        resolveCarModeRatioDelta(
          deltaX: -128,
          screenWidth: 1280,
          side: CarModePanelSide.left,
        ),
        lessThan(0),
      );
    });

    test('屏幕宽度 0 / 负数时返回 0（不产生 NaN / Infinity）', () {
      expect(
        resolveCarModeRatioDelta(
          deltaX: 100,
          screenWidth: 0,
          side: CarModePanelSide.left,
        ),
        0.0,
      );
      expect(
        resolveCarModeRatioDelta(
          deltaX: 100,
          screenWidth: -10,
          side: CarModePanelSide.left,
        ),
        0.0,
      );
    });

    test('位移为 NaN 时返回 0', () {
      expect(
        resolveCarModeRatioDelta(
          deltaX: double.nan,
          screenWidth: 1280,
          side: CarModePanelSide.left,
        ),
        0.0,
      );
    });
  });

  group('screenAspect / isCarLikeScreen / isPortraitOrSquareScreen', () {
    test('短边/长边：横屏 16:9 ≈ 0.5625', () {
      expect(screenAspect(1920, 1080), closeTo(1080 / 1920, 0.001));
    });

    test('方屏 880×860 ≈ 0.977', () {
      expect(screenAspect(880, 860), closeTo(860 / 880, 0.001));
    });

    test('竖屏手机长比 ≈ 0.46：不算车机屏', () {
      expect(screenAspect(1080, 2340), closeTo(1080 / 2340, 0.001));
      expect(isCarLikeScreen(1080, 2340), isFalse);
    });

    test('16:9 横屏车机（0.5625）判定为车机屏', () {
      expect(isCarLikeScreen(1920, 1080), isTrue);
    });

    test('方屏 / 竖屏车机判定为车机屏', () {
      expect(isCarLikeScreen(880, 860), isTrue);
      expect(isCarLikeScreen(1080, 1920), isTrue);
    });

    test('竖屏或近方屏判定：竖屏手机不属于（长比 < 0.8 不为方屏）', () {
      // 竖屏（高>宽）恒 true，与长比无关
      expect(isPortraitOrSquareScreen(1080, 1920), isTrue);
      // 近方屏横屏也 true
      expect(isPortraitOrSquareScreen(880, 860), isTrue);
      // 16:9 横屏：非竖屏且长比 0.5625 < 0.8 → false
      expect(isPortraitOrSquareScreen(1920, 1080), isFalse);
    });
  });

  group('resolveCarModePanelHeight', () {
    test('默认 30%：屏高 800 → 240', () {
      expect(
        resolveCarModePanelHeight(screenHeight: 800, ratio: 0.30),
        closeTo(240.0, 0.001),
      );
    });

    test('窄屏被物理下限托底：200 屏 20% → 140 而不是 40', () {
      expect(
        resolveCarModePanelHeight(screenHeight: 200, ratio: 0.20),
        closeTo(kCarModePanelMinHeight, 0.001),
      );
    });

    test('屏高 0 / 负数不抛异常', () {
      expect(resolveCarModePanelHeight(screenHeight: 0, ratio: 0.30), 0.0);
      expect(resolveCarModePanelHeight(screenHeight: -10, ratio: 0.30), 0.0);
    });
  });

  group('resolveCarModeHeightDelta', () {
    test('贴底：向下拖 = 面板变高', () {
      expect(
        resolveCarModeHeightDelta(
          deltaY: 80,
          screenHeight: 800,
          atBottom: true,
        ),
        closeTo(0.10, 0.001),
      );
    });

    test('向上拖为负增量', () {
      expect(
        resolveCarModeHeightDelta(
          deltaY: -80,
          screenHeight: 800,
          atBottom: true,
        ),
        lessThan(0),
      );
    });

    test('非法输入返回 0', () {
      expect(
        resolveCarModeHeightDelta(
          deltaY: 80,
          screenHeight: 0,
          atBottom: true,
        ),
        0.0,
      );
    });
  });
}
