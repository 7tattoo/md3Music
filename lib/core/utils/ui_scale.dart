import 'package:flutter/material.dart';

/// 「调整全局界面大小」（ThemeProvider.uiScale）对非文字元素的换算。
///
/// 这里读 [MediaQuery] 的 textScaler，而不是直接读 ThemeProvider，是为了让
/// 封面/头像与文字共用同一个缩放来源，豁免范围也自动一致：
/// - app.dart 的 builder 把全局 textScaler 设为 `TextScaler.linear(uiScale)`；
/// - lyrics_view.dart 把它覆写为 [TextScaler.noScaling]，
///   歌词界面内的封面/头像随之保持原尺寸，不需要再传标记进去。
extension UiScaleQuery on BuildContext {
  /// 缩放一个逻辑尺寸（封面边长、头像半径、圆角等）。
  ///
  /// `double.infinity`（由父级空间决定尺寸的填充式封面）原样返回：
  /// 那类封面跟随布局容器，缩放它只会溢出。
  double scaledSize(double size) =>
      size.isFinite ? MediaQuery.textScalerOf(this).scale(size) : size;

  /// 缩放图片解码缓存尺寸，避免放大后封面/头像变模糊。
  int scaledCache(int px) =>
      MediaQuery.textScalerOf(this).scale(px.toDouble()).round();
}
