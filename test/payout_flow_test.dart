import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/features/agreements/controllers/agreement_controller.dart';
import 'package:landa_app/features/agreements/services/agreement_service.dart';
import 'package:landa_app/features/auth/models/user_model.dart';
import 'package:landa_app/features/payouts/controllers/payout_controller.dart';
import 'package:landa_app/features/payouts/models/payout_models.dart';
import 'package:landa_app/features/payouts/services/payout_service.dart';
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

  tearDown(() => ApiConstants.baseUrl = originalBaseUrl);

  test('bank list is parsed for the picker', () async {
    final service = PayoutService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/users/banks/');
          return _json([
            {'name': 'Access Bank'},
            {'name': 'STANBIC IBTC BANK'},
            // Defensive: a nameless row must not become a blank picker entry.
            {'name': ''},
          ]);
        }),
      ),
    );

    final banks = await service.getBanks();
    expect(banks.map((b) => b.name), ['Access Bank', 'STANBIC IBTC BANK']);
  });

  test('a missing payout account parses as a MISSING envelope', () async {
    final service = PayoutService(
      apiClient: ApiClient(
        client: MockClient(
          (request) async => _jsonObject({
            'status': 'MISSING',
            'payout_account_required': false,
            'payout_account_required_for': 'AGREEMENT_EXECUTION',
            'detail':
                'Add and verify payout account details before executing an agreement.',
          }),
        ),
      ),
    );

    final account = await service.getPayoutAccount();
    expect(account.status, PayoutAccountStatus.missing);
    expect(account.isVerified, isFalse);
    expect(
      account.hasDetails,
      isFalse,
      reason: 'the envelope carries no bank/account to prefill from',
    );
    expect(account.requiredFor, 'AGREEMENT_EXECUTION');
  });

  test('saving sends the resolution token and nothing else', () async {
    // The backend rejects any request carrying a client-supplied
    // account_name. The confirmed token is the entire payload.
    Map<String, dynamic>? captured;
    var method = '';
    final controller = PayoutController(
      service: PayoutService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            method = request.method;
            if (request.url.path.endsWith('/payout-account/resolve/')) {
              return _jsonObject({
                'bank_name': 'Stanbic IBTC Bank',
                'bank_code': '221',
                'account_number_masked': '******6034',
                'account_name': 'AKINTAN AYOMIDE AKINDAMOLA',
                'resolution_token': 'rsl_TOKEN',
              });
            }
            captured = jsonDecode(request.body) as Map<String, dynamic>;
            return _jsonObject({
              'id': 'PAYOUT_UUID',
              'bank_name': 'STANBIC IBTC BANK',
              'account_number': '******6034',
              'account_name': 'AKINTAN AYOMIDE AKINDAMOLA',
              'status': 'VERIFIED',
              'provider': 'paystack',
              'verified_at': '2026-08-21T14:00:00Z',
            }, 201);
          }),
        ),
      ),
    );

    await controller.resolveAccount(
      bankName: 'STANBIC IBTC BANK',
      accountNumber: '0023966034',
    );
    final verified = await controller.submitPayoutAccount();

    expect(verified, isTrue);
    expect(
      method,
      'POST',
      reason: 'no saved account yet, so this creates rather than updates',
    );
    expect(captured, {
      'resolution_token': 'rsl_TOKEN',
    }, reason: 'sending account_name is rejected by the backend');
    expect(controller.isVerified, isTrue);
    expect(controller.account?.accountNumber, '******6034');
  });

  test('resolving sends the bank code when the picker supplied one', () async {
    // Resolving by display name is what used to fail on near-duplicate banks
    // ("Access Bank" vs "Access Bank (Diamond)"). The code removes the guess.
    Map<String, dynamic>? captured;
    final controller = PayoutController(
      service: PayoutService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/banks/')) {
              return _json([
                {'name': 'Access Bank', 'code': '044', 'slug': 'access-bank'},
              ]);
            }
            captured = jsonDecode(request.body) as Map<String, dynamic>;
            return _jsonObject({
              'account_name': 'ADA OKAFOR',
              'resolution_token': 'rsl_TOKEN',
            });
          }),
        ),
      ),
    );

    await controller.loadBanks();
    await controller.resolveAccount(
      bankName: 'Access Bank',
      accountNumber: '0000001111',
    );

    expect(captured?['bank_code'], '044');
    expect(
      captured?.containsKey('bank_name'),
      isFalse,
      reason: 'the code is unambiguous, so the name is not sent alongside it',
    );
  });

  test(
    'saving without a confirmed account never reaches the network',
    () async {
      var calls = 0;
      final controller = PayoutController(
        service: PayoutService(
          apiClient: ApiClient(
            client: MockClient((_) async {
              calls++;
              return _jsonObject({}, 201);
            }),
          ),
        ),
      );

      expect(await controller.submitPayoutAccount(), isFalse);
      expect(
        calls,
        0,
        reason: 'there is no token, so there is no valid request',
      );
      expect(controller.errorMessage, contains('Confirm'));
    },
  );

  test('an existing account is replaced with PATCH, not POST', () async {
    var method = '';
    final controller = PayoutController(
      service: PayoutService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            method = request.method;
            if (request.method == 'GET') {
              return _jsonObject({
                'id': 'PAYOUT_UUID',
                'bank_name': 'Access Bank',
                'account_number': '******1111',
                'account_name': 'ADA OKAFOR',
                'status': 'VERIFIED',
              });
            }
            if (request.url.path.endsWith('/payout-account/resolve/')) {
              return _jsonObject({
                'bank_name': 'Zenith Bank',
                'bank_code': '057',
                'account_number_masked': '******2222',
                'account_name': 'ADA OKAFOR',
                'resolution_token': 'rsl_NEW',
              });
            }
            return _jsonObject({
              'id': 'PAYOUT_UUID',
              'bank_name': 'Zenith Bank',
              'account_number': '******2222',
              'account_name': 'ADA OKAFOR',
              'status': 'VERIFIED',
            });
          }),
        ),
      ),
    );

    await controller.loadPayoutAccount();
    await controller.resolveAccount(
      bankName: 'Zenith Bank',
      accountNumber: '0000002222',
    );
    await controller.submitPayoutAccount();
    expect(method, 'PATCH');
    expect(controller.account?.bankName, 'Zenith Bank');
  });

  test('a rejected save does not report the account as verified', () async {
    final controller = PayoutController(
      service: PayoutService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/payout-account/resolve/')) {
              return _jsonObject({
                'account_name': 'ADA OKAFOR',
                'resolution_token': 'rsl_STALE',
              });
            }
            return _jsonObject({
              'code': 'RESOLUTION_TOKEN_EXPIRED',
              'detail': 'Resolve the bank account again before saving it.',
            }, 409);
          }),
        ),
      ),
    );

    await controller.resolveAccount(
      bankName: 'Zenith Bank',
      accountNumber: '0000002222',
    );
    expect(await controller.submitPayoutAccount(), isFalse);
    expect(controller.errorMessage, contains('Resolve the bank account'));
    expect(controller.isVerified, isFalse);
  });

  test(
    'a payout-blocked sign surfaces as a retryable prompt, not a dead error',
    () async {
      var signCalls = 0;
      final controller = AgreementController(
        agreementService: AgreementService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              signCalls++;
              if (signCalls == 1) {
                // The landlord reached final signing without payout details.
                return _jsonObject({
                  'code': 'PAYOUT_ACCOUNT_REQUIRED',
                  'detail':
                      'Add and verify payout account details before executing this agreement.',
                }, 403);
              }
              return _jsonObject(_executedAgreement());
            }),
          ),
        ),
      );

      final blocked = await controller.signAgreement('agreement-id');
      expect(blocked, isFalse);
      expect(
        controller.errorNeedsPayoutAccount,
        isTrue,
        reason: 'the screen keys its payout prompt off this flag',
      );
      expect(
        controller.errorIsConnection,
        isFalse,
        reason: 'a 403 is the server saying no, not an unreachable server',
      );

      // After payout verification the same call is retried and succeeds.
      final retried = await controller.signAgreement('agreement-id');
      expect(retried, isTrue);
      expect(signCalls, 2);
      expect(
        controller.errorNeedsPayoutAccount,
        isFalse,
        reason: 'the flag must clear once the retry succeeds',
      );
    },
  );

  test('profile payout capability flags are parsed', () {
    final landlord = UserModel.fromJson({
      'id': 'owner-id',
      'email': 'owner@example.com',
      'role': 'OWNER',
      'verification_status': 'VERIFIED',
      'payout_account_status': 'MISSING',
      'can_create_properties': true,
      'can_execute_agreements': false,
      'payout_account_required_for': 'AGREEMENT_EXECUTION',
    });

    expect(landlord.payoutAccountStatus, PayoutAccountStatus.missing);
    expect(
      landlord.canCreateProperties,
      isTrue,
      reason: 'payout setup is deliberately not a prerequisite for properties',
    );
    expect(landlord.canExecuteAgreements, isFalse);
    expect(landlord.needsPayoutSetup, isTrue);

    final tenant = UserModel.fromJson({
      'id': 'tenant-id',
      'email': 'tenant@example.com',
      'role': 'TENANT',
      'verification_status': 'VERIFIED',
      'payout_account_status': 'NOT_REQUIRED',
    });
    expect(
      tenant.needsPayoutSetup,
      isFalse,
      reason: 'tenants never receive payouts',
    );
  });

  test('an unrecognised payout status never reads as verified', () {
    expect(
      PayoutAccountStatus.fromString('SOMETHING_NEW'),
      PayoutAccountStatus.unknown,
    );
    expect(PayoutAccountStatus.unknown.isVerified, isFalse);
    expect(PayoutAccountStatus.unknown.needsSetup, isTrue);
    // UNVERIFIED and MISSING both mean "no usable account yet".
    expect(
      PayoutAccountStatus.fromString('UNVERIFIED'),
      PayoutAccountStatus.missing,
    );
  });

  test('cached profile round-trips the payout status', () {
    // toJson used .name once, which emitted "notRequired" and re-parsed as
    // unknown: flipping a tenant into "needs payout setup" on relaunch.
    for (final status in PayoutAccountStatus.values) {
      final user = UserModel(
        id: 'id',
        email: 'a@b.com',
        phone: '',
        role: UserRole.owner,
        verificationStatus: VerificationStatus.verified,
        payoutAccountStatus: status,
      );
      expect(
        UserModel.fromJson(user.toJson()).payoutAccountStatus,
        status,
        reason: 'round-trip failed for ${status.wireValue}',
      );
    }
  });
}

http.Response _json(List<dynamic> body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response _jsonObject(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

Map<String, dynamic> _executedAgreement() => {
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
  'rules': '',
  'agreement_text': '',
  'status': 'EXECUTED',
  'tenant_signature_hash': 'tenant-signature',
  'landlord_signature_hash': 'landlord-signature',
  'tenant_signed_at': '2026-08-21T10:00:00Z',
  'landlord_signed_at': '2026-08-21T10:05:00Z',
  'executed_at': '2026-08-21T10:05:00Z',
  'pay_rent_unlocked': true,
  'created_at': '2026-08-21T09:00:00Z',
};
