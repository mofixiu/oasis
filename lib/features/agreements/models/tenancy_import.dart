import 'agreement_model.dart';

/// One tenancy a landlord already has, being recorded in Oasis for the first
/// time.
///
/// This is not an invitation to rent somewhere. The person is already living
/// in the unit, the money was already agreed, and often a term is already part
/// paid, so the agreement written from this row starts in the past and the
/// app has to say what is already settled, or the tenant's first sight of
/// Oasis is a screen telling them they owe rent they paid months ago.
class TenancyImportRow {
  final String unitId;

  /// The unit as the landlord sees it, kept alongside the id so a failure can
  /// name the flat rather than a UUID.
  final String unitLabel;

  /// Email, phone or UUID: whatever the landlord has. The backend resolves
  /// all three (guide §2, Tenant Lookup Inputs).
  final String tenantContact;

  /// Annual rent, as a decimal string, whatever the plan. The instalments are
  /// the backend's arithmetic, not the app's.
  final String rentAmount;

  /// When the tenancy actually began. In the past, that is the whole point.
  final DateTime startDate;

  final DateTime endDate;

  final RentPlan rentPlan;

  final String rules;

  /// Whether the rent for this term has already been collected offline.
  ///
  /// Almost always true for a Nigerian tenancy being imported: annual rent is
  /// paid up front, so a tenancy that began eight months ago is paid up for
  /// another four. Sent as `rent_paid_until` = [endDate].
  final bool rentAlreadyPaid;

  const TenancyImportRow({
    required this.unitId,
    required this.unitLabel,
    required this.tenantContact,
    required this.rentAmount,
    required this.startDate,
    required this.endDate,
    required this.rentPlan,
    required this.rules,
    required this.rentAlreadyPaid,
  });

  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// The wire shape, which is `POST /agreements/`'s body plus the two fields
  /// that make it an import rather than an invitation.
  ///
  /// Sending it to `POST /agreements/` today is safe: DRF drops keys its
  /// serializer does not declare, so an older backend writes the backdated
  /// agreement and ignores the settlement, which is exactly the degraded
  /// behaviour §1.6 of `backend_change_spec_v6.md` describes.
  Map<String, dynamic> toJson() => {
    'unit': unitId,
    'tenant': tenantContact.trim(),
    'rent_amount': rentAmount.trim(),
    'start_date': isoDate(startDate),
    'end_date': isoDate(endDate),
    'rules': rules.trim(),
    if (rentPlan.apiValue != null) 'rent_plan': rentPlan.apiValue,
    // Marks this as a tenancy that predates Oasis, so the backend can execute
    // it without pretending the signatures happened here.
    'is_existing_tenancy': true,
    if (rentAlreadyPaid) 'rent_paid_until': isoDate(endDate),
  };
}

/// How one row of an import ended.
///
/// A per-row result rather than one verdict for the batch, because the batch
/// will be partly wrong the first time every landlord runs it: a mistyped
/// email, a unit already assigned, and "3 of 7 failed" is only useful if it
/// says which three and why.
class TenancyImportOutcome {
  final TenancyImportRow row;

  /// The agreement, when one was written.
  final TenancyAgreementModel? agreement;

  /// Why this row failed, already presentable. Null on success.
  final String? error;

  /// Whether the tenant had no Oasis account and was invited to claim one.
  ///
  /// Only ever true against a backend that implements the import endpoint:
  /// `POST /agreements/` rejects an unknown tenant outright, which is the gap
  /// that made this feature need a spec at all.
  final bool tenantWasInvited;

  const TenancyImportOutcome({
    required this.row,
    this.agreement,
    this.error,
    this.tenantWasInvited = false,
  });

  bool get succeeded => error == null;

  factory TenancyImportOutcome.fromJson(
    Map<String, dynamic> json,
    TenancyImportRow row,
  ) {
    final error = json['error'] ?? json['detail'];
    final agreement = json['agreement'];
    final tenantStatus = json['tenant_status']?.toString().toUpperCase();
    return TenancyImportOutcome(
      row: row,
      agreement: agreement is Map<String, dynamic>
          ? TenancyAgreementModel.fromJson(agreement)
          : null,
      error: error?.toString().trim().isNotEmpty == true
          ? error.toString()
          : null,
      tenantWasInvited: tenantStatus == 'INVITED',
    );
  }
}

/// What a whole import came to.
class TenancyImportReport {
  final List<TenancyImportOutcome> outcomes;

  const TenancyImportReport(this.outcomes);

  List<TenancyImportOutcome> get succeeded =>
      outcomes.where((outcome) => outcome.succeeded).toList();

  List<TenancyImportOutcome> get failed =>
      outcomes.where((outcome) => !outcome.succeeded).toList();

  int get invitedCount =>
      outcomes.where((outcome) => outcome.tenantWasInvited).length;

  bool get isCompleteSuccess => failed.isEmpty && outcomes.isNotEmpty;
  bool get isCompleteFailure => succeeded.isEmpty && outcomes.isNotEmpty;
}
