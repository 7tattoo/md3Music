/// 逐字 mask alpha 渲染器（核心渲染组件）
///
/// 参照 spec.md "Requirement: 逐字 mask alpha 渲染" 实现。
/// 文字本身固定白色，靠 mask alpha 区分已播 / 未播字：
/// - 当前行（GRADIENT 模式）：已播字 alpha = dynamicBrightAlpha，未播字 alpha = dynamicDarkAlpha，
///   当前字按指数衰减在两者之间过渡，左亮右暗。
/// - 非当前行（SOLID 模式）：整行均匀 alpha = dynamicDarkAlpha。
///
/// 本类不是 Widget，是核心绘制逻辑类，由外部 CustomPainter 调用 [paintLine]。
/// 动画驱动由外部 AnimationController + Ticker 调用 [tick] 实现（SubTask 7.7）。
library;

import 'dart:collection';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../layout/lyric_layout.dart';
import '../models/lyric_line.dart';

/// 逐字 mask alpha 渲染器。
///
/// 持有当前 scale、isActive、currentLineProgress 与每个 word 的当前 alpha 值，
/// 通过 [tick] 推进指数衰减动画，通过 [paintLine] 用对应 alpha 逐字绘制白色文本。
class WordRenderer {
  WordRenderer();

  // ============== 内部状态 ==============

  /// 当前是否为当前行（GRADIENT 模式）。默认 false（SOLID）。
  bool _isActive = false;

  /// 当前行缩放，0.97（inactive）~1.0（active）。默认 inactive。
  double _scale = LyricLayout.inactiveScale;

  /// 当前行播放进度（0~1，相对当前行）。默认 0。
  double _currentLineProgress = 0.0;

  /// 当前绑定的 LyricLine。用于检测 line 切换并重置 alpha map。
  LyricLine? _boundLine;

  /// 缓存的字号（用于检测 fontSize 变化时重新测量 word 宽度）。
  double _boundFontSize = -1;

  /// 每个 word 的缓存宽度（在 [_ensureBound] 时一次性测量）。
  ///
  /// **性能优化**：之前每帧 paintLine 都为每个 word 创建 TextPainter + layout
  /// 来测量宽度（用于换行判断）。现在只在 line 切换或 fontSize 变化时测量一次。
  /// 10 word/行 × 60fps = 每秒 600 次 layout → 缓存后降为 0 次/帧。
  List<double> _wordWidths = const <double>[];

  /// 复用的 TextPainter 实例（避免每帧创建对象）。
  ///
  /// 注意：text setter 会标记需要 layout，所以 layout 还是要做，
  /// 但省了 TextPainter 对象创建+GC 的开销。
  final TextPainter _painter = TextPainter(textDirection: TextDirection.ltr);

  /// 每个 word index 的当前 alpha 值。
  final Map<int, double> _wordAlphas = <int, double>{};

  /// 每个 word index 的当前 Y 轴偏移（上浮特效）。
  ///
  /// AMLL 规范：当前字会轻微上浮（最大约 -3px），用指数衰减平滑过渡。
  /// 已播字回到 0，未播字保持 0，当前字上浮。
  final Map<int, double> _wordYOffsets = <int, double>{};

  /// AMLL 上浮最大幅度（px）：当前字最大上浮 -3px。
  static const double _maxLiftPx = -3.0;

  /// AMLL 上浮 ATTACK 速度：当前字上浮指数衰减系数。
  static const double _liftAttackSpeed = 30.0;

  /// AMLL 上浮 RELEASE 速度：当前字回落指数衰减系数。
  static const double _liftReleaseSpeed = 10.0;

  // ============== 状态查询 ==============

  /// 当前 alpha map（不可变视图，供测试断言）。
  ///
  /// 使用 [UnmodifiableMapView] 包装，外部只读，修改不影响内部状态。
  @visibleForTesting
  Map<int, double> get wordAlphas =>
      UnmodifiableMapView<int, double>(_wordAlphas);

