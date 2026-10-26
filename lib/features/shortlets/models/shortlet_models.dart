/// Models for short lets: units let by the night rather than by the year.
///
/// A short let is deliberately its own shape rather than a flag on a tenancy.
/// Nothing about it maps cleanly onto the rental flow: there is no agreement
/// to sign, the price is per night, the landlord approves rather than
/// counter-signs, and the whole thing is over in a weekend.
///
/// Money arrives from the backend as decimal strings and stays that way all
/// the way to `OasisCurrency`, for the same reason it does in the vault: a
/// price rendered a naira out is worse than one that fails to render.
///
/// The guide documents the request bodies for these endpoints but not the
/// response bodies, so every field below is read defensively: a missing one
/// degrades to a sensible default rather than throwing, and unknown statuses
/// never resolve to anything that would let money move.
library;

import 'package:flutter/foundation.dart';

import '../../../core/network/api_constants.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/app_variant.dart';

/// The cancellation terms a host selects for a short-let listing.
///
/// The backend remains authoritative for the exact cutoff and refund amount:
/// these values give the app human-readable disclosure before a tenant asks
/// for dates, not permission to calculate a refund locally.
enum ShortLetCancellationPolicy {
  flexible('FLEXIBLE'),
  moderate('MODERATE'),
  strict('STRICT'),
  nonRefundable('NON_REFUNDABLE');

  final String wireValue;

  const ShortLetCancellationPolicy(this.wireValue);

  static ShortLetCancellationPolicy fromString(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'MODERATE':
        return ShortLetCancellationPolicy.moderate;
      case 'STRICT':
        return ShortLetCancellationPolicy.strict;
      case 'NON_REFUNDABLE':
      case 'NON-REFUNDABLE':
        return ShortLetCancellationPolicy.nonRefundable;
      case 'FLEXIBLE':
      default:
        // Older servers do not send this field. The platform default is
        // Flexible, so absence must be safe and visible, not an unknown term.
        return ShortLetCancellationPolicy.flexible;
    }
  }

  String get label => switch (this) {
    ShortLetCancellationPolicy.flexible => 'Flexible',
    ShortLetCancellationPolicy.moderate => 'Moderate',
    ShortLetCancellationPolicy.strict => 'Strict',
    ShortLetCancellationPolicy.nonRefundable => 'Non-refundable',
  };

  String get defaultSummary => switch (this) {
    ShortLetCancellationPolicy.flexible =>
      'Free cancellation until 24 hours before check-in.',
    ShortLetCancellationPolicy.moderate =>
      'Free cancellation until 5 days before check-in; 50% until 24 hours before.',
    ShortLetCancellationPolicy.strict =>
      'Free cancellation until 14 days before check-in; 50% until 7 days before.',
    ShortLetCancellationPolicy.nonRefundable =>
      'No accommodation refund after payment, except where Oasis or the host cancels.',
  };
}

/// Where the host's share of a paid stay currently stands.
///
/// Deliberately a field of its own rather than folded into
/// [ShortLetBookingStatus]. A booking's *journey* (requested, paid, checked
/// in, checked out) and the *money* backing it used to be told as one story:
/// "paid" implied the host had been paid, and that stopped being true the
/// day payout release moved from "the moment the guest pays" to "the
/// check-in date". Two axes now, tracked separately, exactly as the backend
/// sends them.
enum HostPayoutStatus {
  /// No booking, or a booking that has not been paid for yet.
  notFunded,

  /// Paid, and waiting for the release time: 24 hours after checkout.
  held,

  /// Paid out to the host.
  released,

  /// Held, but a tenant dispute is stopping the release.
  blocked,

  /// Sent back to the tenant instead of the host: a cancellation or a
  /// resolved dispute that went the guest's way.
  refunded,

  unknown;

  static HostPayoutStatus fromString(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'NOT_FUNDED':
        return HostPayoutStatus.notFunded;
      case 'HELD':
        return HostPayoutStatus.held;
      case 'RELEASED':
      case 'PAID':
        return HostPayoutStatus.released;
      case 'BLOCKED':
        return HostPayoutStatus.blocked;
      case 'REFUNDED':
        return HostPayoutStatus.refunded;
      default:
        return HostPayoutStatus.unknown;
    }
  }

  /// Local fallback wording, used only when the backend omits
  /// `host_payout_status_label`. The backend's own label is preferred
  /// wherever it is present: it is written for this exact banner, where
  /// this is a guess at what it would say.
  String get fallbackLabel {
    switch (this) {
      case HostPayoutStatus.notFunded:
        return 'Not paid yet';
      case HostPayoutStatus.held:
        return 'Scheduled for payout';
      case HostPayoutStatus.released:
        return 'Paid to host';
      case HostPayoutStatus.blocked:
        return 'Payout paused';
      case HostPayoutStatus.refunded:
        return 'Refunded to tenant';
      case HostPayoutStatus.unknown:
        return 'Payout status unclear';
    }
  }
}

/// Where a booking request has got to.
enum ShortLetBookingStatus {
  /// Requested; the landlord has not decided yet.
  pending,

  /// Approved and waiting to be paid. The window is short: the backend gives
  /// the tenant 24 hours from approval.
  approved,

  /// Paid. What happens to the host's money from here is tracked separately
  /// on [ShortLetBooking.hostPayoutStatus]: it is held until a day after
  /// checkout, not released the moment this status is reached.
  paid,

  /// The guest has arrived. Nothing about the money changes here; this exists
  /// so the app can stop offering pre-arrival actions (cancel, and the
  /// backend's own pre-check-in refund policy) the moment they stop applying.
  checkedIn,

  /// The guest has left. The caution fee's 24-hour claim window opens here,
  /// and the host payout releases when the same 24 hours are up: again,
  /// tracked on [ShortLetBooking.hostPayoutStatus], not here.
  checkedOut,

  /// Fully settled: stayed, checked out, and nothing left to claim or
  /// dispute. Folding this into [checkedOut] would offer a late dispute or
  /// claim action the backend can only refuse.
  completed,

  /// Paid, but the guest has raised a problem that blocks the host payout
  /// until it is settled.
  disputed,

  rejected,
  cancelled,

  /// Approved but not paid inside the window.
  expired,

  unknown;

