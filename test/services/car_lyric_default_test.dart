import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('车载歌词开关默认值', () {
    test('未设置过时默认开启（这些包名就是为 vivo 车机场景打的）', () async {
      final repo = SettingsRepository();
      expect(await repo.getCarLyricEnabled(), isTrue);
    });

    test('用户显式关闭后保持关闭', () async {
      SharedPreferences.setMockInitialValues({
        'settings_car_lyric_enabled': false,
      });
      final repo = SettingsRepository();
      expect(await repo.getCarLyricEnabled(), isFalse);
    });

    test('写入后可读回', () async {
      final repo = SettingsRepository();
      await repo.setCarLyricEnabled(false);
      expect(await repo.getCarLyricEnabled(), isFalse);
      await repo.setCarLyricEnabled(true);
      expect(await repo.getCarLyricEnabled(), isTrue);
    });
  });
}