  /// 当前 scale 对应的 factor（0~1）。
  ///
  /// 公式：`factor = clamp01((scale - 0.97) / 0.03)`
  double get factor {
    final raw = (_scale - LyricLayout.inactiveScale) /
        (LyricLayout.activeScale - LyricLayout.inactiveScale);
    return raw.clamp(0.0, 1.0).toDouble();
  }

  /// 动态暗态 alpha（未播字 / 非当前行 SOLID）。
  ///
  /// 公式：`dynamicDarkAlpha = factor * 0.2 + 0.2`，范围 0.2~0.4。
  double get dynamicDarkAlpha => factor * 0.2 + 0.2;

  /// 动态亮态 alpha（已播字 / 当前字目标）。
  ///
  /// 公式：`dynamicBrightAlpha = factor * 0.8 + 0.2`，范围 0.2~1.0。
  double get dynamicBrightAlpha => factor * 0.8 + 0.2;

  /// 当前是否为当前行。
  bool get isActive => _isActive;

  /// 当前行播放进度（0~1）。
  double get currentLineProgress => _currentLineProgress;

  // ============== 状态设置 ==============

  /// 设置当前行状态。
  ///
  /// [isActive] 为 true 时启用 GRADIENT 模式（已播亮 / 未播暗），
  /// 为 false 时启用 SOLID 模式（整行均匀暗）。
  /// [scale] 是行缩放，0.97（inactive）~1.0（active）。
  void setLineState({required bool isActive, required double scale}) {
    _isActive = isActive;
    _scale = scale;
  }

  // ============== 动画推进 ==============

  /// 推进动画。
  ///
  /// [dt] 距上一帧的时间间隔（秒）。[progress] 当前行播放进度 0~1，
  /// 用于判断每个 word 是"已播"、"当前"、"未播"，分别计算目标 alpha。
  /// 用指数衰减公式 `alpha += (target - alpha) * (1 - exp(-speed * dt))`
  /// 平滑过渡：变亮用 [LyricLayout.attackSpeed]（50.0），变暗用 [LyricLayout.releaseSpeed]（7.0）。
  /// 差值小于 [LyricLayout.alphaEpsilon]（0.001）时吸附到目标。
  void tick(double dt, double progress) {
    _currentLineProgress = progress.clamp(0.0, 1.0).toDouble();
    if (dt <= 0) return;
    if (_boundLine == null || _boundLine!.words.isEmpty) return;

    final double dark = dynamicDarkAlpha;
    final double bright = dynamicBrightAlpha;
    final int wordCount = _boundLine!.words.length;

    for (int i = 0; i < wordCount; i++) {
      final double target = _targetAlphaFor(i, wordCount, dark, bright);
      final double current = _wordAlphas[i] ?? dark;
      // 变亮用 ATTACK（快），变暗用 RELEASE（慢）
      final double speed = target >= current
          ? LyricLayout.attackSpeed
          : LyricLayout.releaseSpeed;
      final double decay = 1.0 - exp(-speed * dt);
      double next = current + (target - current) * decay;
      // 阈值收敛：差值小于 alphaEpsilon 直接吸附到目标
      if ((next - target).abs() < LyricLayout.alphaEpsilon) {
        next = target;
      }
      _wordAlphas[i] = next;

      // AMLL 上浮特效：当前字上浮到 _maxLiftPx，其他字回到 0
      final double targetY = _targetYOffsetFor(i, wordCount);
      final double currentY = _wordYOffsets[i] ?? 0;
      final double ySpeed = targetY >= currentY
          ? _liftAttackSpeed
          : _liftReleaseSpeed;
      final double yDecay = 1.0 - exp(-ySpeed * dt);
      double nextY = currentY + (targetY - currentY) * yDecay;
      if ((nextY - targetY).abs() < LyricLayout.alphaEpsilon) {
        nextY = targetY;
      }
      _wordYOffsets[i] = nextY;
    }
  }

