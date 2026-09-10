import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeController extends ChangeNotifier {
  static const String _themeModeKey = 'oasis_theme_mode';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Starts on [ThemeMode.system] until the user picks a side.
  ///
  /// This is what makes a cold start in dark mode look right: the OS-drawn
  /// launch screen can only follow the system appearance, so an app that
  /// defaulted to light on a dark phone flashed white before its own dark
  /// splash appeared. Following the system by default keeps the launch
  /// screen, the Flutter splash and the app itself in one state.
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// True only for an explicit dark choice. Screens that need "is the UI dark
  /// right now" should ask [AppTheme.isDarkMode], which resolves
  /// [ThemeMode.system] against the platform brightness.
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> loadThemeMode() async {
    try {
      final storedMode = await _storage.read(key: _themeModeKey);

      _themeMode = switch (storedMode) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        // Nothing stored: the user has never chosen, so follow the phone.
        _ => ThemeMode.system,
      };
    } catch (_) {
      _themeMode = ThemeMode.system;
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
