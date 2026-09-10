import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/vault/controllers/vault_controller.dart';
import 'package:oasis_app/features/vault/models/vault_models.dart';
import 'package:oasis_app/features/vault/services/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The vault holds real money, so these cover the two things that would cost a
/// landlord if they were wrong: withdrawing twice, and one user's balance
/// surviving into the next session.
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

  test('the vault reports its balance regardless of payout setup', () async {
    // The point of the vault: money arrives whether or not a bank account has
    // been set up, and the balance payload says nothing about payout standing.
    final service = VaultService(
      apiClient: ApiClient(
        client: MockClient(
          (request) async => _jsonObject({
            'id': 'VAULT_UUID',
            'available_balance': '1350000.00',
            'pending_withdrawal_balance': '100000.00',
            'total_credited': '1450000.00',
            'total_withdrawn': '100000.00',
            'currency': 'NGN',
          }),
        ),
      ),
    );

    final vault = await service.getVault();
    expect(vault.availableBalance, '1350000.00');
    expect(vault.pendingWithdrawalBalance, '100000.00');
    expect(vault.hasAvailableBalance, isTrue);
    expect(vault.hasPendingWithdrawal, isTrue);
  });

  test('a zero balance is not mistaken for money', () async {
    final service = VaultService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => _jsonObject({
            'available_balance': '0.00',
            'pending_withdrawal_balance': '0.00',
          }),
        ),
      ),
    );

    final vault = await service.getVault();
    expect(vault.hasAvailableBalance, isFalse);
    expect(vault.hasPendingWithdrawal, isFalse);
  });

  test('withdrawals carry an idempotency key', () async {
    String? sentKey;
    final service = VaultService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentKey = request.headers['Idempotency-Key'];
          return _jsonObject({
            'id': 'w1',
            'reference': 'LW-1',
            'amount': '200000.00',
            'status': 'PROCESSING',
          }, status: 202);
        }),
      ),
    );

    await service.requestWithdrawal(
      amount: '200000.00',
      idempotencyKey: 'wd-abc',
      vaultPin: '1234',
    );
    expect(sentKey, 'wd-abc');
  });

  test('a retried withdrawal reuses the same key', () async {
    // A tap that fails and is tried again is one withdrawal, not two. The key
    // is what lets the backend recognise that.
    final keys = <String>[];
    var shouldFail = true;

    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/withdrawals/') &&
                request.method == 'POST') {
              keys.add(request.headers['Idempotency-Key'] ?? '');
              if (shouldFail) {
                return _jsonObject({
                  'code': 'PROVIDER_UNAVAILABLE',
                  'detail': 'Transfers are briefly unavailable.',
                }, status: 502);
              }
              return _jsonObject({
                'id': 'w1',
                'amount': '200000.00',
                'status': 'PENDING_REVIEW',
              }, status: 201);
            }
            return _jsonObject({'available_balance': '1150000.00'});
          }),
        ),
      ),
    );

    expect(await controller.withdraw('200000.00', vaultPin: '1234'), isNull);
    shouldFail = false;
    expect(await controller.withdraw('200000.00', vaultPin: '1234'), isNotNull);

    expect(keys.length, 2);
    expect(
      keys.first,
      keys.last,
      reason: 'the retry is the same intent and must not settle twice',
    );
  });

  test('a fresh withdrawal intent gets a new key', () async {
    final keys = <String>[];
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/withdrawals/') &&
                request.method == 'POST') {
              keys.add(request.headers['Idempotency-Key'] ?? '');
              return _jsonObject({
                'id': 'w',
                'amount': '1000.00',
                'status': 'PENDING_REVIEW',
              }, status: 201);
            }
            return _jsonObject({'available_balance': '0.00'});
          }),
        ),
      ),
    );

    await controller.withdraw('1000.00', vaultPin: '1234');
    // A second, deliberate withdrawal must not be merged with the first.
    controller.beginWithdrawalIntent();
    await controller.withdraw('1000.00', vaultPin: '1234');

    expect(keys.length, 2);
    expect(keys.first, isNot(keys.last));
  });

  test('signing out clears the balance', () async {
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _jsonObject({'available_balance': '1350000.00'}),
          ),
        ),
      ),
    );

    await controller.loadVault();
    expect(controller.availableBalance, '1350000.00');

    controller.resetSessionState();
    expect(controller.vault, isNull);
    expect(
      controller.availableBalance,
      '0.00',
      reason: "one landlord's balance must never be shown to the next user",
    );
    expect(controller.transactions, isEmpty);
  });

  test('a credit and a debit read differently in the ledger', () {
    // Direction comes from the payload, never inferred: a returned withdrawal
    // is money coming back even though it belongs to a withdrawal.
    final credit = VaultTransaction.fromJson({
      'id': 't1',
      'transaction_type': 'CREDIT',
      'amount': '450000.00',
      'balance_after': '450000.00',
      'source_reference': 'escrow_release:LR-1A2B3C4D5E6F',
      'description': 'Escrow release for LR-1A2B3C4D5E6F',
      'payment_reference': 'LR-1A2B3C4D5E6F',
    });
    final debit = VaultTransaction.fromJson({
      'id': 't2',
      'transaction_type': 'DEBIT',
      'amount': '200000.00',
      'balance_after': '250000.00',
      'withdrawal_id': 'w1',
    });

    expect(credit.isCredit, isTrue);
    expect(credit.title, 'Escrow release for LR-1A2B3C4D5E6F');
    expect(credit.paymentReference, 'LR-1A2B3C4D5E6F');
    expect(debit.isCredit, isFalse);
    expect(debit.withdrawalId, 'w1');
  });

  test('an in-flight withdrawal never reads as paid', () {
    // Both pending states are promises the bank has not kept yet. Saying
    // "paid" before the money lands is the worst error available here.
    expect(WithdrawalStatus.fromString('PENDING_REVIEW').isInFlight, isTrue);
    expect(WithdrawalStatus.fromString('PENDING_REVIEW').label, 'Under review');
    expect(WithdrawalStatus.fromString('PENDING_TRANSFER').isInFlight, isTrue);
    expect(WithdrawalStatus.fromString('PENDING_TRANSFER').label, 'On its way');
    expect(WithdrawalStatus.fromString('PAID').isInFlight, isFalse);
    expect(WithdrawalStatus.fromString('FAILED').isReturned, isTrue);
    expect(WithdrawalStatus.fromString('CANCELLED').isReturned, isTrue);
  });

  test('an unknown status is never treated as paid', () {
    // A status the app has not seen before must not turn into "your money
    // arrived": it stays in flight so the screen keeps checking.
    final unknown = WithdrawalStatus.fromString('SOMETHING_NEW');
    expect(unknown, WithdrawalStatus.unknown);
    expect(unknown.isInFlight, isTrue);
    expect(unknown.isReturned, isFalse);
  });
}

http.Response _jsonObject(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
