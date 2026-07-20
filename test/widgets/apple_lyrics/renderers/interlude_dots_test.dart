import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/widgets/apple_lyrics/layout/lyric_layout.dart';
import 'package:md3music/widgets/apple_lyrics/renderers/interlude_dots.dart';

void main() {
  group('InterludeDots', () {
    test('初始状态：无间奏，isInterlude 返回 false，shouldRender=false', () {
      final dots = InterludeDots();
      expect(dots.startTime, isNull);
      expect(dots.endTime, isNull);
      expect(dots.isInterlude(0), isFalse);
      expect(dots.isInterlude(5000), isFalse);
      expect(dots.shouldRender, isFalse);
      // tick 不抛异常即可（返回 void）
      dots.tick(0.016);
      dots.tick(0.1);
    });

    group('设置间奏后 (start=1000, end=7000)', () {
      // 注意：按 API 约定，endTime 是调用方已减去 interludeEarlyEndMs(250ms) 的值。
      // 这里模拟"下一行 startTime=7250ms"的场景，传入 endTime=7250-250=7000。
      const start = 1000;
      const end = 7000;
      late InterludeDots dots;

      setUp(() {
        dots = InterludeDots();
        dots.setInterlude(start, end);
        // 推进 1 帧（16ms）使动画时钟启动
        dots.tick(0.016);
      });

      test('setInterlude 后 shouldRender=true', () {
        expect(dots.shouldRender, isTrue);
      });

      test('间奏时段内 isInterlude 返回 true（基于 currentTimeMs 判定）', () {
        expect(dots.isInterlude(1000), isTrue);
        expect(dots.isInterlude(3000), isTrue);
        expect(dots.isInterlude(6999), isTrue);
      });

      test('间奏边界：startTime 处 isInterlude=true，endTime 处 isInterlude=false', () {
        expect(dots.isInterlude(start), isTrue);
        expect(dots.isInterlude(end), isFalse);
      });

      test('间奏外时刻 isInterlude 返回 false', () {
        expect(dots.isInterlude(start - 1), isFalse);
        expect(dots.isInterlude(end), isFalse);
        expect(dots.isInterlude(end + 1000), isFalse);
      });
    });

    group('clear()', () {
      test('clear 后 isInterlude 返回 false，shouldRender=false', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        dots.tick(0.016);
        expect(dots.isInterlude(3000), isTrue);
        expect(dots.shouldRender, isTrue);

        dots.clear();
        expect(dots.startTime, isNull);
        expect(dots.endTime, isNull);
        expect(dots.isInterlude(3000), isFalse);
        expect(dots.isInterlude(1000), isFalse);
        expect(dots.shouldRender, isFalse);
      });
    });

    group('setInterlude 重新设置', () {
      test('重新设置后旧时段失效，新时段生效', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        dots.tick(0.016);
        expect(dots.isInterlude(3000), isTrue);

        dots.setInterlude(10000, 20000);
        dots.tick(0.016);
        expect(dots.isInterlude(3000), isFalse);
        expect(dots.isInterlude(15000), isTrue);
      });

      test('相同间奏重复调用 setInterlude 不重置（幂等）', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        dots.tick(0.016);
        // 推进一段时间
        dots.tick(0.5);
        // 再次设置相同间奏，shouldRender 仍为 true，且动画时钟不重置
        dots.setInterlude(1000, 7000);
        expect(dots.shouldRender, isTrue);
        expect(dots.isInterlude(3000), isTrue);
      });

      test('setInterlude(null, null) 清除间奏', () {
        final dots = InterludeDots();
        dots.setInterlude(1000, 7000);
        dots.tick(0.016);
        expect(dots.shouldRender, isTrue);

        dots.setInterlude(null, null);
        expect(dots.shouldRender, isFalse);
        expect(dots.startTime, isNull);
      });
    });

    group('间奏检测规则集成（参照 spec.md）', () {
      test('相邻行间隔 >= 4000ms 应触发间奏（由调用方判定，本类只接收时段）', () {
        final dots = InterludeDots();
        const currentEnd = 1000;
        const nextStart = 6000;
        const gap = nextStart - currentEnd;
        expect(gap, greaterThanOrEqualTo(LyricLayout.interludeThresholdMs));

        dots.setInterlude(currentEnd, nextStart - LyricLayout.interludeEarlyEndMs);
        dots.tick(0.016);
        expect(dots.isInterlude(currentEnd), isTrue);
        expect(dots.isInterlude(nextStart - LyricLayout.interludeEarlyEndMs - 1), isTrue);
        expect(dots.isInterlude(nextStart - LyricLayout.interludeEarlyEndMs), isFalse);
      });

      test('相邻行间隔 < 4000ms 不应触发间奏（调用方不调用 setInterlude）', () {
        final dots = InterludeDots();
        const currentEnd = 1000;
        const nextStart = 4000;
        const gap = nextStart - currentEnd;
        expect(gap, lessThan(LyricLayout.interludeThresholdMs));

        expect(dots.isInterlude(currentEnd), isFalse);
        expect(dots.shouldRender, isFalse);
      });
    });
  });
}
