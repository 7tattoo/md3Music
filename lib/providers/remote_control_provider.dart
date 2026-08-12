import 'package:flutter/material.dart';

import '../data/repositories/settings_repository.dart';

/// 遥控器模式开关的全局状态源。
///
/// 仿照 [GridColumnsProvider] 的写法：构造时从 [SettingsRepository] 异步读取
/// 持久化偏好，开关变化时通知监听器并落盘。
///
/// 遥控模式开启时同时应用全局焦点高亮策略：
/// - 开启 → [FocusHighlightStrategy.alwaysTraditional]：所有 Material 可聚焦控件
///   （IconButton/ListTile/TextButton/Slider/SwitchListTile 等）自动显示焦点
///   高亮并可用方向键/D-pad 遍历。
/// - 关闭 → [FocusHighlightStrategy.automatic]：恢复平台默认，触屏行为不变。
class RemoteControlProvider extends ChangeNotifier {
  bool _enabled = false;

  /// 是否启用遥控器模式。
  bool get enabled => _enabled;

  RemoteControlProvider() {
    loadFromSettings();
  }

  /// 从 [SettingsRepository] 读取遥控器模式开关并初始化。
  Future<void> loadFromSettings() async {
    final enabled = await SettingsRepository().getRemoteControlEnabled();
    if (_enabled == enabled) return;
    _enabled = enabled;
    _applyFocusStrategy();
    notifyListeners();
  }

  /// 设置遥控器模式开关。仅当值实际变化时应用焦点策略并通知监听器。
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _applyFocusStrategy();
    notifyListeners();
    SettingsRepository().setRemoteControlEnabled(value);
  }

  /// 应用全局焦点高亮策略。仅在 runApp 后、FocusManager 已初始化时调用
  /// （本 provider 挂载于 MultiProvider，构建时 FocusManager 必然可用）。
  void _applyFocusStrategy() {
    FocusManager.instance.highlightStrategy = _enabled
        ? FocusHighlightStrategy.alwaysTraditional
        : FocusHighlightStrategy.automatic;
  }
}
