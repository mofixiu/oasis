import '../../properties/models/property_model.dart';

enum AgreementStatus {
  draft,
  pending,
  executed,
  expired,
  voided,

  // Legacy staging values retained only so older agreements can still render.
  sent,
  tenantSigned,
  activated;

  static AgreementStatus fromString(String? status) {
    switch (status?.toUpperCase()) {
      case 'SENT':
        return AgreementStatus.sent;
      case 'TENANT_SIGNED':
        return AgreementStatus.tenantSigned;
      case 'ACTIVATED':
        return AgreementStatus.activated;
      case 'PENDING':
        return AgreementStatus.pending;
      case 'EXECUTED':
        return AgreementStatus.executed;
      case 'EXPIRED':
        return AgreementStatus.expired;
      case 'VOIDED':
        return AgreementStatus.voided;
      default:
        return AgreementStatus.draft;
    }
  }

  String get label {
    switch (this) {
      case AgreementStatus.draft:
        return 'DRAFT';
      case AgreementStatus.pending:
        return 'PENDING';
      case AgreementStatus.executed:
        return 'EXECUTED';
      case AgreementStatus.expired:
        return 'EXPIRED';
      case AgreementStatus.voided:
        return 'VOIDED';
      case AgreementStatus.sent:
        return 'SENT';
      case AgreementStatus.tenantSigned:
        return 'TENANT_SIGNED';
      case AgreementStatus.activated:
        return 'ACTIVATED';
    }
  }

  String get userFriendlyTitle {
    switch (this) {
      case AgreementStatus.draft:
        return 'Draft Agreement';
      case AgreementStatus.pending:
        return 'Awaiting Tenant Signature';
      case AgreementStatus.executed:
        return 'Agreement Executed';
      case AgreementStatus.expired:
        return 'Agreement Expired';
      case AgreementStatus.voided:
        return 'Agreement Voided';
      case AgreementStatus.sent:
        return 'Awaiting Signature';
      case AgreementStatus.tenantSigned:
        return 'Awaiting Landlord Signature';
      case AgreementStatus.activated:
        return 'Legacy Active Agreement';
    }
  }
}

/// Which screen an agreement belongs on.
///
/// [AgreementStatus] cannot answer this on its own: it carries three legacy
/// staging values, and `PENDING` covers both "nobody has signed" and "the
/// tenant has signed, the landlord has not". Both still need a signature, so
/// both belong on the dashboard. Splitting the two ideas keeps the routing
/// rule in one place instead of scattered `status ==` checks across screens.
enum AgreementBucket {
  /// Someone still has to sign. Shown on the dashboard, where it is a task.
  actionRequired,

  /// Signed, expired or voided. Shown in the profile, where it is a record.
  completed;

  static AgreementBucket fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'COMPLETED':
        return AgreementBucket.completed;
      case 'ACTION_REQUIRED':
        return AgreementBucket.actionRequired;
      default:
        // An unrecognised bucket must not silently hide an agreement that
        // still needs signing, so fall back to the actionable side.
        return AgreementBucket.actionRequired;
    }
  }
}

/// Where an executed agreement's rent has got to, from the backend's
/// `rent_payment` block. Saves the payments screen from cross-referencing two
/// lists to work out whether rent is still owed.
enum RentPaymentStatus {
  notDue,
  due,
  inEscrow,
  paid,
  failed,
  unknown;

  static RentPaymentStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'NOT_DUE':
        return RentPaymentStatus.notDue;
      case 'DUE':
        return RentPaymentStatus.due;
      case 'IN_ESCROW':
        return RentPaymentStatus.inEscrow;
      case 'PAID':
        return RentPaymentStatus.paid;
      case 'FAILED':
        return RentPaymentStatus.failed;
      default:
        return RentPaymentStatus.unknown;
    }
  }
}

/// The backend's `rent_payment` block on an agreement.
class RentPayment {
  final RentPaymentStatus status;
  final String amount;
  final String platformFee;
  final String totalAmount;
  final String? paymentId;