  static ShortLetBookingStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'PENDING':
      case 'REQUESTED':
        return ShortLetBookingStatus.pending;
      case 'APPROVED':
        return ShortLetBookingStatus.approved;
      case 'PAID':
      case 'ESCROW':
      // The spelling staging actually sends. Its absence here is what made a
      // successfully paid stay render as unreadable, with no check-in
      // notes, no message button and no place on the tenant's dashboard,
      // and sent everyone looking at Paystack for a bug that was one missing
      // case in this switch.
      case 'IN_ESCROW':
      case 'CONFIRMED':
        return ShortLetBookingStatus.paid;
      case 'CHECKED_IN':
        return ShortLetBookingStatus.checkedIn;
      case 'CHECKED_OUT':
        return ShortLetBookingStatus.checkedOut;
      // RELEASED is not in the backend's documented booking-status
      // vocabulary (2026-09-03 payout update): it is a *payout* status now.
      // Kept here as a legacy alias in case an older record still carries it
      // as the booking status: without this, every such stay would render as
      // unreadable, which is the exact bug this mapping exists to prevent.
      case 'RELEASED':
      case 'COMPLETED':
        return ShortLetBookingStatus.completed;
      case 'REJECTED':
      case 'DECLINED':
        return ShortLetBookingStatus.rejected;
      case 'CANCELLED':
      case 'CANCELED':
        return ShortLetBookingStatus.cancelled;
      case 'DISPUTED':
        return ShortLetBookingStatus.disputed;
      case 'EXPIRED':
        return ShortLetBookingStatus.expired;
      default:
        // Never guess "paid" or "approved": both unlock actions. A stay the
        // tenant would travel for, a payment the app would offer, and a
        // status the app has not seen is not evidence for either.
        //
        // But say so. This used to fall through in silence, and the only
        // trace was a booking pill reading "Processing" with no buttons under
        // it: indistinguishable, from the outside, from a payment stuck in
        // Paystack. The API guide still documents no status vocabulary for
        // short-let bookings (`backend_change_spec_v7.md` §8), so an
        // unrecognised one is a real possibility rather than a defensive
        // hypothetical, and the name of it is the whole diagnosis.
        if (value != null && value.trim().isNotEmpty) {
          debugPrint(
            '[SHORTLET] Unrecognised booking status "$value". The app has '
            'no case for it, so the booking will render as unreadable with no '
            'actions. Add it to ShortLetBookingStatus.fromString.',
          );
        } else {
          debugPrint('[SHORTLET] Booking arrived with no status field at all.');
        }
        return ShortLetBookingStatus.unknown;
    }
  }

  String get label {
    switch (this) {
      case ShortLetBookingStatus.pending:
        return 'Awaiting host';
      case ShortLetBookingStatus.approved:
        return 'Approved, pay to confirm';
      case ShortLetBookingStatus.paid:
        return 'Confirmed';
      case ShortLetBookingStatus.checkedIn:
        return 'Checked in';
      case ShortLetBookingStatus.checkedOut:
        return 'Checked out';
      case ShortLetBookingStatus.completed:
        return isOasisV2 ? 'Completed' : 'Stay complete';
      case ShortLetBookingStatus.disputed:
        return 'Under review';
      case ShortLetBookingStatus.rejected:
        return 'Declined';
      case ShortLetBookingStatus.cancelled:
        return 'Cancelled';
      case ShortLetBookingStatus.expired:
        return 'Expired';
      case ShortLetBookingStatus.unknown:
        // Deliberately not "Processing". That word described a payment moving
        // through a provider, which is not what this state is: it is the app
        // failing to read the backend's answer. Saying "Processing" sent
        // people looking at Paystack for a bug that was in this file.
        return 'Status unclear';
    }
  }

  /// Shorter wording for a landlord, who is the one deciding rather than
  /// waiting.
  String get landlordLabel {
    switch (this) {
      case ShortLetBookingStatus.pending:
        return 'Needs your decision';
      case ShortLetBookingStatus.approved:
        return 'Approved, awaiting payment';
      case ShortLetBookingStatus.paid:
        // Deliberately silent on the money here, that is what
        // [ShortLetBooking.hostPayoutStatusLabel] is for, shown alongside
        // this pill rather than folded into it. Payout is held until a day
        // after checkout, not released the moment a booking is paid.
        return 'Paid, booking confirmed';
      case ShortLetBookingStatus.checkedIn:
        return 'Guest checked in';
      case ShortLetBookingStatus.checkedOut:
        return 'Guest checked out';
      case ShortLetBookingStatus.completed:
        return isOasisV2 ? 'Completed' : 'Stay complete';
      case ShortLetBookingStatus.disputed:
        return 'Guest raised a problem';
      case ShortLetBookingStatus.rejected:
        return 'You declined';
      case ShortLetBookingStatus.cancelled:
        return 'Guest cancelled';
      case ShortLetBookingStatus.expired:
        return 'Expired unpaid';
      case ShortLetBookingStatus.unknown:
        return 'Status unclear';
    }
  }

  /// Waiting on the landlord to approve or reject.
  bool get needsLandlordDecision => this == ShortLetBookingStatus.pending;

  /// The tenant owes money and the stay is not confirmed until they pay.
  bool get needsPayment => this == ShortLetBookingStatus.approved;

  /// Money has been taken, at any point from payment through to the stay
  /// being fully settled.
  bool get isPaid =>
      this == ShortLetBookingStatus.paid ||
      this == ShortLetBookingStatus.checkedIn ||
      this == ShortLetBookingStatus.checkedOut ||
      this == ShortLetBookingStatus.disputed ||
      this == ShortLetBookingStatus.completed;

  /// Whether the guest can still raise a problem, going purely off the
  /// booking's journey. [ShortLetBooking.canDispute] is the one screens
  /// should actually read, because it adds the host-payout check this cannot
  /// make on its own. This stays as the fallback for a booking whose payout
  /// fields have not arrived yet.
  bool get isDisputable =>
      this == ShortLetBookingStatus.paid ||
      this == ShortLetBookingStatus.checkedIn ||
      this == ShortLetBookingStatus.checkedOut;

  /// Nothing more will happen to this booking. A dispute is deliberately not
  /// closed: someone is still working on it.
  bool get isClosed =>
      this == ShortLetBookingStatus.rejected ||
      this == ShortLetBookingStatus.cancelled ||
      this == ShortLetBookingStatus.expired;

  /// Whether the tenant may cancel an unpaid request. Paid booking
  /// cancellation is further gated by [ShortLetBooking.canBeCancelledByTenant]
  /// because it depends on the check-in date and the backend quote.
  bool get isCancellableByTenant =>
      this == ShortLetBookingStatus.pending ||
      this == ShortLetBookingStatus.approved;
}

/// A unit offered for nightly stays, from the landlord or tenant short-let
/// listing endpoints.
class ShortLetListing {
  final String id;

  /// The unit being let. Kept as an id because the listing endpoints are
  /// indexed by it; [unitNumber] and [propertyName] are the display copy.
  final String unitId;
  final String unitNumber;
  final String propertyName;
  final String address;
  final String city;
  final String state;

  final String nightlyPrice;

  /// Refundable deposit the host asks for on top of the nightly total.
  ///
  /// Optional for the host and "0.00" when they want none, which is the
  /// common case, so every reader must branch on [hasCautionFee] rather than
  /// rendering a ₦0 line that reads as a charge. When it is set the guest
  /// has no choice about it: the backend folds it into the booking total, and
  /// the stay is not confirmed until the whole amount is paid.
  final String cautionFee;

  /// Optional host-selected cancellation terms. Older backend payloads omit
  /// this; [cancellationPolicy] then correctly falls back to FLEXIBLE.
  final ShortLetCancellationPolicy cancellationPolicy;
  final String cancellationPolicySummary;

  final int minimumNights;
  final int maximumGuests;

  /// The host's own description of the place.
  ///
  /// Free text and the only part of a listing written *to* a guest rather
  /// than about the unit: what the flat is like, what is nearby, what to
  /// expect. Empty on a listing whose host has not written one yet: every
  /// reader must branch on [hasDescription] rather than rendering a gap where
  /// the paragraph should be.
  ///
  /// Distinct from [houseRules], which is what a guest must not do, and from
  /// [checkInNotes], which is arrival logistics and only shown after payment.
  final String description;

  /// Mean guest rating out of 5, and how many stays it is averaged over.
  ///
  /// Null rather than 0.0 when nobody has reviewed: a new listing has no
  /// rating, and showing it as zero stars would read as a bad one.
  final double? averageRating;
  final int reviewCount;

  final int bedrooms;
  final int bathrooms;

