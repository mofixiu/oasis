import 'dart:io';
import '../models/user_model.dart';

abstract class IAuthService {
  /// Registers a new user (OWNER or TENANT)
  Future<UserModel> register({
    required String email,
    required String password,
    required String phone,
    required UserRole role,
  });

  /// Logs in a user and stores JWT tokens
  Future<UserModel> login({required String email, required String password});

  /// Sends a reset link or one-time code to a registered email address.
  Future<void> requestPasswordReset({required String email});

  /// Completes a password reset using the single-use token from the reset
  /// email/link and sets [newPassword] as the account password.
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  });

  /// Fetches current authenticated user profile
  Future<UserModel> getProfile();

  /// Uploads selfie image and NIN for identity verification.
  ///
  /// [givenNames]/[lastName]/[email] are optional and only required for
  /// Smile ID sandbox test identities once the backend is switched to
  /// `VERIFICATION_PROVIDER=smile_id`; the mock provider ignores them.
  Future<Map<String, dynamic>> verifyIdentity({
    required File selfie,
    required String nin,
    String? givenNames,
    String? lastName,
    String? email,
  });

  /// Retrieves the current asynchronous identity-verification outcome.
  Future<Map<String, dynamic>> getVerificationStatus();

  /// Logs out user and clears local token storage
  Future<void> logout();
}
