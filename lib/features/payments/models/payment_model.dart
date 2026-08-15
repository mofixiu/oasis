import '../../properties/models/property_model.dart';

enum PaymentStatus {
  pending,
  escrow,
  disputed,
  failed,
  released,
  refunded,
  unknown;

  static PaymentStatus fromString(String? status) {
    switch (status?.toUpperCase()) {
      case 'PENDING':
        return PaymentStatus.pending;
      case 'ESCROW':
        return PaymentStatus.escrow;
      case 'DISPUTED':
        return PaymentStatus.disputed;
      case 'FAILED':
        return PaymentStatus.failed;
      case 'RELEASED':
        return PaymentStatus.released;
      case 'REFUNDED':
        return PaymentStatus.refunded;
      default:
        // Never assume ESCROW for an unrecognised status: claiming money is
        // safely held when the backend said otherwise is the worst failure
        // mode here. Surface it as unknown instead.
        return PaymentStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case PaymentStatus.pending:
        return 'PENDING';
      case PaymentStatus.escrow:
        return 'ESCROW';
      case PaymentStatus.disputed:
        return 'DISPUTED';
      case PaymentStatus.failed:
        return 'FAILED';
      case PaymentStatus.released:
        return 'RELEASED';
      case PaymentStatus.refunded:
        return 'REFUNDED';
      case PaymentStatus.unknown:
        return 'UNKNOWN';
    }
  }

  String get userFriendlyTitle {
    switch (this) {
      case PaymentStatus.pending:
        return 'Awaiting Paystack Payment';
      case PaymentStatus.escrow:
        return 'In Escrow (48h Lock)';
      case PaymentStatus.disputed:
        return 'Disputed — Under Review';
      case PaymentStatus.failed:
        return 'Payment Failed';
      case PaymentStatus.released:
        return 'Escrow Released';
      case PaymentStatus.refunded:
        return 'Refunded';
      case PaymentStatus.unknown:
        return 'Status Unavailable';
    }
  }
}

class PaymentModel {
  final String id;
  final String agreement;
  final String agreementStatus;
  final String tenant;
  final String tenantEmail;
  final String? landlordEmail;
  final String amount;
  final String platformFee;
  final String totalAmount;
  final String reference;
  final String provider;
  final String providerReference;
  final String? authorizationUrl;
  final String? accessCode;
  final PaymentStatus status;
  final String paidAt;
  final String escrowReleaseAt;
  /// Backend-computed countdown to escrow release. Null when the backend did
  /// not supply it (e.g. list payloads); never derive it client-side.
  final int? escrowSecondsRemaining;
  final bool canDispute;
  final String? disputedAt;
  final String disputeReason;
  final bool isReadyForRelease;
  final String? releasedAt;
  final PropertyModel? property;
  final UnitModel? unit;

  PaymentModel({
    required this.id,
    required this.agreement,
    required this.agreementStatus,
    required this.tenant,
    required this.tenantEmail,
    this.landlordEmail,
    required this.amount,
    required this.platformFee,
    required this.totalAmount,
    required this.reference,
    required this.provider,
    required this.providerReference,
    this.authorizationUrl,
    this.accessCode,
    required this.status,
    required this.paidAt,
    required this.escrowReleaseAt,
    this.escrowSecondsRemaining,
    this.canDispute = false,
    this.disputedAt,
    this.disputeReason = '',
    required this.isReadyForRelease,
    this.releasedAt,
    this.property,
    this.unit,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] ?? '',
      agreement: json['agreement'] ?? '',
      agreementStatus: json['agreement_status'] ?? '',
      tenant: json['tenant'] ?? '',
      tenantEmail: json['tenant_email'] ?? '',
      landlordEmail: json['landlord_email'],
      amount: json['amount']?.toString() ?? '0.00',
      platformFee: json['platform_fee']?.toString() ?? '0.00',
      totalAmount:
          json['total_amount']?.toString() ??
          json['amount']?.toString() ??
          '0.00',
      reference: json['reference'] ?? '',
      provider: json['provider']?.toString() ?? '',
      providerReference:
          json['provider_reference']?.toString() ??
          json['reference']?.toString() ??
          '',
      authorizationUrl: json['authorization_url']?.toString(),
      accessCode: json['access_code']?.toString(),
      status: PaymentStatus.fromString(json['status']),
      paidAt: json['paid_at'] ?? '',
      escrowReleaseAt: json['escrow_release_at'] ?? '',
      escrowSecondsRemaining: json['escrow_seconds_remaining'] is num
          ? (json['escrow_seconds_remaining'] as num).toInt()
          : int.tryParse(json['escrow_seconds_remaining']?.toString() ?? ''),
      canDispute: json['can_dispute'] ?? false,
      disputedAt: json['disputed_at']?.toString(),
      disputeReason: json['dispute_reason']?.toString() ?? '',
      isReadyForRelease: json['is_ready_for_release'] ?? false,
      releasedAt: json['released_at'],
      property:
          json['property'] != null && json['property'] is Map<String, dynamic>
          ? PropertyModel.fromJson(json['property'])
          : null,
      unit: json['unit'] != null && json['unit'] is Map<String, dynamic>
          ? UnitModel.fromJson(json['unit'])
          : null,
    );
  }
}
