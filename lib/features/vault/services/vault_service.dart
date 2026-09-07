import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/vault_models.dart';

/// Talks to the vault endpoints: the balance, its ledger, withdrawals out to
/// a bank, and, for tenants, top-ups in.
///
/// Nothing here is role-branched. The backend scopes every one of these to the
/// caller's own vault, so a tenant and a landlord hit the same paths and get
/// their own money back.
class VaultService {
  final ApiClient _apiClient;

  VaultService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// The caller's own balance. Payout standing is *not* part of this
  /// response: it comes from `PayoutController`, so the two are never guessed
  /// at from one another.
  Future<VaultSummary> getVault() async {
    debugPrint(
      '[VAULT SERVICE] Fetching vault GET ${ApiConstants.vaultEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.vaultEndpoint);
    if (response is Map<String, dynamic>) {
      final summary = VaultSummary.fromJson(response);
      debugPrint(
        '[VAULT SERVICE] Available=₦${summary.availableBalance}, '
        'PendingWithdrawal=₦${summary.pendingWithdrawalBalance}',
      );
      return summary;
    }
    return const VaultSummary();
  }

  /// Full ledger, newest first.
  ///
  /// The endpoint is cursor-paginated; [cursor] carries the opaque value from
  /// the previous page. Returns the rows and the next cursor together so the
  /// controller can decide whether there is more to load.
  Future<({List<VaultTransaction> transactions, String? nextCursor})>
  getTransactions({String? cursor, int limit = 25}) async {
    debugPrint(
      '[VAULT SERVICE] Fetching ledger GET ${ApiConstants.vaultTransactionsEndpoint} '
      '(cursor=${cursor ?? 'start'})',
    );
    final response = await _apiClient.get(
      ApiConstants.vaultTransactionsEndpoint,
      queryParameters: {'cursor': cursor, 'limit': '$limit'},
    );

    // Tolerate both shapes: the paginated envelope this endpoint is specified
    // to return, and a bare list, so the screen still works if the backend
    // ships the simple version first.
    if (response is Map<String, dynamic>) {
      final results = response['results'];
      return (
        transactions: results is List
            ? results
                  .whereType<Map<String, dynamic>>()
                  .map(VaultTransaction.fromJson)
                  .toList()
            : <VaultTransaction>[],
        nextCursor: response['has_more'] == true
            ? response['next_cursor']?.toString()
            : null,
      );
    }
    if (response is List) {
      return (
        transactions: response
            .whereType<Map<String, dynamic>>()
            .map(VaultTransaction.fromJson)
            .toList(),
        nextCursor: null,
      );
    }
    return (transactions: <VaultTransaction>[], nextCursor: null);
  }

  /// Whether a vault PIN exists and whether PIN entry is currently locked.
  ///
  /// Read before offering any action that spends from the vault, so the app
  /// prompts for a PIN that exists and offers to create one that does not.
  Future<VaultPinStatus> getPinStatus() async {
    debugPrint(
      '[VAULT SERVICE] Fetching PIN status GET ${ApiConstants.vaultPinEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.vaultPinEndpoint);
    final status = VaultPinStatus.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[VAULT SERVICE] PIN set=${status.isSet}, locked=${status.isLocked}, '
      'attemptsRemaining=${status.attemptsRemaining}',
    );
    return status;
  }

  /// Creates the vault PIN. The account password is required so a borrowed,
  /// already-unlocked phone cannot set one.
  ///
  /// Neither the password nor the PIN is ever logged, here or anywhere below.
  Future<VaultPinStatus> createPin({
    required String password,
    required String pin,
  }) async {
    debugPrint(
      '[VAULT SERVICE] Creating PIN POST ${ApiConstants.vaultPinEndpoint}',
    );
    final response = await _apiClient.post(
      ApiConstants.vaultPinEndpoint,
      body: {'password': password, 'vault_pin': pin},
    );
    return VaultPinStatus.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Changes the vault PIN. Needs both the account password and the PIN in
  /// force, so knowing either one alone is not enough to replace it.
  Future<VaultPinStatus> changePin({
    required String password,
    required String currentPin,
    required String newPin,
  }) async {
    debugPrint(
      '[VAULT SERVICE] Changing PIN PATCH ${ApiConstants.vaultPinEndpoint}',
    );
    final response = await _apiClient.patch(
      ApiConstants.vaultPinEndpoint,
      body: {
        'password': password,
        'current_vault_pin': currentPin,
        'new_vault_pin': newPin,
      },
    );
    return VaultPinStatus.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Requests a withdrawal to the caller's saved payout account.
  ///
  /// [idempotencyKey] is generated once per user intent and reused on every
  /// retry of that same intent, so a tap that times out and is tried again
  /// settles as one withdrawal rather than two.
  ///
  /// [vaultPin] is the user's 4-digit vault PIN, which the backend requires on
  /// every withdrawal. It is passed straight through and never stored.
  ///
  /// The destination account is never sent: the backend reads it from the
  /// caller's own verified record, so no request shape can redirect a payout
  /// somewhere else.
  Future<Withdrawal> requestWithdrawal({
    required String amount,
    required String idempotencyKey,
    required String vaultPin,
  }) async {
    debugPrint(
      '[VAULT SERVICE] Requesting withdrawal POST ${ApiConstants.withdrawalsEndpoint} (₦$amount)',
    );
    final response = await _apiClient.post(
      ApiConstants.withdrawalsEndpoint,
      body: {'amount': amount, 'vault_pin': vaultPin},
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    final withdrawal = Withdrawal.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[VAULT SERVICE] Withdrawal ${withdrawal.id} → ${withdrawal.status.label}',
    );
    return withdrawal;
  }

  /// Past and in-flight withdrawals.
  Future<List<Withdrawal>> getWithdrawals() async {
    debugPrint(
      '[VAULT SERVICE] Fetching withdrawals GET ${ApiConstants.withdrawalsEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.withdrawalsEndpoint);
    if (response is Map<String, dynamic> && response['results'] is List) {
      return (response['results'] as List)
          .whereType<Map<String, dynamic>>()
          .map(Withdrawal.fromJson)
          .toList();
    }
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(Withdrawal.fromJson)
          .toList();
    }
    return const [];
  }

  /// Starts a tenant top-up and returns the provider checkout to open.
  ///
  /// [idempotencyKey] is generated once per top-up intent and reused on every
  /// retry of that intent, so a request that times out and is tried again
  /// cannot become two charges.
  Future<VaultTopUp> requestTopUp({
    required String amount,
    required String idempotencyKey,
  }) async {
    debugPrint(
      '[VAULT SERVICE] Starting top-up POST ${ApiConstants.vaultTopUpsEndpoint} (₦$amount)',
    );
    final response = await _apiClient.post(
      ApiConstants.vaultTopUpsEndpoint,
      body: {'amount': amount},
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    final topUp = VaultTopUp.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[VAULT SERVICE] Top-up ${topUp.reference} → ${topUp.status.label}, '
      'checkout=${topUp.hasCheckout}',
    );
    return topUp;
  }

  /// Confirms a top-up with the backend once provider checkout closes.
  ///
  /// The app never marks a top-up settled itself. Checkout closing tells us
  /// only that a browser went away, not that money moved.
  Future<VaultTopUp> verifyTopUp(VaultTopUp topUp) async {
    final endpoint = ApiConstants.verifyTopUpEndpoint(topUp.id);
    debugPrint('[VAULT SERVICE] Verifying top-up ${topUp.id} POST $endpoint');
    final response = await _apiClient.post(
      endpoint,
      body: topUp.providerReference.isEmpty
          ? <String, dynamic>{}
          : {'reference': topUp.providerReference},
    );
    final verified = VaultTopUp.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[VAULT SERVICE] Top-up ${verified.id} → ${verified.status.label}',
    );
    return verified;
  }
}