  /// ISO dates bounding when the unit can be booked at all.
  final String? availableFrom;
  final String? availableTo;

  /// Individual ISO dates inside the window that are not bookable.
  final List<String> blockedDates;

  final String houseRules;

  /// Arrival instructions. The backend only reveals these to a guest who has
  /// paid, so this is usually empty on a browse response: the UI must not
  /// present its absence as the host having written nothing.
  final String checkInNotes;

  /// Whether the landlord currently has the listing switched on. An inactive
  /// listing stays visible to its owner and disappears from tenant browse.
  final bool isActive;

  final List<String> photoUrls;

  /// The cover selected by the backend for the unit. This is separate from
  /// [photoUrls]: compact short-let responses can include just this field.
  final String? selectedCoverPhotoUrl;

  /// The unit's walkthrough, when it has one.
  ///
  /// Read from the unit rather than the property: a short let is one flat, and
  /// what a guest wants to see is the room they will sleep in.
  final String? videoUrl;

  final String createdAt;

  /// How far this listing is from the coordinates the search was made with.
  ///
  /// Only present on a location-aware browse: the backend returns it when
  /// the app sends `latitude`/`longitude`, and omits it otherwise. Null means
  /// "not measured", never "zero away", so the UI hides the badge rather than
  /// claiming the guest is standing in the doorway.
  final double? distanceKm;

  /// Whether the backend found these dates bookable, when the search carried
  /// `check_in`/`check_out`.
  ///
  /// Three states, and the third is the reason this is nullable rather than a
  /// bool: null means no dates were searched, so nothing was checked. Only
  /// `false` is evidence the stay is unavailable: treating "not checked" as
  /// unavailable would mark every ordinary browse result as blocked.
  final bool? isAvailableForPeriod;

  /// The backend's sentence for why those dates will not work. Empty unless
  /// [isAvailableForPeriod] is false, and shown as written: the backend knows
  /// about blocked dates and rival bookings the app cannot see.
  final String unavailableReason;

  const ShortLetListing({
    required this.id,
    this.unitId = '',
    this.unitNumber = '',
    this.propertyName = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.nightlyPrice = '0.00',
    this.cautionFee = '0.00',
    this.cancellationPolicy = ShortLetCancellationPolicy.flexible,
    this.cancellationPolicySummary = '',
    this.minimumNights = 1,
    this.maximumGuests = 1,
    this.description = '',
    this.averageRating,
    this.reviewCount = 0,
    this.bedrooms = 0,
    this.bathrooms = 0,
    this.availableFrom,
    this.availableTo,
    this.blockedDates = const [],
    this.houseRules = '',
    this.checkInNotes = '',
    this.isActive = true,
    this.photoUrls = const [],
    this.selectedCoverPhotoUrl,
    this.videoUrl,
    this.createdAt = '',
    this.distanceKm,
    this.isAvailableForPeriod,
    this.unavailableReason = '',
  });

  factory ShortLetListing.fromJson(Map<String, dynamic> json) {
    // The unit can arrive as a bare id or as a nested object, depending on
    // which endpoint answered. Read either without insisting on one.
    final unit = json['unit'];
    final unitMap = unit is Map<String, dynamic> ? unit : const {};
    final property = json['property'] is Map<String, dynamic>
        ? json['property'] as Map<String, dynamic>
        : (unitMap['property'] is Map<String, dynamic>
              ? unitMap['property'] as Map<String, dynamic>
              : const {});

    return ShortLetListing(
      id: json['id']?.toString() ?? '',
      unitId: (unit is Map ? unitMap['id'] : unit)?.toString() ?? '',
      unitNumber: (json['unit_number'] ?? unitMap['unit_number'] ?? '')
          .toString(),
      // The same snippet gives a listing a top-level `name`. Taken as the
      // property name when nothing better is present, so a listing that
      // arrives that way still has a title instead of reading "Short let".
      propertyName:
          (json['property_name'] ?? property['name'] ?? json['name'] ?? '')
              .toString(),
      address: (json['address'] ?? property['address'] ?? '').toString(),
      city: (json['city'] ?? property['city'] ?? '').toString(),
      state: (json['state'] ?? property['state'] ?? '').toString(),
      // `nightly_price` everywhere in API guide 18 except one illustrative
      // snippet, which calls it `nightly_rate`. Reading both costs a line and
      // the alternative, if that snippet turns out to be the serializer,
      // is every stay in the marketplace advertised at ₦0. Raised as
      // `backend_change_spec_v13.md` §2.
      nightlyPrice:
          (json['nightly_price'] ?? json['nightly_rate'])?.toString() ?? '0.00',
      cautionFee: json['caution_fee']?.toString() ?? '0.00',
      cancellationPolicy: ShortLetCancellationPolicy.fromString(
        json['cancellation_policy']?.toString(),
      ),
      cancellationPolicySummary:
          json['cancellation_policy_summary']?.toString() ?? '',
      minimumNights: _readInt(json['minimum_nights']) ?? 1,
      maximumGuests: _readInt(json['maximum_guests']) ?? 1,
      // The unit's own description is the fallback: a host who wrote one when
      // they added the flat should not have to write it again to let it by
      // the night.
      description: (json['description'] ?? unitMap['description'] ?? '')
          .toString()
          .trim(),
      averageRating: _readDouble(json['average_rating']),
      reviewCount: _readInt(json['review_count']) ?? 0,
      bedrooms: _readInt(json['bedrooms'] ?? unitMap['bedrooms']) ?? 0,
      bathrooms: _readInt(json['bathrooms'] ?? unitMap['bathrooms']) ?? 0,
      availableFrom: _readDate(json['available_from']),
      availableTo: _readDate(json['available_to']),
      blockedDates: _readStrings(json['blocked_dates']),
      houseRules: json['house_rules']?.toString() ?? '',
      checkInNotes: json['check_in_notes']?.toString() ?? '',
      // Absent means active: a listing the backend returned without the flag
      // is one it is serving, and hiding it would lose the landlord bookings.
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      photoUrls: _readMediaUrls(
        json['photo_urls'] ??
            unitMap['photo_urls'] ??
            property['photo_urls'] ??
            json['images'] ??
            unitMap['images'],
      ),
      selectedCoverPhotoUrl: _readMediaUrl(
        json['cover_photo_url'] ??
            unitMap['cover_photo_url'] ??
            property['cover_photo_url'] ??
            json['image_url'] ??
            unitMap['image_url'],
      ),
      videoUrl: _readNonEmpty(json['video_url'] ?? unitMap['video_url']),
      createdAt: json['created_at']?.toString() ?? '',
      distanceKm: _readDouble(json['distance_km']),
      // Strictly a bool: a missing key and a non-bool value both mean "not
      // checked", and neither is grounds for telling a guest the dates are
      // taken.
      isAvailableForPeriod: json['is_available_for_period'] is bool
          ? json['is_available_for_period'] as bool
          : null,
      unavailableReason: json['unavailable_reason']?.toString() ?? '',
    );
  }

  /// What to call this listing in a list. Falls back through what is present
  /// rather than rendering an empty title.
  String get title {
    if (propertyName.isNotEmpty && unitNumber.isNotEmpty) {
      return '$propertyName · Unit $unitNumber';
    }
    if (propertyName.isNotEmpty) return propertyName;
    if (unitNumber.isNotEmpty) return 'Unit $unitNumber';
    return 'Short let';
  }