  const RentPayment({
    required this.status,
    this.amount = '0.00',
    this.platformFee = '0.00',
    this.totalAmount = '0.00',
    this.paymentId,
  });

  factory RentPayment.fromJson(Map<String, dynamic> json) => RentPayment(
    status: RentPaymentStatus.fromString(json['status']?.toString()),
    amount: json['amount']?.toString() ?? '0.00',
    platformFee: json['platform_fee']?.toString() ?? '0.00',
    totalAmount: json['total_amount']?.toString() ?? '0.00',
    paymentId: json['payment_id']?.toString(),
  );

  /// Rent is owed and nothing has been started yet.
  bool get isDue => status == RentPaymentStatus.due;
}

/// How often rent falls due on an agreement.
///
/// Nigerian tenancies are overwhelmingly paid a year up front, but shorter
/// cycles are common enough, and are what a tenant saving in the vault
/// actually wants, that the plan is part of the agreement rather than
/// assumed.
enum RentPlan {
  annual,
  sixMonthly,
  quarterly,
  monthly,
  weekly,
  unknown;

  /// The plans a landlord may choose when writing an agreement, in the order
  /// a Nigerian tenancy is most likely to use them. [unknown] is deliberately
  /// absent: it exists only to absorb a value the backend adds later.
  static const List<RentPlan> selectable = [
    RentPlan.annual,
    RentPlan.sixMonthly,
    RentPlan.quarterly,
    RentPlan.monthly,
    RentPlan.weekly,
  ];

  /// The backend's default when an agreement is created without a plan.
  static const RentPlan fallback = RentPlan.annual;

  /// Reads a plan from the backend, accepting the documented creation aliases
  /// alongside the canonical values: an agreement written with `YEARLY` can
  /// come back either way, and both mean the same tenancy.
  static RentPlan fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'ANNUAL':
      case 'YEARLY':
        return RentPlan.annual;
      case 'SIX_MONTHLY':
      case 'BIANNUAL':
        return RentPlan.sixMonthly;
      case 'QUARTERLY':
      case 'THREE_MONTHLY':
        return RentPlan.quarterly;
      case 'MONTHLY':
        return RentPlan.monthly;
      case 'WEEKLY':
        return RentPlan.weekly;
      default:
        return RentPlan.unknown;
    }
  }

  /// The canonical value to send when creating an agreement.
  ///
  /// Always the canonical name, never an alias: the aliases exist so the
  /// backend can accept other callers' vocabulary, not so this app should
  /// invent its own. [unknown] sends nothing, letting the backend apply its
  /// own default rather than having one guessed here.
  String? get apiValue {
    switch (this) {
      case RentPlan.annual:
        return 'ANNUAL';
      case RentPlan.sixMonthly:
        return 'SIX_MONTHLY';
      case RentPlan.quarterly:
        return 'QUARTERLY';
      case RentPlan.monthly:
        return 'MONTHLY';
      case RentPlan.weekly:
        return 'WEEKLY';
      case RentPlan.unknown:
        return null;
    }
  }

  String get label {
    switch (this) {
      case RentPlan.annual:
        return 'Yearly';
      case RentPlan.sixMonthly:
        return 'Every 6 months';
      case RentPlan.quarterly:
        return 'Every 3 months';
      case RentPlan.monthly:
        return 'Monthly';
      case RentPlan.weekly:
        return 'Weekly';
      case RentPlan.unknown:
        return 'Rent';
    }
  }

  /// How the plan divides a year's rent, for the landlord choosing one.
  ///
  /// The instalment count a tenant actually owes comes from the backend's
  /// `instalments_total`; this is only the shape of the choice being made.
  String get description {
    switch (this) {
      case RentPlan.annual:
        return 'One payment for the year';
      case RentPlan.sixMonthly:
        return "The year's rent in 2 payments";
      case RentPlan.quarterly:
        return "The year's rent in 4 payments";
      case RentPlan.monthly:
        return "The year's rent in 12 payments";
      case RentPlan.weekly:
        return "The year's rent in weekly payments";
      case RentPlan.unknown:
        return '';
    }
  }
}

