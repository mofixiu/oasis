import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';

/// Registers this phone to receive push notifications, and unregisters it.
///
/// The backend half of this is live (API guide 19 §2): the endpoints work,
/// they are idempotent on the token, and a token posted for a different user
/// *moves* to that user. What is not live yet is delivery — the backend is
/// waiting on a Firebase service-account credential, and until it has one the
/// sends silently no-op.
///
/// The app's own missing half is the token. It needs `firebase_messaging`,
/// which needs a `google-services.json`, which needs a Firebase project that
/// does not exist yet. **Adding the dependency without that file breaks the
/// Android build**, so it is deliberately not added; this service is the
/// piece that does not depend on it, written now so that when the project
/// lands the remaining work is one dependency and two calls.
///
/// ## Why the sign-out call matters more than the sign-in one
///
/// Registering late costs somebody a notification. *Failing to unregister*
/// keeps sending "rent is due for Unit A1" to a phone whose owner signed out
/// weeks ago — on a shared or resold handset, that is somebody else's tenancy
/// details arriving on a stranger's lock screen. [unregister] is the half to
/// get right.
class DeviceService {
  final ApiClient _apiClient;

  DeviceService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// This device's platform, in the two values the backend accepts.
  ///
  /// Anything that is not iOS is reported as Android: the only two builds
  /// that ship are those, and a desktop debug session has no push token to
  /// register in the first place.
  static String get platform => Platform.isIOS ? 'IOS' : 'ANDROID';

  /// Registers (or refreshes) this device's push token.
  ///
  /// Safe to call on every launch, which is what the app should do: FCM
  /// reissues a token on reinstall, on a data clear, and periodically on its
  /// own, and the endpoint updates rather than duplicating.
  ///
  /// Returns the device id, or null when the call failed. Failure is
  /// deliberately quiet at the call site: push is an enhancement, and a
  /// sign-in that reports an error because a notification token did not
  /// register is a worse experience than one that quietly has no push.
  Future<String?> register({
    required String token,
    String? appVersion,
  }) async {
    if (token.trim().isEmpty) return null;
    debugPrint(
      '[DEVICE SERVICE] Registering push token POST '
      '${ApiConstants.devicesEndpoint} ($platform)',
    );
    final response = await _apiClient.post(
      ApiConstants.devicesEndpoint,
      body: {
        'token': token.trim(),
        'platform': platform,
        if (appVersion != null && appVersion.isNotEmpty)
          'app_version': appVersion,
      },
    );
    if (response is Map<String, dynamic>) {
      return response['id']?.toString();
    }
    return null;
  }

  /// Removes this device so it stops receiving pushes for the signed-out
  /// account.
  ///
  /// Addressed by token rather than by id, because the token is the thing the
  /// app is certain to still be holding at sign-out; the id came back from a
  /// registration that may have happened on a previous launch.
  Future<void> unregister(String token) async {
    if (token.trim().isEmpty) return;
    debugPrint(
      '[DEVICE SERVICE] Removing push token DELETE '
      '${ApiConstants.devicesEndpoint}',
    );
    await _apiClient.delete(
      ApiConstants.devicesEndpoint,
      queryParameters: {'token': token.trim()},
    );
  }

  /// The devices currently registered to this account.
  ///
  /// Not used by any screen yet. It is what a "signed in on these devices"
  /// settings row would read, and it is the cheapest way to check from a
  /// debug session whether registration actually landed.
  Future<List<RegisteredDevice>> list() async {
    final response = await _apiClient.get(ApiConstants.devicesEndpoint);
    final rows = response is Map<String, dynamic>
        ? response['results']
        : response;
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(RegisteredDevice.fromJson)
        .toList();
  }
}

/// One phone registered against the signed-in account.
class RegisteredDevice {
  final String id;
  final String platform;
  final String? appVersion;
  final String? createdAt;

  const RegisteredDevice({
    required this.id,
    required this.platform,
    this.appVersion,
    this.createdAt,
  });

  factory RegisteredDevice.fromJson(Map<String, dynamic> json) =>
      RegisteredDevice(
        id: json['id']?.toString() ?? '',
        platform: json['platform']?.toString() ?? '',
        appVersion: json['app_version']?.toString(),
        createdAt: json['created_at']?.toString(),
      );
}
