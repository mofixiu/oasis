import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/models/user_model.dart';

/// Keeps the session on the device.
///
/// Sign-in tokens, the role and the cached profile (which holds the user's
/// email and phone) live in the platform's secure store: the iOS Keychain and
/// Android's Keystore-backed encrypted preferences. Only the onboarding flag
/// and the one-time migration marker stay in plain [SharedPreferences].
class AuthTokenStorage {
  static const String _keyAccessToken = 'oasis_access_token';
  static const String _keyRefreshToken = 'oasis_refresh_token';
  static const String _keyUserRole = 'oasis_user_role';
  static const String _keyOnboardingDone = 'oasis_onboarding_done';
  static const String _keyUserProfile = 'oasis_user_profile';

  /// Legacy key from the dismissible "identity verified" banner, which no
  /// longer exists. Retained only so `clear()` cleans it off older installs.
  static const String _keyVerifiedBannerDismissed =
      'oasis_verified_banner_dismissed';

  /// Set in plain preferences once this install has moved to secure storage.
  /// It also tells a fresh install apart from an upgrade: plain preferences
  /// are wiped on uninstall but Keychain items are not, so a missing marker
  /// with nothing to migrate means any Keychain session is a leftover from a
  /// previous install and must not sign the new one in.
  static const String _keySecureStorageReady = 'oasis_secure_storage_v1';

  static const List<String> _secureKeys = [
    _keyAccessToken,
    _keyRefreshToken,
    _keyUserRole,
    _keyUserProfile,
  ];

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    // Keystore-backed encrypted preferences. resetOnError clears the store
    // instead of failing forever when its key is gone (for example after a
    // backup is restored onto a new phone); the user just signs in again.
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    // Readable after the first unlock so background refreshes still work,
    // and never copied to iCloud or onto another device.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static bool _migrated = false;
  static Future<bool>? _migrating;

  /// Runs the one-time move out of plain preferences before the first read or
  /// write. Safe to call many times; concurrent callers share one run, and
  /// once it has succeeded it is not run again this launch. Resolves to false
  /// when the move could not finish.
  ///
  /// The finished state is a plain flag rather than a cached future: a future
  /// remembers the zone it was created in, which in widget tests is a fake
  /// clock that stops at the end of each test.
  static Future<bool> _ensureReady() {
    if (_migrated) return Future.value(true);
    return _migrating ??= _migrate().whenComplete(() => _migrating = null);
  }