  /// "Lagos, Lagos": deduplicated, because a city and state of the same name
  /// is normal in Nigeria and "Lagos, Lagos" reads as a mistake.
  String get location {
    final parts = <String>[
      if (city.isNotEmpty) city,
      if (state.isNotEmpty && state.toLowerCase() != city.toLowerCase()) state,
    ];
    return parts.isEmpty ? address : parts.join(', ');
  }

  String? get coverPhotoUrl =>
      selectedCoverPhotoUrl ?? (photoUrls.isEmpty ? null : photoUrls.first);

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  bool get hasDescription => description.trim().isNotEmpty;

  /// Whether the host asks for a refundable deposit at all.
  ///
  /// Tested against the parsed minor units rather than the string, because
  /// "0.00", "0" and "" all mean the same thing and only one of them is
  /// what the backend happens to send.
  bool get hasCautionFee => (OasisCurrency.minorUnits(cautionFee) ?? 0) > 0;

  String get resolvedCancellationPolicySummary {
    final summary = cancellationPolicySummary.trim();
    return summary.isEmpty ? cancellationPolicy.defaultSummary : summary;
  }

  /// Whether this listing has been reviewed enough to show a rating.
  bool get hasRating => averageRating != null && reviewCount > 0;

  /// "4.8": one decimal, which is as much precision as a star rating earns.
  String? get ratingLabel =>
      hasRating ? averageRating!.toStringAsFixed(1) : null;

  /// Whether the searched dates came back refused. False when no dates were
  /// searched, so an ordinary browse marks nothing.
  bool get isUnavailableForPeriod => isAvailableForPeriod == false;

  /// Why the dates will not work, falling back to a plain sentence when the
  /// backend refused without giving one.
  String get unavailableLabel {
    final reason = unavailableReason.trim();
    if (reason.isNotEmpty) return reason;
    return 'Not available for the dates you picked.';
  }

  /// "1.2 km away", or null when the search carried no coordinates.
  ///
  /// Rounded to whole kilometres past 10, where a decimal is noise: the guest
  /// is deciding whether somewhere is walkable, not navigating to it.
  String? get distanceLabel {
    final km = distanceKm;
    if (km == null || km < 0) return null;
    if (km < 1) return '${(km * 1000).round()} m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  /// Total for [nights] nights, before any platform fee or deposit. Null when
  /// the price is unreadable: better no figure than a wrong one.
  String? totalFor(int nights) {
    if (nights <= 0) return null;
    final perNight = OasisCurrency.minorUnits(nightlyPrice);
    if (perNight == null) return null;
    return OasisCurrency.fromMinorUnits(perNight * nights);
  }

  /// Nights plus the deposit: what the guest will actually be asked for,
  /// still before the platform fee the backend adds at approval.
  ///
  /// Kept separate from [totalFor] so a quote can show the two lines the
  /// guest is owed: what the stay costs, and what they get back afterwards.
  String? totalWithDepositFor(int nights) {
    final stay = totalFor(nights);
    if (stay == null) return null;
    if (!hasCautionFee) return stay;
    final sum = OasisCurrency.minorUnits(stay);
    final deposit = OasisCurrency.minorUnits(cautionFee);
    if (sum == null || deposit == null) return stay;
    return OasisCurrency.fromMinorUnits(sum + deposit);
  }

  /// Whether [date] (ISO `YYYY-MM-DD`) is inside the availability window and
  /// not individually blocked.
  ///
  /// The backend re-checks all of this on booking, so this exists only to stop
  /// the app offering dates that will certainly be refused.
  bool isDateBookable(DateTime date) {
    final from = _parse(availableFrom);
    final to = _parse(availableTo);
    final day = DateTime(date.year, date.month, date.day);
    if (from != null && day.isBefore(from)) return false;
    if (to != null && day.isAfter(to)) return false;
    return !blockedDates.contains(_isoDate(day));
  }

  /// Whether every night from [checkIn] up to (not including) [checkOut] is
  /// bookable. Checkout day is excluded because nobody sleeps there that
  /// night: blocking on it would refuse back-to-back stays.
  bool coversStay(DateTime checkIn, DateTime checkOut) {
    if (!checkOut.isAfter(checkIn)) return false;
    for (
      var day = DateTime(checkIn.year, checkIn.month, checkIn.day);
      day.isBefore(DateTime(checkOut.year, checkOut.month, checkOut.day));
      day = day.add(const Duration(days: 1))
    ) {
      if (!isDateBookable(day)) return false;
    }
    return true;
  }

  static DateTime? _parse(String? iso) =>
      iso == null || iso.isEmpty ? null : DateTime.tryParse(iso);
}

/// What `POST /host/listings/` made: the listing, plus the ids of the
/// property and unit behind it, which the app needs to add photos next.
///
/// The response is the ordinary short-let listing, with `property` and
/// `unit` nested in it (confirmed by the backend, 2026-10-23). Ids sent bare
/// rather than nested are read too. The unit's details fall back to what the
/// host just typed.
class HostListingResult {
  final ShortLetListing listing;
  final String propertyId;
  final String unitId;
  final String unitNumber;
  final int bedrooms;
  final int bathrooms;

  const HostListingResult({
    required this.listing,
    required this.propertyId,
    required this.unitId,
    required this.unitNumber,
    required this.bedrooms,
    required this.bathrooms,
  });

  factory HostListingResult.fromJson(
    Map<String, dynamic> json, {
    required String fallbackUnitNumber,
    required int fallbackBedrooms,
    required int fallbackBathrooms,
  }) {
    String idOf(Object? value) => switch (value) {
      Map() => value['id']?.toString() ?? '',
      null => '',
      _ => value.toString(),
    };
    String firstOf(List<String> values) =>
        values.firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final listing = ShortLetListing.fromJson(json);
    final unit = json['unit'] is Map<String, dynamic>
        ? json['unit'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return HostListingResult(
      listing: listing,
      propertyId: firstOf([
        idOf(json['property']),
        idOf(json['property_id']),
        idOf(unit['property']),
      ]),
      unitId: firstOf([listing.unitId, idOf(json['unit_id'])]),
      unitNumber: firstOf([listing.unitNumber, fallbackUnitNumber]),
      bedrooms: _readInt(unit['bedrooms']) ?? fallbackBedrooms,
      bathrooms: _readInt(unit['bathrooms']) ?? fallbackBathrooms,
    );
  }
}

/// One booking of a short let, from either role's booking endpoint.
class ShortLetBooking {
  final String id;
  final String listingId;

  /// Display copy for the listing, when the backend nests or flattens it.
  final String unitNumber;
  final String propertyName;
  final String address;

  /// ISO dates. Checkout is the morning the guest leaves, so the number of
  /// nights is the gap between them.
  final String checkIn;
  final String checkOut;

  final int guestCount;
  final String message;

  final ShortLetBookingStatus status;

  /// The backend's own status string, kept verbatim.
  ///
  /// Only ever read when [status] came out as `unknown`. A booking the app
  /// cannot interpret is still a booking somebody paid for, and showing them
  /// the word the server actually used turns "something is wrong" into a
  /// sentence they can quote to support, and turns a bug report into a
  /// one-line fix here.
  final String rawStatus;

  /// What the stay costs. [totalAmount] is the figure to charge and the one to
  /// show: it is the backend's, never recomputed here.
  final String nightlyPrice;
  final String amount;
  final String platformFee;

  /// The refundable deposit inside [totalAmount], quoted separately so the
  /// guest can see which part of what they paid is coming back.
  final String cautionFee;

