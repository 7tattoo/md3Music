import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/widgets/apple_lyrics/models/lyric_line.dart';
import 'package:md3music/widgets/apple_lyrics/parsers/lrc_parser.dart';

/// LrcParser 单元测试
/// 覆盖：标准行、两位/三位毫秒、一行多时间戳、元数据过滤、空输入、
/// 仅元数据、纯文本跳过、UTF-8 中文、多行混合排序、duration 字段
void main() {
  group('LrcParser.parse', () {
    test('标准单行：[01:23.45]Hello → 1 行，startTime=83450', () {
      final result = LrcParser.parse('[01:23.45]Hello');
      expect(result, hasLength(1));
      final line = result.first;
      expect(line.startTime, 83450);
      expect(line.text, 'Hello');
      expect(line.words, isEmpty);
      expect(line.hasWordTiming, isFalse);
    });

    test('两位毫秒：[00:05.45]World → startTime=5450', () {
      final result = LrcParser.parse('[00:05.45]World');
      expect(result, hasLength(1));
      expect(result.first.startTime, 5450);
      expect(result.first.text, 'World');
    });

    test('三位毫秒：[00:05.456]World → startTime=5456', () {
      final result = LrcParser.parse('[00:05.456]World');
      expect(result, hasLength(1));
      expect(result.first.startTime, 5456);
      expect(result.first.text, 'World');
    });

    test('一行多时间戳：[00:10.00][00:30.00]Chorus → 2 行按 startTime 升序', () {
      final result = LrcParser.parse('[00:10.00][00:30.00]Chorus');
      expect(result, hasLength(2));
      expect(result[0].startTime, 10000);
      expect(result[0].text, 'Chorus');
      expect(result[1].startTime, 30000);
      expect(result[1].text, 'Chorus');
      // 确认升序
      expect(result[0].startTime <= result[1].startTime, isTrue);
    });

    test('元数据过滤：[ar:]/[ti:] 跳过，仅保留歌词行', () {
      final result =
          LrcParser.parse('[ar:Artist]\n[ti:Title]\n[00:01.00]Lyric');
      expect(result, hasLength(1));
      expect(result.first.startTime, 1000);
      expect(result.first.text, 'Lyric');
    });

    test('空输入返回空列表', () {
      expect(LrcParser.parse(''), isEmpty);
    });

    test('仅元数据返回空列表', () {
      final result = LrcParser.parse(
        '[ar:Artist]\n[ti:Title]\n[al:Album]\n[by:Author]',
      );
      expect(result, isEmpty);
    });

    test('无时间戳的纯文本跳过，返回空列表', () {
      expect(LrcParser.parse('just text'), isEmpty);
    });

    test('UTF-8 中文正确解析', () {
      final result = LrcParser.parse('[00:30.00]你好世界');
      expect(result, hasLength(1));
      expect(result.first.startTime, 30000);
      expect(result.first.text, '你好世界');
    });

    test('多行混合：3 行歌词 + 2 行元数据 → 3 行按时间排序', () {
      final lrc = '''
[ar:Artist]
[ti:Title]
[00:20.00]Third
[00:05.00]First
[00:10.00]Second
''';
      final result = LrcParser.parse(lrc);
      expect(result, hasLength(3));
      expect(result[0].startTime, 5000);
      expect(result[0].text, 'First');
      expect(result[1].startTime, 10000);
      expect(result[1].text, 'Second');
      expect(result[2].startTime, 20000);
      expect(result[2].text, 'Third');
    });

    test('duration 字段为 0（所有 LyricLine）', () {
      final result = LrcParser.parse('[00:01.00]A\n[00:02.00]B');
      expect(result, hasLength(2));
      for (final line in result) {
        expect(line.duration, 0);
      }
    });

    test('translation 字段为 null', () {
      final result = LrcParser.parse('[00:01.00]Hello');
      expect(result, hasLength(1));
      expect(result.first.translation, isNull);
    });

    test('空行跳过', () {
      final result = LrcParser.parse('\n\n[00:01.00]Hello\n\n');
      expect(result, hasLength(1));
      expect(result.first.text, 'Hello');
    });

    test('全部元数据标签均被过滤', () {
      final lrc = '''
[offset:+100]
[id:123]
[hash:abc]
[total:180]
[language:zh]
[sign:署名]
[qq:123456]
[00:01.00]Lyric
''';
      final result = LrcParser.parse(lrc);
      expect(result, hasLength(1));
      expect(result.first.text, 'Lyric');
    });

    test('损坏输入不抛异常，返回空列表', () {
      expect(LrcParser.parse('[[[broken'), isEmpty);
    });

    test('无时间戳但有方括号的行跳过', () {
      expect(LrcParser.parse('[not a timestamp]text'), isEmpty);
    });

    test('一行多时间戳乱序输入也会按 startTime 升序输出', () {
      final result = LrcParser.parse('[00:30.00][00:10.00]Chorus');
      expect(result, hasLength(2));
      expect(result[0].startTime, 10000);
      expect(result[1].startTime, 30000);
    });

    test('LyricLine 相等性：相同时间戳与文本相等', () {
      final a = LrcParser.parse('[00:01.00]Hello');
      const b = LyricLine(startTime: 1000, duration: 0, text: 'Hello');
      expect(a.first, equals(b));
    });
  });
}
