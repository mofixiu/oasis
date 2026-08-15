import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/features/agreements/models/agreement_model.dart';
import 'package:landa_app/features/agreements/services/agreement_service.dart';
import 'package:landa_app/features/payments/controllers/payment_controller.dart';
import 'package:landa_app/features/payments/models/payment_model.dart';
import 'package:landa_app/features/payments/services/payment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(
      access: 'test-access-token',
      refresh: 'test-refresh-token',
    );
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() {
    ApiConstants.baseUrl = originalBaseUrl;
  });

  test(
    'agreement creation, tenant signing, landlord execution, and payment follow the PRD contract',
    () async {
      var signCalls = 0;
      final apiClient = ApiClient(
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer test-access-token');

          switch (request.url.path) {
            case '/api/users/agreements/':
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {
                'unit': 'unit-id',
                'tenant': 'tenant@example.com',
                'rent_amount': '450000.00',
                'start_date': '2026-09-01',
                'end_date': '2027-08-31',
                'rules': 'Keep shared areas clean.',
              });
              return _jsonResponse(_agreementPayload(), 201);
            case '/api/users/agreements/agreement-id/sign/':
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), isEmpty);
              signCalls++;
              return _jsonResponse(
                _agreementPayload(
                  tenantSigned: true,
                  executed: signCalls == 2,
                  landlordSigned: signCalls == 2,
                  payRentUnlocked: signCalls == 2,
                ),
              );
            case '/api/users/payments/':
              expect(request.method, 'POST');
              expect(signCalls, 2);
              expect(jsonDecode(request.body), {'agreement': 'agreement-id'});
              return _jsonResponse(_paymentPayload(status: 'PENDING'), 201);
            case '/api/users/payments/payment-id/verify/':
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {
                'reference': 'LR-1A2B3C4D5E6F',
              });
              return _jsonResponse(_paymentPayload(status: 'ESCROW'));
            default:
              fail('Unexpected API request: ${request.method} ${request.url}');
          }
        }),
      );
      final agreementService = AgreementService(apiClient: apiClient);
      final paymentService = PaymentService(apiClient: apiClient);

      final pending = await agreementService.createAgreement(
        unitId: 'unit-id',
        tenantId: 'tenant@example.com',
        rentAmount: '450000.00',
        startDate: '2026-09-01',
        endDate: '2027-08-31',
        rules: 'Keep shared areas clean.',
      );
      expect(pending.status, AgreementStatus.pending);
      expect(pending.canTenantSign, isTrue);
      expect(pending.canLandlordSign, isFalse);
      expect(pending.canPayRent, isFalse);

      final tenantSigned = await agreementService.signAgreement(pending.id);
      expect(tenantSigned.status, AgreementStatus.pending);
      expect(tenantSigned.hasTenantSigned, isTrue);
      expect(tenantSigned.canLandlordSign, isTrue);
      expect(tenantSigned.canPayRent, isFalse);

      final executed = await agreementService.signAgreement(tenantSigned.id);
      expect(executed.status, AgreementStatus.executed);
      expect(executed.hasLandlordSigned, isTrue);
      expect(executed.canPayRent, isTrue);

      final initializedPayment = await paymentService.initializePayment(
        executed.id,
      );
      expect(initializedPayment.agreementStatus, 'EXECUTED');
      expect(initializedPayment.status, PaymentStatus.pending);
      expect(
        initializedPayment.authorizationUrl,
        'https://checkout.paystack.com/example',
      );

      final escrowPayment = await paymentService.verifyPayment(
        initializedPayment,
      );
      expect(escrowPayment.status, PaymentStatus.escrow);
    },
  );

  test(
    'the payment controller never calls the backend before rent is unlocked',
    () async {
      var paymentRequests = 0;
      final paymentService = PaymentService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            paymentRequests++;
            expect(request.url.path, '/api/users/payments/');
            return _jsonResponse(_paymentPayload(), 201);
          }),
        ),
      );
      final controller = PaymentController(paymentService: paymentService);
      final lockedAgreement = TenancyAgreementModel.fromJson(
        _agreementPayload(),
      );

      final lockedPayment = await controller.initializePayment(lockedAgreement);
      expect(lockedPayment, isNull);
      expect(paymentRequests, 0);
      expect(controller.errorMessage, contains('locked'));

      final executedAgreement = TenancyAgreementModel.fromJson(
        _agreementPayload(
          tenantSigned: true,
          landlordSigned: true,
          executed: true,
          payRentUnlocked: true,
        ),
      );
      final createdPayment = await controller.initializePayment(
        executedAgreement,
      );
      expect(createdPayment, isNotNull);
      expect(paymentRequests, 1);
    },
  );

  test('escrow status exposes the backend countdown and dispute window', () async {
    final paymentService = PaymentService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/users/payments/payment-id/escrow/');
          return _jsonResponse(
            _paymentPayload(
              escrowSecondsRemaining: 172800,
              canDispute: true,
            ),
          );
        }),
      ),
    );

    final escrow = await paymentService.getEscrowStatus('payment-id');
    expect(escrow.status, PaymentStatus.escrow);
    expect(escrow.escrowSecondsRemaining, 172800);
    expect(escrow.canDispute, isTrue);
    expect(escrow.disputedAt, isNull);
  });

  test('disputing a payment sends the reason and closes the window', () async {
    final paymentService = PaymentService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/users/payments/payment-id/dispute/');
          expect(jsonDecode(request.body), {
            'reason': 'The unit was not handed over as agreed.',
          });
          return _jsonResponse(
            _paymentPayload(
              status: 'DISPUTED',
              canDispute: false,
              disputedAt: '2026-08-15T11:00:00Z',
              disputeReason: 'The unit was not handed over as agreed.',
            ),
          );
        }),
      ),
    );

    final disputed = await paymentService.disputePayment(
      'payment-id',
      reason: 'The unit was not handed over as agreed.',
    );
    expect(disputed.status, PaymentStatus.disputed);
    expect(disputed.canDispute, isFalse);
    expect(disputed.disputedAt, isNotNull);
    expect(
      disputed.disputeReason,
      'The unit was not handed over as agreed.',
    );
  });

  test('an unrecognised payment status never masquerades as ESCROW', () {
    // Regression guard: the old fromString() fell through to `escrow`, which
    // would have shown a DISPUTED/REFUNDED payment as safely held funds.
    expect(PaymentStatus.fromString('DISPUTED'), PaymentStatus.disputed);
    expect(PaymentStatus.fromString('REFUNDED'), PaymentStatus.refunded);
    expect(PaymentStatus.fromString('SOMETHING_NEW'), PaymentStatus.unknown);
    expect(PaymentStatus.fromString(null), PaymentStatus.unknown);
  });
}

