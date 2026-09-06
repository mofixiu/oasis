import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/payout_models.dart';

class PayoutService {
  final ApiClient _apiClient;

  PayoutService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Banks the provider supports. The app sends back the chosen `name`: the
  /// backend resolves it to a provider bank code itself.
  Future<List<BankOption>> getBanks() async {
    debugPrint(
      '[PAYOUT SERVICE] Fetching banks GET ${ApiConstants.banksEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.banksEndpoint);
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(BankOption.fromJson)
          .where((bank) => bank.name.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// Current payout account. Returns a `MISSING` envelope rather than a 404
  /// when the user has not set one up.
  Future<PayoutAccount> getPayoutAccount() async {
    debugPrint(
      '[PAYOUT SERVICE] Fetching payout account GET ${ApiConstants.payoutAccountEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.payoutAccountEndpoint);
    if (response is Map<String, dynamic>) {
      final account = PayoutAccount.fromJson(response);
      debugPrint('[PAYOUT SERVICE] Payout status: ${account.status.label}');
      return account;
    }
    return const PayoutAccount(status: PayoutAccountStatus.unknown);
  }

  /// Asks the provider who owns a bank account, without saving anything.
  ///
  /// Sends [bankCode] when the picker supplied one. Resolving by name is what
  /// used to fail on near-duplicate banks ("Access Bank" vs "Access Bank
  /// (Diamond)"), and the bank list now carries codes, so there is no reason
  /// to keep guessing from a display string.
  ///
  /// Returns null only when the provider found no account. Every other
  /// failure is thrown so the screen reports the real reason.
  Future<AccountResolution?> resolveAccount({
    required String bankName,
    String? bankCode,
    required String accountNumber,
  }) async {
    debugPrint(
      '[PAYOUT SERVICE] Resolving account POST ${ApiConstants.payoutAccountResolveEndpoint} '
      '(Bank: ${bankCode?.isNotEmpty == true ? bankCode : bankName})',
    );
    final response = await _apiClient.post(
      ApiConstants.payoutAccountResolveEndpoint,
      body: {
        if (bankCode != null && bankCode.isNotEmpty)
          'bank_code': bankCode
        else
          'bank_name': bankName,
        'account_number': accountNumber,
      },
    );
    final resolution = AccountResolution.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint('[PAYOUT SERVICE] Resolved as "${resolution.accountName}"');
    return resolution.isUsable ? resolution : null;
  }

  /// Saves the account the user just confirmed on screen.
  ///
  /// Sends the resolution token and nothing else. The backend **rejects** any
  /// request carrying a client-supplied `account_name`
  /// (`ACCOUNT_NAME_NOT_ACCEPTED`): the name must come from bank
  /// verification, so there is deliberately no parameter for one here.
  ///
  /// `PATCH` is an upsert on the backend, so [isUpdate] only affects which
  /// verb is used, never whether the call can succeed.
  Future<PayoutAccount> savePayoutAccount({
    required String resolutionToken,
    bool isUpdate = false,
  }) async {
    debugPrint(
      '[PAYOUT SERVICE] Saving payout account '
      '${isUpdate ? 'PATCH' : 'POST'} ${ApiConstants.payoutAccountEndpoint}',
    );
    final body = {'resolution_token': resolutionToken};
    final response = isUpdate
        ? await _apiClient.patch(ApiConstants.payoutAccountEndpoint, body: body)
        : await _apiClient.post(ApiConstants.payoutAccountEndpoint, body: body);
    return PayoutAccount.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }
}