/// When rent next falls due on an executed agreement, from the backend's
/// `rent_schedule` block.
///
/// This is what the tenant dashboard shows once there is nothing left to
/// sign: an agreement that is fully executed stops being a task and becomes a
/// bill with a date on it.
///
/// Every date here is the backend's. The app never invents a due date: a
/// wrong one either panics a tenant who has months left or, worse, reassures
/// one who is about to be late.
class RentSchedule {
  final RentPlan plan;

  /// ISO date (`2026-11-01`) the next instalment is due. Null when nothing
  /// more is owed on this agreement.
  final String? nextDueDate;

  /// What that instalment costs, including any platform fee.
  final String nextAmountDue;

  /// Backend-computed days until [nextDueDate]. Negative when overdue. Null
  /// on payloads that omit it, in which case [daysUntilDue] works it out from
  /// the date itself.
  final int? serverDaysUntilDue;

  final bool isOverdue;

  /// Progress through the term, e.g. 1 of 2 for a six-month plan.
  final int instalmentsPaid;
  final int instalmentsTotal;

  const RentSchedule({
    this.plan = RentPlan.unknown,
    this.nextDueDate,
    this.nextAmountDue = '0.00',
    this.serverDaysUntilDue,
    this.isOverdue = false,
    this.instalmentsPaid = 0,
    this.instalmentsTotal = 0,
  });

  factory RentSchedule.fromJson(Map<String, dynamic> json) => RentSchedule(
    plan: RentPlan.fromString(json['plan']?.toString()),
    nextDueDate: json['next_due_date']?.toString(),
    nextAmountDue: json['next_amount_due']?.toString() ?? '0.00',
    serverDaysUntilDue: json['days_until_due'] is num
        ? (json['days_until_due'] as num).toInt()
        : int.tryParse(json['days_until_due']?.toString() ?? ''),
    isOverdue: json['is_overdue'] == true,
    instalmentsPaid: (json['instalments_paid'] as num?)?.toInt() ?? 0,
    instalmentsTotal: (json['instalments_total'] as num?)?.toInt() ?? 0,
  );

