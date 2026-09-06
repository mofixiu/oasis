/// State of a landlord's payout account, as reported by both
/// `GET /payout-account/` and the `payout_account_status` field on the profile.
enum PayoutAccountStatus {
  /// Not applicable: e.g. tenants, who never receive payouts.
  notRequired,

  /// Landlord has no payout account on file yet.
  missing,

  /// Submitted but not yet confirmed by the provider.
  pending,

  /// Verified with the provider; agreement execution and escrow release are
  /// unblocked.
  verified,

  /// Provider verification failed; the landlord must correct the details.
  failed,

  unknown;

  static PayoutAccountStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'NOT_REQUIRED':
        return PayoutAccountStatus.notRequired;
      case 'MISSING':
      // The guide lists UNVERIFIED alongside MISSING; both mean "no usable
      // payout account yet", so they share a state.
      case 'UNVERIFIED':
        return PayoutAccountStatus.missing;
      case 'PENDING':
        return PayoutAccountStatus.pending;
      case 'VERIFIED':
        return PayoutAccountStatus.verified;
      case 'FAILED':
        return PayoutAccountStatus.failed;
      default:
        // Never assume VERIFIED for an unrecognised status, that would show
        // a landlord an unblocked action the backend will reject.
        return PayoutAccountStatus.unknown;
    }
  }

  /// Wire spelling, so a cached profile round-trips back to the same state.
  /// `.name` would emit `notRequired` and re-parse as [unknown].
  String get wireValue {
    switch (this) {
      case PayoutAccountStatus.notRequired:
        return 'NOT_REQUIRED';
      case PayoutAccountStatus.missing:
        return 'MISSING';
      case PayoutAccountStatus.pending:
        return 'PENDING';
      case PayoutAccountStatus.verified:
        return 'VERIFIED';
      case PayoutAccountStatus.failed:
        return 'FAILED';
      case PayoutAccountStatus.unknown:
        return 'UNKNOWN';
    }
  }

  bool get isVerified => this == PayoutAccountStatus.verified;

  /// Whether the landlord still has payout setup to do.
  bool get needsSetup =>
      this == PayoutAccountStatus.missing ||
      this == PayoutAccountStatus.failed ||
      this == PayoutAccountStatus.unknown;

  String get label {
    switch (this) {
      case PayoutAccountStatus.notRequired:
        return 'NOT REQUIRED';
      case PayoutAccountStatus.missing:
        return 'NOT SET UP';
      case PayoutAccountStatus.pending:
        return 'PENDING';
      case PayoutAccountStatus.verified:
        return 'VERIFIED';
      case PayoutAccountStatus.failed:
        return 'FAILED';
      case PayoutAccountStatus.unknown:
        return 'UNKNOWN';
    }
  }
}

/// A bank offered by `GET /banks/`.
///
/// The backend now returns a provider `code` alongside the name. Sending the
/// code back removes the whole class of "the name did not resolve" failures
/// that came from near-duplicate bank names, so the app prefers it and keeps
/// the name only for display.
class BankOption {
  final String name;
  final String code;
  final String slug;

  const BankOption({required this.name, this.code = '', this.slug = ''});

  factory BankOption.fromJson(Map<String, dynamic> json) => BankOption(
    name: (json['name'] ?? '').toString(),
    code: (json['code'] ?? '').toString(),
    slug: (json['slug'] ?? '').toString(),
  );
}

/// Landlord payout account. Account numbers arrive masked (`"******6034"`).
class PayoutAccount {
  final String? id;
  final String bankName;
  final String accountNumber;
  final String accountName;
  final PayoutAccountStatus status;
  final String? provider;
  final String? verifiedAt;
  final String? lastVerifiedAt;

  /// What the payout account is currently gating, e.g.
  /// `"AGREEMENT_EXECUTION"`. Null when nothing is blocked.
  final String? requiredFor;

  /// Backend-supplied explanation shown when setup is still outstanding.
  final String? detail;

  const PayoutAccount({
    this.id,
    this.bankName = '',
    this.accountNumber = '',
    this.accountName = '',
    required this.status,
    this.provider,
    this.verifiedAt,
    this.lastVerifiedAt,
    this.requiredFor,
    this.detail,
  });

  bool get isVerified => status.isVerified;

  /// True when the payload carries actual account details rather than just a
  /// "MISSING" status envelope.
  bool get hasDetails => bankName.isNotEmpty && accountNumber.isNotEmpty;

  factory PayoutAccount.fromJson(Map<String, dynamic> json) => PayoutAccount(
    id: json['id']?.toString(),
    bankName: (json['bank_name'] ?? '').toString(),
    accountNumber: (json['account_number'] ?? '').toString(),
    accountName: (json['account_name'] ?? '').toString(),
    status: PayoutAccountStatus.fromString(json['status']?.toString()),
    provider: json['provider']?.toString(),
    verifiedAt: json['verified_at']?.toString(),
    lastVerifiedAt: json['last_verified_at']?.toString(),
    requiredFor: json['payout_account_required_for']?.toString(),
    detail: json['detail']?.toString(),
  );
}

/// The account a bank confirmed for a given bank + account number.
///
/// This is what removes the "account name mismatch" class of failure: the
/// landlord no longer types their own name for the backend to compare against
/// the bank's version of it. They type ten digits and confirm what comes back.
class AccountResolution {
  final String bankName;
  final String bankCode;

  /// The name as the bank holds it, which is frequently surname-first and
  /// rarely how the account holder would write it themselves.
  final String accountName;

  final String accountNumberMasked;

  /// Short-lived proof that this account was resolved for this user, so the
  /// save step cannot be pointed at a different account number than the one
  /// that was confirmed on screen. Null before the backend ships it.
  final String? resolutionToken;

  const AccountResolution({
    required this.accountName,
    this.bankName = '',
    this.bankCode = '',
    this.accountNumberMasked = '',
    this.resolutionToken,
  });

  factory AccountResolution.fromJson(Map<String, dynamic> json) =>
      AccountResolution(
        accountName: (json['account_name'] ?? '').toString(),
        bankName: (json['bank_name'] ?? '').toString(),
        bankCode: (json['bank_code'] ?? '').toString(),
        accountNumberMasked: (json['account_number_masked'] ?? '').toString(),
        resolutionToken: json['resolution_token']?.toString(),
      );

  bool get isUsable => accountName.trim().isNotEmpty;
}
