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
  landlordBroadcast,
  messageReceived,
  vaultCredited,
  vaultTopUpSucceeded,
  vaultTopUpFailed,
  withdrawalPaid,
  withdrawalFailed,

  // Short lets. A booking request and its decision are the shortlet
  // equivalent of an agreement arriving and being signed, so they get their
  // own types rather than being folded into the rental ones.
  shortLetBookingRequested,
  shortLetBookingApproved,
  shortLetBookingRejected,
  shortLetBookingCancelled,
  shortLetPaymentInitiated,
  shortLetPaymentRecorded,

  /// A guest or host sent a message on a paid stay's thread.
  shortLetMessageReceived,

  /// A host opened a caution-fee claim, or a guest answered one.
  shortLetCautionFeeClaim,

  // Artisan Fix used to raise seven types, one per handover in a repair:
  // requested, accepted, declined, quoted, paid, recorded, completed. API
  // guide 18 removed the workflow and the notifications with it (§7B). Fix
  // is a directory now; nothing about an artisan happens *to* anybody, so
  // there is nothing to announce.

  // Rent reminders. Three separate types rather than one with a payload
  // flag, so the list can colour and sort them differently: "due in 30
  // days" and "you are late" are not the same message.
  rentDueSoon,
  rentDue,
  rentOverdue,

  // The 72-hour window between a tenancy being signed and its first rent
  // reaching escrow (API guide 19 §1). Separate from the rent reminders
  // above because the stake is different: miss one of those and you are
  // late, miss this one and the backend voids the agreement and puts the
  // flat back on the market.
  firstRentReminder,
  tenancyLapsed,

  // Price movement. Only ever sent on a *drop*, and only to people with a
  // live interest: an applicant on that unit, a guest with a booking on
  // that stay. A rise is not news anybody wants pushed at them.
  unitPriceChanged,
  shortLetPriceChanged,

  /// A pending booking was re-priced at the moment the host approved it,
  /// because the listing's nightly price had moved since the request. Its own
  /// type rather than an approval, because the guest is being told a number
  /// changed and needs to look before they pay.
  shortLetBookingRepriced,

  // Identity verification finishing. Until these existed the app had to poll
  // `GET /verify/status/` to find out, which meant a user could sit on the
  // verification screen for minutes after being cleared.
  verificationSucceeded,
  verificationFailed,

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
      case 'LANDLORD_BROADCAST':
        return NotificationType.landlordBroadcast;
      case 'MESSAGE_RECEIVED':
        return NotificationType.messageReceived;
      case 'VAULT_CREDITED':
        return NotificationType.vaultCredited;
      case 'VAULT_TOPUP_SUCCEEDED':
        return NotificationType.vaultTopUpSucceeded;
      case 'VAULT_TOPUP_FAILED':
        return NotificationType.vaultTopUpFailed;
      case 'RENT_DUE_SOON':
        return NotificationType.rentDueSoon;
      case 'RENT_DUE':
        return NotificationType.rentDue;
      case 'RENT_OVERDUE':
        return NotificationType.rentOverdue;
      case 'FIRST_RENT_REMINDER':
        return NotificationType.firstRentReminder;
      case 'TENANCY_LAPSED':
        return NotificationType.tenancyLapsed;
      case 'WITHDRAWAL_PAID':
        return NotificationType.withdrawalPaid;
      case 'WITHDRAWAL_FAILED':
        return NotificationType.withdrawalFailed;
      case 'SHORT_LET_BOOKING_REQUESTED':
        return NotificationType.shortLetBookingRequested;
      case 'SHORT_LET_BOOKING_APPROVED':
        return NotificationType.shortLetBookingApproved;
      case 'SHORT_LET_BOOKING_REJECTED':
        return NotificationType.shortLetBookingRejected;
      case 'SHORT_LET_BOOKING_CANCELLED':
        return NotificationType.shortLetBookingCancelled;
      case 'SHORT_LET_PAYMENT_INITIATED':
        return NotificationType.shortLetPaymentInitiated;
      case 'SHORT_LET_PAYMENT_RECORDED':
        return NotificationType.shortLetPaymentRecorded;
      case 'SHORT_LET_MESSAGE_RECEIVED':
        return NotificationType.shortLetMessageReceived;
      case 'SHORT_LET_CAUTION_FEE_CLAIM':
        return NotificationType.shortLetCautionFeeClaim;
      case 'UNIT_PRICE_CHANGED':
        return NotificationType.unitPriceChanged;
      case 'SHORT_LET_PRICE_CHANGED':
        return NotificationType.shortLetPriceChanged;
      case 'SHORT_LET_BOOKING_REPRICED':
        return NotificationType.shortLetBookingRepriced;
      case 'VERIFICATION_SUCCEEDED':
        return NotificationType.verificationSucceeded;
      case 'VERIFICATION_FAILED':
        return NotificationType.verificationFailed;
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
      case NotificationType.landlordBroadcast:
        return 'LANDLORD_BROADCAST';
      case NotificationType.messageReceived:
        return 'MESSAGE_RECEIVED';
      case NotificationType.vaultCredited:
        return 'VAULT_CREDITED';
      case NotificationType.vaultTopUpSucceeded:
        return 'VAULT_TOPUP_SUCCEEDED';
      case NotificationType.vaultTopUpFailed:
        return 'VAULT_TOPUP_FAILED';
      case NotificationType.rentDueSoon:
        return 'RENT_DUE_SOON';
      case NotificationType.rentDue:
        return 'RENT_DUE';
      case NotificationType.rentOverdue:
        return 'RENT_OVERDUE';
      case NotificationType.firstRentReminder:
        return 'FIRST_RENT_REMINDER';
      case NotificationType.tenancyLapsed:
        return 'TENANCY_LAPSED';
      case NotificationType.withdrawalPaid:
        return 'WITHDRAWAL_PAID';
      case NotificationType.withdrawalFailed:
        return 'WITHDRAWAL_FAILED';
      case NotificationType.shortLetBookingRequested:
        return 'SHORT_LET_BOOKING_REQUESTED';
      case NotificationType.shortLetBookingApproved:
        return 'SHORT_LET_BOOKING_APPROVED';
      case NotificationType.shortLetBookingRejected:
        return 'SHORT_LET_BOOKING_REJECTED';
      case NotificationType.shortLetBookingCancelled:
        return 'SHORT_LET_BOOKING_CANCELLED';
      case NotificationType.shortLetPaymentInitiated:
        return 'SHORT_LET_PAYMENT_INITIATED';
      case NotificationType.shortLetPaymentRecorded:
        return 'SHORT_LET_PAYMENT_RECORDED';
      case NotificationType.shortLetMessageReceived:
        return 'SHORT_LET_MESSAGE_RECEIVED';
      case NotificationType.shortLetCautionFeeClaim:
        return 'SHORT_LET_CAUTION_FEE_CLAIM';
      case NotificationType.unitPriceChanged:
        return 'UNIT_PRICE_CHANGED';
      case NotificationType.shortLetPriceChanged:
        return 'SHORT_LET_PRICE_CHANGED';
      case NotificationType.shortLetBookingRepriced:
        return 'SHORT_LET_BOOKING_REPRICED';
      case NotificationType.verificationSucceeded:
        return 'VERIFICATION_SUCCEEDED';
      case NotificationType.verificationFailed:
        return 'VERIFICATION_FAILED';
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
      case NotificationType.landlordBroadcast:
        return 'From your landlord';
      case NotificationType.messageReceived:
        return 'New message';
      case NotificationType.vaultCredited:
        return 'Money in your vault';
      case NotificationType.vaultTopUpSucceeded:
        return 'Vault topped up';
      case NotificationType.vaultTopUpFailed:
        return 'Top-up failed';
      case NotificationType.rentDueSoon:
        return 'Rent coming up';
      case NotificationType.rentDue:
        return 'Rent due';
      case NotificationType.rentOverdue:
        return 'Rent overdue';
      case NotificationType.firstRentReminder:
        return 'First rent still due';
      case NotificationType.tenancyLapsed:
        return 'Tenancy lapsed';
      case NotificationType.withdrawalPaid:
        return 'Withdrawal paid';
      case NotificationType.withdrawalFailed:
        return 'Withdrawal failed';
      case NotificationType.shortLetBookingRequested:
        return 'Booking request';
      case NotificationType.shortLetBookingApproved:
        return 'Booking approved';
      case NotificationType.shortLetBookingRejected:
        return 'Booking declined';
      case NotificationType.shortLetBookingCancelled:
        return 'Booking cancelled';
      case NotificationType.shortLetPaymentInitiated:
        return 'Booking payment started';
      case NotificationType.shortLetPaymentRecorded:
        return 'Booking paid';
      case NotificationType.shortLetMessageReceived:
        return 'New message';
      case NotificationType.shortLetCautionFeeClaim:
        return 'Caution fee claim';
      // "Price dropped" rather than "Price changed": the backend only sends
      // these on a drop, and naming the direction is the whole reason the
      // notification is worth reading.
      case NotificationType.unitPriceChanged:
        return 'Rent dropped';
      case NotificationType.shortLetPriceChanged:
        return 'Price dropped';
      case NotificationType.shortLetBookingRepriced:
        return 'Booking re-priced';
      case NotificationType.verificationSucceeded:
        return 'You are verified';
      case NotificationType.verificationFailed:
        return 'Verification failed';
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
      case NotificationType.landlordBroadcast:
        return Icons.campaign_outlined;
      case NotificationType.messageReceived:
        return Icons.forum_outlined;
      case NotificationType.vaultCredited:
        return Icons.account_balance_wallet_outlined;
      case NotificationType.vaultTopUpSucceeded:
        return Icons.savings_outlined;
      case NotificationType.vaultTopUpFailed:
        return Icons.credit_card_off_outlined;
      case NotificationType.rentDueSoon:
        return Icons.event_outlined;
      case NotificationType.rentDue:
        return Icons.event_available_outlined;
      case NotificationType.rentOverdue:
        return Icons.event_busy_outlined;
      case NotificationType.firstRentReminder:
        return Icons.lock_clock_outlined;
      case NotificationType.tenancyLapsed:
        return Icons.heart_broken_outlined;
      case NotificationType.withdrawalPaid:
        return Icons.north_east_rounded;
      case NotificationType.withdrawalFailed:
        return Icons.error_outline_rounded;
      case NotificationType.shortLetBookingRequested:
        return Icons.calendar_month_outlined;
      case NotificationType.shortLetBookingApproved:
        return Icons.event_available_outlined;
      case NotificationType.shortLetBookingRejected:
        return Icons.event_busy_outlined;
      case NotificationType.shortLetBookingCancelled:
        return Icons.free_cancellation_outlined;
      case NotificationType.shortLetPaymentInitiated:
        return Icons.hourglass_top_outlined;
      case NotificationType.shortLetPaymentRecorded:
        return Icons.luggage_outlined;
      case NotificationType.shortLetMessageReceived:
        return Icons.forum_outlined;
      case NotificationType.shortLetCautionFeeClaim:
        return Icons.shield_outlined;
      case NotificationType.unitPriceChanged:
      case NotificationType.shortLetPriceChanged:
        return Icons.trending_down_rounded;
      case NotificationType.shortLetBookingRepriced:
        return Icons.published_with_changes_rounded;
      case NotificationType.verificationSucceeded:
        return Icons.verified_user_outlined;
      case NotificationType.verificationFailed:
        return Icons.gpp_bad_outlined;
      case NotificationType.unknown:
        return Icons.notifications_outlined;
    }
  }

  Color get accentColor {
    switch (this) {
      case NotificationType.agreementExecuted:
      case NotificationType.paymentRecorded:
      case NotificationType.escrowReleased:
      case NotificationType.vaultCredited:
      case NotificationType.vaultTopUpSucceeded:
      case NotificationType.withdrawalPaid:
      case NotificationType.shortLetBookingApproved:
      case NotificationType.shortLetPaymentRecorded:
      // A price coming down is good news for whoever is being told, and
      // being verified is the moment the app becomes usable at all.
      case NotificationType.unitPriceChanged:
      case NotificationType.shortLetPriceChanged:
      case NotificationType.verificationSucceeded:
        return AppTheme.successColor;
      case NotificationType.escrowDisputed:
      case NotificationType.withdrawalFailed:
      case NotificationType.vaultTopUpFailed:
      case NotificationType.shortLetBookingRejected:
      // Being late costs a tenant their tenancy, so it reads as urgently as
      // a dispute rather than as another calendar note.
      case NotificationType.rentOverdue:
      // The tenancy is gone and the flat is back on the market. Nothing in
      // the app is more of a loss to the person being told.
      case NotificationType.tenancyLapsed:
      case NotificationType.verificationFailed:
        return AppTheme.disputeColor;
      case NotificationType.rentDueSoon:
      case NotificationType.rentDue:
      // Half the window is gone and the home is still losable.
      case NotificationType.firstRentReminder:
      // An approved booking expires 24 hours after approval, so a request
      // waiting on someone is genuinely time-limited.
      case NotificationType.shortLetBookingRequested:
        // Both of these are somebody waiting: an artisan on an answer, a tenant
        // on a price they have to accept before the work can start.
        return AppTheme.warningColor;
      case NotificationType.shortLetBookingCancelled:
      case NotificationType.shortLetPaymentInitiated:
      case NotificationType.agreementReceived:
      case NotificationType.agreementSigned:
      case NotificationType.paymentInitiated:
      case NotificationType.landlordBroadcast:
      case NotificationType.messageReceived:
      case NotificationType.shortLetMessageReceived:
      // A number the guest already saw has moved, and they pay next. It is
      // not a failure, but it is something to look at before paying.
      case NotificationType.shortLetBookingRepriced:
      case NotificationType.unknown:
        return AppTheme.primaryColor;
      // A claim has a response window and a payout paused behind it: the
      // same shape as a booking request waiting on a decision.
      case NotificationType.shortLetCautionFeeClaim:
        return AppTheme.warningColor;
    }
  }

  /// The tinted fill behind this type's icon.
  ///
  /// Takes a context because the tint is theme-aware: the light-mode pastels
  /// are unreadable under white icons in dark mode.
  Color surfaceColor(BuildContext context) {
    switch (this) {
      case NotificationType.agreementExecuted:
      case NotificationType.paymentRecorded:
      case NotificationType.escrowReleased:
      case NotificationType.vaultCredited:
      case NotificationType.vaultTopUpSucceeded:
      case NotificationType.withdrawalPaid:
      case NotificationType.shortLetBookingApproved:
      case NotificationType.shortLetPaymentRecorded:
      case NotificationType.unitPriceChanged:
      case NotificationType.shortLetPriceChanged:
      case NotificationType.verificationSucceeded:
        return AppTheme.successSurface(context);
      case NotificationType.escrowDisputed:
      case NotificationType.withdrawalFailed:
      case NotificationType.vaultTopUpFailed:
      case NotificationType.tenancyLapsed:
      case NotificationType.rentOverdue:
      case NotificationType.shortLetBookingRejected:
      case NotificationType.verificationFailed:
        return AppTheme.disputeSurface(context);
      case NotificationType.rentDueSoon:
      case NotificationType.rentDue:
      case NotificationType.firstRentReminder:
      case NotificationType.shortLetBookingRequested:
      case NotificationType.shortLetBookingCancelled:
      case NotificationType.shortLetPaymentInitiated:
      case NotificationType.agreementReceived:
      case NotificationType.agreementSigned:
      case NotificationType.paymentInitiated:
      case NotificationType.landlordBroadcast:
      case NotificationType.messageReceived:
      case NotificationType.shortLetMessageReceived:
      case NotificationType.shortLetCautionFeeClaim:
      case NotificationType.shortLetBookingRepriced:
      case NotificationType.unknown:
        return AppTheme.vacantSurface(context);
    }
  }
}

