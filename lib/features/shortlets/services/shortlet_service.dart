import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/shortlet_models.dart';

/// Talks to the short-let endpoints.
///
/// Unlike the vault, these *are* role-branched: the backend serves landlords
/// and tenants from separate paths, because the two see different things about
/// the same booking. A landlord sees who is asking, a tenant sees what it
/// costs. The service mirrors that split rather than hiding it, so a call can
/// never quietly hit the wrong role's route.
class ShortLetService {
  final ApiClient _apiClient;

  ShortLetService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  // ---------------------------------------------------------------- landlord

  /// The landlord's own listings, active or not.
  Future<List<ShortLetListing>> getLandlordListings() async {
    debugPrint(
      '[SHORTLET SERVICE] Fetching listings GET ${ApiConstants.landlordShortLetsEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.landlordShortLetsEndpoint,
    );
    final listings = _listOf(response, ShortLetListing.fromJson);
    debugPrint('[SHORTLET SERVICE] ${listings.length} listing(s)');
    return listings;
  }

  /// Creates a listing, or edits one that already exists.
  ///
  /// [listingId] decides which. Null means create: `POST` to the collection.
  /// Supplied means edit: `PATCH` the listing's own path.
  ///
  /// This used to be one `POST` for both, because the backend keyed a listing
  /// to its unit and quietly treated a second post as an edit. API guide 18
  /// ends that: a second `POST` for a unit that already has a listing is
  /// refused with `409 LISTING_EXISTS`. Sending an edit as a create now
  /// fails, which is why every caller has to say which it is doing.
  ///
  /// [availableFrom]/[availableTo] are the host's booking window, and both
  /// are genuinely optional: a host who takes bookings whenever sets
  /// neither. They are sent as explicit JSON `null` rather than omitted,
  /// for two reasons: an omitted key cannot *clear* a window the host set
  /// last time (the old value simply survives the save), and a serializer
  /// that accepts null tells us so, where an absent key is indistinguishable
  /// from a field the backend has never heard of.
  ///
  /// [cautionFee] is the refundable deposit, `"0.00"` when the host wants
  /// none. Always sent, so turning a deposit off is a save like any other.
  /// [cancellationPolicy] is optional for the host; the app explicitly sends
  /// the selected value so editing a listing never silently keeps old terms.
  ///
  /// [description] is the host's write-up of the place, and is always sent,
  /// including empty, for the same reason the window is: an omitted key
  /// cannot clear a paragraph the host has just deleted.
  Future<ShortLetListing> saveListing({
    required String unitId,
    String? listingId,
    required String nightlyPrice,
    required int minimumNights,
    required int maximumGuests,
    String description = '',
    String cautionFee = '0.00',
    ShortLetCancellationPolicy cancellationPolicy =
        ShortLetCancellationPolicy.flexible,
    String? availableFrom,
    String? availableTo,
    List<String> blockedDates = const [],
    String houseRules = '',
    String checkInNotes = '',
    bool isActive = true,
  }) async {
    final isEdit = listingId != null && listingId.isNotEmpty;
    final endpoint = isEdit
        ? ApiConstants.landlordShortLetDetailEndpoint(listingId)
        : ApiConstants.landlordShortLetsEndpoint;
    // `unit` is only meaningful on a create. On an edit the listing already
    // knows its unit, and moving one between units is not a thing the API
    // offers: sending it would be asking for a rejection.
    final body = <String, dynamic>{
      if (!isEdit) 'unit': unitId,
      'nightly_price': nightlyPrice,
      'minimum_nights': minimumNights,
      'maximum_guests': maximumGuests,
      'description': description,
      'caution_fee': cautionFee,
      'cancellation_policy': cancellationPolicy.wireValue,
      'available_from': availableFrom,
      'available_to': availableTo,
      'blocked_dates': blockedDates,
      'house_rules': houseRules,
      'check_in_notes': checkInNotes,
      'is_active': isActive,
    };

    debugPrint(
      '[SHORTLET SERVICE] ${isEdit ? 'Editing' : 'Creating'} listing '
      '${isEdit ? 'PATCH' : 'POST'} $endpoint '
      '(unit=$unitId, ₦$nightlyPrice/night, deposit=₦$cautionFee, '
      'window=${availableFrom ?? 'any'}→${availableTo ?? 'any'}, active=$isActive)',
    );
    final response = isEdit
        ? await _apiClient.patch(endpoint, body: body)
        : await _apiClient.post(endpoint, body: body);
    return ShortLetListing.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Booking requests across all of the landlord's listings.
  Future<List<ShortLetBooking>> getLandlordBookings() async {
    debugPrint(
      '[SHORTLET SERVICE] Fetching bookings GET ${ApiConstants.landlordShortLetBookingsEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.landlordShortLetBookingsEndpoint,
    );
    final bookings = _listOf(response, ShortLetBooking.fromJson);
    debugPrint('[SHORTLET SERVICE] ${bookings.length} booking(s)');
    return bookings;
  }

  /// Approves a request, which starts the guest's 24-hour payment window.
  Future<ShortLetBooking> approveBooking(String bookingId) async {
    final endpoint = ApiConstants.approveShortLetBookingEndpoint(bookingId);
    debugPrint('[SHORTLET SERVICE] Approving $bookingId POST $endpoint');
    final response = await _apiClient.post(endpoint, body: <String, dynamic>{});
    return ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Declines a request. [reason] is sent when the landlord gave one: the
  /// guest is told, so a blank rejection is worth avoiding where possible.
  Future<ShortLetBooking> rejectBooking(
    String bookingId, {
    String? reason,
  }) async {
    final endpoint = ApiConstants.rejectShortLetBookingEndpoint(bookingId);
    debugPrint('[SHORTLET SERVICE] Rejecting $bookingId POST $endpoint');
    final response = await _apiClient.post(
      endpoint,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  // ------------------------------------------------------------------ tenant

  /// Active listings a verified tenant can book.
  ///
  /// Two ways to narrow it, and they are alternatives rather than a pair:
  /// [location] is a typed area name, [latitude]/[longitude] are the device's
  /// own position. Coordinates win when both are somehow set, because a guest
  /// who has just allowed location is asking about where they are standing.
  ///
  /// [radiusKm] is only meaningful with coordinates; left null the backend
  /// applies its own 10km default, which is what the app wants: no reason to
  /// hard-code a number here that the backend already owns.
  ///
  /// [checkIn]/[checkOut] are a different axis and sit alongside either: they
  /// do not filter the results, they annotate them. The backend still returns
  /// stays that are taken for those dates, tagged with
  /// `is_available_for_period` and a reason, and the app is required to show
  /// them rather than quietly drop them. Both dates go together: one alone
  /// describes no period, so neither is sent.
  ///
  /// [minPrice]/[maxPrice] filter by nightly price when no dates are set, or
  /// by total stay price for the searched dates once they are: the backend
  /// decides which, on its own, depending on whether [checkIn]/[checkOut]
  /// are present. Decimal strings, same as every other amount this app sends.
  ///
  /// [minBedrooms] narrows to places with at least that many bedrooms. Sent
  /// as a floor rather than an exact count because that is how the question
  /// is actually asked: a family of five needs *at least* three rooms and
  /// will happily take four. See `backend_change_spec_v11.md` §3; the
  /// controller filters the response as well, so the control works against a
  /// deployment that has not shipped the parameter yet.
  Future<List<ShortLetListing>> browseListings({
    String? location,
    double? latitude,
    double? longitude,
    int? radiusKm,
    String? checkIn,
    String? checkOut,
    String? minPrice,
    String? maxPrice,
    int? minBedrooms,
  }) async {
    final hasCoordinates = latitude != null && longitude != null;
    final hasDates =
        checkIn != null &&
        checkIn.isNotEmpty &&
        checkOut != null &&
        checkOut.isNotEmpty;
    final query = location?.trim();
    debugPrint(
      '[SHORTLET SERVICE] Browsing GET ${ApiConstants.tenantShortLetsEndpoint} '
      '(${hasCoordinates ? 'near $latitude,$longitude' : 'location=${query?.isNotEmpty == true ? query : '-'}'}'
      '${hasDates ? ', $checkIn → $checkOut' : ''}'
      '${minPrice != null || maxPrice != null ? ', ₦${minPrice ?? '0'}–₦${maxPrice ?? '∞'}' : ''}'
      '${minBedrooms != null ? ', $minBedrooms+ bedrooms' : ''})',
    );
    final response = await _apiClient.get(
      ApiConstants.tenantShortLetsEndpoint,
      queryParameters: {
        if (hasCoordinates) ...{
          'latitude': latitude.toStringAsFixed(6),
          'longitude': longitude.toStringAsFixed(6),
          'radius_km': radiusKm?.toString(),
        } else
          'location': (query?.isEmpty ?? true) ? null : query,
        if (hasDates) ...{'check_in': checkIn, 'check_out': checkOut},
        'min_price': minPrice,
        'max_price': maxPrice,
        'min_bedrooms': minBedrooms?.toString(),
      },
    );
    final listings = _listOf(response, ShortLetListing.fromJson);
    debugPrint(
      '[SHORTLET SERVICE] ${listings.length} listing(s), '
      '${listings.where((l) => l.isUnavailableForPeriod).length} taken for '
      'those dates',
    );
    return listings;
  }

  /// The tenant's own bookings, in every state.
  Future<List<ShortLetBooking>> getMyBookings() async {
    debugPrint(
      '[SHORTLET SERVICE] Fetching my bookings GET ${ApiConstants.tenantShortLetBookingsEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.tenantShortLetBookingsEndpoint,
    );
    return _listOf(response, ShortLetBooking.fromJson);
  }

  /// Requests dates. The backend re-checks minimum nights, guest count,
  /// availability, blocked dates and clashes with approved bookings, so a
  /// rejection here is authoritative and its wording is worth showing as sent.
  Future<ShortLetBooking> requestBooking({
    required String listingId,
    required String checkIn,
    required String checkOut,
    required int guestCount,
    String message = '',
  }) async {
    debugPrint(
      '[SHORTLET SERVICE] Requesting booking POST ${ApiConstants.tenantShortLetBookingsEndpoint} '
      '($checkIn → $checkOut, $guestCount guest(s))',
    );
    final response = await _apiClient.post(
      ApiConstants.tenantShortLetBookingsEndpoint,
      body: {
        'listing': listingId,
        'check_in': checkIn,
        'check_out': checkOut,
        'guest_count': guestCount,
        if (message.trim().isNotEmpty) 'message': message.trim(),
      },
    );
    final booking = ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[SHORTLET SERVICE] Booking ${booking.id} → ${booking.status.label}',
    );
    return booking;
  }

  /// Withdraws a request, or (now that cancellation reaches paid,
  /// pre-check-in bookings too) cancels a paid stay under its cancellation
  /// policy. [reason] is optional either way.
  Future<ShortLetBooking> cancelBooking(
    String bookingId, {
    String? reason,
  }) async {
    final endpoint = ApiConstants.cancelShortLetBookingEndpoint(bookingId);
    debugPrint('[SHORTLET SERVICE] Cancelling $bookingId POST $endpoint');
    final response = await _apiClient.post(
      endpoint,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Quotes the refund a tenant would get for cancelling right now, without
  /// actually cancelling anything.
  ///
  /// Returns the raw body rather than a parsed booking: the response shape is
  /// undocumented, and [ShortLetBooking.withCancelPreview] is what actually
  /// interprets it, reading only the fields it recognises.
  Future<Map<String, dynamic>> getCancelPreview(String bookingId) async {
    final endpoint = ApiConstants.tenantShortLetCancelPreviewEndpoint(
      bookingId,
    );
    debugPrint('[SHORTLET SERVICE] Previewing cancel $bookingId GET $endpoint');
    final response = await _apiClient.get(endpoint);
    return response is Map<String, dynamic> ? response : const {};
  }

  /// The host's own withdrawal from a booking. [reason] is required: the
  /// backend does not accept this one bare, unlike a tenant cancellation.
  Future<ShortLetBooking> cancelBookingAsHost({
    required String bookingId,
    required String reason,
  }) async {
    final endpoint = ApiConstants.landlordCancelShortLetBookingEndpoint(
      bookingId,
    );
    debugPrint('[SHORTLET SERVICE] Host cancelling $bookingId POST $endpoint');
    final response = await _apiClient.post(
      endpoint,
      body: {'reason': reason.trim()},
    );
    return ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Pays for an approved booking, from a card or from the vault.
  ///
  /// [idempotencyKey] is generated once per payment intent and reused on every
  /// retry of that intent, so a request that times out and is tried again
  /// cannot charge twice.
  ///
  /// [vaultPin] is required for a vault payment and must not be sent for a
  /// card one: the PIN is a second factor on money leaving the vault, and
  /// attaching it to a card charge would put it on the wire for nothing.
  Future<ShortLetBooking> payForBooking({
    required String bookingId,
    required String idempotencyKey,
    required bool fromVault,
    String? vaultPin,
  }) async {
    final endpoint = ApiConstants.payShortLetBookingEndpoint(bookingId);
    debugPrint(
      '[SHORTLET SERVICE] Paying $bookingId POST $endpoint '
      '(source=${fromVault ? 'VAULT' : 'CARD'})',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {
        'source': fromVault ? 'VAULT' : 'CARD',
        if (fromVault && vaultPin != null) 'vault_pin': vaultPin,
      },
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    final booking = ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[SHORTLET SERVICE] Booking ${booking.id} → ${booking.status.label}, '
      'checkout=${booking.hasCheckout}',
    );
    return booking;
  }

  /// Confirms a card payment with the backend once provider checkout closes.
  ///
  /// The app never marks a booking paid itself: checkout closing tells us only
  /// that a browser went away, not that money moved.
  Future<ShortLetBooking> verifyPayment({
    required String paymentId,
    String? reference,
  }) async {
    final endpoint = ApiConstants.verifyShortLetPaymentEndpoint(paymentId);
    debugPrint(
      '[SHORTLET SERVICE] Verifying payment $paymentId POST $endpoint',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {
        if (reference != null && reference.isNotEmpty) 'reference': reference,
      },
    );
    final booking = ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[SHORTLET SERVICE] Payment $paymentId → ${booking.status.label}',
    );
    return booking;
  }

  /// Raises a dispute on a paid stay while its refundable caution fee is held.
  ///
  /// The backend releases only the caution fee after checkout, so this has to
  /// land before that job runs: a dispute is what makes it skip that refund.
  Future<ShortLetBooking> disputePayment({
    required String paymentId,
    String? reason,
  }) async {
    final endpoint = ApiConstants.disputeShortLetPaymentEndpoint(paymentId);
    debugPrint('[SHORTLET SERVICE] Disputing $paymentId POST $endpoint');
    final response = await _apiClient.post(
      endpoint,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    final booking = ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[SHORTLET SERVICE] Payment $paymentId → ${booking.status.label}',
    );
    return booking;
  }

  /// Tells the backend the guest's problem is settled, so the host payout,
  /// blocked since the dispute, can release. If the normal release time has
  /// already passed, the backend releases it immediately on this call.
  Future<ShortLetBooking> resolveDispute({
    required String paymentId,
    String? note,
  }) async {
    final endpoint = ApiConstants.resolveShortLetDisputeEndpoint(paymentId);
    debugPrint(
      '[SHORTLET SERVICE] Resolving dispute $paymentId POST $endpoint',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    final booking = ShortLetBooking.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[SHORTLET SERVICE] Payment $paymentId → ${booking.status.label}',
    );
    return booking;
  }

  /// Host claims some or all of a checked-out stay's caution fee.
  ///
  /// [claimedAmount] left null claims the whole deposit, per the backend's
  /// own rule. The response shape for the created claim is not documented:
  /// this returns the raw body and callers refresh the booking list rather
  /// than trying to parse a claim object out of it.
  Future<Map<String, dynamic>> openCautionClaim({
    required String bookingId,
    String? claimedAmount,
    required String reason,
    List<String> evidence = const [],
  }) async {
    final endpoint = ApiConstants.openShortLetCautionClaimEndpoint(bookingId);
    debugPrint(
      '[SHORTLET SERVICE] Opening caution claim $bookingId POST $endpoint',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {
        if (claimedAmount != null) 'claimed_amount': claimedAmount,
        'reason': reason.trim(),
        if (evidence.isNotEmpty) 'evidence': evidence,
      },
    );
    return response is Map<String, dynamic> ? response : const {};
  }

  /// Tenant answers a caution-fee claim: accept it, reject it, or counter
  /// with a smaller amount.
  Future<Map<String, dynamic>> respondToCautionClaim({
    required String claimId,
    required String response,
    String? counterAmount,
    String? note,
  }) async {
    final endpoint = ApiConstants.respondToShortLetCautionClaimEndpoint(
      claimId,
    );
    debugPrint(
      '[SHORTLET SERVICE] Responding to claim $claimId ($response) '
      'POST $endpoint',
    );
    final result = await _apiClient.post(
      endpoint,
      body: {
        'response': response,
        if (counterAmount != null) 'counter_amount': counterAmount,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return result is Map<String, dynamic> ? result : const {};
  }

  /// Reads a list response in either shape the API uses: a bare array, or a
  /// paginated envelope with a `results` key.
  List<T> _listOf<T>(dynamic response, T Function(Map<String, dynamic>) parse) {
    if (response is List) {
      return response.whereType<Map<String, dynamic>>().map(parse).toList();
    }
    if (response is Map<String, dynamic> && response['results'] is List) {
      return (response['results'] as List)
          .whereType<Map<String, dynamic>>()
          .map(parse)
          .toList();
    }
    return const [];
  }
}
