import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/core/services/car_lyric_builder.dart';
import 'package:md3music/widgets/apple_lyrics/models/lyric_line.dart';

void main() {
  group('carLrcTag', () {
    test('输出标准 [mm:ss.xxx] 行级标签', () {
      expect(carLrcTag(0), '[00:00.000]');
      expect(carLrcTag(1234), '[00:01.234]');
      expect(carLrcTag(75_400), '[01:15.400]');
    });

    test('负数时间钳到 0（LRC 不接受负时间戳）', () {
      expect(carLrcTag(-5), '[00:00.000]');
    });

    test('超过 100 分钟不截断分钟位', () {
      expect(carLrcTag(101 * 60 * 1000), '[101:00.000]');
    });
  });

  group('buildCarWholeLrc', () {
    test('空列表返回空串（调用方据此走清空路径，不写负状态）', () {
      expect(buildCarWholeLrc(const []), '');
    });

    test('逐行输出并以换行分隔', () {
      const lines = [
        LyricLine(startTime: 12_340, duration: 2000, text: '第一行'),
        LyricLine(startTime: 18_900, duration: 2000, text: '第二行'),
      ];
      expect(
        buildCarWholeLrc(lines),
        '[00:12.340]第一行\n[00:18.900]第二行\n',
      );
    });

    test('跳过空文本行与纯空白行', () {
      const lines = [
        LyricLine(startTime: 1000, duration: 0, text: ''),
        LyricLine(startTime: 2000, duration: 0, text: '   '),
        LyricLine(startTime: 3000, duration: 0, text: '有内容'),
      ];
      expect(buildCarWholeLrc(lines), '[00:03.000]有内容\n');
    });

    test('文本两端空白被裁剪', () {
      const lines = [LyricLine(startTime: 0, duration: 0, text: '  歌词  ')];
      expect(buildCarWholeLrc(lines), '[00:00.000]歌词\n');
    });

    test('有逐字时间戳时绝不输出 ELRC 尖括号标签', () {
      const lines = [
        LyricLine(
          startTime: 16_440,
          duration: 2000,
          text: '歌词',
          words: [
            LyricWord(startTime: 16_440, duration: 360, text: '歌'),
            LyricWord(startTime: 16_800, duration: 400, text: '词'),
          ],
        ),
      ];
      final out = buildCarWholeLrc(lines);
      expect(out, '[00:16.440]歌词\n');
      expect(out.contains('<'), isFalse);
      expect(out.contains('>'), isFalse);
    });

    test('翻译不作为独立行输出（避免车机每句重复）', () {
      const lines = [
        LyricLine(
          startTime: 5000,
          duration: 2000,
          text: 'Hello',
          translation: '你好',
        ),
      ];
      final out = buildCarWholeLrc(lines);
      expect(out, '[00:05.000]Hello\n');
      expect(out.contains('你好'), isFalse);
    });

    test('罗马音不作为独立行输出', () {
      const lines = [
        LyricLine(startTime: 5000, duration: 2000, text: '桜', roma: 'sakura'),
      ];
      expect(buildCarWholeLrc(lines).contains('sakura'), isFalse);
    });

    test('全为空文本行时返回空串', () {
      const lines = [
        LyricLine(startTime: 1000, duration: 0, text: ''),
        LyricLine(startTime: 2000, duration: 0, text: '  '),
      ];
      expect(buildCarWholeLrc(lines), '');
    });

    test('输出只含行级标签，不含单行协议会用到的其它标记', () {
      const lines = [
        LyricLine(startTime: 0, duration: 0, text: 'a'),
        LyricLine(startTime: 1000, duration: 0, text: 'b'),
      ];
      final out = buildCarWholeLrc(lines);
      // 行数 == 非空歌词行数，说明没有插入额外行
      expect(out.trim().split('\n').length, 2);
      expect(RegExp(r'^\[\d{2,}:\d{2}\.\d{3}\]').hasMatch(out), isTrue);
    });
  });
}
