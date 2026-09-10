import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';
import 'package:oasis_app/features/payments/controllers/payment_controller.dart';
import 'package:oasis_app/features/payments/services/payment_service.dart';
import 'package:oasis_app/features/vault/controllers/vault_controller.dart';
import 'package:oasis_app/features/vault/models/vault_models.dart';
import 'package:oasis_app/features/vault/services/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The vault PIN is the last thing standing between a stolen, already-unlocked
/// phone and someone's rent money. These cover what would actually cost a
/// user: money leaving without the PIN reaching the backend, a lock the app
/// fails to notice, and a PIN or password surviving anywhere after the call
/// that needed it.
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

  test('a withdrawal sends the PIN the backend requires', () async {
    // Without this field the backend refuses the transfer, so its absence
    // would turn every withdrawal into a dead end.
    Map<String, dynamic>? sentBody;
    final service = VaultService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'id': 'w1',
            'amount': '200000.00',
            'status': 'PENDING_REVIEW',
          }, status: 201);
        }),
      ),
    );

    await service.requestWithdrawal(
      amount: '200000.00',
      idempotencyKey: 'wd-1',
      vaultPin: '1234',
    );

    expect(sentBody?['vault_pin'], '1234');
    expect(sentBody?['amount'], '200000.00');
  });

  test('a vault rent payment sends the PIN and its idempotency key', () async {
    // Money already inside Oasis moves with no checkout to fall back on, so
    // both of these have to be on the one request that does it.
    Map<String, dynamic>? sentBody;
    String? sentKey;
    final service = PaymentService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          sentKey = request.headers['Idempotency-Key'];
          return _json({
            'id': 'p1',
            'status': 'ESCROW',
            'amount': '450000.00',
          }, status: 201);
        }),
      ),
    );

    await service.payFromVault(
      agreementId: 'agreement-1',
      idempotencyKey: 'vp-1',
      vaultPin: '4321',
    );

    expect(sentBody?['source'], 'VAULT');
    expect(sentBody?['vault_pin'], '4321');
    expect(sentKey, 'vp-1');
  });

  test('a lock that has expired is not treated as a lock', () async {
    // The backend hands back a timestamp, not a flag. Trusting the flag we
    // fetched five minutes ago would keep someone out of their own money
    // after the lock had already lifted.
    final expired = VaultPinStatus.fromJson({
      'is_set': true,
      'locked_until': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });
    final active = VaultPinStatus.fromJson({
      'is_set': true,
      'locked_until': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
    });

    expect(expired.isLocked, isFalse);
    expect(expired.lockMessage, isNull);
    expect(active.isLocked, isTrue);
    expect(active.lockMessage, contains('minutes'));
  });

  test('an unknown PIN status never claims a PIN exists', () async {
    // "We have not looked" and "there is no PIN" must not collapse into one
    // another: the first should not send anyone into a setup form, and the
    // second must not let the app prompt for a PIN that was never created.
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({'detail': 'Server error.'}, status: 500),
          ),
        ),
      ),
    );

    expect(controller.pinStatus, isNull);
    expect(controller.hasVaultPin, isFalse);
    expect(controller.isPinLocked, isFalse);
    expect(controller.hasLoadedPinStatus, isFalse);

    await controller.loadPinStatus();
    expect(controller.pinStatus, isNull);
    expect(controller.hasVaultPin, isFalse);
  });

  test('only four digits count as a PIN', () {
    expect(isValidVaultPin('1234'), isTrue);
    expect(isValidVaultPin('0000'), isTrue);
    expect(isValidVaultPin('123'), isFalse);
    expect(isValidVaultPin('12345'), isFalse);
    expect(isValidVaultPin('12a4'), isFalse);
    expect(isValidVaultPin(''), isFalse);
  });

  test('a rejected withdrawal re-reads how many tries are left', () async {
    // The rejection code for a wrong PIN is not published, but the PIN
    // endpoint's attempt count is, so the app asks the endpoint that knows
    // rather than pattern-matching an error string.
    var pinFetches = 0;
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/vault/pin/')) {
              pinFetches++;
              return _json({
                'is_set': true,
                'locked_until': null,
                // One fewer than the reading before the attempt: that drop is
                // the whole signal.
                'failed_attempts_remaining': pinFetches == 1 ? 3 : 2,
              });
            }
            if (request.method == 'POST') {
              return _json({'detail': 'Incorrect vault PIN.'}, status: 400);
            }
            return _json({'available_balance': '500000.00'});
          }),
        ),
      ),
    );

    // The PIN sheet reads the status before it will take an entry, so there is
    // always a "before" to compare against by the time a PIN is submitted.
    await controller.loadPinStatus();
    expect(await controller.withdraw('1000.00', vaultPin: '0000'), isNull);

    expect(pinFetches, 2, reason: 'the failure must refresh PIN standing');
    expect(controller.lastAttemptRejectedPin, isTrue);
    expect(controller.pinStatus?.attemptsRemaining, 2);
    expect(controller.pinStatus?.isRunningOutOfAttempts, isTrue);
    expect(
      controller.errorMessage,
      'Incorrect vault PIN.',
      reason: "the status refresh must not overwrite the action's own failure",
    );
    // The count is the part the backend does not send, so the app adds it.
    expect(
      controller.describeFailedAttempt(controller.errorMessage),
      'Incorrect vault PIN. 2 tries left before your vault locks for '
      '15 minutes.',
    );
  });

  test('a locked vault says so instead of repeating the rejection', () async {
    // Once locked, "wrong PIN" is no longer the useful sentence: there is
    // nothing to retry until the lock lifts.
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/vault/pin/')) {
              return _json({
                'is_set': true,
                'locked_until': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 15))
                    .toIso8601String(),
                'failed_attempts_remaining': 0,
              });
            }
            if (request.method == 'POST') {
              return _json({'detail': 'Incorrect vault PIN.'}, status: 400);
            }
            return _json({'available_balance': '500000.00'});
          }),
        ),
      ),
    );

    await controller.withdraw('1000.00', vaultPin: '0000');

    expect(controller.isPinLocked, isTrue);
    expect(
      controller.describeFailedAttempt(controller.errorMessage),
      contains('Too many wrong PINs'),
    );
  });

  test(
    'a failure that was not the PIN is reported as the backend put it',
    () async {
      // A provider outage must not be dressed up as a PIN problem: the count
      // is untouched, so nothing is added to the message.
      final controller = VaultController(
        vaultService: VaultService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.url.path.endsWith('/vault/pin/')) {
                return _json({'is_set': true, 'failed_attempts_remaining': 1});
              }
              if (request.method == 'POST') {
                return _json({
                  'code': 'PROVIDER_UNAVAILABLE',
                  'detail': 'Paystack could not be reached.',
                }, status: 502);
              }
              return _json({'available_balance': '500000.00'});
            }),
          ),
        ),
      );

      await controller.loadPinStatus();
      await controller.withdraw('1000.00', vaultPin: '1234');

      expect(controller.lastAttemptRejectedPin, isFalse);
      expect(
        controller.describeFailedAttempt(controller.errorMessage),
        'Paystack could not be reached.',
      );
    },
  );

  test('a rejection with nothing to compare against stays unclaimed', () async {
    // With no reading from before the attempt, there is no evidence the PIN
    // was the problem, so the app reports the backend's sentence and adds
    // nothing to it. Guessing here would blame the user for an outage.
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/vault/pin/')) {
              return _json({'is_set': true, 'failed_attempts_remaining': 2});
            }
            if (request.method == 'POST') {
              return _json({'detail': 'Incorrect vault PIN.'}, status: 400);
            }
            return _json({'available_balance': '500000.00'});
          }),
        ),
      ),
    );

    await controller.withdraw('1000.00', vaultPin: '0000');

    expect(controller.lastAttemptRejectedPin, isFalse);
    expect(
      controller.describeFailedAttempt(controller.errorMessage),
      'Incorrect vault PIN.',
    );
  });

  test('a lock appearing after a failed attempt is reported as one', () async {
    var locked = false;
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/vault/pin/')) {
              return _json({
                'is_set': true,
                'locked_until': locked
                    ? DateTime.now()
                          .toUtc()
                          .add(const Duration(minutes: 15))
                          .toIso8601String()
                    : null,
                'failed_attempts_remaining': locked ? 0 : 1,
              });
            }
            return _json({'available_balance': '0.00'});
          }),
        ),
      ),
    );

    await controller.loadPinStatus();
    expect(controller.isPinLocked, isFalse);

    locked = true;
    expect(await controller.refreshPinStatusAfterFailedAttempt(), isTrue);
    expect(controller.isPinLocked, isTrue);
  });

  test('a short balance is offered a top-up, not just an error', () async {
    // The one money failure with somewhere to go. It has to be told apart
    // from every other rejection, or the tenant is left to work out the gap.
    final controller = PaymentController(
      paymentService: PaymentService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({
              'code': 'INSUFFICIENT_VAULT_BALANCE',
              'detail': 'Your vault balance does not cover this rent.',
              'shortfall': '72500.00',
            }, status: 400),
          ),
        ),
      ),
    );

    final payment = await controller.payRentFromVault(
      _executedAgreement(),
      vaultPin: '1234',
    );

    expect(payment, isNull);
    expect(controller.vaultBalanceFellShort, isTrue);
    expect(controller.vaultShortfall, '72500.00');
    expect(controller.errorMessage, contains('does not cover'));
  });

  test('an ordinary rejection is not mistaken for a short balance', () async {
    final controller = PaymentController(
      paymentService: PaymentService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({'detail': 'Incorrect vault PIN.'}, status: 400),
          ),
        ),
      ),
    );

    expect(
      await controller.payRentFromVault(_executedAgreement(), vaultPin: '0000'),
      isNull,
    );
    expect(controller.vaultBalanceFellShort, isFalse);
    expect(controller.vaultShortfall, isNull);
  });

  test('signing out forgets the PIN standing', () async {
    // PIN status says whether this account has a PIN and whether it is locked.
    // Left behind, the next person to sign in on the phone would be shown the
    // previous user's.
    final controller = VaultController(
      vaultService: VaultService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async =>
                _json({'is_set': true, 'failed_attempts_remaining': 5}),
          ),
        ),
      ),
    );

    await controller.loadPinStatus();
    expect(controller.hasVaultPin, isTrue);

    controller.resetSessionState();
    expect(controller.pinStatus, isNull);
    expect(controller.hasVaultPin, isFalse);
    expect(controller.hasLoadedPinStatus, isFalse);
  });
}

TenancyAgreementModel _executedAgreement() => TenancyAgreementModel.fromJson({
  'id': 'agreement-1',
  'status': 'EXECUTED',
  'rent_amount': '450000.00',
  'pay_rent_unlocked': true,
});

http.Response _json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
