import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';
import 'package:oasis_app/features/payments/models/payment_model.dart';
import 'package:oasis_app/features/payments/models/pending_rent.dart';

/// A tenant with two unpaid units was shown one pending payment. The backend
/// reported the second as `NOT_DUE`, its term starts next year, and letting
/// that verdict override "nothing has ever been paid on this" hid it.
///
/// Hiding a rent bill is the expensive failure here, so these pin that the two
/// signals are a union.
void main() {
  test('two unpaid units are two pending payments', () {
    final pending = pendingRentAgreements(
      agreements: [
        _agreement(id: 'a1', rentPaymentStatus: 'DUE'),
        // Term starts next year, so the backend has not scheduled it. Still a
        // unit with rent outstanding.
        _agreement(id: 'a2', rentPaymentStatus: 'NOT_DUE'),
      ],
      payments: const [],
      isLandlord: false,
    );

    expect(pending.map((a) => a.id), ['a1', 'a2']);
  });

  test('a unit that has been paid drops off', () {
    final pending = pendingRentAgreements(
      agreements: [
        _agreement(id: 'a1', rentPaymentStatus: 'PAID'),
        _agreement(id: 'a2', rentPaymentStatus: 'NOT_DUE'),
      ],
      payments: [_payment(agreement: 'a1', status: 'ESCROW')],
      isLandlord: false,
    );

    expect(pending.map((a) => a.id), ['a2']);
  });

  test('a failed payment leaves the rent still owed', () {
    // The money never moved, so the bill is still outstanding.
    final pending = pendingRentAgreements(
      agreements: [_agreement(id: 'a1', rentPaymentStatus: 'NOT_DUE')],
      payments: [_payment(agreement: 'a1', status: 'FAILED')],
      isLandlord: false,
    );

    expect(pending.map((a) => a.id), ['a1']);
  });

  test('the next instalment shows even though the first was paid', () {
    // A monthly plan: one payment exists, and the backend says more is owed.
    // The payment-record signal alone would hide this.
    final pending = pendingRentAgreements(
      agreements: [_agreement(id: 'a1', rentPaymentStatus: 'DUE')],
      payments: [_payment(agreement: 'a1', status: 'RELEASED')],
      isLandlord: false,
    );

    expect(pending.map((a) => a.id), ['a1']);
  });

  test('an unsigned agreement is not a bill', () {
    // Asking someone to pay for a tenancy that does not exist yet.
    final pending = pendingRentAgreements(
      agreements: [_agreement(id: 'a1', status: 'PENDING')],
      payments: const [],
      isLandlord: false,
    );

    expect(pending, isEmpty);
  });

  test('a landlord is never asked to pay rent on their own unit', () {
    final pending = pendingRentAgreements(
      agreements: [_agreement(id: 'a1', rentPaymentStatus: 'DUE')],
      payments: const [],
      isLandlord: true,
    );

    expect(pending, isEmpty);
  });
}

TenancyAgreementModel _agreement({
  required String id,
  String status = 'EXECUTED',
  String? rentPaymentStatus,
}) => TenancyAgreementModel.fromJson({
  'id': id,
  'unit': 'unit-$id',
  'unit_number': id.toUpperCase(),
  'rent_amount': '300000.00',
  'status': status,
  'pay_rent_unlocked': status == 'EXECUTED',
  if (rentPaymentStatus != null)
    'rent_payment': {
      'status': rentPaymentStatus,
      'amount': '300000.00',
      'total_amount': '315000.00',
    },
});

PaymentModel _payment({required String agreement, required String status}) =>
    PaymentModel.fromJson({
      'id': 'p-$agreement',
      'agreement': agreement,
      'amount': '300000.00',
      'total_amount': '315000.00',
      'status': status,
    });
