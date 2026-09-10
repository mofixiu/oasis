import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';

/// Where an agreement is rendered is now decided by [AgreementBucket] rather
/// than by `status ==` checks inside each screen. That makes this mapping a
/// contract between the dashboard and the profile: get it wrong and either an
/// agreement needing a signature disappears, or a signed one clutters the
/// dashboard it was deliberately moved off.
void main() {
  TenancyAgreementModel build({
    required String status,
    String? bucket,
    String tenantSignature = '',
    String landlordSignature = '',
  }) => TenancyAgreementModel.fromJson({
    'id': 'agreement-1',
    'unit': 'unit-1',
    'unit_number': 'A1',
    'status': status,
    if (bucket != null) 'bucket': bucket,
    'tenant_signature_hash': tenantSignature,
    'landlord_signature_hash': landlordSignature,
    'rent_amount': '450000.00',
    'pay_rent_unlocked': status == 'EXECUTED',
  });

  group('agreements still needing a signature stay on the dashboard', () {
    for (final status in ['DRAFT', 'PENDING', 'SENT', 'TENANT_SIGNED']) {
      test(status, () {
        final agreement = build(status: status);
        expect(agreement.bucket, AgreementBucket.actionRequired);
        expect(agreement.needsSignature, isTrue);
        expect(agreement.isCompleted, isFalse);
      });
    }

    test('PENDING with the tenant already signed is still a task', () {
      // The landlord has yet to counter-sign, so this belongs on the
      // dashboard even though half the signatures are in.
      final agreement = build(status: 'PENDING', tenantSignature: 'abc123');
      expect(agreement.bucket, AgreementBucket.actionRequired);
      expect(agreement.awaitingLandlordSignature, isTrue);
    });
  });

  group('settled agreements move to the profile', () {
    for (final status in ['EXECUTED', 'EXPIRED', 'VOIDED', 'ACTIVATED']) {
      test(status, () {
        final agreement = build(status: status);
        expect(agreement.bucket, AgreementBucket.completed);
        expect(agreement.isCompleted, isTrue);
        expect(agreement.needsSignature, isFalse);
      });
    }
  });

  test('both signatures present reads as fully signed', () {
    final agreement = build(
      status: 'EXECUTED',
      tenantSignature: 'abc123',
      landlordSignature: 'def456',
    );
    expect(agreement.isFullySigned, isTrue);
  });

  test("the backend's own bucket wins once it starts sending one", () {
    // Forward compatibility: if the API ever classifies a status differently
    // from the local fallback, the server is the authority.
    final agreement = build(status: 'PENDING', bucket: 'COMPLETED');
    expect(agreement.bucket, AgreementBucket.completed);
  });

  test('an unrecognised bucket never hides an unsigned agreement', () {
    // Failing towards "still needs signing" keeps the agreement visible and
    // actionable. Failing the other way would strand both parties.
    final agreement = build(status: 'PENDING', bucket: 'SOMETHING_NEW');
    expect(agreement.bucket, AgreementBucket.actionRequired);
  });
}
