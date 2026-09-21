import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/repositories/settings_repository.dart';

/// 应用界面语言选择：跟随系统 / 中文 / English。
///
/// 独立于 chinese_song_screen 等业务开关，只决定 MaterialApp 的 [locale]。
/// 跟随系统时为 null，由 Flutter 按系统区域 + [MaterialApp.supportedLocales]
/// 解析（本项目仅支持 zh / en，其他区域回落到模板语言 zh）。
enum AppLanguage {
  system,
  zh,
  en;
}

class L10nProvider extends ChangeNotifier {
  L10nProvider() {
    load();
  }

  AppLanguage _language = AppLanguage.system;

  /// 当前选择的语言。
  AppLanguage get language => _language;

  /// 喂给 [MaterialApp.locale]。跟随系统返回 null。
  Locale? get locale => switch (_language) {
        AppLanguage.system => null,
        AppLanguage.zh => const Locale('zh'),
        AppLanguage.en => const Locale('en'),
      };

  /// 设置页用：当前是否「跟随系统」。
  bool get followSystem => _language == AppLanguage.system;

  Future<void> load() async {
    try {
      final raw = await SettingsRepository().getLanguage();
      _language = _parse(raw);
      notifyListeners();
    } catch (_) {
      // 读取失败保持跟随系统，不影响启动。
    }
  }

  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
    try {
      await SettingsRepository().setLanguage(_name(lang));
    } catch (_) {}
  }

  static AppLanguage _parse(String raw) => switch (raw) {
        'zh' => AppLanguage.zh,
        'en' => AppLanguage.en,
        _ => AppLanguage.system,
      };

  static String _name(AppLanguage lang) => switch (lang) {
        AppLanguage.system => 'system',
        AppLanguage.zh => 'zh',
        AppLanguage.en => 'en',
      };
}