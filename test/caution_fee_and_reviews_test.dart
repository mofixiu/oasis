import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/features/reviews/models/review_models.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';

/// Money and reputation: the two things it is worst to render slightly wrong.
///
/// A caution fee is optional for the host and compulsory for the guest, which
/// gives it three states the UI has to keep straight (none, held, returned)
/// and a "₦0 refundable deposit" line on a listing with no deposit reads as a
/// charge. A rating has a fourth state most star widgets get wrong: unrated,
/// which is not the same as nought stars.
void main() {
  group('caution fee', () {
    test('no deposit is no deposit, whatever shape the zero arrives in', () {
      // The backend has sent all three of these for "none" at various points.
      for (final zero in ['0.00', '0', '']) {
        final listing = ShortLetListing(id: 'l1', cautionFee: zero);
        expect(
          listing.hasCautionFee,
          isFalse,
          reason: 'cautionFee "$zero" should read as no deposit',
        );
      }
    });

    test('a quote adds the deposit to the nights', () {
      const listing = ShortLetListing(
        id: 'l1',
        nightlyPrice: '50000.00',
        cautionFee: '25000.00',
      );

      // Two nights of stay, plus the one-off deposit, not two deposits.
      expect(listing.totalFor(2), '100000.00');
      expect(listing.totalWithDepositFor(2), '125000.00');
    });

    test('a quote without a deposit is just the nights', () {
      const listing = ShortLetListing(id: 'l1', nightlyPrice: '50000.00');

      expect(listing.totalWithDepositFor(3), listing.totalFor(3));
    });

    test('a booking separates what is spent from what is held', () {
      const booking = ShortLetBooking(
        id: 'b1',
        totalAmount: '125000.00',
        cautionFee: '25000.00',
      );

      expect(booking.hasCautionFee, isTrue);
      // The number that answers "what is this stay costing me?".
      expect(booking.amountExcludingCautionFee, '100000.00');
      expect(booking.isCautionFeeRefunded, isFalse);
    });

    test('a returned deposit is distinguishable from a held one', () {
      const held = ShortLetBooking(id: 'b1', cautionFee: '25000.00');
      const returned = ShortLetBooking(
        id: 'b2',
        cautionFee: '25000.00',
        cautionFeeRefundedAt: '2026-09-05T10:00:00Z',
      );

      expect(held.isCautionFeeRefunded, isFalse);
      expect(returned.isCautionFeeRefunded, isTrue);
    });

    test('the deposit is read from the listing when the booking omits it', () {
      // Booking payloads nest the listing on some endpoints and flatten it on
      // others; a guest must see the deposit either way.
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'PAID',
        'listing': {'id': 'l1', 'caution_fee': '30000.00'},
      });

      expect(booking.cautionFee, '30000.00');
      expect(booking.hasCautionFee, isTrue);
    });
  });

  group('short-let cancellation policy', () {
    test(
      'a missing server field safely uses the platform flexible default',
      () {
        final listing = ShortLetListing.fromJson(const {'id': 'l1'});

        expect(listing.cancellationPolicy, ShortLetCancellationPolicy.flexible);
        expect(listing.resolvedCancellationPolicySummary, contains('24 hours'));
      },
    );

    test('the booking reads server-authoritative refund amounts', () {
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'PAID',
        'cancellation_policy': 'MODERATE',
        'accommodation_refund_amount': '47500.00',
        'platform_fee_refund_amount': '0.00',
        'caution_fee_refund_amount': '25000.00',
        'total_refund_amount': '72500.00',
      });

      expect(booking.cancellationPolicy, ShortLetCancellationPolicy.moderate);
      expect(booking.totalRefundAmount, '72500.00');
      expect(booking.hasRefundQuote, isTrue);
      expect(booking.canBeCancelledByTenant, isTrue);
    });
  });

  group('messaging and reviews on a stay', () {
    test('a thread only opens once the stay is paid for', () {
      const pending = ShortLetBooking(
        id: 'b1',
        status: ShortLetBookingStatus.pending,
      );
      const paid = ShortLetBooking(
        id: 'b2',
        status: ShortLetBookingStatus.paid,
      );

      // An unpaid request is not a relationship, and a channel to a host
      // before one exists is a channel to a stranger.
      expect(pending.canMessage, isFalse);
      expect(paid.canMessage, isTrue);
    });

    test('a review is only offered after checkout, and only once', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      final stayed = ShortLetBooking(
        id: 'b1',
        status: ShortLetBookingStatus.paid,
        checkOut: shortLetIsoDate(yesterday),
      );
      final upcoming = ShortLetBooking(
        id: 'b2',
        status: ShortLetBookingStatus.paid,
        checkOut: shortLetIsoDate(tomorrow),
      );
      final alreadyReviewed = ShortLetBooking(
        id: 'b3',
        status: ShortLetBookingStatus.paid,
        checkOut: shortLetIsoDate(yesterday),
        hasReview: true,
      );

      expect(stayed.canReview, isTrue);
      expect(upcoming.canReview, isFalse, reason: 'they have not been yet');
      expect(alreadyReviewed.canReview, isFalse);
    });
  });

  group('the escrow spellings', () {
    test('IN_ESCROW is a paid stay, not an unreadable one', () {
      // The live bug. Staging sends IN_ESCROW; the app only knew ESCROW, so a
      // stay that had actually been paid for rendered with no check-in notes,
      // no message button, no dashboard card and no way to raise a problem.
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'IN_ESCROW',
      });

      expect(booking.status, ShortLetBookingStatus.paid);
      expect(booking.status.isPaid, isTrue);
      expect(booking.canMessage, isTrue);
      expect(booking.status.isDisputable, isTrue);
    });

    test('both spellings land in the same place', () {
      for (final spelling in ['ESCROW', 'IN_ESCROW', 'PAID', 'CONFIRMED']) {
        expect(
          ShortLetBookingStatus.fromString(spelling),
          ShortLetBookingStatus.paid,
          reason: '"$spelling" means the money has moved',
        );
      }
    });

    test('a fully settled stay is paid but no longer disputable', () {
      // What the nightly release job leaves behind, or the legacy spelling
      // from before the 2026-09-03 payout update named its own CHECKED_OUT
      // status. Either way it has to count as paid, the guest stayed, but
      // there is no money left held, so offering "Report a problem" would be
      // offering a button the backend can only refuse.
      for (final spelling in ['RELEASED', 'COMPLETED']) {
        final status = ShortLetBookingStatus.fromString(spelling);
        expect(status, ShortLetBookingStatus.completed, reason: spelling);
        expect(status.isPaid, isTrue, reason: spelling);
        expect(status.isDisputable, isFalse, reason: spelling);
        // And not filed under "past and cancelled", where the guest could not
        // review it.
        expect(status.isClosed, isFalse, reason: spelling);
      }
    });

    test('checked-in and checked-out are their own journey states', () {
      // The 2026-09-03 payout update gave the booking's journey and its
      // money separate vocabularies. CHECKED_IN/CHECKED_OUT describe where
      // the *stay* has got to; they say nothing about whether the host has
      // been paid, which is why both still count as disputable: there may
      // well be money still held behind either of them.
      final checkedIn = ShortLetBookingStatus.fromString('CHECKED_IN');
      final checkedOut = ShortLetBookingStatus.fromString('CHECKED_OUT');

      expect(checkedIn, ShortLetBookingStatus.checkedIn);
      expect(checkedOut, ShortLetBookingStatus.checkedOut);
      for (final status in [checkedIn, checkedOut]) {
        expect(status.isPaid, isTrue);
        expect(status.isDisputable, isTrue);
        expect(status.isClosed, isFalse);
      }
    });

    test('canDispute adds what the journey status cannot see', () {
      // ShortLetBookingStatus.isDisputable can only read the journey.
      // ShortLetBooking.canDispute is what screens should actually use: it
      // also checks whether there is still a payout to block.
      final held = ShortLetBooking(
        id: 'b1',
        status: ShortLetBookingStatus.checkedOut,
        hostPayoutStatus: HostPayoutStatus.held,
      );
      final released = ShortLetBooking(
        id: 'b2',
        status: ShortLetBookingStatus.checkedOut,
        hostPayoutStatus: HostPayoutStatus.released,
      );
      final unknownPayout = ShortLetBooking(
        id: 'b3',
        status: ShortLetBookingStatus.checkedOut,
        // hostPayoutStatus omitted: an older backend that has not sent
        // payout fields yet must not lose the button over it.
      );

      expect(held.canDispute, isTrue);
      expect(released.canDispute, isFalse);
      expect(unknownPayout.canDispute, isTrue);
    });

    test('a completed stay can still be reviewed', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final booking = ShortLetBooking(
        id: 'b1',
        status: ShortLetBookingStatus.completed,
        checkOut: shortLetIsoDate(yesterday),
      );

      expect(booking.canReview, isTrue);
    });
  });

  group('an unreadable status', () {
    test('an unknown status keeps the backend word verbatim', () {
      // The whole diagnosis lives in this string. Losing it is what turned a
      // one-line mapping bug into a hunt through Paystack webhooks.
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'PAYMENT_FAILED',
      });

      expect(booking.status, ShortLetBookingStatus.unknown);
      expect(booking.rawStatus, 'PAYMENT_FAILED');
      expect(booking.rawStatusLabel, 'Payment failed');
    });

    test('a missing status is distinguishable from an unrecognised one', () {
      final booking = ShortLetBooking.fromJson(const {'id': 'b1'});

      expect(booking.status, ShortLetBookingStatus.unknown);
      // Empty, not "Unknown": the card says a different sentence for a
      // booking that arrived with no status at all.
      expect(booking.rawStatusLabel, isEmpty);
    });

    test('an unreadable status unlocks nothing', () {
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'SOMETHING_NEW',
      });

      // The reason this state is safe, and also the reason it is a dead end
      // the card now has to explain in words.
      expect(booking.status.isPaid, isFalse);
      expect(booking.status.needsPayment, isFalse);
      expect(booking.status.isCancellableByTenant, isFalse);
      expect(booking.status.isDisputable, isFalse);
      expect(booking.canMessage, isFalse);
    });

    test('it is not filed away as closed either', () {
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'SOMETHING_NEW',
      });

      // Closed would bury it under "Past and cancelled", where nobody would
      // find the thing that needs looking at.
      expect(booking.status.isClosed, isFalse);
    });
  });

  group('rating summaries', () {
    test('unrated is not the same as nought stars', () {
      const unrated = RatingSummary.empty;

      // The distinction the whole nullable average exists for: a new listing
      // must not render as a one-star one.
      expect(unrated.hasRating, isFalse);
      expect(unrated.average, isNull);
      expect(unrated.summaryLine, 'No reviews yet');
    });

    test('an average is shown to one decimal', () {
      final summary = RatingSummary.fromJson(const {
        'average_rating': 4.75,
        'review_count': 12,
      });

      expect(summary.label, '4.8');
      expect(summary.summaryLine, '4.8 · 12 reviews');
    });

    test('a count of one is singular', () {
      final summary = RatingSummary.fromJson(const {
        'average_rating': '5',
        'review_count': 1,
      });

      expect(summary.summaryLine, '5.0 · 1 review');
    });

    test('a distribution is only kept when the backend sends one', () {
      final without = RatingSummary.fromJson(const {
        'average_rating': 4.0,
        'review_count': 3,
      });
      final with_ = RatingSummary.fromJson(const {
        'average_rating': 4.0,
        'review_count': 3,
        'distribution': {'5': 2, '3': 1},
      });

      // The bars are drawn from data or not at all: never inferred from the
      // average, which would be a drawing of a guess.
      expect(without.distribution, isEmpty);
      expect(with_.distribution[5], 2);
      expect(with_.distribution[3], 1);
    });

    test('a rating outside 1-5 is clamped rather than rendered', () {
      final review = Review.fromJson(const {'id': 'r1', 'rating': 9});

      expect(review.rating, 5);
    });

    test('an author with no name is still addressable', () {
      final review = Review.fromJson(const {'id': 'r1', 'rating': 4});

      expect(review.displayAuthor, 'An Oasis user');
      expect(review.initial, 'A');
    });
  });
}
