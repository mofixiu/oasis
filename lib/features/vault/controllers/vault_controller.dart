import 'package:flutter/foundation.dart';

import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/vault_allocations.dart';
import '../models/vault_models.dart';
import '../services/vault_service.dart';

/// Holds the signed-in user's vault balance, ledger, withdrawals and, for a
/// tenant: top-ups.
///
/// One controller serves both roles because one vault serves both roles. A
/// landlord's fills from escrow releases; a tenant's fills from top-ups and
/// drains when they pay rent out of it. Nothing below branches on role: the
/// backend returns the caller's own vault, and the screens decide which
/// actions to offer.
///
/// Caches per-user money data, so it must be wiped between sessions: a
/// balance left behind after sign-out would be shown to whoever signs in next.
class VaultController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  /// Keys for [LoadedOnceState].
  static const String kVaultKey = 'vault';
  static const String kTransactionsKey = 'transactions';

  final VaultService _vaultService;

  VaultController({VaultService? vaultService})
    : _vaultService = vaultService ?? VaultService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isWithdrawing = false;

  /// True while a withdrawal is in flight. The sheet's button reads this, so
  /// a double tap cannot start a second transfer.
  bool get isWithdrawing => _isWithdrawing;

  bool _isToppingUp = false;

  /// True while a top-up is being created or verified, for the same reason.
  bool get isToppingUp => _isToppingUp;

  VaultSummary? _vault;
  VaultSummary? get vault => _vault;

  List<VaultTransaction> _transactions = [];
  List<VaultTransaction> get transactions => _transactions;

  String? _nextCursor;

  /// Whether the ledger has another page to fetch.
  bool get hasMoreTransactions => _nextCursor != null;

  List<Withdrawal> _withdrawals = [];
  List<Withdrawal> get withdrawals => _withdrawals;

  VaultPinStatus? _pinStatus;

  /// Whether a vault PIN exists and whether entry is locked. Null until it has
  /// been fetched, which is not the same as "no PIN", so screens must not
  /// treat the two alike.
  VaultPinStatus? get pinStatus => _pinStatus;

  /// True once the PIN status has been read at least once this session.
  bool get hasLoadedPinStatus => _pinStatus != null;

  /// True only when we know a PIN exists. False while unknown, so a screen
  /// never prompts for a PIN that was never created.
  bool get hasVaultPin => _pinStatus?.isSet ?? false;

  /// True only when we know PIN entry is locked out.
  bool get isPinLocked => _pinStatus?.isLocked ?? false;

  bool _isSavingPin = false;

  /// True while a PIN is being created or changed, so the form's button
  /// cannot be submitted twice.
  bool get isSavingPin => _isSavingPin;

  VaultAllocations _allocations = const VaultAllocations.empty();

  /// How the tenant is splitting one balance across the units they rent. A
  /// plan held on the device, not a second account: see [VaultAllocations].
  VaultAllocations get allocations => _allocations;

  /// The user these allocations belong to. Held so a save cannot be written
  /// under the wrong account after a session change.
  String _allocationsUserId = '';

  bool _lastAttemptRejectedPin = false;

  /// Whether the most recent money-out attempt looks to have been refused over
  /// the PIN rather than anything else.
  ///
  /// The backend's rejection code for a wrong PIN is not part of the published
  /// contract, but `GET /vault/pin/` is, and it reports the attempt count and
  /// the lock. So this is not read off an error string: it is the difference
  /// between the PIN standing before the attempt and after it.
  bool get lastAttemptRejectedPin => _lastAttemptRejectedPin;

  /// The idempotency key for the withdrawal the user is currently composing.
  ///
  /// Generated once when the sheet opens and reused for every retry of that
  /// same intent, so a tap that times out and is tried again settles as one
  /// withdrawal. Cleared only once the request succeeds.
  String? _withdrawalIdempotencyKey;

  VaultTopUp? _pendingTopUp;

  /// The top-up currently being paid for, held so the screen can verify it
  /// when provider checkout closes.
  VaultTopUp? get pendingTopUp => _pendingTopUp;

  /// The idempotency key for the top-up the user is currently composing.
  /// Same contract as [_withdrawalIdempotencyKey], for the same reason.
  String? _topUpIdempotencyKey;

  String get availableBalance => _vault?.availableBalance ?? '0.00';

  /// Whether there is anything to withdraw. Whether the user *may* withdraw
  /// also depends on their payout account, which lives on `PayoutController`:
  /// the vault endpoint does not report it, and inferring one from the other
  /// is how screens end up disagreeing.
  bool get hasAvailableBalance => _vault?.hasAvailableBalance ?? false;

  /// Whether the balance would settle a bill of [amount] in full.
  ///
  /// False when the vault has not loaded: offering to pay from a balance we
  /// have not seen would put the user through a checkout that fails.
  bool canCover(String amount) => _vault?.covers(amount) ?? false;

  @override
  void resetSessionState() {
    _vault = null;
    _transactions = [];
    _withdrawals = [];
    _nextCursor = null;
    _withdrawalIdempotencyKey = null;
    _pendingTopUp = null;
    _topUpIdempotencyKey = null;
    _pinStatus = null;
    // The plan is per person; the next user on this phone must not inherit it.
    VaultAllocations.clearFor(_allocationsUserId);
    _allocations = const VaultAllocations.empty();
    _allocationsUserId = '';
    _lastAttemptRejectedPin = false;
    _isLoading = false;
    _isWithdrawing = false;
    _isToppingUp = false;
    _isSavingPin = false;
    resetLoadedState();
    clearFailure();
    notifyListeners();
  }

  /// Loads the balance card. Safe to call on every visit to the payments tab,
  /// by either role.
  Future<void> loadVault() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _vault = await _vaultService.getVault();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kVaultKey);
      notifyListeners();
    }
  }

  /// Loads the first page of the full ledger, replacing the summary's preview.
  Future<void> loadTransactions() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final page = await _vaultService.getTransactions();
      _transactions = page.transactions;
      _nextCursor = page.nextCursor;
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kTransactionsKey);
      notifyListeners();
    }
  }

  /// Appends the next ledger page. No-op when there is nothing more.
  Future<void> loadMoreTransactions() async {
    final cursor = _nextCursor;
    if (cursor == null || _isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final page = await _vaultService.getTransactions(cursor: cursor);
      _transactions = [..._transactions, ...page.transactions];
      _nextCursor = page.nextCursor;
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadWithdrawals() async {
    try {
      _withdrawals = await _vaultService.getWithdrawals();
    } catch (e) {
      captureFailure(e);
    }
    notifyListeners();
  }

  /// Loads this user's savings plan from the device.
  ///
  /// Failure is quiet: a plan that will not load leaves every rent card
  /// measuring against nothing set aside, which is wrong but harmless, and
  /// far better than an error over the payments screen.
  Future<void> loadAllocations(String userId) async {
    if (userId.isEmpty || userId == _allocationsUserId) return;
    _allocationsUserId = userId;
    _allocations = await VaultAllocations.load(userId);
    notifyListeners();
  }

  /// What is set aside towards [agreementId], capped at what the vault
  /// actually holds. Never more than the money that exists.
  String setAsideFor(String agreementId) =>
      _allocations.setAsideFor(agreementId, availableBalance);

  /// Records that money just added is meant for [agreementId].
  ///
  /// Called after a top-up settles rather than when it starts: money that
  /// never arrived should not appear as savings towards anything.
  Future<void> setAside({
    required String agreementId,
    required String amount,
  }) async {
    final next = _allocations.plus(agreementId, amount);
    if (identical(next, _allocations)) return;
    _allocations = next;
    notifyListeners();
    await _allocations.save(_allocationsUserId);
  }

  /// Forgets the plan for [agreementId] once its rent has been paid.
  Future<void> clearSetAside(String agreementId) async {
    final next = _allocations.without(agreementId);
    if (identical(next, _allocations)) return;
    _allocations = next;
    notifyListeners();
    await _allocations.save(_allocationsUserId);
  }

  /// Reads whether a vault PIN exists and whether entry is locked.
  ///
  /// Called whenever a sheet that spends money opens, rather than once at
  /// launch: the lock expires on a timer and a stale status would either keep
  /// someone out after it lifted or invite them into an entry that will fail.
  Future<void> loadPinStatus() async {
    try {
      _pinStatus = await _vaultService.getPinStatus();
    } catch (e) {
      captureFailure(e);
    }
    notifyListeners();
  }

  /// Creates the vault PIN. Returns true when it was saved.
  Future<bool> createPin({
    required String password,
    required String pin,
  }) async {
    _isSavingPin = true;
    clearFailure();
    notifyListeners();

    try {
      _pinStatus = await _vaultService.createPin(password: password, pin: pin);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSavingPin = false;
      notifyListeners();
    }
  }

  /// Changes the vault PIN. Returns true when it was saved.
  ///
  /// A wrong current PIN counts against the same five-attempt lock as a wrong
  /// PIN at withdrawal time, so the status is refreshed on failure to keep the
  /// remaining-attempts warning honest.
  Future<bool> changePin({
    required String password,
    required String currentPin,
    required String newPin,
  }) async {
    _isSavingPin = true;
    clearFailure();
    notifyListeners();

    try {
      _pinStatus = await _vaultService.changePin(
        password: password,
        currentPin: currentPin,
        newPin: newPin,
      );
      return true;
    } catch (e) {
      captureFailure(e);
      await _refreshPinStatusQuietly();
      return false;
    } finally {
      _isSavingPin = false;
      notifyListeners();
    }
  }

  /// Re-reads the PIN status after a money-out attempt this controller did not
  /// make (a vault-funded rent payment, which `PaymentController` owns) and
  /// reports whether the PIN looks to have been the reason it failed.
  ///
  /// [withdraw] does this for itself; this is the hook for everything else
  /// that spends from the vault, so both paths reach the same conclusion the
  /// same way.
  Future<bool> refreshPinStatusAfterFailedAttempt() async {
    _lastAttemptRejectedPin = await _detectPinRejection();
    notifyListeners();
    return _lastAttemptRejectedPin;
  }

  /// Re-reads PIN standing and reports whether it moved against the user:
  /// fewer attempts left than before, or a lock that has just appeared.
  Future<bool> _detectPinRejection() async {
    final before = _pinStatus;
    await _refreshPinStatusQuietly();
    final after = _pinStatus;
    if (after == null) return false;
    if (after.isLocked && before?.isLocked != true) return true;
    final was = before?.attemptsRemaining;
    final now = after.attemptsRemaining;
    return was != null && now != null && now < was;
  }

  /// Refreshes PIN standing without disturbing the failure already on the
  /// controller: the user needs to see why their action failed, not why the
  /// follow-up status check did.
  Future<void> _refreshPinStatusQuietly() async {
    try {
      _pinStatus = await _vaultService.getPinStatus();
    } catch (_) {
      // Leave the previous status in place: a status we could not refresh is
      // still better than none, and this call is never the user's request.
    }
  }

  /// Requests a withdrawal, returning it on success and null on failure.
  ///
  /// [vaultPin] is the user's 4-digit PIN, which the backend requires on every
  /// withdrawal. It is passed through to the request and never held here.
  ///
  /// On success the balance is refreshed from the server rather than adjusted
  /// locally: the backend is the authority on what a withdrawal did to the
  /// balance, and guessing would show a number that does not match the ledger.
  Future<Withdrawal?> withdraw(
    String amount, {
    required String vaultPin,
  }) async {
    _isWithdrawing = true;
    _lastAttemptRejectedPin = false;
    clearFailure();
    notifyListeners();

    // Reuse the key across retries of the same intent so a failed-then-retried
    // tap cannot become two transfers.
    _withdrawalIdempotencyKey ??= _newIdempotencyKey('wd');

    try {
      final withdrawal = await _vaultService.requestWithdrawal(
        amount: amount,
        idempotencyKey: _withdrawalIdempotencyKey!,
        vaultPin: vaultPin,
      );
      _withdrawalIdempotencyKey = null;
      _withdrawals = [withdrawal, ..._withdrawals];
      await loadVault();
      return withdrawal;
    } catch (e) {
      captureFailure(e);
      // The rejection may have been the PIN. Re-read its standing so the sheet
      // can say how many tries are left, or that the vault is now locked.
      _lastAttemptRejectedPin = await _detectPinRejection();
      return null;
    } finally {
      _isWithdrawing = false;
      notifyListeners();
    }
  }

  /// Creates a top-up and returns it with the provider checkout to open.
  ///
  /// The vault is *not* credited here and the balance is deliberately not
  /// refreshed: money has not moved until the provider says so, which is what
  /// [verifyTopUp] is for.
  Future<VaultTopUp?> startTopUp(String amount) async {
    _isToppingUp = true;
    clearFailure();
    notifyListeners();

    _topUpIdempotencyKey ??= _newIdempotencyKey('tu');

    try {
      final topUp = await _vaultService.requestTopUp(
        amount: amount,
        idempotencyKey: _topUpIdempotencyKey!,
      );
      _pendingTopUp = topUp;
      return topUp;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isToppingUp = false;
      notifyListeners();
    }
  }

  /// Confirms the pending top-up with the backend after checkout closes, and
  /// refreshes the balance from the server when it settled.
  ///
  /// Returns null when there was nothing to verify or the call failed.
  Future<VaultTopUp?> verifyTopUp() async {
    final pending = _pendingTopUp;
    if (pending == null) return null;

    _isToppingUp = true;
    clearFailure();
    notifyListeners();

    try {
      final verified = await _vaultService.verifyTopUp(pending);
      _pendingTopUp = verified;
      if (verified.status.isSettled) {
        // One intent, one charge: the key is only spent once the money is in.
        _topUpIdempotencyKey = null;
        await loadVault();
      }
      return verified;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isToppingUp = false;
      notifyListeners();
    }
  }

  /// Starts a fresh top-up intent. Called when the top-up sheet opens so a
  /// new, deliberate top-up is never merged with the previous one.
  void beginTopUpIntent() {
    _topUpIdempotencyKey = null;
    _pendingTopUp = null;
  }

  /// Starts a fresh withdrawal intent. Called when the withdraw sheet opens so
  /// a new, deliberate withdrawal is never merged with the previous one.
  void beginWithdrawalIntent() => _withdrawalIdempotencyKey = null;

  /// How to word a money-out attempt that failed, given [fallback]: the
  /// backend's own sentence for what went wrong.
  ///
  /// A lock replaces the rejection outright, because it changes what the user
  /// should do next. A rejected PIN keeps the backend's wording and adds the
  /// count the backend does not send: how close they are to being locked out.
  String describeFailedAttempt(String? fallback) {
    final status = _pinStatus;
    if (status != null && status.isLocked) {
      return status.lockMessage ?? 'Too many wrong PINs. Try again shortly.';
    }
    final message =
        fallback ?? 'That did not go through. Try again in a moment.';
    if (_lastAttemptRejectedPin &&
        status != null &&
        status.isRunningOutOfAttempts) {
      return '$message ${status.attemptsRemaining} '
          '${status.attemptsRemaining == 1 ? 'try' : 'tries'} left before your '
          'vault locks for 15 minutes.';
    }
    return message;
  }

  /// A key unique to one money-moving intent, [prefix] naming which kind.
  /// Time plus identity hash is enough: it only has to be unique per user, and
  /// the backend scopes it that way.
  String _newIdempotencyKey(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-'
      '${identityHashCode(this)}';
}