class NotificationItemModel {
  final String id;
  final String notificationType;
  final String message;
  final bool isRead;
  final String createdAt;

  /// Heading, when the backend sends one. A broadcast has a subject of its
  /// own ("Water supply maintenance"); older notification types do not, and
  /// fall back to the type's label.
  final String? title;

  /// Who caused it, when a person did. Null for system events.
  final String? actorName;

  /// Deep-link payload: ids the app can act on, keyed by notification type.
  /// Unknown or missing keys are absent, never an error.
  final Map<String, dynamic> data;

  NotificationItemModel({
    required this.id,
    required this.notificationType,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.title,
    this.actorName,
    this.data = const {},
  });

  /// The same notification, read.
  ///
  /// For the moment between tapping a row and the server confirming it: the
  /// badge and the row have to change immediately, and the controller needs
  /// the original back if the request fails.
  NotificationItemModel copyWithRead() => NotificationItemModel(
    id: id,
    notificationType: notificationType,
    message: message,
    isRead: true,
    createdAt: createdAt,
    title: title,
    actorName: actorName,
    data: data,
  );

  NotificationType get type => NotificationType.fromString(notificationType);

  /// What to show as the row's heading.
  String get headline {
    final given = title?.trim();
    return given == null || given.isEmpty ? type.label : given;
  }