  /// Cancellation terms copied from the listing when the booking was made.
  /// The amounts are server-calculated current entitlements, never app maths.
  final ShortLetCancellationPolicy cancellationPolicy;
  final int? cancellationPolicyVersion;
  final String accommodationRefundAmount;
  final String platformFeeRefundAmount;
  final String cautionFeeRefundAmount;
  final String totalRefundAmount;

  /// When the deposit was returned, if it has been. Null while it is still
  /// held, which is the normal state right up to a day after checkout.
  final String? cautionFeeRefundedAt;

  final String totalAmount;

  /// The host's cut of a paid stay, and where it currently stands.
  ///
  /// Read from `host_payout*` first and the temporary `landlord_payout*`
  /// aliases second, per the 2026-09-03 payout update: the backend keeps
  /// both in circulation for now, but `host_*` is the name that survives.
  final String hostPayout;
  final HostPayoutStatus hostPayoutStatus;

  /// The backend's own copy for [hostPayoutStatus], preferred over
  /// [HostPayoutStatus.fallbackLabel] wherever it is present: this is
  /// written for the exact banner it appears in, not guessed at here.
  final String hostPayoutStatusLabel;
  final String hostPayoutStatusDescription;

  /// When the payout is due to release: 24 hours after checkout (API guide
  /// 20; it used to be 12:00 PM on the check-in date). Null once released,
  /// and null before payment.
  final String? hostPayoutReleaseAt;

  /// When the payout actually left, if it has.
  final String? hostPaidAt;

  /// Raw backend word for the caution fee's own escrow state: `IN_ESCROW`,
  /// `RELEASED`, `REFUNDED` and so on. Kept as the backend spells it rather
  /// than mapped to a local enum: this is read only for the one
  /// [isCautionFeeRefunded] check below, so a second enum would be
  /// ceremony without a use.
  final String cautionFeeEscrowStatus;

  /// When the host's 24-hour claim window closes and, unclaimed, the caution
  /// fee goes back to the guest.
  final String? cautionFeeReleaseReadyAt;

  /// The host's claim against the caution fee, when there is one (spec v16
  /// §7). Null means no claim has been made, or the backend has not started
  /// sending it yet.
  final CautionClaim? cautionClaim;

  /// The thread for this stay, once the backend has opened one.
  ///
  /// Only exists after payment: a guest and a host with no confirmed booking
  /// between them have nothing to arrange, and opening a channel earlier
  /// would be a way to reach strangers. Empty means "not yet", never
  /// "messaging is off".
  final String conversationId;

  /// Whether this guest has already reviewed the stay. Stops the app offering
  /// a form the backend would reject as a duplicate.
  final bool hasReview;

  /// The guest, for a landlord looking at a request.
  final String tenantEmail;
  final String tenantName;

  /// Set once payment starts. The payment id is what the verify endpoint is
  /// keyed on, so a booking without one cannot be verified.
  final String? paymentId;
  final String? paymentReference;

  /// Provider checkout for a card payment. Null for a vault payment, which
  /// settles server-side with no page to open.
  final String? authorizationUrl;
  final String? accessCode;

  /// When an approved booking stops being payable. The backend gives 24 hours
  /// from approval.
  final String? paymentDeadline;

  /// Arrival instructions, released by the backend once the stay is paid for.
  final String checkInNotes;

  /// What the guest said was wrong, when they raised a dispute.
  final String disputeReason;
  final String? disputedAt;

  final String createdAt;

  const ShortLetBooking({
    required this.id,
    this.listingId = '',
    this.unitNumber = '',
    this.propertyName = '',
    this.address = '',
    this.checkIn = '',
    this.checkOut = '',
    this.guestCount = 1,
    this.message = '',
    this.status = ShortLetBookingStatus.unknown,
    this.rawStatus = '',
    this.nightlyPrice = '0.00',
    this.amount = '0.00',
    this.platformFee = '0.00',
    this.cautionFee = '0.00',
    this.cancellationPolicy = ShortLetCancellationPolicy.flexible,
    this.cancellationPolicyVersion,
    this.accommodationRefundAmount = '0.00',
    this.platformFeeRefundAmount = '0.00',
    this.cautionFeeRefundAmount = '0.00',
    this.totalRefundAmount = '0.00',
    this.cautionFeeRefundedAt,
    this.totalAmount = '0.00',
    this.hostPayout = '0.00',
    this.hostPayoutStatus = HostPayoutStatus.unknown,
    this.hostPayoutStatusLabel = '',
    this.hostPayoutStatusDescription = '',
    this.hostPayoutReleaseAt,
    this.hostPaidAt,
    this.cautionFeeEscrowStatus = '',
    this.cautionFeeReleaseReadyAt,
    this.cautionClaim,
    this.conversationId = '',
    this.hasReview = false,
    this.tenantEmail = '',
    this.tenantName = '',
    this.paymentId,
    this.paymentReference,
    this.authorizationUrl,
    this.accessCode,
    this.paymentDeadline,
    this.checkInNotes = '',
    this.disputeReason = '',
    this.disputedAt,
    this.createdAt = '',
  });

