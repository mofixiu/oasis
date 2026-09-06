import 'package:flutter/foundation.dart';

import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/payout_models.dart';
import '../services/payout_service.dart';

class PayoutController extends ChangeNotifier
    with LoadFailureState
    implements SessionScopedController {
  final PayoutService _service;

  PayoutController({PayoutService? service})
    : _service = service ?? PayoutService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  PayoutAccount? _account;
  PayoutAccount? get account => _account;

  List<BankOption> _banks = [];
  List<BankOption> get banks => _banks;

  /// Distinguishes "never loaded" from "loaded and absent", so the settings
  /// row shows a skeleton rather than briefly claiming payout is unset.
  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  bool _isResolving = false;
  bool get isResolving => _isResolving;

  AccountResolution? _resolution;

  /// The account the bank confirmed, once the digits have been checked.
  AccountResolution? get resolution => _resolution;

  PayoutAccountStatus get status =>
      _account?.status ?? PayoutAccountStatus.unknown;

  bool get isVerified => status.isVerified;

  @override
  void resetSessionState() {
    _account = null;
    _resolution = null;
    _isResolving = false;
    // Bank list is reference data, not user data, but it is cheap to refetch
    // and holding it across accounts has no benefit.
    _banks = [];
    clearFailure();
    _isLoading = false;
    _isSubmitting = false;
    _hasLoaded = false;
    notifyListeners();
  }

  Future<void> loadPayoutAccount() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();
    try {
      _account = await _service.getPayoutAccount();
    } catch (e) {
      captureFailure(e);
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the bank picker options. Cached after the first successful fetch:
  /// the provider's bank list does not change within a session.
  Future<void> loadBanks() async {
    if (_banks.isNotEmpty) return;
    _isLoading = true;
    notifyListeners();
    try {
      _banks = await _service.getBanks();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Asks the bank who owns an account number, so the user confirms a
  /// name rather than typing one.
  ///
  /// Returns true when a name came back, false when the bank could not find
  /// the account: [errorMessage] then holds the reason.
  Future<bool> resolveAccount({
    required String bankName,
    required String accountNumber,
  }) async {
    _isResolving = true;
    _resolution = null;
    clearFailure();
    notifyListeners();

    try {
      final resolved = await _service.resolveAccount(
        bankName: bankName,
        // The picker hands back a display name; the code comes from the same
        // bank list, so resolution never depends on matching a string.
        bankCode: bankCodeFor(bankName),
        accountNumber: accountNumber,
      );
      if (resolved == null) {
        setFailureMessage(
          'That account number does not exist at this bank. Check the digits '
          'and try again.',
        );
        return false;
      }
      _resolution = resolved;
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isResolving = false;
      notifyListeners();
    }
  }

  /// Drops a confirmed account, e.g. when the bank or the digits change and
  /// the previously confirmed name no longer describes what is on screen.
  void clearResolution() {
    if (_resolution == null) return;
    _resolution = null;
    notifyListeners();
  }

  /// The provider bank code for a display name, if the loaded list has one.
  String? bankCodeFor(String bankName) {
    for (final bank in _banks) {
      if (bank.name == bankName && bank.code.isNotEmpty) return bank.code;
    }
    return null;
  }

  /// Saves the account the user confirmed on screen.
  ///
  /// Requires a resolution: the backend accepts nothing but a
  /// `resolution_token`, so without one there is no request worth sending.
  /// Returns true only when the provider verified the account, which is the
  /// signal the caller needs before retrying a blocked withdrawal.
  Future<bool> submitPayoutAccount() async {
    final token = _resolution?.resolutionToken;
    if (token == null || token.isEmpty) {
      setFailureMessage('Confirm your account details before saving.');
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    clearFailure();
    notifyListeners();
    try {
      final existing = _account;
      final saved = await _service.savePayoutAccount(
        resolutionToken: token,
        isUpdate: existing != null && existing.hasDetails,
      );
      _account = saved;
      _hasLoaded = true;
      // The token is single-use; holding on to it would let a later save
      // silently reuse a stale confirmation.
      _resolution = null;
      return saved.isVerified;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