  /// The conversation this notification points at, if any.
  String? get conversationId => data['conversation_id']?.toString();

  /// The unit a broadcast was about, used to offer "Message landlord".
  String? get unitId => data['unit_id']?.toString();

  /// The agreement a rent reminder is about, so the row can take the tenant
  /// straight to the bill rather than to a list to hunt through.
  String? get agreementId => data['agreement_id']?.toString();

  /// When rent falls due, on a reminder. ISO date; null on every other type.
  String? get rentDueDate => data['due_date']?.toString();

  /// The short-let booking a caution-fee-claim or stay-message notification
  /// is about.
  String? get shortLetBookingId =>
      (data['booking_id'] ?? data['short_let_booking_id'])?.toString();

  /// The claim a [NotificationType.shortLetCautionFeeClaim] notification is
  /// about: what the tenant needs to respond to it. There is no endpoint to
  /// list open claims, so this id, arriving with the notification, is the
  /// only way the app ever learns one exists.
  String? get cautionClaimId => data['claim_id']?.toString();

  /// What the host is asking for, and why, carried on the same notification
  /// so the tenant can decide without a round trip.
  String? get cautionClaimAmount =>
      (data['claimed_amount'] ?? data['amount'])?.toString();
  String? get cautionClaimReason => data['reason']?.toString();

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    final payload = json['data'];
    return NotificationItemModel(
      id: json['id'] ?? '',
      notificationType: json['notification_type'] ?? '',
      message: json['message'] ?? '',
      isRead: json['is_read'] ?? false,
      createdAt: json['created_at'] ?? '',
      title: json['title']?.toString(),
      actorName: json['actor_name']?.toString(),
      data: payload is Map<String, dynamic> ? payload : const {},
    );
  }
}