  /// 计算指定 word index 的目标 Y 偏移（AMLL 上浮特效）。
  ///
  /// - 非当前行：所有 word Y=0（不上浮）。
  /// - 当前行：
  ///   - 已播字（index < 当前 word 索引）：Y=_maxLiftPx（保持上浮，不回落）。
  ///   - 当前字（index == 当前 word 索引）：按 word 内进度 0 → _maxLiftPx 上浮。
  ///     **使用 smoothstep 曲线（ease-in-out）**：`t' = t*t*(3-2*t)`
  ///     起步和结束更柔，避免线性变化的生硬感。
  ///   - 未播字（index > 当前 word 索引）：Y=0。
  ///
  /// 用户确认（grill-me Q2 (A) AMLL 原版）：已播字保持上浮状态，
  /// 营造整行从左到右逐渐浮起的效果，而非"弹一下回落"。
  ///
  /// 用户反馈（grill-me 第三轮）：上浮动画不够细腻，一顿一顿的。
  /// 改用 smoothstep 曲线让起步和结束更平滑。
  double _targetYOffsetFor(int index, int wordCount) {
    if (!_isActive) return 0;
    final double wordPos = _currentLineProgress * wordCount;
    final int currentIdx = wordPos.floor();
    if (index < currentIdx) {
      // 已播字：保持上浮
      return _maxLiftPx;
    }
    if (index == currentIdx) {
      // 当前 word 内进度（0~1），用 smoothstep 曲线（ease-in-out）
      // smoothstep: t*t*(3-2*t)，起步和结束更柔
      final double wp = wordPos - currentIdx;
      final double eased = wp * wp * (3 - 2 * wp);
      return _maxLiftPx * eased;
    }
    // 未播字：不上浮
    return 0;
  }

  /// 计算指定 word index 的目标 alpha。
  ///
  /// - 非当前行：所有 word 目标 = [dynamicDarkAlpha]（SOLID）。
  /// - 当前行：根据 [_currentLineProgress] 映射到 word 索引位置：
  ///   - 已播字（index < 当前 word 索引）目标 = [dynamicBrightAlpha]。
  ///   - 未播字（index > 当前 word 索引）目标 = [dynamicDarkAlpha]。
  ///   - 当前字（index == 当前 word 索引）按 word 内进度在 dark~bright 之间线性插值。
  double _targetAlphaFor(
      int index, int wordCount, double dark, double bright) {
    if (!_isActive) return dark;
    // 当前行 GRADIENT：progress 映射到 word 索引位置
    final double wordPos = _currentLineProgress * wordCount;
    final int currentIdx = wordPos.floor();
    if (index < currentIdx) {
      return bright;
    } else if (index > currentIdx) {
      return dark;
    } else {
      // 当前 word 内进度（0~1）线性插值 dark → bright
      final double wp = wordPos - currentIdx;
      return dark + (bright - dark) * wp;
    }
  }

  // ============== 绘制 ==============

  /// 绘制单行歌词。
  ///
  /// [offset] 是行起始绘制原点。文字颜色固定白色 #FFFFFFFF，
  /// 通过逐字 alpha 区分已播 / 未播。
  ///
  /// [maxWidth] 为该行可用最大文字宽度（视口宽 - 左右 1em 边距）。
  /// 当 word 累加 dx 超过 [maxWidth] 且 dx > 0 时换行：
  /// dx 归零，currentY += mainLineHeight × wrapLineHeightFactor（0.8x 行高）。
  ///
  /// **性能优化**：
  /// - word 宽度用 [_wordWidths] 缓存（[_ensureBound] 时一次性测量），
  ///   换行判断不再每帧创建 TextPainter + layout
  /// - 复用 [_painter] 实例，避免每帧创建对象（layout 还是要做，
  ///   因为 alpha 变了需要重新设置 TextSpan，但省了对象创建+GC）
  void paintLine(
      Canvas canvas, Offset offset, LyricLine line, double fontSize,
      {double maxWidth = double.infinity}) {
    _ensureBound(line, fontSize);

    if (line.words.isEmpty) {
      _paintSolidFallback(canvas, offset, line, fontSize, maxWidth: maxWidth);
      return;
    }

    double dx = 0; // 相对 offset.dx 的水平偏移
    double currentY = offset.dy; // 当前视觉行的 y 坐标
    final double dark = dynamicDarkAlpha;
    // 换行内部行高 = 主行高 × 0.8（与 LyricLayout.measureLineHeight 一致）
    final double wrapLineHeight =
        fontSize * LyricLayout.lineHeight * LyricLayout.wrapLineHeightFactor;
    final double lineHeight = LyricLayout.lineHeight;

    for (int i = 0; i < line.words.length; i++) {
      final LyricWord word = line.words[i];
      final double alpha = _wordAlphas[i] ?? dark;
      // AMLL 上浮特效：当前字 Y 偏移（上浮）
      final double yOffset = _wordYOffsets[i] ?? 0;
      // 用缓存宽度做换行判断（避免每帧 TextPainter.layout 测量）
      final double width =
          i < _wordWidths.length ? _wordWidths[i] : 0;
      // 自动换行：累计宽度超过 maxWidth 且本视觉行已有 word 时换行
      if (dx + width > maxWidth && dx > 0) {
        dx = 0;
        currentY += wrapLineHeight;
      }
      // 复用 _painter 实例绘制（set text + layout + paint）
      _painter.text = TextSpan(
        text: word.text,
        style: TextStyle(
          color: Color.fromRGBO(255, 255, 255, alpha),
          fontSize: fontSize,
          height: lineHeight,
        ),
      );
      _painter.layout();
      _painter.paint(canvas, Offset(offset.dx + dx, currentY + yOffset));
      dx += width;
    }
  }

