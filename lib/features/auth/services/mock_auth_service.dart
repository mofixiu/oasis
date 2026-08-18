import 'dart:io';
import '../models/consent_model.dart';
import '../models/user_model.dart';
import 'i_auth_service.dart';

/// Mock implementation of the IAuthService.
class MockAuthService implements IAuthService {
  @override
  Future<UserModel> register({
    required String email,
    required String password,
    required String phone,
    required UserRole role,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return UserModel(
      id: 'mock-user-id',
      email: email,
      phone: phone,
      role: role,
      verificationStatus: VerificationStatus.unverified,
    );
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return UserModel(
      id: 'mock-user-id',
      email: email,
      phone: '+2348012345678',
      role: UserRole.owner,
      verificationStatus: VerificationStatus.unverified,
    );
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
  }

  @override
  Future<ConsentModel> acceptConsent({
    required String consentType,
    required String version,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return ConsentModel(
      id: 'mock-consent-id',
      consentType: consentType,
      version: version,
      acceptedAt: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<UserModel> getProfile() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return UserModel(
      id: 'mock-user-id',
      email: 'owner@example.com',
      phone: '+2348012345678',
      role: UserRole.owner,
      verificationStatus: VerificationStatus.verified,
    );
  }

  @override
  Future<Map<String, dynamic>> verifyIdentity({
    required File selfie,
    required String nin,
    String? givenNames,
    String? lastName,
    String? email,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return {'status': 'PENDING', 'badge': 'PENDING'};
  }

  @override
  Future<Map<String, dynamic>> getVerificationStatus() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return {'verification_status': 'VERIFIED'};
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