  static Future<bool> _migrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keySecureStorageReady) ?? false) {
        return _migrated = true;
      }

      final legacy = <String, String>{};
      for (final key in _secureKeys) {
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) legacy[key] = value;
      }

      if (legacy.isEmpty) {
        // Fresh install (or one that was signed out): drop anything a
        // previous install left in the Keychain.
        for (final key in _secureKeys) {
          await _secure.delete(key: key);
        }
      } else {
        for (final entry in legacy.entries) {
          await _secure.write(key: entry.key, value: entry.value);
        }
      }

      // Only remove the plain copies once the secure writes succeeded.
      for (final key in _secureKeys) {
        await prefs.remove(key);
      }
      await prefs.setBool(_keySecureStorageReady, true);
      return _migrated = true;
    } catch (_) {
      // Secure storage unavailable, or the wipe of a leftover session failed.
      // Leave the marker unset so the move is tried again next time.
      return false;
    }
  }

  static Future<void> _write(String key, String value) async {
    await _ensureReady();
    await _secure.write(key: key, value: value);
  }

  static Future<String?> _read(String key) async {
    // Until the move has finished, whatever is in the Keychain may belong to
    // a previous install, so treat the device as signed out.
    if (!await _ensureReady()) return null;
    return _secure.read(key: key);
  }

  // In-memory fallback cache
  static String? _memAccessToken;
  static String? _memRefreshToken;
  static String? _memUserRole;
  static String? _memUserProfileJson;
  static bool _memOnboardingDone = false;

  /// Saves access and refresh tokens
  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    _memAccessToken = access;
    _memRefreshToken = refresh;
    try {
      await _write(_keyAccessToken, access);
      await _write(_keyRefreshToken, refresh);
    } catch (_) {
      _notice('Could not save the session; keeping it in memory.');
    }
  }

  /// Updates only the access token (after refresh)
  static Future<void> saveAccessToken(String access) async {
    _memAccessToken = access;
    try {
      await _write(_keyAccessToken, access);
    } catch (_) {
      _notice('Could not save the refreshed session; keeping it in memory.');
    }
  }

  /// Retrieves the stored access token
  static Future<String?> getAccessToken() async {
    if (_memAccessToken != null) return _memAccessToken;
    try {
      _memAccessToken = await _read(_keyAccessToken);
      return _memAccessToken;
    } catch (_) {
      _notice('Could not read the saved session.');
      return _memAccessToken;
    }
  }

  /// Retrieves the stored refresh token
  static Future<String?> getRefreshToken() async {
    if (_memRefreshToken != null) return _memRefreshToken;
    try {
      _memRefreshToken = await _read(_keyRefreshToken);
      return _memRefreshToken;
    } catch (_) {
      _notice('Could not read the saved session.');
      return _memRefreshToken;
    }
  }

  /// Stores user role ("OWNER" or "TENANT")
  static Future<void> saveUserRole(String role) async {
    _memUserRole = role;
    try {
      await _write(_keyUserRole, role);
    } catch (_) {
      _notice('Could not save the account role.');
    }
  }

  /// Gets stored user role
  static Future<String?> getUserRole() async {
    if (_memUserRole != null) return _memUserRole;
    try {
      _memUserRole = await _read(_keyUserRole);
      return _memUserRole;
    } catch (_) {
      return _memUserRole;
    }
  }

  /// Saves cached user profile model
  static Future<void> saveUserProfile(UserModel user) async {
    final jsonStr = jsonEncode(user.toJson());
    _memUserProfileJson = jsonStr;
    _memUserRole = user.role.toServerString();
    try {
      await _write(_keyUserProfile, jsonStr);
      await _write(_keyUserRole, user.role.toServerString());
    } catch (_) {
      _notice('Could not save the cached profile.');
    }
  }

  /// Gets cached user profile model
  static Future<UserModel?> getCachedUserProfile() async {
    try {
      String? jsonStr = _memUserProfileJson;
      if (jsonStr == null) {
        jsonStr = await _read(_keyUserProfile);
        _memUserProfileJson = jsonStr;
      }
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr);
        return UserModel.fromJson(map);
      }
    } catch (_) {
      _notice('Could not read the cached profile.');
    }
    return null;
  }

  /// Check if onboarding is completed
  static Future<bool> isOnboardingCompleted() async {
    if (_memOnboardingDone) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _memOnboardingDone = prefs.getBool(_keyOnboardingDone) ?? false;
      return _memOnboardingDone;
    } catch (_) {
      return _memOnboardingDone;
    }
  }

  /// Mark onboarding as completed
  static Future<void> setOnboardingCompleted() async {
    _memOnboardingDone = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyOnboardingDone, true);
    } catch (_) {}
  }

  /// Clears stored tokens and auth state
  static Future<void> clear() async {
    _memAccessToken = null;
    _memRefreshToken = null;
    _memUserRole = null;
    _memUserProfileJson = null;
    try {
      await _ensureReady();
      for (final key in _secureKeys) {
        await _secure.delete(key: key);
      }
    } catch (_) {}
    try {
      // Plain copies too, in case the move to secure storage never ran.
      final prefs = await SharedPreferences.getInstance();
      for (final key in _secureKeys) {
        await prefs.remove(key);
      }
      await prefs.remove(_keyVerifiedBannerDismissed);
    } catch (_) {}
  }

  /// Forgets the in-memory session and the migration state, as if the app
  /// had just launched. Tests only.
  @visibleForTesting
  static void resetForTest() {
    _migrated = false;
    _migrating = null;
    _memAccessToken = null;
    _memRefreshToken = null;
    _memUserRole = null;
    _memUserProfileJson = null;
    _memOnboardingDone = false;
  }

  /// Debug-only log line. Never includes token values or the error text,
  /// which can echo what was being written.
  static void _notice(String message) {
    if (kDebugMode) debugPrint('[TOKEN STORAGE NOTICE] $message');
  }
}
