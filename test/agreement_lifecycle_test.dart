import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/features/agreements/models/agreement_model.dart';
import 'package:landa_app/features/auth/controllers/auth_controller.dart';
import 'package:landa_app/features/auth/models/consent_model.dart';
import 'package:landa_app/features/auth/models/user_model.dart';
import 'package:landa_app/features/auth/services/i_auth_service.dart';

void main() {
  TenancyAgreementModel agreement(Map<String, dynamic> overrides) {
    return TenancyAgreementModel.fromJson({
      'id': 'agreement-id',
      'unit': 'unit-id',
      'unit_number': 'A1',
      'landlord': 'landlord-id',
      'landlord_email': 'owner@example.com',
      'tenant': 'tenant-id',
      'tenant_email': 'tenant@example.com',
      'rent_amount': '450000.00',
      'start_date': '2026-09-01',
      'end_date': '2027-08-31',
      'rules': 'Keep shared areas clean.',
      'agreement_text': 'Agreement text',
      'status': 'PENDING',
      'tenant_signature_hash': '',
      'landlord_signature_hash': '',
      'pay_rent_unlocked': false,
      'created_at': '2026-08-13T10:00:00Z',
      ...overrides,
    });
  }

  test('PRD tenancy signing order unlocks rent only after execution', () {
    final pending = agreement({});
    final tenantSigned = agreement({
      'tenant_signature_hash': 'tenant-signature',
      'tenant_signed_at': '2026-08-13T10:05:00Z',
    });
    final executed = agreement({
      'status': 'EXECUTED',
      'tenant_signature_hash': 'tenant-signature',
      'landlord_signature_hash': 'landlord-signature',
      'pay_rent_unlocked': true,
    });
    final executedButLocked = agreement({
      'status': 'EXECUTED',
      'tenant_signature_hash': 'tenant-signature',
      'landlord_signature_hash': 'landlord-signature',
      'pay_rent_unlocked': false,
    });

    expect(pending.canTenantSign, isTrue);
    expect(pending.canLandlordSign, isFalse);
    expect(pending.canPayRent, isFalse);

    expect(tenantSigned.canTenantSign, isFalse);
    expect(tenantSigned.canLandlordSign, isTrue);
    expect(tenantSigned.canPayRent, isFalse);

    expect(executed.isExecuted, isTrue);
    expect(executed.canPayRent, isTrue);
    expect(executedButLocked.canPayRent, isFalse);
  });

  test(
    'a legacy tenant-signed status without signature evidence cannot counter-sign',
    () {
      final incompleteTenantSignature = agreement({
        'status': 'TENANT_SIGNED',
        'tenant_signature_hash': '',
        'tenant_signed_at': null,
      });

      expect(incompleteTenantSignature.hasTenantSigned, isFalse);
      expect(incompleteTenantSignature.canLandlordSign, isFalse);
      expect(incompleteTenantSignature.canTenantSign, isTrue);
      expect(
        incompleteTenantSignature.progressTitle,
        'Awaiting Tenant Signature',
      );
    },
  );

  test(
    'verification stays pending until the status poll says verified',
    () async {
      final controller = AuthController(
        authService: _VerificationFakeAuthService(),
      );

      final started = await controller.verifyIdentity(
        selfie: File('unused-selfie.jpg'),
        nin: '12345678901',
      );
      expect(started, VerificationStatus.pending);

      final completed = await controller.checkVerificationStatus();
      expect(completed, VerificationStatus.verified);
    },
  );
}

class _VerificationFakeAuthService implements IAuthService {
  @override
  Future<UserModel> getProfile() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> getVerificationStatus() async {
    return {'verification_status': 'VERIFIED'};
  }

  @override
  Future<UserModel> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

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
  }) => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<ConsentModel> acceptConsent({
    required String consentType,
    required String version,
  }) async {
    return ConsentModel(
      id: 'consent-id',
      consentType: consentType,
      version: version,
      acceptedAt: '2026-08-15T10:30:00Z',
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
    return {'status': 'PENDING'};
  }
}
