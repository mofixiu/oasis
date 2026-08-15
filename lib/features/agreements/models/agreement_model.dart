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