http.Response _jsonResponse(Map<String, dynamic> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _agreementPayload({
  bool tenantSigned = false,
  bool landlordSigned = false,
  bool executed = false,
  bool payRentUnlocked = false,
}) {
  return {
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
    'agreement_text': 'Tenancy agreement text.',
    'status': executed ? 'EXECUTED' : 'PENDING',
    'agreement_content_hash': 'agreement-content-hash',
    'tenant_signature_hash': tenantSigned ? 'tenant-signature' : '',
    'landlord_signature_hash': landlordSigned ? 'landlord-signature' : '',
    'tenant_signed_at': tenantSigned ? '2026-08-13T10:05:00Z' : null,
    'landlord_signed_at': landlordSigned ? '2026-08-13T10:10:00Z' : null,
    'executed_at': executed ? '2026-08-13T10:10:00Z' : null,
    'pay_rent_unlocked': payRentUnlocked,
    'created_at': '2026-08-13T10:00:00Z',
  };
}

Map<String, dynamic> _paymentPayload({
  String status = 'ESCROW',
  int? escrowSecondsRemaining,
  bool canDispute = false,
  String? disputedAt,
  String disputeReason = '',
}) {
  final isHeld = status == 'ESCROW' || status == 'DISPUTED';
  return {
    'id': 'payment-id',
    'agreement': 'agreement-id',
    'agreement_status': 'EXECUTED',
    'tenant': 'tenant-id',
    'tenant_email': 'tenant@example.com',
    'amount': '450000.00',
    'platform_fee': '22500.00',
    'total_amount': '472500.00',
    'reference': 'LR-1A2B3C4D5E6F',
    'provider': 'paystack',
    'provider_reference': 'LR-1A2B3C4D5E6F',
    'authorization_url': 'https://checkout.paystack.com/example',
    'access_code': 'access-code',
    'status': status,
    'paid_at': isHeld ? '2026-08-13T10:15:00Z' : null,
    'escrow_release_at': isHeld ? '2026-08-15T10:15:00Z' : null,
    'escrow_seconds_remaining': escrowSecondsRemaining,
    'can_dispute': canDispute,
    'disputed_at': disputedAt,
    'dispute_reason': disputeReason,
    'is_ready_for_release': false,
    'released_at': null,
  };
}
