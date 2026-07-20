import 'package:flutter/material.dart';

import 'lyric_preferences.dart';

/// 歌词字号/行间距调节面板。
///
/// 可嵌入设置页或作为 BottomSheet 弹出。
/// 用 AnimatedBuilder 监听 [LyricPreferences]，滑动滑块时实时刷新歌词。
///
/// 字号范围 12~30px，行间距系数范围 1.0~2.0。
/// 行高公式：`actualLineHeight = (fontSize / defaultFontSize) * lineSpacing`。
class LyricPreferencesPanel extends StatelessWidget {
  const LyricPreferencesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = LyricPreferences.instance;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '歌词显示',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => prefs.reset(),
                    child: const Text('重置'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 字号滑块
              Text('字号：${prefs.fontSize.round()} px'),
              Slider(
                min: LyricPreferences.minFontSize,
                max: LyricPreferences.maxFontSize,
                divisions:
                    (LyricPreferences.maxFontSize -
                            LyricPreferences.minFontSize)
                        .round(),
                value: prefs.fontSize,
                onChanged: prefs.setFontSize,
              ),
              const SizedBox(height: 8),
              // 行间距滑块
              Text('行间距：${prefs.lineSpacing.toStringAsFixed(1)} ×'),
              Slider(
                min: LyricPreferences.minLineSpacing,
                max: LyricPreferences.maxLineSpacing,
                divisions: ((LyricPreferences.maxLineSpacing -
                            LyricPreferences.minLineSpacing) *
                        10)
                    .round(),
                value: prefs.lineSpacing,
                onChanged: prefs.setLineSpacing,
              ),
              const SizedBox(height: 8),
              // 实际行高预览
              Text(
                '实际行高倍数：${prefs.lineHeightMultiplier.toStringAsFixed(2)} ×',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
