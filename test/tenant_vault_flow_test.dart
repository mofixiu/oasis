import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';
import 'package:oasis_app/features/payments/controllers/payment_controller.dart';
import 'package:oasis_app/features/payments/models/payment_model.dart';
import 'package:oasis_app/features/payments/services/payment_service.dart';
import 'package:oasis_app/features/vault/controllers/vault_controller.dart';
import 'package:oasis_app/features/vault/models/vault_models.dart';
import 'package:oasis_app/features/vault/services/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tenant vault is savings, so these cover what would actually cost a
/// tenant money: being charged twice for one top-up, being told money landed
/// when it did not, and paying rent from a balance that was never debited.
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

  test('a top-up returns its checkout without crediting the vault', () async {
    // Starting a top-up must not move the balance. Money has not moved until
    // the provider says so, and a balance that jumps early is a lie.
    var vaultFetches = 0;
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/vault/')) {
              vaultFetches++;
              return _json({'available_balance': '0.00'});
            }
            return _json({
              'id': 'topup-1',
              'amount': '150000.00',
              'status': 'PENDING',
              'reference': 'TU-ABC123',
              'authorization_url': 'https://checkout.example.test/TU-ABC123',
            }, status: 201);
          }),
        ),
      ),
    );

    final topUp = await controller.startTopUp('150000.00');
    expect(topUp, isNotNull);
    expect(topUp!.status, TopUpStatus.pending);
    expect(topUp.hasCheckout, isTrue);
    expect(topUp.status.isSettled, isFalse);
    expect(vaultFetches, 0);
  });

  test('one top-up intent keeps one idempotency key across retries', () async {
    // A tap that times out and is tried again must be one charge, not two.
    final keys = <String>[];
    var attempt = 0;
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            keys.add(request.headers['Idempotency-Key'] ?? '');
            attempt++;
            if (attempt == 1) {
              return _json({'detail': 'Upstream hiccup'}, status: 502);
            }
            return _json({
              'id': 'topup-1',
              'amount': '150000.00',
              'status': 'PENDING',
              'authorization_url': 'https://checkout.example.test/x',
            }, status: 201);
          }),
        ),
      ),
    );

    await controller.startTopUp('150000.00');
    await controller.startTopUp('150000.00');

    expect(keys, hasLength(2));
    expect(keys.first, isNotEmpty);
    expect(keys.first, keys.last);
  });

  test('a new top-up intent gets a new key', () async {
    final keys = <String>[];
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            keys.add(request.headers['Idempotency-Key'] ?? '');
            return _json({
              'id': 'topup-1',
              'amount': '150000.00',
              'status': 'PENDING',
              'authorization_url': 'https://checkout.example.test/x',
            }, status: 201);
          }),
        ),
      ),
    );

    await controller.startTopUp('150000.00');
    controller.beginTopUpIntent();
    await controller.startTopUp('50000.00');

    expect(keys.first, isNot(keys.last));
  });

  test('the balance is refetched only once a top-up settles', () async {
    var vaultFetches = 0;
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            final path = request.url.path;
            if (path.endsWith('/vault/')) {
              vaultFetches++;
              return _json({'available_balance': '150000.00'});
            }
            if (path.contains('/verify/')) {
              return _json({
                'id': 'topup-1',
                'amount': '150000.00',
                'status': 'SUCCEEDED',
              });
            }
            return _json({
              'id': 'topup-1',
              'amount': '150000.00',
              'status': 'PENDING',
              'authorization_url': 'https://checkout.example.test/x',
            }, status: 201);
          }),
        ),
      ),
    );

    await controller.startTopUp('150000.00');
    expect(vaultFetches, 0);

    final verified = await controller.verifyTopUp();
    expect(verified!.status, TopUpStatus.succeeded);
    expect(vaultFetches, 1);
    expect(controller.availableBalance, '150000.00');
  });

  test('an unknown top-up status never reads as money in', () {
    // The one error worth guarding: telling a tenant their rent money is
    // there when the provider has not confirmed it.
    final unknown = TopUpStatus.fromString('SOMETHING_NEW');
    expect(unknown, TopUpStatus.unknown);
    expect(unknown.isSettled, isFalse);
    expect(TopUpStatus.fromString('ABANDONED').isSettled, isFalse);
    expect(TopUpStatus.fromString('SUCCEEDED').isSettled, isTrue);
  });

  test('a top-up with no checkout link is not openable', () {
    final topUp = VaultTopUp.fromJson({
      'id': 'topup-1',
      'amount': '150000.00',
      'status': 'PENDING',
    });
    expect(topUp.hasCheckout, isFalse);
  });

  test('canCover is false until the vault has actually loaded', () async {
    // Offering "pay from vault" against a balance we have not seen would put
    // the tenant through a payment that is refused.
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({'available_balance': '450000.00'}),
          ),
        ),
      ),
    );

    expect(controller.canCover('450000.00'), isFalse);
    await controller.loadVault();
    expect(controller.canCover('450000.00'), isTrue);
    expect(controller.canCover('450000.01'), isFalse);
  });

  test('paying rent from the vault sends the vault source', () async {
    Map<String, dynamic>? sentBody;
    String? sentKey;
    final controller = PaymentController(
      paymentService: PaymentService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            sentKey = request.headers['Idempotency-Key'];
            return _json({
              'id': 'payment-1',
              'agreement': 'agreement-1',
              'amount': '450000.00',
              'total_amount': '472500.00',
              'reference': 'LR-VAULT01',
              'status': 'ESCROW',
            }, status: 201);
          }),
        ),
      ),
    );

    final payment = await controller.payRentFromVault(
      _executedAgreement(),
      vaultPin: '1234',
    );

    expect(payment, isNotNull);
    expect(payment!.status, PaymentStatus.escrow);
    // The PIN travels with the request and nothing else does: no account
    // details, no balance the app worked out for itself.
    expect(sentBody, {
      'agreement': 'agreement-1',
      'source': 'VAULT',
      'vault_pin': '1234',
    });
    expect(sentKey, isNotEmpty);
    expect(controller.payments.single.id, 'payment-1');
  });

  test(
    'a vault payment that did not settle is reported as a failure',
    () async {
      // No checkout to fall back on here: if the backend did not put it in
      // escrow, the vault was not debited and the tenant still owes rent.
      final controller = PaymentController(
        paymentService: PaymentService(
          apiClient: ApiClient(
            client: MockClient(
              (_) async => _json({
                'id': 'payment-1',
                'agreement': 'agreement-1',
                'amount': '450000.00',
                'reference': 'LR-VAULT01',
                'status': 'PENDING',
              }, status: 201),
            ),
          ),
        ),
      );

      final payment = await controller.payRentFromVault(
        _executedAgreement(),
        vaultPin: '1234',
      );

      expect(payment, isNull);
      expect(controller.errorMessage, contains('did not complete'));
      expect(controller.errorMessage, contains('not been charged'));
    },
  );

  test('rent cannot be paid from the vault before execution', () async {
    var called = false;
    final controller = PaymentController(
      paymentService: PaymentService(
        apiClient: ApiClient(
          client: MockClient((_) async {
            called = true;
            return _json({});
          }),
        ),
      ),
    );

    final payment = await controller.payRentFromVault(
      TenancyAgreementModel.fromJson({
        'id': 'agreement-1',
        'status': 'PENDING',
        'rent_amount': '450000.00',
        'pay_rent_unlocked': false,
      }),
      vaultPin: '1234',
    );

    expect(payment, isNull);
    expect(called, isFalse);
    expect(controller.errorMessage, contains('locked'));
  });

  test('signing out clears the tenant top-up in progress', () async {
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({
              'id': 'topup-1',
              'amount': '150000.00',
              'status': 'PENDING',
              'authorization_url': 'https://checkout.example.test/x',
            }, status: 201),
          ),
        ),
      ),
    );

    await controller.startTopUp('150000.00');
    expect(controller.pendingTopUp, isNotNull);

    controller.resetSessionState();

    // Nothing about one tenant's money may survive into the next session.
    expect(controller.pendingTopUp, isNull);
    expect(controller.isToppingUp, isFalse);
    expect(controller.availableBalance, '0.00');
  });
}

TenancyAgreementModel _executedAgreement() => TenancyAgreementModel.fromJson({
  'id': 'agreement-1',
  'unit_number': '4B',
  'rent_amount': '450000.00',
  'status': 'EXECUTED',
  'pay_rent_unlocked': true,
});

http.Response _json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
