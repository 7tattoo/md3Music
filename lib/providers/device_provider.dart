import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备类型选择模式。
///
/// - [auto]：根据屏幕最短边自动检测（>= 600dp → Pad）
/// - [phone]：强制手机模式
/// - [pad]：强制 Pad 模式
enum DeviceType { auto, phone, pad }

class DeviceProvider extends ChangeNotifier {
  static const String _key = 'device_type';

  DeviceType _deviceType = DeviceType.auto;

  DeviceType get deviceType => _deviceType;

  /// 实际生效的是否为 Pad 设备。
  ///
  /// [auto] 模式下根据屏幕最短边自动判断，
  /// [phone]/[pad] 模式下直接返回对应值。
  bool get isPad {
    switch (_deviceType) {
      case DeviceType.auto:
        return _autoDetect();
      case DeviceType.phone:
        return false;
      case DeviceType.pad:
        return true;
    }
  }

  /// 自动检测：物理屏幕最短边 >= 600dp → Pad。
  bool _autoDetect() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= 600;
  }

  DeviceProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key) ?? 0;
    _deviceType = DeviceType.values[index.clamp(0, DeviceType.values.length - 1)];
    notifyListeners();
  }

  Future<void> setDeviceType(DeviceType type) async {
    if (_deviceType == type) return;
    _deviceType = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, type.index);
  }
}