  factory ShortLetBooking.fromJson(Map<String, dynamic> json) {
    final listing = json['listing'];
    final listingMap = listing is Map<String, dynamic> ? listing : const {};
    final property = json['property'] is Map<String, dynamic>
        ? json['property'] as Map<String, dynamic>
        : (listingMap['property'] is Map<String, dynamic>
              ? listingMap['property'] as Map<String, dynamic>
              : const {});
    // Payment fields may sit at the top level or inside a nested payment
    // object, depending on whether this came back from list or from pay.
    final payment = json['payment'] is Map<String, dynamic>
        ? json['payment'] as Map<String, dynamic>
        : const {};

    final amount = (json['amount'] ?? payment['amount'])?.toString();
    final total = (json['total_amount'] ?? payment['total_amount'])?.toString();

    return ShortLetBooking(
      id: json['id']?.toString() ?? '',
      listingId:
          (listing is Map ? listingMap['id'] : listing)?.toString() ?? '',
      unitNumber: (json['unit_number'] ?? listingMap['unit_number'] ?? '')
          .toString(),
      propertyName:
          (json['property_name'] ??
                  listingMap['property_name'] ??
                  property['name'] ??
                  '')
              .toString(),
      address: (json['address'] ?? property['address'] ?? '').toString(),
      checkIn: _readDate(json['check_in']) ?? '',
      checkOut: _readDate(json['check_out']) ?? '',
      guestCount: _readInt(json['guest_count']) ?? 1,
      message: json['message']?.toString() ?? '',
      status: ShortLetBookingStatus.fromString(json['status']?.toString()),
      rawStatus: json['status']?.toString().trim() ?? '',
      nightlyPrice:
          (json['nightly_price'] ?? listingMap['nightly_price'] ?? '0.00')
              .toString(),
      amount: amount ?? '0.00',
      platformFee: (json['platform_fee'] ?? payment['platform_fee'] ?? '0.00')
          .toString(),
      cautionFee:
          (json['caution_fee'] ??
                  payment['caution_fee'] ??
                  listingMap['caution_fee'] ??
                  '0.00')
              .toString(),
      cancellationPolicy: ShortLetCancellationPolicy.fromString(
        json['cancellation_policy'] ??
            payment['cancellation_policy'] ??
            listingMap['cancellation_policy'],
      ),
      cancellationPolicyVersion: _readInt(
        json['cancellation_policy_version'] ??
            payment['cancellation_policy_version'],
      ),
      accommodationRefundAmount:
          (json['accommodation_refund_amount'] ??
                  payment['accommodation_refund_amount'] ??
                  '0.00')
              .toString(),
      platformFeeRefundAmount:
          (json['platform_fee_refund_amount'] ??
                  payment['platform_fee_refund_amount'] ??
                  '0.00')
              .toString(),
      cautionFeeRefundAmount:
          (json['caution_fee_refund_amount'] ??
                  payment['caution_fee_refund_amount'] ??
                  '0.00')
              .toString(),
      totalRefundAmount:
          (json['total_refund_amount'] ??
                  payment['total_refund_amount'] ??
                  '0.00')
              .toString(),
      cautionFeeRefundedAt:
          (json['caution_fee_refunded_at'] ??
                  payment['caution_fee_refunded_at'])
              ?.toString(),
      // Without a quoted total, the charge is the stay amount itself rather
      // than zero: a "₦0" booking would read as free.
      totalAmount: total ?? amount ?? '0.00',
      hostPayout:
          (json['host_payout'] ??
                  payment['host_payout'] ??
                  json['landlord_payout'] ??
                  payment['landlord_payout'] ??
                  '0.00')
              .toString(),
      hostPayoutStatus: HostPayoutStatus.fromString(
        (json['host_payout_status'] ??
                payment['host_payout_status'] ??
                json['landlord_payout_status'] ??
                payment['landlord_payout_status'])
            ?.toString(),
      ),
      hostPayoutStatusLabel:
          (json['host_payout_status_label'] ??
                  payment['host_payout_status_label'] ??
                  '')
              .toString(),
      hostPayoutStatusDescription:
          (json['host_payout_status_description'] ??
                  payment['host_payout_status_description'] ??
                  '')
              .toString(),
      // `escrow_release_at` carries the same moment (API guide 20), for a
      // payload that only has the payment's own field.
      hostPayoutReleaseAt:
          (json['host_payout_release_at'] ??
                  payment['host_payout_release_at'] ??
                  json['escrow_release_at'] ??
                  payment['escrow_release_at'])
              ?.toString(),
      hostPaidAt:
          (json['host_paid_at'] ??
                  payment['host_paid_at'] ??
                  json['landlord_paid_at'] ??
                  payment['landlord_paid_at'])
              ?.toString(),
      cautionFeeEscrowStatus:
          (json['caution_fee_escrow_status'] ??
                  payment['caution_fee_escrow_status'] ??
                  '')
              .toString(),
      cautionFeeReleaseReadyAt:
          (json['caution_fee_release_ready_at'] ??
                  payment['caution_fee_release_ready_at'])
              ?.toString(),
      cautionClaim: switch (json['caution_claim'] ?? payment['caution_claim']) {
        final Map<String, dynamic> claim => CautionClaim.fromJson(claim),
        _ => null,
      },
      tenantEmail: (json['tenant_email'] ?? json['guest_email'] ?? '')
          .toString(),
      tenantName:
          (json['tenant_name'] ??
                  json['guest_name'] ??
                  json['tenant_full_name'] ??
                  '')
              .toString(),
      paymentId: (json['payment_id'] ?? payment['id'])?.toString(),
      paymentReference: (json['reference'] ?? payment['reference'])?.toString(),
      authorizationUrl:
          (json['authorization_url'] ?? payment['authorization_url'])
              ?.toString(),
      accessCode: (json['access_code'] ?? payment['access_code'])?.toString(),
      paymentDeadline:
          (json['payment_deadline'] ?? json['pay_by'] ?? json['expires_at'])
              ?.toString(),
      checkInNotes:
          (json['check_in_notes'] ?? listingMap['check_in_notes'] ?? '')
              .toString(),
      disputeReason: (json['dispute_reason'] ?? payment['dispute_reason'] ?? '')
          .toString(),
      disputedAt: (json['disputed_at'] ?? payment['disputed_at'])?.toString(),
      conversationId:
          (json['conversation_id'] ??
                  (json['conversation'] is Map
                      ? (json['conversation'] as Map)['id']
                      : json['conversation']) ??
                  '')
              .toString(),
      hasReview: json['has_review'] == true || json['review'] != null,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  DateTime? get checkInDate => ShortLetListing._parse(checkIn);
  DateTime? get checkOutDate => ShortLetListing._parse(checkOut);

  /// Nights slept, which is the gap between the two dates rather than the
  /// number of calendar days touched.
  int get nights {
    final start = checkInDate;
    final end = checkOutDate;
    if (start == null || end == null) return 0;
    final difference = end.difference(start).inDays;
    return difference > 0 ? difference : 0;
  }

  String get title {
    if (propertyName.isNotEmpty && unitNumber.isNotEmpty) {
      return '$propertyName · Unit $unitNumber';
    }
    if (propertyName.isNotEmpty) return propertyName;
    if (unitNumber.isNotEmpty) return 'Unit $unitNumber';
    return 'Short stay';
  }

  /// Who is staying, for a landlord's list.
  String get guestLabel => tenantName.isNotEmpty
      ? tenantName
      : (tenantEmail.isNotEmpty ? tenantEmail : 'A guest');

  /// Whether there is a provider checkout worth opening.
  bool get hasCheckout =>
      authorizationUrl != null && authorizationUrl!.trim().isNotEmpty;

  /// Whether a refundable deposit forms part of this booking.
  bool get hasCautionFee => (OasisCurrency.minorUnits(cautionFee) ?? 0) > 0;

  /// Whether the deposit has already come back.
  bool get isCautionFeeRefunded =>
      cautionFeeRefundedAt != null && cautionFeeRefundedAt!.isNotEmpty;

  /// The backend's current refund quote is meaningful only when it contains a
  /// positive amount. It is a disclosure, not a local eligibility decision.
  bool get hasRefundQuote =>
      (OasisCurrency.minorUnits(totalRefundAmount) ?? 0) > 0;

  /// The booking has not started and is in a state the tenant can cancel.
  /// The server still decides the actual refund and may refuse stale data.
  bool get canBeCancelledByTenant =>
      status.isCancellableByTenant ||
      (status == ShortLetBookingStatus.paid && !hasCheckedOut);

  /// Whether the host can withdraw from this booking themselves: an
  /// emergency, not a scheduled reject. Only before the guest has arrived:
  /// the backend routes anything after check-in through support instead of
  /// this endpoint.
  bool get canBeCancelledByHost =>
      status == ShortLetBookingStatus.pending ||
      status == ShortLetBookingStatus.approved ||
      status == ShortLetBookingStatus.paid;

  /// [ShortLetBookingStatus.isDisputable] can only read the booking's
  /// journey; this adds the one thing it cannot see: whether there is
  /// still a payout to block. A stay already paid out, already blocked by an
  /// earlier dispute, or already refunded has nothing left for a second
  /// dispute to hold.
  bool get canDispute {
    if (!status.isDisputable) return false;
    switch (hostPayoutStatus) {
      case HostPayoutStatus.released:
      case HostPayoutStatus.blocked:
      case HostPayoutStatus.refunded:
        return false;
      case HostPayoutStatus.notFunded:
      case HostPayoutStatus.held:
      case HostPayoutStatus.unknown:
        // Unknown means the backend has not sent payout fields yet: fall
        // back to the journey-only answer rather than hiding the button.
        return true;
    }
  }

  /// Whether the host may open a caution-fee claim: there is a deposit, it
  /// has not already gone back to the guest, the stay is over, no claim is
  /// open yet, and the 24-hour window has not closed. The backend enforces
  /// the window itself; this stops the button outliving it.
  bool get canClaimCautionFee =>
      hasCautionFee &&
      !isCautionFeeRefunded &&
      cautionClaim == null &&
      _isStayOver &&
      !_claimWindowClosed;

  bool get _isStayOver =>
      status == ShortLetBookingStatus.checkedOut ||
      status == ShortLetBookingStatus.completed ||
      (status.isPaid && hasCheckedOut);

  /// When the claim window closes, in local time, if the backend said.
  DateTime? get cautionClaimDeadline =>
      DateTime.tryParse(cautionFeeReleaseReadyAt ?? '')?.toLocal();

  bool get _claimWindowClosed {
    final deadline = cautionClaimDeadline;
    return deadline != null && !DateTime.now().isBefore(deadline);
  }

  /// Time the host has left to inspect and claim, or null when that is not
  /// the situation or the backend sent no deadline.
  Duration? get cautionClaimWindowLeft {
    if (!isAwaitingCheckoutInspection) return null;
    final deadline = cautionClaimDeadline;
    if (deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// The stay is over, the caution fee is still held, and the host has not
  /// claimed or released it: the host's checkout inspection is due.
  bool get isAwaitingCheckoutInspection =>
      canClaimCautionFee && status != ShortLetBookingStatus.disputed;

  /// Where the guest's caution fee stands, for the guest's own screens.
  CautionFeeStage get cautionFeeStage {
    if (!hasCautionFee) return CautionFeeStage.none;
    if (isCautionFeeRefunded) return CautionFeeStage.returned;
    final claim = cautionClaim;
    if (claim != null) {
      if (claim.status == CautionClaimStatus.open) {
        return CautionFeeStage.claimed;
      }
      if (claim.status.isUnderReview) return CautionFeeStage.underReview;
      return CautionFeeStage.settled;
    }
    if (status == ShortLetBookingStatus.disputed) {
      return CautionFeeStage.underReview;
    }
    if (!status.isPaid) return CautionFeeStage.none;
    if (_isStayOver) return CautionFeeStage.inspection;
    return CautionFeeStage.held;
  }

  /// What the stay itself costs, with the deposit taken back out.
  ///
  /// The guest is told one number to pay, but two things are inside it, and
  /// only one of them is money they are spending.
  String get amountExcludingCautionFee => hasCautionFee
      ? (OasisCurrency.subtract(totalAmount, cautionFee) ?? totalAmount)
      : totalAmount;

  /// The backend's status word, tidied for display: "PAYMENT_FAILED"
  /// becomes "Payment failed". Empty when the backend sent no status at all,
  /// which is its own kind of answer.
  String get rawStatusLabel {
    final raw = rawStatus.trim();
    if (raw.isEmpty) return '';
    final words = raw.replaceAll('_', ' ').toLowerCase();
    return words[0].toUpperCase() + words.substring(1);
  }

  /// [hostPayoutStatusLabel] when the backend sent one, falling back to a
  /// local guess when it did not. Shown to the host, next to and separate
  /// from the booking-status pill: the whole point of splitting these two
  /// fields apart.
  String get resolvedHostPayoutLabel {
    final label = hostPayoutStatusLabel.trim();
    return label.isEmpty ? hostPayoutStatus.fallbackLabel : label;
  }

  /// Same fallback rule as [resolvedHostPayoutLabel], for the longer
  /// explanatory sentence.
  String get resolvedHostPayoutDescription =>
      hostPayoutStatusDescription.trim();

  /// Whether guest and host can message each other about this stay.
  ///
  /// Gated on payment on purpose: the thread is for arranging a stay that is
  /// actually happening (where the key is, what the gate code is) not a way
  /// to negotiate before one exists.
  bool get canMessage => status.isPaid;

  /// Whether checkout is behind us, using the date rather than any flag:
  /// the backend has no "stayed" status, and the calendar is the fact.
  bool get hasCheckedOut {
    final end = checkOutDate;
    if (end == null) return false;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).isAfter(end) ||
        DateTime(now.year, now.month, now.day).isAtSameMomentAs(end);
  }

  /// Whether to offer this guest a review form: they paid, they have been,
  /// and they have not written one yet.
  bool get canReview => status.isPaid && hasCheckedOut && !hasReview;

  /// How long is left to pay for an approved booking, or null when that is
  /// not the situation or the backend sent no deadline.
  ///
  /// Compared against the clock rather than trusted as a stored flag, because
  /// the window closes on its own while the screen is open.
  Duration? get timeLeftToPay {
    if (!status.needsPayment) return null;
    final raw = paymentDeadline;
    if (raw == null || raw.isEmpty) return null;
    final deadline = DateTime.tryParse(raw)?.toLocal();
    if (deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  ShortLetBooking copyWith({
    String? id,
    String? listingId,
    String? unitNumber,
    String? propertyName,
    String? address,
    String? checkIn,
    String? checkOut,
    int? guestCount,
    String? message,
    ShortLetBookingStatus? status,
    String? rawStatus,
    String? nightlyPrice,
    String? amount,
    String? platformFee,
    String? cautionFee,
    ShortLetCancellationPolicy? cancellationPolicy,
    int? cancellationPolicyVersion,
    String? accommodationRefundAmount,
    String? platformFeeRefundAmount,
    String? cautionFeeRefundAmount,
    String? totalRefundAmount,
    String? cautionFeeRefundedAt,
    String? totalAmount,
    String? hostPayout,
    HostPayoutStatus? hostPayoutStatus,
    String? hostPayoutStatusLabel,
    String? hostPayoutStatusDescription,
    String? hostPayoutReleaseAt,
    String? hostPaidAt,
    String? cautionFeeEscrowStatus,
    String? cautionFeeReleaseReadyAt,
    CautionClaim? cautionClaim,
    String? conversationId,
    bool? hasReview,
    String? tenantEmail,
    String? tenantName,
    String? paymentId,
    String? paymentReference,
    String? authorizationUrl,
    String? accessCode,
    String? paymentDeadline,
    String? checkInNotes,
    String? disputeReason,
    String? disputedAt,
    String? createdAt,
  }) => ShortLetBooking(
    id: id ?? this.id,
    listingId: listingId ?? this.listingId,
    unitNumber: unitNumber ?? this.unitNumber,
    propertyName: propertyName ?? this.propertyName,
    address: address ?? this.address,
    checkIn: checkIn ?? this.checkIn,
    checkOut: checkOut ?? this.checkOut,
    guestCount: guestCount ?? this.guestCount,
    message: message ?? this.message,
    status: status ?? this.status,
    rawStatus: rawStatus ?? this.rawStatus,
    nightlyPrice: nightlyPrice ?? this.nightlyPrice,
    amount: amount ?? this.amount,
    platformFee: platformFee ?? this.platformFee,
    cautionFee: cautionFee ?? this.cautionFee,
    cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
    cancellationPolicyVersion:
        cancellationPolicyVersion ?? this.cancellationPolicyVersion,
    accommodationRefundAmount:
        accommodationRefundAmount ?? this.accommodationRefundAmount,
    platformFeeRefundAmount:
        platformFeeRefundAmount ?? this.platformFeeRefundAmount,
    cautionFeeRefundAmount:
        cautionFeeRefundAmount ?? this.cautionFeeRefundAmount,
    totalRefundAmount: totalRefundAmount ?? this.totalRefundAmount,
    cautionFeeRefundedAt: cautionFeeRefundedAt ?? this.cautionFeeRefundedAt,
    totalAmount: totalAmount ?? this.totalAmount,
    hostPayout: hostPayout ?? this.hostPayout,
    hostPayoutStatus: hostPayoutStatus ?? this.hostPayoutStatus,
    hostPayoutStatusLabel: hostPayoutStatusLabel ?? this.hostPayoutStatusLabel,
    hostPayoutStatusDescription:
        hostPayoutStatusDescription ?? this.hostPayoutStatusDescription,
    hostPayoutReleaseAt: hostPayoutReleaseAt ?? this.hostPayoutReleaseAt,
    hostPaidAt: hostPaidAt ?? this.hostPaidAt,
    cautionFeeEscrowStatus:
        cautionFeeEscrowStatus ?? this.cautionFeeEscrowStatus,
    cautionFeeReleaseReadyAt:
        cautionFeeReleaseReadyAt ?? this.cautionFeeReleaseReadyAt,
    cautionClaim: cautionClaim ?? this.cautionClaim,
    conversationId: conversationId ?? this.conversationId,
    hasReview: hasReview ?? this.hasReview,
    tenantEmail: tenantEmail ?? this.tenantEmail,
    tenantName: tenantName ?? this.tenantName,
    paymentId: paymentId ?? this.paymentId,
    paymentReference: paymentReference ?? this.paymentReference,
    authorizationUrl: authorizationUrl ?? this.authorizationUrl,
    accessCode: accessCode ?? this.accessCode,
    paymentDeadline: paymentDeadline ?? this.paymentDeadline,
    checkInNotes: checkInNotes ?? this.checkInNotes,
    disputeReason: disputeReason ?? this.disputeReason,
    disputedAt: disputedAt ?? this.disputedAt,
    createdAt: createdAt ?? this.createdAt,
  );

  /// Merges a cancel-preview response's refund/policy fields onto this
  /// booking, leaving identity, dates and status untouched.
  ///
  /// The preview endpoint's response shape is not documented as of the
  /// current API guide, so this parses it with the exact same defensive keys
  /// [ShortLetBooking.fromJson] already reads for the refund breakdown,
  /// rather than assuming the preview payload is a full booking object, and
  /// keeps only that slice of it.
  ShortLetBooking withCancelPreview(Map<String, dynamic> json) {
    final preview = ShortLetBooking.fromJson(json);
    return copyWith(
      cancellationPolicy: preview.cancellationPolicy,
      cancellationPolicyVersion: preview.cancellationPolicyVersion,
      accommodationRefundAmount: preview.accommodationRefundAmount,
      platformFeeRefundAmount: preview.platformFeeRefundAmount,
      cautionFeeRefundAmount: preview.cautionFeeRefundAmount,
      totalRefundAmount: preview.totalRefundAmount,
    );
  }
}

/// Reads an int from a value that may arrive as a number or a string.
int? _readInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

/// Reads a double from a value that may arrive as a number or a string.
double? _readDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

/// Normalises a date to `YYYY-MM-DD`, tolerating a full timestamp.
String? _readDate(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  return raw.length >= 10 ? raw.substring(0, 10) : raw;
}

/// Reads a string, treating an empty one as absent: a `""` video URL is a
/// field the backend has not filled in, not a video at an empty address.
String? _readNonEmpty(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

List<String> _readStrings(Object? value) => value is List
    ? value.map((item) => item.toString()).where((s) => s.isNotEmpty).toList()
    : const [];

/// Reads photo data from both listing serializers. Most endpoints return a
/// list of URL strings, while media endpoints return objects with `image_url`.
/// Supporting both means a serializer optimisation cannot turn every Stays
/// card into a placeholder.
List<String> _readMediaUrls(Object? value) => value is List
    ? value.map(_readMediaUrl).whereType<String>().toList(growable: false)
    : const [];

/// Converts a media value into an address `Image.network` can load.
///
/// The deployed API sends absolute URLs, but older rows can still contain a
/// `/media/...` path. Resolve those against the API origin rather than the
/// `/api/users` path; otherwise Flutter requests a non-existent
/// `/api/users/media/...` resource.
String? _readMediaUrl(Object? value) {
  final raw = switch (value) {
    Map map => (map['image_url'] ?? map['url'] ?? map['src'])?.toString(),
    _ => value?.toString(),
  }?.trim();
  if (raw == null || raw.isEmpty) return null;

  if (raw.startsWith('//')) return 'https:$raw';

  final uri = Uri.tryParse(raw);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return raw;

  final apiUri = Uri.parse(ApiConstants.baseUrl);
  final origin = apiUri.replace(path: '/', query: null, fragment: null);
  return origin.resolve(raw).toString();
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// `YYYY-MM-DD` for the API, from a picked date.
String shortLetIsoDate(DateTime date) => _isoDate(date);

/// Where a guest's caution fee stands.
enum CautionFeeStage {
  /// No caution fee on this booking, or nothing paid yet.
  none,

  /// Paid and held while the stay is ahead or under way.
  held,

  /// The stay is over and the host is inside the 24-hour claim window.
  inspection,

  /// The host has claimed some or all of it and the guest needs to answer.
  claimed,

  /// The guest rejected or countered, or reported a problem: Oasis decides.
  underReview,

  /// A claim was agreed and the money has been split.
  settled,

  /// Back in the guest's vault.
  returned,
}

enum CautionClaimStatus {
  /// Waiting for the guest to accept, reject or counter.
  open,
  accepted,
  rejected,
  countered,

  /// Settled by Oasis support after a rejection or counter.
  resolved,
  unknown;

  static CautionClaimStatus fromString(String? value) =>
      switch (value?.trim().toUpperCase()) {
        'OPEN' || 'PENDING' || 'AWAITING_TENANT' => CautionClaimStatus.open,
        'ACCEPTED' => CautionClaimStatus.accepted,
        'REJECTED' => CautionClaimStatus.rejected,
        'COUNTERED' => CautionClaimStatus.countered,
        'RESOLVED' || 'CLOSED' || 'SETTLED' => CautionClaimStatus.resolved,
        _ => CautionClaimStatus.unknown,
      };

  bool get isUnderReview =>
      this == CautionClaimStatus.rejected ||
      this == CautionClaimStatus.countered;
}

/// A host's claim against a guest's caution fee (spec v16 §7).
class CautionClaim {
  final String id;
  final CautionClaimStatus status;
  final String claimedAmount;
  final String reason;
  final String counterAmount;
  final List<String> evidence;
  final String createdAt;

  const CautionClaim({
    required this.id,
    required this.status,
    this.claimedAmount = '0.00',
    this.reason = '',
    this.counterAmount = '',
    this.evidence = const [],
    this.createdAt = '',
  });

  factory CautionClaim.fromJson(Map<String, dynamic> json) => CautionClaim(
    id: json['id']?.toString() ?? '',
    status: CautionClaimStatus.fromString(json['status']?.toString()),
    claimedAmount: (json['claimed_amount'] ?? json['amount'] ?? '0.00')
        .toString(),
    reason: (json['reason'] ?? '').toString(),
    counterAmount: (json['counter_amount'] ?? '').toString(),
    evidence: [
      for (final url
          in (json['evidence'] is List ? json['evidence'] as List : const []))
        if (url is String && url.isNotEmpty) url,
    ],
    createdAt: (json['created_at'] ?? '').toString(),
  );
}
