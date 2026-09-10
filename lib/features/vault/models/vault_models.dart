/// Models for the vault: the in-app balance every Oasis account holds.
///
/// A landlord's fills when rent leaves escrow and empties through withdrawals.
/// A tenant's fills when they top it up and empties when they pay rent out of
/// it or withdraw it back. Same balance, same ledger, same models: the only
/// thing that differs is which direction money usually moves.
///
/// Money arrives from the backend as decimal strings (`"450000.00"`) and stays
/// that way all the way to `OasisCurrency`. Nothing here parses to `double`:
/// a balance rendered a naira out is worse than one that fails to render.
library;

import '../../../core/utils/oasis_currency.dart';

/// One append-only ledger row from `GET /vault/transactions/`.
class VaultTransaction {
  final String id;

  /// `CREDIT` when money entered the vault, `DEBIT` when it left. Read from
  /// the backend rather than inferred, because a failed withdrawal comes back
  /// as a credit even though it belongs to a withdrawal.
  final bool isCredit;

  final String amount;
  final String balanceAfter;
  final String description;

  /// Backend idempotency key, e.g. `escrow_release:LR-1A2B3C4D5E6F`. Shown
  /// nowhere; useful when a landlord queries a specific line.
  final String sourceReference;

  final String? paymentId;
  final String? paymentReference;
  final String? withdrawalId;
  final String createdAt;

  const VaultTransaction({
    required this.id,
    required this.isCredit,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    this.sourceReference = '',
    this.paymentId,
    this.paymentReference,
    this.withdrawalId,
    this.createdAt = '',
  });

  factory VaultTransaction.fromJson(Map<String, dynamic> json) =>
      VaultTransaction(
        id: json['id']?.toString() ?? '',
        isCredit:
            (json['transaction_type']?.toString().toUpperCase() ?? 'CREDIT') ==
            'CREDIT',
        amount: json['amount']?.toString() ?? '0.00',
        balanceAfter: json['balance_after']?.toString() ?? '0.00',
        description: json['description']?.toString() ?? '',
        sourceReference: json['source_reference']?.toString() ?? '',
        paymentId: json['payment']?.toString(),
        paymentReference: json['payment_reference']?.toString(),
        withdrawalId: json['withdrawal_id']?.toString(),
        createdAt: json['created_at']?.toString() ?? '',
      );

  /// The backend writes a readable description for every row; this is only a
  /// safety net for an older or hand-inserted entry.
  String get title => description.isNotEmpty
      ? description
      : (isCredit ? 'Money in' : 'Money out');
}

/// A vault balance, from `GET /vault/`.
class VaultSummary {
  final String id;
  final String currency;

  /// Spendable right now: withdrawable, and for a tenant, payable as rent.
  final String availableBalance;

  /// Held against withdrawals the provider has not settled yet. Already
  /// deducted from [availableBalance]: it is shown so someone who just
  /// withdrew can see where the difference went.
  final String pendingWithdrawalBalance;

  /// Lifetime totals, for the ledger header.
  final String totalCredited;
  final String totalWithdrawn;

  /// Lifetime rent paid out of this vault. Tenants only; `0.00` for a
  /// landlord, who never spends from theirs.
  final String totalSpent;

  final String updatedAt;

  const VaultSummary({
    this.id = '',
    this.currency = 'NGN',
    this.availableBalance = '0.00',
    this.pendingWithdrawalBalance = '0.00',
    this.totalCredited = '0.00',
    this.totalWithdrawn = '0.00',
    this.totalSpent = '0.00',
    this.updatedAt = '',
  });

  factory VaultSummary.fromJson(Map<String, dynamic> json) => VaultSummary(
    id: json['id']?.toString() ?? '',
    currency: json['currency']?.toString() ?? 'NGN',
    availableBalance: json['available_balance']?.toString() ?? '0.00',
    pendingWithdrawalBalance:
        json['pending_withdrawal_balance']?.toString() ?? '0.00',
    totalCredited: json['total_credited']?.toString() ?? '0.00',
    totalWithdrawn: json['total_withdrawn']?.toString() ?? '0.00',
    totalSpent: json['total_spent']?.toString() ?? '0.00',
    updatedAt: json['updated_at']?.toString() ?? '',
  );

  bool get hasAvailableBalance => _isPositive(availableBalance);
  bool get hasPendingWithdrawal => _isPositive(pendingWithdrawalBalance);

  /// Whether the balance would settle a bill of [amount] in full.
  bool covers(String amount) => OasisCurrency.covers(availableBalance, amount);

  /// Whether a decimal string is more than zero, without parsing it to a
  /// double: these are money and stay textual end to end.
  static bool _isPositive(String amount) => amount
      .replaceAll(RegExp(r'[^0-9]'), '')
      .replaceAll(RegExp(r'^0+'), '')
      .isNotEmpty;
}

