/// 统一歌词模型。
///
/// 定义 [LyricWord]（字级时间戳）与 [LyricLine]（行级时间戳 + 字列表）
/// 两个不可变值对象，供所有歌词解析器（KRC / LRC / 纯文本）输出统一结构，
/// 渲染层只认模型不关心来源。详见 spec.md "Requirement: 统一歌词模型"。
library;

import 'package:flutter/foundation.dart';

/// 单个歌词字（逐字时间戳）。
///
/// 用于 KRC 逐字渲染：每个字携带独立的起止时间，渲染器据此计算
/// mask alpha 渐变（已播字亮 / 未播字暗）。LRC 与纯文本不产生 [LyricWord]。
class LyricWord {
  /// 起始时间，毫秒，绝对时间（相对歌曲起点）。
  final int startTime;

  /// 持续时长，毫秒。
  final int duration;

  /// 歌词字面文本。
  final String text;

  /// 常量构造函数。
  const LyricWord({
    required this.startTime,
    required this.duration,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricWord &&
          runtimeType == other.runtimeType &&
          startTime == other.startTime &&
          duration == other.duration &&
          text == other.text;

  @override
  int get hashCode => Object.hash(startTime, duration, text);

  @override
  String toString() =>
      'LyricWord(startTime: $startTime, duration: $duration, text: \'$text\')';
}

/// 单行歌词。
///
/// 既能承载逐字时间戳（[words] 非空，KRC 来源），也能承载整行时间戳
/// （[words] 为空，LRC / 纯文本来源）。渲染器通过 [hasWordTiming] 判断
/// 是否启用逐字 mask 渲染或整行降级渲染。
class LyricLine {
  /// 起始时间，毫秒。
  final int startTime;

  /// 持续时长，毫秒。
  final int duration;

  /// 整行纯文本（合并 [words] 的文本或直接来自 LRC 行）。
  final String text;

  /// 逐字时间戳列表，可能为空（LRC / 纯文本）。默认空常量列表。
  final List<LyricWord> words;

  /// 翻译文本，可空（如无翻译数据）。
  final String? translation;

  /// 常量构造函数。[words] 默认空常量列表。
  const LyricLine({
    required this.startTime,
    required this.duration,
    required this.text,
    this.words = const [],
    this.translation,
  });

  /// 该行是否有逐字时间戳。渲染器据此切换逐字 / 整行模式。
  bool get hasWordTiming => words.isNotEmpty;

  /// 行结束时间 = [startTime] + [duration]。
  int get endTime => startTime + duration;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine &&
          runtimeType == other.runtimeType &&
          startTime == other.startTime &&
          duration == other.duration &&
          text == other.text &&
          translation == other.translation &&
          listEquals(words, other.words);

  @override
  int get hashCode => Object.hash(
        startTime,
        duration,
        text,
        translation,
        Object.hashAll(words),
      );

  @override
  String toString() =>
      'LyricLine(startTime: $startTime, duration: $duration, text: \'$text\', '
      'words: ${words.length}, translation: ${translation == null ? 'null' : '\'$translation\''})';
}
