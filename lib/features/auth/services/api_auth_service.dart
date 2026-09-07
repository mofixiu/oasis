import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/auth_token_storage.dart';
import '../models/consent_model.dart';
import '../models/user_model.dart';
import 'i_auth_service.dart';

class ApiAuthService implements IAuthService {
  final ApiClient _apiClient;

  ApiAuthService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  @override
  Future<UserModel> register({
    required String email,
    required String password,
    required String phone,
    required UserRole role,
    String? category,
    String? location,
    String? bio,
    int? yearsOfExperience,
  }) async {
    debugPrint(
      '[AUTH SERVICE] Registering user: $email | Role: ${role.toServerString()} | Phone: $phone',
    );

    // The trade fields belong to an artisan account and nothing else. Gated
    // on the role rather than on the arguments being non-null so a stray
    // value from a half-filled form can never be posted against an owner.
    final isArtisan = role == UserRole.artisan;
    if (isArtisan) {
      debugPrint(
        '[AUTH SERVICE] Artisan trade: $category | $location | '
        '${yearsOfExperience ?? 0} year(s)',
      );
    }

    try {
      await _apiClient.post(
        ApiConstants.registerEndpoint,
        body: {
          'email': email,
          'password': password,
          'phone': phone,
          'role': role.toServerString(),
          if (isArtisan && category != null && category.isNotEmpty)
            'category': category,
          if (isArtisan && location != null && location.trim().isNotEmpty)
            'location': location.trim(),
          if (isArtisan && bio != null && bio.trim().isNotEmpty)
            'bio': bio.trim(),
          if (isArtisan && yearsOfExperience != null)
            'years_of_experience': yearsOfExperience,
        },
        requiresAuth: false,
      );
      debugPrint(
        '[AUTH SERVICE] Registration successful. Logging in automatically for JWT tokens...',
      );
    } on ApiException catch (e) {
      if (e.message.contains('already exists')) {
        debugPrint(
          'ℹ [AUTH SERVICE] Account already exists. Attempting automatic login with provided credentials...',
        );
        try {
          return await login(email: email, password: password);
        } catch (_) {
          // If login fails (e.g. wrong password), rethrow original registration error
          rethrow;
        }
      }
      rethrow;
    }

    return await login(email: email, password: password);
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    debugPrint('[AUTH SERVICE] Logging in user: $email');

    final response = await _apiClient.post(
      ApiConstants.loginEndpoint,
      body: {'email': email, 'password': password},
      requiresAuth: false,
    );

    if (response is Map<String, dynamic> &&
        response.containsKey('access') &&
        response.containsKey('refresh')) {
      debugPrint(
        '[AUTH SERVICE] Storing JWT tokens locally (Access & Refresh)',
      );
      await AuthTokenStorage.saveTokens(
        access: response['access'],
        refresh: response['refresh'],
      );
    }

    UserModel profile;
    if (response is Map<String, dynamic> &&
        response.containsKey('user') &&
        response['user'] != null) {
      profile = UserModel.fromJson(response['user']);
      debugPrint(
        '[AUTH SERVICE] Profile received directly in /login/ payload: ID=${profile.id}, Role=${profile.role.toServerString()}, Verification=${profile.verificationStatus.label}',
      );
    } else {
      profile = await getProfile();
    }

    await AuthTokenStorage.saveUserProfile(profile);
    debugPrint(
      '[AUTH SERVICE] User logged in as: ${profile.email} (${profile.role.toServerString()})',
    );
    return profile;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    debugPrint('[AUTH SERVICE] Requesting password reset for: $email');
    await _apiClient.post(
      ApiConstants.passwordResetRequestEndpoint,
      body: {'email': email},
      requiresAuth: false,
    );
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    debugPrint('[AUTH SERVICE] Confirming password reset with token.');
    await _apiClient.post(
      ApiConstants.passwordResetConfirmEndpoint,
      body: {'token': token, 'new_password': newPassword},
      requiresAuth: false,
    );
  }

  @override
  Future<ConsentModel> acceptConsent({
    required String consentType,
    required String version,
  }) async {
    debugPrint('[AUTH SERVICE] Accepting consent: $consentType v$version');
    final response = await _apiClient.post(
      ApiConstants.consentsEndpoint,
      body: {'consent_type': consentType, 'version': version},
      requiresAuth: true,
    );
    final consent = ConsentModel.fromJson(response);
    debugPrint(
      '[AUTH SERVICE] Consent recorded: ID=${consent.id}, Accepted=${consent.acceptedAt}',
    );
    return consent;
  }

  @override
  Future<UserModel> getProfile() async {
    debugPrint(
      '[AUTH SERVICE] Fetching user profile from GET ${ApiConstants.profileEndpoint}...',
    );
    try {
      final response = await _apiClient.get(
        ApiConstants.profileEndpoint,
        requiresAuth: true,
      );

      final user = UserModel.fromJson(response);
      await AuthTokenStorage.saveUserProfile(user);
      debugPrint(
        '[AUTH SERVICE] Profile retrieved: ID=${user.id}, Role=${user.role.toServerString()}, Verification=${user.verificationStatus.label}',
      );
      return user;
    } catch (e) {
      debugPrint(
        '[AUTH SERVICE] Failed to fetch live profile ($e). Checking cached local profile...',
      );
      final cachedUser = await AuthTokenStorage.getCachedUserProfile();
      if (cachedUser != null) {
        debugPrint(
          '[AUTH SERVICE] Using cached user profile: ${cachedUser.email} (${cachedUser.role.toServerString()})',
        );
        return cachedUser;
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> verifyIdentity({
    required File selfie,
    required String nin,
    String? givenNames,
    String? lastName,
    String? email,
  }) async {
    debugPrint(
      '[AUTH SERVICE] Starting identity verification with selfie and NIN.',
    );
    final fields = <String, String>{'nin': nin};
    if (givenNames != null && givenNames.trim().isNotEmpty) {
      fields['given_names'] = givenNames.trim();
    }
    if (lastName != null && lastName.trim().isNotEmpty) {
      fields['last_name'] = lastName.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      fields['email'] = email.trim();
    }
    final response = await _apiClient.postMultipart(
      ApiConstants.verifyEndpoint,
      fields: fields,
      fileField: 'selfie',
      file: selfie,
      requiresAuth: true,
    );

    if (response is Map<String, dynamic>) {
      debugPrint(
        '[AUTH SERVICE] Verification request accepted with status: ${response['status'] ?? response['verification_status']}',
      );
      return response;
    }

    throw ApiException('Unexpected verification response from the server.');
  }

  @override
  Future<Map<String, dynamic>> getVerificationStatus() async {
    debugPrint(
      '[AUTH SERVICE] Checking verification status GET ${ApiConstants.verificationStatusEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.verificationStatusEndpoint,
      requiresAuth: true,
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    throw ApiException(
      'Unexpected verification-status response from the server.',
    );
  }

  @override
  Future<void> logout() async {
    debugPrint('[AUTH SERVICE] User logging out. Clearing token storage...');
    await AuthTokenStorage.clear();
  }
}
