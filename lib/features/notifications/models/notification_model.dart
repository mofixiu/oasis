import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Notification categories emitted by the backend.
///
/// [unknown] keeps the list resilient: a type added on the backend before the
/// app ships still renders with sensible defaults instead of crashing or
/// being silently hidden.
enum NotificationType {
  agreementReceived,
  agreementSigned,
  agreementExecuted,
  paymentInitiated,
  paymentRecorded,
  escrowDisputed,
  escrowReleased,
  unknown;

  static NotificationType fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'AGREEMENT_RECEIVED':
        return NotificationType.agreementReceived;
      case 'AGREEMENT_SIGNED':
        return NotificationType.agreementSigned;
      case 'AGREEMENT_EXECUTED':
        return NotificationType.agreementExecuted;
      case 'PAYMENT_INITIATED':
        return NotificationType.paymentInitiated;
      case 'PAYMENT_RECORDED':
        return NotificationType.paymentRecorded;
      case 'ESCROW_DISPUTED':
        return NotificationType.escrowDisputed;
      case 'ESCROW_RELEASED':
        return NotificationType.escrowReleased;
      default:
        return NotificationType.unknown;
    }
  }

  /// Wire value used for the `?type=` query filter.
  String? get queryValue {
    switch (this) {
      case NotificationType.agreementReceived:
        return 'AGREEMENT_RECEIVED';
      case NotificationType.agreementSigned:
        return 'AGREEMENT_SIGNED';
      case NotificationType.agreementExecuted:
        return 'AGREEMENT_EXECUTED';
      case NotificationType.paymentInitiated:
        return 'PAYMENT_INITIATED';
      case NotificationType.paymentRecorded:
        return 'PAYMENT_RECORDED';
      case NotificationType.escrowDisputed:
        return 'ESCROW_DISPUTED';
      case NotificationType.escrowReleased:
        return 'ESCROW_RELEASED';
      case NotificationType.unknown:
        return null;
    }
  }

  String get label {
    switch (this) {
      case NotificationType.agreementReceived:
        return 'Agreement received';
      case NotificationType.agreementSigned:
        return 'Agreement signed';
      case NotificationType.agreementExecuted:
        return 'Agreement executed';
      case NotificationType.paymentInitiated:
        return 'Payment started';
      case NotificationType.paymentRecorded:
        return 'Payment recorded';
      case NotificationType.escrowDisputed:
        return 'Dispute raised';
      case NotificationType.escrowReleased:
        return 'Escrow released';
      case NotificationType.unknown:
        return 'Update';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationType.agreementReceived:
        return Icons.mark_email_unread_outlined;
      case NotificationType.agreementSigned:
        return Icons.draw_outlined;
      case NotificationType.agreementExecuted:
        return Icons.verified_outlined;
      case NotificationType.paymentInitiated:
        return Icons.hourglass_top_outlined;
      case NotificationType.paymentRecorded:
        return Icons.payments_outlined;
      case NotificationType.escrowDisputed:
        return Icons.gavel_outlined;
      case NotificationType.escrowReleased:
        return Icons.lock_open_outlined;
      case NotificationType.unknown:
        return Icons.notifications_outlined;
    }
  }

  Color get accentColor {
    switch (this) {
      case NotificationType.agreementExecuted:
      case NotificationType.paymentRecorded:
      case NotificationType.escrowReleased:
        return AppTheme.successColor;
      case NotificationType.escrowDisputed:
        return AppTheme.disputeColor;
      case NotificationType.agreementReceived:
      case NotificationType.agreementSigned:
      case NotificationType.paymentInitiated:
      case NotificationType.unknown:
        return AppTheme.primaryColor;
    }
  }

  Color get surfaceColor {
    switch (this) {
      case NotificationType.agreementExecuted:
      case NotificationType.paymentRecorded:
      case NotificationType.escrowReleased:
        return AppTheme.successSurfaceColor;
      case NotificationType.escrowDisputed:
        return AppTheme.disputeSurfaceColor;
      case NotificationType.agreementReceived:
      case NotificationType.agreementSigned:
      case NotificationType.paymentInitiated:
      case NotificationType.unknown:
        return AppTheme.vacantSurfaceColor;
    }
  }
}

class NotificationItemModel {
  final String id;
  final String notificationType;
  final String message;
  final bool isRead;
  final String createdAt;

  NotificationItemModel({
    required this.id,
    required this.notificationType,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  NotificationType get type => NotificationType.fromString(notificationType);

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    return NotificationItemModel(
      id: json['id'] ?? '',
      notificationType: json['notification_type'] ?? '',
      message: json['message'] ?? '',
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }
}
