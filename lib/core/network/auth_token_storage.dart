import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/models/user_model.dart';

class AuthTokenStorage {
  static const String _keyAccessToken = 'landa_access_token';
  static const String _keyRefreshToken = 'landa_refresh_token';
  static const String _keyUserRole = 'landa_user_role';
  static const String _keyOnboardingDone = 'landa_onboarding_done';
  static const String _keyUserProfile = 'landa_user_profile';
  /// Legacy key from the dismissible "identity verified" banner, which no
  /// longer exists. Retained only so `clear()` cleans it off older installs.
  static const String _keyVerifiedBannerDismissed =
      'landa_verified_banner_dismissed';

  // In-memory fallback cache
  static String? _memAccessToken;
  static String? _memRefreshToken;
  static String? _memUserRole;
  static String? _memUserProfileJson;
  static bool _memOnboardingDone = false;

  /// Saves access and refresh tokens
  static Future<void> saveTokens({required String access, required String refresh}) async {
    _memAccessToken = access;
    _memRefreshToken = refresh;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccessToken, access);
      await prefs.setString(_keyRefreshToken, refresh);
    } catch (e) {
      debugPrint('⚠️ [TOKEN STORAGE NOTICE] Could not write to SharedPreferences ($e), using in-memory cache.');
    }
  }

  /// Updates only the access token (after refresh)
  static Future<void> saveAccessToken(String access) async {
    _memAccessToken = access;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccessToken, access);
    } catch (e) {
      debugPrint('⚠️ [TOKEN STORAGE NOTICE] Could not write access token ($e), using in-memory cache.');
    }
  }

  /// Retrieves the stored access token
  static Future<String?> getAccessToken() async {
    if (_memAccessToken != null) return _memAccessToken;
    try {
      final prefs = await SharedPreferences.getInstance();
      _memAccessToken = prefs.getString(_keyAccessToken);
      return _memAccessToken;
    } catch (e) {
      debugPrint('⚠️ [TOKEN STORAGE NOTICE] Could not read SharedPreferences ($e).');
      return _memAccessToken;
    }
  }

  /// Retrieves the stored refresh token
  static Future<String?> getRefreshToken() async {
    if (_memRefreshToken != null) return _memRefreshToken;
    try {
      final prefs = await SharedPreferences.getInstance();
      _memRefreshToken = prefs.getString(_keyRefreshToken);
      return _memRefreshToken;
    } catch (e) {
      debugPrint('⚠️ [TOKEN STORAGE NOTICE] Could not read SharedPreferences ($e).');
      return _memRefreshToken;
    }
  }

  /// Stores user role ("OWNER" or "TENANT")
  static Future<void> saveUserRole(String role) async {
    _memUserRole = role;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserRole, role);
    } catch (e) {
      debugPrint('⚠️ [TOKEN STORAGE NOTICE] Could not write user role ($e).');
    }
  }

  /// Gets stored user role
  static Future<String?> getUserRole() async {
    if (_memUserRole != null) return _memUserRole;
    try {
      final prefs = await SharedPreferences.getInstance();
      _memUserRole = prefs.getString(_keyUserRole);
      return _memUserRole;
    } catch (e) {
      return _memUserRole;
    }
  }

  /// Saves cached user profile model
  static Future<void> saveUserProfile(UserModel user) async {
    final jsonStr = jsonEncode(user.toJson());
    _memUserProfileJson = jsonStr;
    _memUserRole = user.role.toServerString();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserProfile, jsonStr);
      await prefs.setString(_keyUserRole, user.role.toServerString());
    } catch (e) {
      debugPrint('⚠️ [TOKEN STORAGE NOTICE] Could not write user profile ($e).');
    }
  }

  /// Gets cached user profile model
  static Future<UserModel?> getCachedUserProfile() async {
    try {
      String? jsonStr = _memUserProfileJson;
      if (jsonStr == null) {
        final prefs = await SharedPreferences.getInstance();
        jsonStr = prefs.getString(_keyUserProfile);
        _memUserProfileJson = jsonStr;
      }
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr);
        return UserModel.fromJson(map);
      }
    } catch (e) {
      debugPrint('⚠️ [TOKEN STORAGE NOTICE] Could not read cached user profile ($e).');
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAccessToken);
      await prefs.remove(_keyRefreshToken);
      await prefs.remove(_keyUserRole);
      await prefs.remove(_keyUserProfile);
      await prefs.remove(_keyVerifiedBannerDismissed);
    } catch (_) {}
  }
}