  /// Days until rent is due; negative once it is late, null when unknown.
  ///
  /// Prefers the backend's own count: it knows the tenancy's timezone and
  /// what counts as a day, and falls back to the date only so a payload that
  /// predates the field still renders.
  int? get daysUntilDue {
    final fromServer = serverDaysUntilDue;
    if (fromServer != null) return fromServer;

    final due = dueDate;
    if (due == null) return null;
    final today = DateTime.now();
    return DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  DateTime? get dueDate {
    final raw = nextDueDate;
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Something is owed on this agreement, now or later.
  bool get hasUpcomingPayment => dueDate != null || isOverdue;

  /// Payable now, rather than a date to plan for. The backend's `is_overdue`
  /// wins; the day count is the fallback.
  bool get isDueNow => isOverdue || (daysUntilDue ?? 1) <= 0;

  /// Close enough that the tenant should be acting rather than planning.
  ///
  /// Thirty days, matching the point in the backend's reminder ladder where
  /// the messages stop being "start saving" and start being "this is due".
  /// The earlier milestones (six months out, three months out) are runway,
  /// and the card shows those as a plain date rather than a warning.
  bool get isDueSoon {
    final days = daysUntilDue;
    return days != null && days > 0 && days <= 30;
  }
}

class TenancyAgreementModel {
  final String id;
  final String unit;
  final String unitNumber;
  final PropertyModel? property;
  final String landlord;
  final String landlordEmail;
  final String tenant;
  final String tenantEmail;
  final String rentAmount;
  final String startDate;
  final String endDate;
  final String rules;
  final String agreementText;
  final AgreementStatus status;
  final String agreementContentHash;
  final String tenantSignatureHash;
  final String landlordSignatureHash;
  final String? tenantSignedAt;
  final String? landlordSignedAt;
  final String? activatedAt;
  final String? executedAt;
  final bool payRentUnlocked;
  final String createdAt;

  /// The backend's `is_fully_signed`. Null on payloads that predate it, in
  /// which case [isFullySigned] falls back to the signature hashes.
  final bool? serverFullySigned;

  /// Whose signature the agreement is waiting on: `"TENANT"`, `"LANDLORD"`,
  /// or null when nothing is outstanding. Server-computed, so the card's call
  /// to action does not have to be derived from signature hashes.
  final String? awaitingSignatureFrom;

  /// When the agreement became fully signed. Null until then.
  final String? signedAt;

  /// Rent standing for an executed agreement. Null on payloads that predate
  /// the field, in which case the payments screen falls back to comparing the
  /// agreement against the payment list.
  final RentPayment? rentPayment;

  /// When rent next falls due, and on what cycle. Null on payloads that
  /// predate the field and on agreements nobody has executed yet.
  final RentSchedule? rentSchedule;

  /// The agreement's own `rent_plan`, which is set the moment the agreement is
  /// written.
  ///
  /// Separate from the schedule's `plan` because the schedule does not exist
  /// until the agreement is payable, so this is the only way to tell a tenant
  /// reviewing an unsigned agreement what cycle they are being asked to sign
  /// up to. [plan] prefers whichever of the two is actually known.
  final RentPlan rentPlan;

  /// `bucket` as computed by the backend, once it starts sending one.
  /// Null against the current API: [bucket] then works it out locally from
  /// the status and signature data, which produces the same answer.
  final AgreementBucket? serverBucket;

  TenancyAgreementModel({
    required this.id,
    required this.unit,
    required this.unitNumber,
    this.property,
    required this.landlord,
    required this.landlordEmail,
    required this.tenant,
    required this.tenantEmail,
    required this.rentAmount,
    required this.startDate,
    required this.endDate,
    required this.rules,
    required this.agreementText,
    required this.status,
    required this.agreementContentHash,
    required this.tenantSignatureHash,
    required this.landlordSignatureHash,
    this.tenantSignedAt,
    this.landlordSignedAt,
    this.activatedAt,
    this.executedAt,
    required this.payRentUnlocked,
    required this.createdAt,
    this.serverBucket,
    this.serverFullySigned,
    this.awaitingSignatureFrom,
    this.signedAt,
    this.rentPayment,
    this.rentSchedule,
    this.rentPlan = RentPlan.unknown,
  });

  factory TenancyAgreementModel.fromJson(Map<String, dynamic> json) {
    return TenancyAgreementModel(
      id: json['id']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      unitNumber: json['unit_number']?.toString() ?? '',
      property:
          json['property'] != null && json['property'] is Map<String, dynamic>
          ? PropertyModel.fromJson(json['property'])
          : null,
      landlord: json['landlord']?.toString() ?? '',
      landlordEmail: json['landlord_email']?.toString() ?? '',
      tenant: json['tenant']?.toString() ?? '',
      tenantEmail: json['tenant_email']?.toString() ?? '',
      rentAmount: json['rent_amount']?.toString() ?? '0.00',
      startDate: json['start_date']?.toString() ?? '',
      endDate: json['end_date']?.toString() ?? '',
      rules: json['rules']?.toString() ?? '',
      agreementText: json['agreement_text']?.toString() ?? '',
      status: AgreementStatus.fromString(json['status']),
      agreementContentHash: json['agreement_content_hash']?.toString() ?? '',
      tenantSignatureHash: json['tenant_signature_hash']?.toString() ?? '',
      landlordSignatureHash: json['landlord_signature_hash']?.toString() ?? '',
      tenantSignedAt: json['tenant_signed_at']?.toString(),
      landlordSignedAt: json['landlord_signed_at']?.toString(),
      activatedAt: json['activated_at']?.toString(),
      executedAt: json['executed_at']?.toString(),
      payRentUnlocked: json['pay_rent_unlocked'] ?? false,
      createdAt: json['created_at']?.toString() ?? '',
      serverBucket: json['bucket'] == null
          ? null
          : AgreementBucket.fromString(json['bucket']?.toString()),
      serverFullySigned: json['is_fully_signed'] is bool
          ? json['is_fully_signed'] as bool
          : null,
      awaitingSignatureFrom: json['awaiting_signature_from']?.toString(),
      signedAt: json['signed_at']?.toString(),
      rentPayment: json['rent_payment'] is Map<String, dynamic>
          ? RentPayment.fromJson(json['rent_payment'])
          : null,
      rentSchedule: json['rent_schedule'] is Map<String, dynamic>
          ? RentSchedule.fromJson(json['rent_schedule'])
          : null,
      rentPlan: RentPlan.fromString(json['rent_plan']?.toString()),
    );
  }

  /// A tenant-signed PRD agreement remains PENDING. The signature data, not
  /// a legacy display status, determines whether the landlord may
  /// counter-sign. In particular, `TENANT_SIGNED` is not enough evidence to
  /// send a landlord signing request: the current backend validates the
  /// signature fields themselves.
  bool get hasTenantSigned =>
      tenantSignatureHash.trim().isNotEmpty ||
      (tenantSignedAt?.trim().isNotEmpty ?? false);

  bool get hasLandlordSigned =>
      landlordSignatureHash.trim().isNotEmpty ||
      (landlordSignedAt?.trim().isNotEmpty ?? false);

  bool get isExecuted => status == AgreementStatus.executed;

  bool get awaitingLandlordSignature => hasTenantSigned && !isExecuted;

  /// Treat a legacy `TENANT_SIGNED` value without matching signature data as
  /// pending. This lets the tenant complete a signing attempt that the
  /// backend did not persist instead of leaving both parties stuck.
  bool get canTenantSign =>
      (status == AgreementStatus.pending ||
          status == AgreementStatus.tenantSigned) &&
      !hasTenantSigned;

  bool get canLandlordSign =>
      status == AgreementStatus.pending && hasTenantSigned && !isExecuted;

  /// The PRD requires both the executed state and the explicit backend lock
  /// flag before the tenant can create a payment.
  bool get canPayRent => isExecuted && payRentUnlocked;

  /// The tenancy is signed by both parties but no rent has ever been paid on
  /// it, and rent is owed *now*.
  ///
  /// Landa's whole promise is that rent goes through escrow, and testers
  /// found the gap in it: sign the agreement and the flat is yours, on the
  /// app's own screens, before a naira has moved. The backend marks a unit
  /// occupied when the application is approved and executes the agreement on
  /// the landlord's counter-signature; neither step asks about money.
  ///
  /// Closing that properly is a backend rule — see
  /// `backend docs/backend_change_spec_v14.md` §2, which is where occupancy
  /// has to stop being granted on a signature alone. What the app can do
  /// meanwhile is stop *saying* the tenancy is live: a tenant who has signed
  /// and not paid sees the first rent as the outstanding step, and the
  /// landlord sees the unit as reserved rather than occupied.
  ///
  /// Deliberately conservative, because a false positive here accuses a
  /// paid-up tenant of owing money:
  ///
  /// * anything paid on the tenancy already (`instalments_paid > 0`, or a
  ///   payment in escrow) clears it for good;
  /// * `NOT_DUE`, and a payload with no `rent_payment` block at all, clear it
  ///   too. That is the case for a tenancy the landlord imported with rent
  ///   already collected off-platform, which is a normal way to arrive on
  ///   Landa and must not be branded unpaid.
  ///
  /// So it fires only when the backend itself says rent is owed and nothing
  /// has been paid.
  bool get awaitingFirstRent {
    if (!isExecuted) return false;
    if ((rentSchedule?.instalmentsPaid ?? 0) > 0) return false;
    final status = rentPayment?.status;
    if (status == null) return false;
    return status == RentPaymentStatus.due ||
        status == RentPaymentStatus.failed;
  }

  /// True once both parties' signatures are recorded.
  ///
  /// Prefers the backend's own verdict, which also accounts for legacy records
  /// whose signature hashes were never persisted.
  bool get isFullySigned =>
      serverFullySigned ?? (hasTenantSigned && hasLandlordSigned);

  /// Rent is owed on this agreement and no payment has been started.
  ///
  /// Uses the backend's `rent_payment` block when present. Without it the
  /// caller has to compare against the payment list itself, which is why this
  /// returns null rather than false: "unknown" and "not due" are different.
  bool? get isRentDue => rentPayment?.isDue;

  /// What the tenant owes next on this agreement, or null when there is
  /// nothing to show.
  ///
  /// Falls back to the end of the term when the backend has not sent a
  /// schedule: an executed annual tenancy does have a next rent date, and it
  /// is the day the current term runs out. The fallback carries no plan and
  /// no instalment counts, because those would be guesses: only the date and
  /// the amount are things we actually know.
  RentSchedule? get upcomingRent {
    final fromServer = rentSchedule;
    if (fromServer != null) {
      return fromServer.hasUpcomingPayment ? fromServer : null;
    }
    if (!isExecuted) return null;

    // Rent that is owed right now outranks any date: the tenant can pay it
    // today, whatever the term dates say.
    if (isRentDue == true) {
      return RentSchedule(
        plan: plan,
        nextAmountDue: _fallbackAmountDue,
        isOverdue: true,
      );
    }
    if (endDate.trim().isEmpty) return null;
    return RentSchedule(
      plan: plan,
      nextDueDate: endDate,
      nextAmountDue: _fallbackAmountDue,
    );
  }

  /// What to quote when the backend sent no schedule of its own.
  ///
  /// The real `next_amount_due` includes the platform fee, so this matches it
  /// with the fee-inclusive total wherever the agreement carries one. Quoting
  /// the bare rent instead would understate every bill by 5%, and on the
  /// payments screen, where the vault balance is checked against this figure,
  /// it would offer a payment that is then declined.
  ///
  /// A non-annual plan's instalment is smaller than this, but with no schedule
  /// there is nothing to divide it by that would not be a guess.
  String get _fallbackAmountDue => rentPayment?.totalAmount ?? rentAmount;

  /// The rent cycle, from whichever source knows it.
  ///
  /// The schedule is authoritative once it exists; before execution the
  /// agreement's own `rent_plan` is all there is.
  RentPlan get plan {
    final scheduled = rentSchedule?.plan ?? RentPlan.unknown;
    if (scheduled != RentPlan.unknown) return scheduled;
    return rentPlan;
  }

  /// Where this agreement belongs: the dashboard or the profile.
  ///
  /// Prefers the backend's own `bucket` when present so the two stay in step
  /// once the API starts sending it.
  AgreementBucket get bucket {
    final fromServer = serverBucket;
    if (fromServer != null) return fromServer;

    switch (status) {
      case AgreementStatus.executed:
      case AgreementStatus.expired:
      case AgreementStatus.voided:
      // Legacy synonym for executed.
      case AgreementStatus.activated:
        return AgreementBucket.completed;
      case AgreementStatus.draft:
      case AgreementStatus.pending:
      case AgreementStatus.sent:
      case AgreementStatus.tenantSigned:
        return AgreementBucket.actionRequired;
    }
  }

  /// Still needs a signature from someone, so it stays on the dashboard.
  bool get needsSignature => bucket == AgreementBucket.actionRequired;

  /// Done with signing: a record, not a task.
  bool get isCompleted => bucket == AgreementBucket.completed;

  String get progressTitle {
    if (isExecuted) return 'Agreement Executed';
    if (awaitingLandlordSignature) return 'Awaiting Landlord Signature';
    // Some older staging records retained TENANT_SIGNED after a failed or
    // incomplete tenant-signing attempt. Without signature evidence, present
    // the actionable state rather than inviting the landlord to counter-sign.
    if (canTenantSign) return 'Awaiting Tenant Signature';
    return status.userFriendlyTitle;
  }
}
