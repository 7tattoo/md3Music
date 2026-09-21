import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

/// 便捷访问生成的应用文案：`context.l10n.carModeTitle`。
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}