  /// 整行降级绘制（无 word 时间戳时使用）。
  ///
  /// [maxWidth] 用于自动换行（默认 [double.infinity] 不换行）。
  /// 复用 [_painter] 实例避免对象创建。
  void _paintSolidFallback(
      Canvas canvas, Offset offset, LyricLine line, double fontSize,
      {double maxWidth = double.infinity}) {
    if (line.text.isEmpty) return;
    final double alpha = dynamicDarkAlpha;
    _painter.text = TextSpan(
      text: line.text,
      style: TextStyle(
        color: Color.fromRGBO(255, 255, 255, alpha),
        fontSize: fontSize,
        height: LyricLayout.lineHeight,
      ),
    );
    _painter.layout(
        maxWidth: maxWidth == double.infinity ? double.infinity : maxWidth);
    _painter.paint(canvas, offset);
  }

  /// 检测 line 切换并重置 alpha map，同时测量并缓存所有 word 宽度。
  ///
  /// 若传入的 line 与当前绑定不是同一对象引用（[identical] 失败），
  /// 或 fontSize 变化，重新初始化每个 word 的 alpha 为 [dynamicDarkAlpha]，
  /// 并测量每个 word 的宽度缓存到 [_wordWidths]。
  ///
  /// **性能优化**：word 宽度只在此时测量一次，paintLine 用缓存宽度做换行判断，
  /// 避免每帧创建 N 个 TextPainter + layout。
  void _ensureBound(LyricLine line, double fontSize) {
    final sameLine = identical(_boundLine, line);
    final sameFontSize = _boundFontSize == fontSize;
    if (sameLine && sameFontSize) return;
    _boundLine = line;
    _boundFontSize = fontSize;
    _wordAlphas.clear();
    _wordYOffsets.clear();
    final double dark = dynamicDarkAlpha;
    // 测量所有 word 宽度并缓存
    _wordWidths = List<double>.filled(line.words.length, 0);
    for (int i = 0; i < line.words.length; i++) {
      _painter.text = TextSpan(
        text: line.words[i].text,
        style: TextStyle(
          fontSize: fontSize,
          height: LyricLayout.lineHeight,
        ),
      );
      _painter.layout();
      _wordWidths[i] = _painter.width;
      _wordAlphas[i] = dark;
      _wordYOffsets[i] = 0;
    }
  }

  /// 重置状态：清空 alpha map、Y 偏移、归零 progress、scale 回到 inactive、isActive=false、解绑 line。
  void reset() {
    _isActive = false;
    _scale = LyricLayout.inactiveScale;
    _currentLineProgress = 0.0;
    _boundLine = null;
    _boundFontSize = -1;
    _wordWidths = const <double>[];
    _wordAlphas.clear();
    _wordYOffsets.clear();
  }
}
