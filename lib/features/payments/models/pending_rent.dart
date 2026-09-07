import '../../agreements/models/agreement_model.dart';
import 'payment_model.dart';

/// Which tenancies still owe rent.
///
/// A union of two signals, never an override of one by the other:
///
/// - the backend's `rent_payment.status` on the agreement, which says rent is
///   owed *now*, which is what catches the second instalment of a monthly
///   plan once the first has been paid;
/// - the absence of any payment against the agreement, which says nothing has
///   been paid on it at all, which is what catches a tenancy the backend
///   has not scheduled yet.
///
/// Letting the first override the second is what hid a real unit: `NOT_DUE` on
/// a term starting next year is still a unit with rent outstanding, and the
/// tenant was shown one card when two were unpaid.
///
/// Taking either as sufficient can only ever show more, which is the safe
/// direction: an extra card is a nuisance, a missing one is unpaid rent.
/// Nothing already settled slips through: a non-failed payment removes the
/// second signal, and the backend supplies the first.
///
/// Tenants only. A landlord's own executed agreements also satisfy
/// `canPayRent`, and asking a landlord to pay rent on their own unit would be
/// nonsense.
List<TenancyAgreementModel> pendingRentAgreements({
  required List<TenancyAgreementModel> agreements,
  required List<PaymentModel> payments,
  required bool isLandlord,
}) {
  if (isLandlord) return const [];

  final startedAgreementIds = payments
      .where((p) => p.status != PaymentStatus.failed)
      .map((p) => p.agreement)
      .toSet();

  return agreements
      .where((a) => a.canPayRent)
      .where(
        (a) => (a.isRentDue ?? false) || !startedAgreementIds.contains(a.id),
      )
      .toList();
}