/// Where a tenant's vault top-up has got to.
///
/// Mirrors the rent payment lifecycle rather than inventing a second one: the
/// money takes the same route through the same provider checkout.
enum TopUpStatus {
  /// Created, provider checkout not completed yet.
  pending,

  /// Provider confirmed and the vault has been credited.
  succeeded,

  failed,
  abandoned,
  unknown;

  static TopUpStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'PENDING':
        return TopUpStatus.pending;
      case 'SUCCEEDED':
      case 'SUCCESS':
        return TopUpStatus.succeeded;
      case 'FAILED':
        return TopUpStatus.failed;
      case 'ABANDONED':
        return TopUpStatus.abandoned;
      default:
        // Never guess "succeeded": telling someone their money landed when it
        // did not is the one error that costs them a rent payment.
        return TopUpStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case TopUpStatus.pending:
        return 'Awaiting payment';
      case TopUpStatus.succeeded:
        return 'Added';
      case TopUpStatus.failed:
        return 'Failed';
      case TopUpStatus.abandoned:
        return 'Cancelled';
      case TopUpStatus.unknown:
        return 'Processing';
    }
  }

  bool get isSettled => this == TopUpStatus.succeeded;
}

/// One tenant top-up: money moving from a card or bank into the vault.
class VaultTopUp {
  final String id;
  final String amount;
  final String currency;
  final TopUpStatus status;
  final String reference;

  /// Provider checkout page. Null once the top-up has settled, and on any
  /// response where the provider did not hand one back: the sheet treats a
  /// missing URL as a failure rather than opening nothing.
  final String? authorizationUrl;

  final String? accessCode;
  final String providerReference;
  final String failureReason;
  final String createdAt;
  final String? completedAt;

  const VaultTopUp({
    required this.id,
    required this.amount,
    required this.status,
    this.currency = 'NGN',
    this.reference = '',
    this.authorizationUrl,
    this.accessCode,
    this.providerReference = '',
    this.failureReason = '',
    this.createdAt = '',
    this.completedAt,
  });

  factory VaultTopUp.fromJson(Map<String, dynamic> json) => VaultTopUp(
    id: json['id']?.toString() ?? '',
    amount: json['amount']?.toString() ?? '0.00',
    currency: json['currency']?.toString() ?? 'NGN',
    status: TopUpStatus.fromString(json['status']?.toString()),
    reference: json['reference']?.toString() ?? '',
    authorizationUrl: json['authorization_url']?.toString(),
    accessCode: json['access_code']?.toString(),
    providerReference:
        json['provider_reference']?.toString() ??
        json['reference']?.toString() ??
        '',
    failureReason: json['failure_reason']?.toString() ?? '',
    createdAt: json['created_at']?.toString() ?? '',
    completedAt: json['completed_at']?.toString(),
  );

  /// Whether there is a checkout page worth opening.
  bool get hasCheckout =>
      authorizationUrl != null && authorizationUrl!.trim().isNotEmpty;
}

/// Where a withdrawal has got to.
///
/// The two pending states matter to the user for different reasons:
/// [pendingReview] means a person still has to approve it, [pendingTransfer]
/// means the bank has it. Neither is "paid", and the UI must not say so.
enum WithdrawalStatus {
  pendingReview,
  pendingTransfer,
  paid,
  failed,
  cancelled,
  unknown;

  static WithdrawalStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'PENDING_REVIEW':
        return WithdrawalStatus.pendingReview;
      case 'PENDING_TRANSFER':
        return WithdrawalStatus.pendingTransfer;
      case 'PAID':
        return WithdrawalStatus.paid;
      case 'FAILED':
        return WithdrawalStatus.failed;
      case 'CANCELLED':
        return WithdrawalStatus.cancelled;
      default:
        // Never guess "paid" for an unrecognised status: telling a landlord
        // money has arrived when it has not is the worst available error.
        return WithdrawalStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case WithdrawalStatus.pendingReview:
        return 'Under review';
      case WithdrawalStatus.pendingTransfer:
        return 'On its way';
      case WithdrawalStatus.paid:
        return 'Paid';
      case WithdrawalStatus.failed:
        return 'Failed';
      case WithdrawalStatus.cancelled:
        return 'Cancelled';
      case WithdrawalStatus.unknown:
        return 'Processing';
    }
  }

  /// Still moving, so the screen should re-check it on the next visit.
  bool get isInFlight =>
      this == WithdrawalStatus.pendingReview ||
      this == WithdrawalStatus.pendingTransfer ||
      this == WithdrawalStatus.unknown;

  /// The money came back to the vault. Not a success, but not a loss either.
  bool get isReturned =>
      this == WithdrawalStatus.failed || this == WithdrawalStatus.cancelled;
}

