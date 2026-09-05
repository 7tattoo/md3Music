/// vivo 车机整段 LRC 构造（纯函数，供单测）。
///
/// 车联投屏（ucar）与原子随身听（vivomusicmix）都只接受**标准行级 LRC**：
/// 车机侧解析器（`ub/e.java` / `com/vivo/musicwidgetmix/lrc/e.java` 同源）
/// 只认 `[mm:ss.xxx]文本` 这一种行格式，并按 PlaybackState 进度自行切行。
///
/// 两条铁律：
/// 1. **绝不输出 ELRC 逐字标签** `<mm:ss.xxx>` —— 车机把它当普通文本原样显示，
///    结果是歌词里混进一串时间戳。
/// 2. **绝不输出翻译行 / 空文本行** —— 翻译行与主行同时间戳，车机会把两行
///    都当独立歌词行，表现为每句重复；空行则会显示成空白跳行。
library;

import 'package:md3music/widgets/apple_lyrics/models/lyric_line.dart';

/// 毫秒 → LRC 行级时间标签 `[mm:ss.xxx]`。
///
/// 分钟不截断到 2 位：超过 100 分钟的长音频（演唱会、有声书）保持真实值，
/// 车机解析器按 `:` 分段取整数，位数不敏感。
String carLrcTag(int ms) {
  final safe = ms < 0 ? 0 : ms;
  final m = safe ~/ 60000;
  final s = (safe % 60000) ~/ 1000;
  final msPart = safe % 1000;
  return '[${m.toString().padLeft(2, '0')}'
      ':${s.toString().padLeft(2, '0')}'
      '.${msPart.toString().padLeft(3, '0')}]';
}

/// 由统一歌词模型构造车机整段 LRC。
///
/// 空列表 / 全为空文本行 → 返回空串，调用方据此走「清空」路径
/// （发空 `lrc_change` + 摘掉 `LYRICS_WHOLE`），**绝不写负状态**。
String buildCarWholeLrc(List<LyricLine> lines) {
  if (lines.isEmpty) return '';
  final buffer = StringBuffer();
  for (final line in lines) {
    final text = line.text.trim();
    if (text.isEmpty) continue;
    buffer
      ..write(carLrcTag(line.startTime))
      ..write(text)
      ..write('\n');
  }
  return buffer.toString();
}
