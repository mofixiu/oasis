import 'dart:io';
import '../models/consent_model.dart';
import '../models/user_model.dart';

abstract class IAuthService {
  /// Registers a new user.
  ///
  /// [category], [location], [bio] and [yearsOfExperience] describe the trade
  /// an artisan works in and are only sent for [UserRole.artisan]: the
  /// backend rejects them on an owner or tenant registration, and an owner has
  /// no trade to describe.
  Future<UserModel> register({
    required String email,
    required String password,
    required String phone,
    required UserRole role,
    String? category,
    String? location,
    String? bio,
    int? yearsOfExperience,
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

  /// Records acceptance of a consent record. The backend requires this to
  /// succeed at least once before it will accept `verifyIdentity`.
  Future<ConsentModel> acceptConsent({
    required String consentType,
    required String version,
  });

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