/// One withdrawal from the vault to the landlord's bank.
class Withdrawal {
  final String id;
  final String amount;
  final String currency;
  final WithdrawalStatus status;

  /// Bank details as they were when the withdrawal was requested. Snapshotted
  /// by the backend so history stays truthful after the account changes.
  final String bankName;
  final String accountNumber;
  final String accountName;

  final String providerReference;
  final String failureReason;
  final String requestedAt;
  final String? processedAt;

  const Withdrawal({
    required this.id,
    required this.amount,
    required this.status,
    this.currency = 'NGN',
    this.bankName = '',
    this.accountNumber = '',
    this.accountName = '',
    this.providerReference = '',
    this.failureReason = '',
    this.requestedAt = '',
    this.processedAt,
  });

  factory Withdrawal.fromJson(Map<String, dynamic> json) => Withdrawal(
    id: json['id']?.toString() ?? '',
    amount: json['amount']?.toString() ?? '0.00',
    currency: json['currency']?.toString() ?? 'NGN',
    status: WithdrawalStatus.fromString(json['status']?.toString()),
    bankName: (json['bank_name_snapshot'] ?? json['bank_name'] ?? '')
        .toString(),
    accountNumber: json['account_number']?.toString() ?? '',
    accountName: (json['account_name_snapshot'] ?? json['account_name'] ?? '')
        .toString(),
    providerReference: json['provider_reference']?.toString() ?? '',
    failureReason: json['failure_reason']?.toString() ?? '',
    requestedAt: json['requested_at']?.toString() ?? '',
    processedAt: json['processed_at']?.toString(),
  );

  /// Where the money went, for a history row.
  String get destination => bankName.isEmpty
      ? 'your bank'
      : '$bankName ${accountNumber.isEmpty ? '' : accountNumber}'.trim();
}

/// Standing of the 4-digit PIN that guards money leaving the vault, from
/// `GET /vault/pin/`.
///
/// The PIN is a second factor on the two actions that move money out: a
/// withdrawal to a bank, and a tenant paying rent from their balance, so the
/// app treats this as the authority on whether either can be attempted at all.
/// Nothing here is cached across sessions: it is re-read whenever a sheet that
/// spends money opens.
class VaultPinStatus {
  /// Whether a PIN exists. Until it does, nothing can leave the vault, and
  /// the app should offer to create one rather than prompt for one.
  final bool isSet;

  /// When PIN entry unlocks again after too many wrong tries, or null when it
  /// is not locked.
  final DateTime? lockedUntil;

  /// Tries left before a lock, when the backend reports it.
  final int? attemptsRemaining;

  const VaultPinStatus({
    this.isSet = false,
    this.lockedUntil,
    this.attemptsRemaining,
  });

  factory VaultPinStatus.fromJson(Map<String, dynamic> json) => VaultPinStatus(
    isSet: json['is_set'] == true,
    lockedUntil: _parseTime(json['locked_until']),
    attemptsRemaining: _parseCount(json['failed_attempts_remaining']),
  );

  /// Whether PIN entry is refused right now.
  ///
  /// Compared against the current time rather than trusted as a flag, because
  /// the lock expires on its own and a status fetched a few minutes ago would
  /// otherwise keep the user out after it lifted.
  bool get isLocked {
    final until = lockedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// How much longer the lock has to run, or null when it is not locked.
  Duration? get lockRemaining =>
      isLocked ? lockedUntil!.difference(DateTime.now()) : null;

  /// Whether it is worth warning that the next wrong try locks the vault.
  /// Deliberately quiet until the count is genuinely low: a "5 tries left"
  /// warning on a first attempt only makes people nervous.
  bool get isRunningOutOfAttempts =>
      !isLocked && attemptsRemaining != null && attemptsRemaining! <= 2;

  /// A lock, in the plainest words available. Null when not locked.
  String? get lockMessage {
    final remaining = lockRemaining;
    if (remaining == null) return null;
    final minutes = remaining.inMinutes;
    if (minutes < 1) return 'Too many wrong PINs. Try again in under a minute.';
    return 'Too many wrong PINs. Try again in $minutes '
        '${minutes == 1 ? 'minute' : 'minutes'}.';
  }

  static DateTime? _parseTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    // Compared against local wall-clock time, so a UTC timestamp has to be
    // converted rather than subtracted as-is.
    return DateTime.tryParse(raw)?.toLocal();
  }

  static int? _parseCount(Object? value) =>
      value == null ? null : int.tryParse(value.toString());
}

/// Whether [pin] is the shape the backend accepts: exactly four digits.
bool isValidVaultPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);
