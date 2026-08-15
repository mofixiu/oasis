import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeController extends ChangeNotifier {
  static const String _themeModeKey = 'landa_theme_mode';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> loadThemeMode() async {
    try {
      final storedMode = await _storage.read(key: _themeModeKey);

      _themeMode = storedMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      _themeMode = ThemeMode.light;
    }

    notifyListeners();
  }

  Future<void> setDarkMode(bool isDarkModeEnabled) async {
    try {
      await _storage.write(
        key: _themeModeKey,
        value: isDarkModeEnabled ? 'dark' : 'light',
      );
    } catch (_) {
      // Keep the in-memory theme choice even if persistence fails.
    }

    _themeMode = isDarkModeEnabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
