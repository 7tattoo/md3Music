/// LRC 歌词解析器
///
/// 解析标准 LRC 格式歌词文本，输出统一的 [LyricLine] 列表。
///
/// 支持的 LRC 特性：
/// - 时间戳 `[mm:ss.xx]`（2 位毫秒，按厘秒处理）与 `[mm:ss.xxx]`（3 位毫秒）
/// - 一行多时间戳：`[00:10.00][00:30.00]Chorus` 展开为多条 [LyricLine]
/// - 元数据行过滤：`[ar:]`、`[ti:]`、`[al:]`、`[by:]`、`[offset:]` 等
///
/// LRC 没有逐字时间戳信息，因此输出的 [LyricLine.words] 始终为空
/// （[LyricLine.hasWordTiming] 为 false），渲染层应使用整行降级模式。
/// 详见 spec.md "Requirement: LRC 解析器"。
library;

import 'package:md3music/widgets/apple_lyrics/models/lyric_line.dart';

/// LRC 明文解析器。
///
/// 将标准 LRC 文本解析为 [LyricLine] 列表。所有解析失败的情况
/// （如格式损坏、抛异常）一律返回空列表，不向外抛异常。
class LrcParser {
  LrcParser._();

  /// 时间戳正则：匹配 `[mm:ss.xx]` 或 `[mm:ss.xxx]`，全局可一行多次。
  static final RegExp _timestampRegex =
      RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

  /// 元数据前缀正则：匹配 LRC 元数据标签前缀，这些行不属于歌词内容。
  static final RegExp _metadataPrefixRegex = RegExp(
    r'^\[(ar|ti|al|by|offset|id|hash|total|language|sign|qq):',
  );

  /// 解析 LRC 明文为 [LyricLine] 列表。
  ///
  /// 解析失败时返回空列表，不抛异常。
  static List<LyricLine> parse(String lrcText) {
    try {
      final List<LyricLine> result = [];

      // 按行拆分，兼容 \n 与 \r\n
      final lines = lrcText.split(RegExp(r'\r?\n'));

      for (final rawLine in lines) {
        final line = rawLine.trim();

        // 空行跳过
        if (line.isEmpty) continue;

        // 元数据行跳过（[ar:]/[ti:]/[offset:] 等不匹配 mm:ss.xx 格式）
        if (_metadataPrefixRegex.hasMatch(line)) continue;

        // 提取一行内所有时间戳（支持一行多时间戳）
        final matches = _timestampRegex.allMatches(line).toList();
        // 无时间戳的纯文本行跳过（不属于 LRC 标准格式）
        if (matches.isEmpty) continue;

        // 剩余部分作为歌词文本（最后一个时间戳之后的内容）
        final lastMatch = matches.last;
        final text = line.substring(lastMatch.end).trim();

        // 为每个时间戳生成一条 LyricLine（一行多时间戳展开）
        for (final match in matches) {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          final msStr = match.group(3)!;
          // 2 位毫秒按厘秒换算（×10），3 位毫秒直接使用
          final milliseconds =
              int.parse(msStr) * (msStr.length == 2 ? 10 : 1);

          final startTime = (minutes * 60 + seconds) * 1000 + milliseconds;

          result.add(LyricLine(
            startTime: startTime,
            duration: 0, // LRC 没有行 duration 信息，由渲染层根据下一行 startTime 计算
            text: text,
            // words 默认 const []，translation 默认 null
          ));
        }
      }

      // 按 startTime 升序排序
      result.sort((a, b) => a.startTime.compareTo(b.startTime));

      return result;
    } catch (_) {
      // 失败兜底：返回空列表，不抛异常
      return [];
    }
  }
}
