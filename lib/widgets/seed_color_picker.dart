import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 预设种子色选择面板。
///
/// 8 色圆形网格（4 列 × 2 行），当前选中项带勾选标记。
/// 取自 [AppTheme.presetSeedColors]（M3 官方 Theme Builder 的 key tone 40）。
class SeedColorPicker extends StatelessWidget {
  /// 当前选中的颜色（用于高亮显示）。
  final Color currentColor;

  /// 选中颜色后的回调。
  final ValueChanged<Color> onSelected;

  const SeedColorPicker({
    super.key,
    required this.currentColor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择主题色',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: AppTheme.presetSeedColors.length,
            itemBuilder: (ctx, i) {
              final color = AppTheme.presetSeedColors[i];
              final isSelected = color.value == currentColor.value;
              return GestureDetector(
                onTap: () => onSelected(color),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.onSurface
                          : colorScheme.outlineVariant,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            '8 色取自 Material 3 官方 Theme Builder 的 key tone 40',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
