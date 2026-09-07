import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/shortlet_models.dart';
import '../services/shortlet_service.dart';

/// Holds short lets for whichever role is signed in.
///
/// One controller for both roles, but separate lists: a landlord's listings
/// and a tenant's browse results come from different endpoints and mean
/// different things, so collapsing them into one field would let a stale
/// landlord list render on a tenant's screen after a role switch.
///
/// Caches per-user data, so it must be wiped between sessions: a booking left
/// behind after sign-out would be shown to whoever signs in next.
class ShortLetController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  /// Keys for [LoadedOnceState], one per independent fetch.
  ///
  /// Named constants rather than string literals at eight call sites: a typo
  /// in one of them shows up as a skeleton that never resolves, which is a
  /// horrible bug to find by eye.
  static const String kBrowseKey = 'browse';
  static const String kListingsKey = 'listings';
  static const String kBookingsKey = 'bookings';

  final ShortLetService _service;

  ShortLetController({ShortLetService? service})
    : _service = service ?? ShortLetService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// True while a decision, booking, cancellation or payment is in flight, so
  /// a second tap cannot start a second one.
  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  /// Bookings the landlord is currently deciding on, by id. Per-booking rather
  /// than a single flag so approving one request does not grey out the rest.
  final Set<String> _decidingBookingIds = {};
  bool isDeciding(String bookingId) => _decidingBookingIds.contains(bookingId);

  List<ShortLetListing> _listings = [];

  /// The landlord's own listings.
  List<ShortLetListing> get listings => _listings;

  /// The listing this landlord already has on [unitId], or null when the
  /// unit is not let by the night yet.
  ///
  /// The backend keys a listing to its unit, so posting the same unit twice
  /// quietly edits the first listing instead of refusing, which reads, from
  /// the host's side, as the second listing having vanished, or worse, as
  /// their nightly price having changed on a place they thought they were
  /// adding fresh. The app checks first and says so.
  ///
  /// Only as good as [listings]: a unit listed on another device since the
  /// last fetch will not be found here, which is why the save path treats
  /// this as a warning to the host rather than the last word.
  ShortLetListing? listingForUnit(String unitId) {
    if (unitId.isEmpty) return null;
    for (final listing in _listings) {
      if (listing.unitId == unitId) return listing;
    }
    return null;
  }

  List<ShortLetListing> _browseListings = [];

  /// What a tenant can book right now.
  List<ShortLetListing> get browseListings => _browseListings;

  String _searchQuery = '';

  /// The typed area name currently narrowing the browse list.
  String get searchQuery => _searchQuery;

  double? _latitude;
  double? _longitude;

  /// Whether the browse list is being sorted by distance from the device.
  ///
  /// Mutually exclusive with [searchQuery] by construction: setting one
  /// clears the other, because the backend takes coordinates *or* a name and
  /// showing both controls as active would be a lie about which one produced
  /// the results on screen.
  bool get isSearchingNearby => _latitude != null && _longitude != null;

  DateTimeRange? _searchDates;

  /// The dates the browse list is being checked against, if any.
  ///
  /// A separate axis from where: dates do not filter the list, they annotate
  /// it. The backend returns stays that are taken for these dates too, and
  /// this is what tells the screen to render that state.
  DateTimeRange? get searchDates => _searchDates;
  bool get hasSearchDates => _searchDates != null;

  String? _minPrice;
  String? _maxPrice;

  /// The price range narrowing the browse list, as decimal strings: nightly
  /// price with no dates set, total stay price once they are (the backend
  /// switches which one it filters by on its own; the app just sends the
  /// range either way).
  String? get minPrice => _minPrice;
  String? get maxPrice => _maxPrice;
  bool get hasPriceFilter => _minPrice != null || _maxPrice != null;

  int? _minBedrooms;

  /// The smallest number of bedrooms the tenant will accept, or null for any.
  ///
  /// A floor rather than an exact count, because that is the question people
  /// actually ask: a family of five needs *at least* three rooms and will
  /// take four. Studios are counted as zero bedrooms, which is why "any" has
  /// to be null and not 0: 0 would be a filter for studios only.
  int? get minBedrooms => _minBedrooms;
  bool get hasBedroomsFilter => _minBedrooms != null;

  /// Whether anything is narrowing the browse list: what the empty state
  /// checks before suggesting the tenant widen it.
  ///
  /// Dates are deliberately excluded: they never remove a listing, so an
  /// empty list with dates set means the *place* found nothing, and offering
  /// to clear the dates would not bring anything back.
  bool get isBrowseNarrowed =>
      isSearchingNearby ||
      _searchQuery.isNotEmpty ||
      hasPriceFilter ||
      hasBedroomsFilter;

  /// Stays that cannot take the searched dates. Shown, never hidden: the
  /// tenant is owed the reason rather than a shorter list.
  List<ShortLetListing> get unavailableForDates =>
      _browseListings.where((l) => l.isUnavailableForPeriod).toList();

  List<ShortLetBooking> _bookings = [];

  /// Bookings for whichever role loaded them.
  List<ShortLetBooking> get bookings => _bookings;

  /// Requests still waiting on the landlord: the number worth badging.
  int get pendingBookingCount =>
      _bookings.where((b) => b.status.needsLandlordDecision).length;

  /// Approved bookings the tenant still has to pay for.
  List<ShortLetBooking> get bookingsAwaitingPayment =>
      _bookings.where((b) => b.status.needsPayment).toList();

  /// Bookings that are done with: shown under the live ones rather than
  /// mixed in with them.
  List<ShortLetBooking> get closedBookings =>
      _bookings.where((b) => b.status.isClosed).toList();

  /// Bookings still going somewhere: awaiting a decision, awaiting payment, or
  /// paid and upcoming.
  List<ShortLetBooking> get liveBookings =>
      _bookings.where((b) => !b.status.isClosed).toList();

  /// Stays that are paid for and have not been checked out of, soonest first.
  ///
  /// This is what a tenant means by "my trip": money has moved, the host has
  /// confirmed, and there is a date to turn up on. It drives the card on the
  /// dashboard: the complaint that a successful payment left no trace
  /// anywhere the tenant would naturally look.
  List<ShortLetBooking> get confirmedStays {
    final stays = _bookings
        .where((b) => b.status.isPaid && !b.hasCheckedOut)
        .toList();
    stays.sort((a, b) => a.checkIn.compareTo(b.checkIn));
    return stays;
  }

  /// Stays the guest has been on and not yet reviewed.
  List<ShortLetBooking> get staysAwaitingReview =>
      _bookings.where((b) => b.canReview).toList();

  ShortLetBooking? _pendingPayment;

  /// The booking currently being paid for, held so the screen can verify it
  /// when provider checkout closes.
  ShortLetBooking? get pendingPayment => _pendingPayment;

  /// Idempotency keys per booking, so retrying one payment cannot be merged
  /// with another and cannot charge twice.
  final Map<String, String> _paymentKeys = {};

  /// How much more the vault needed, when a vault payment was refused for
  /// want of funds. Null when the last failure was anything else.
  String? _vaultShortfall;
  String? get vaultShortfall => _vaultShortfall;

  bool _vaultBalanceFellShort = false;

  /// Whether the last vault-funded booking payment was refused because the
  /// balance did not cover it: the one failure with an obvious next step.
  bool get vaultBalanceFellShort => _vaultBalanceFellShort;

  @override
  void resetSessionState() {
    _listings = [];
    _browseListings = [];
    _searchQuery = '';
    _latitude = null;
    _longitude = null;
    _searchDates = null;
    _minPrice = null;
    _maxPrice = null;
    _minBedrooms = null;
    _bookings = [];
    _pendingPayment = null;
    _paymentKeys.clear();
    _decidingBookingIds.clear();
    _previewingCancelIds.clear();
    _vaultShortfall = null;
    _vaultBalanceFellShort = false;
    _windowWasWidened = false;
    _existingListingId = null;
    _isLoading = false;
    _isSubmitting = false;
    resetLoadedState();
    clearFailure();
    notifyListeners();
  }

  // ---------------------------------------------------------------- landlord

  Future<void> loadLandlordListings() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _listings = await _service.getLandlordListings();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kListingsKey);
      notifyListeners();
    }
  }

  Future<void> loadLandlordBookings() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _bookings = await _service.getLandlordBookings();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kBookingsKey);
      notifyListeners();
    }
  }

  /// Saves a listing and returns it, or null on failure.
  ///
  /// The list is refetched rather than patched locally: the backend decides
  /// what a saved listing looks like, and guessing would leave a duplicate or
  /// a stale price on screen.
  ///
  /// **The refetch is not part of the save.** It used to be inside the same
  /// `try`, which meant a listing that saved perfectly well and then hit a
  /// slow or failed `GET` came back from here as `null` — and the sheet, which
  /// reads `null` as "it did not save", told the host their listing had
  /// failed. It had not: it was live, and testers reported exactly that ("it
  /// showed an error but it still listed"). A save is finished the moment the
  /// write succeeds; refreshing the local copy afterwards is a convenience,
  /// and a convenience must never be able to report the write as failed.
  Future<ShortLetListing?> saveListing({
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
    _isSubmitting = true;
    _existingListingId = null;
    clearFailure();
    notifyListeners();

    final ShortLetListing listing;
    try {
      listing = await _saveOrWidenWindow(
        unitId: unitId,
        listingId: listingId,
        nightlyPrice: nightlyPrice,
        minimumNights: minimumNights,
        maximumGuests: maximumGuests,
        description: description,
        cautionFee: cautionFee,
        cancellationPolicy: cancellationPolicy,
        availableFrom: availableFrom,
        availableTo: availableTo,
        blockedDates: blockedDates,
        houseRules: houseRules,
        checkInNotes: checkInNotes,
        isActive: isActive,
      );
    } catch (e) {
      // A create refused because the unit is already listed is not really a
      // failure: the host wants that unit let by the night and it is. The
      // id comes back with the refusal so the caller can offer the listing
      // instead of the error.
      _existingListingId = _listingIdFromConflict(e);
      captureFailure(e);
      _isSubmitting = false;
      notifyListeners();
      return null;
    }

    // Past this line the listing exists on the backend, so nothing below may
    // change the answer. A refetch that fails leaves the newly saved listing
    // patched into the local set instead, which is enough for the screen the
    // host lands on, and the next auto-refresh corrects it.
    try {
      _listings = await _service.getLandlordListings();
    } catch (e) {
      debugPrint('[SHORTLET] Saved, but the list refresh failed: $e');
      _mergeListing(listing);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
    return listing;
  }

  /// Puts [listing] into the local set, replacing the entry for the same id
  /// or unit rather than adding a second row for one place.
  void _mergeListing(ShortLetListing listing) {
    final index = _listings.indexWhere(
      (existing) =>
          existing.id == listing.id ||
          (listing.unitId.isNotEmpty && existing.unitId == listing.unitId),
    );
    if (index == -1) {
      _listings = [listing, ..._listings];
    } else {
      _listings = List.of(_listings)..[index] = listing;
    }
  }

  /// Saves the listing, and works around a backend that still insists on a
  /// booking window.
  ///
  /// The window is optional in the app and is meant to be optional in the API
  /// (`backend_change_spec_v7.md` §1). Against a deployment where it is not,
  /// a host who wants to take bookings whenever gets
  /// `{"available_from": ["This field may not be null."]}`, which reads, from
  /// the landlord's side, as the app having lied about the field being
  /// optional, with no indication of which of nine inputs is wrong.
  ///
  /// So: try honestly first, with nulls. Only if *that specific* rejection
  /// comes back, retry once with a window wide enough to mean "any time":
  /// [_openWindowYears] from today, which is the closest that backend can get
  /// to expressing no restriction. The landlord is told, because their listing
  /// now carries a bound they did not choose.
  ///
  /// The retry is self-cancelling: the day §1 ships, the first attempt
  /// succeeds and this path stops running. Delete it then.
  Future<ShortLetListing> _saveOrWidenWindow({
    required String unitId,
    String? listingId,
    required String nightlyPrice,
    required int minimumNights,
    required int maximumGuests,
    required String description,
    required String cautionFee,
    required ShortLetCancellationPolicy cancellationPolicy,
    String? availableFrom,
    String? availableTo,
    List<String> blockedDates = const [],
    String houseRules = '',
    String checkInNotes = '',
    bool isActive = true,
  }) async {
    _windowWasWidened = false;
    try {
      return await _service.saveListing(
        unitId: unitId,
        listingId: listingId,
        nightlyPrice: nightlyPrice,
        minimumNights: minimumNights,
        maximumGuests: maximumGuests,
        description: description,
        cautionFee: cautionFee,
        cancellationPolicy: cancellationPolicy,
        availableFrom: availableFrom,
        availableTo: availableTo,
        blockedDates: blockedDates,
        houseRules: houseRules,
        checkInNotes: checkInNotes,
        isActive: isActive,
      );
    } catch (e) {
      // Only when the host asked for no window in the first place. A host who
      // set dates and had them refused for some other reason must see that
      // rejection, not have their choice silently replaced.
      final askedForAnyDates = availableFrom == null && availableTo == null;
      if (!askedForAnyDates || !_rejectedForMissingWindow(e)) rethrow;

      final today = DateTime.now();
      final listing = await _service.saveListing(
        unitId: unitId,
        listingId: listingId,
        nightlyPrice: nightlyPrice,
        minimumNights: minimumNights,
        maximumGuests: maximumGuests,
        description: description,
        cautionFee: cautionFee,
        cancellationPolicy: cancellationPolicy,
        availableFrom: shortLetIsoDate(today),
        availableTo: shortLetIsoDate(
          DateTime(today.year + _openWindowYears, today.month, today.day),
        ),
        blockedDates: blockedDates,
        houseRules: houseRules,
        checkInNotes: checkInNotes,
        isActive: isActive,
      );
      _windowWasWidened = true;
      return listing;
    }
  }

  /// How far out an "any dates" listing is bookable while the backend still
  /// requires a window. Long enough that no host will hit the far edge, short
  /// enough to be a date a person can read.
  static const int _openWindowYears = 5;

  bool _windowWasWidened = false;

  /// Whether the last save had to invent a booking window because the backend
  /// refused an open-ended one.
  ///
  /// The sheet says so after saving. A host who chose "any dates" and finds
  /// their listing reading "Bookable until 2031" deserves to know why rather
  /// than to think the app ignored them.
  bool get windowWasWidened => _windowWasWidened;

  /// Whether [error] is the backend refusing a listing for want of
  /// `available_from`/`available_to`.
  ///
  /// Matched on the error body's keys rather than its wording: DRF's sentence
  /// is the same for every required field, and only the key says which.
  static bool _rejectedForMissingWindow(Object error) {
    if (error is! ApiException) return false;
    final errors = error.errors;
    if (errors is! Map) return false;
    return errors.containsKey('available_from') ||
        errors.containsKey('available_to');
  }

  String? _existingListingId;

  /// The listing the backend pointed at when it refused a create as a
  /// duplicate, or null when the last failure was anything else.
  ///
  /// `409 LISTING_EXISTS` carries a `listing_id`, which is the difference
  /// between a dead end and a way forward: the host meant to list that unit,
  /// it is already listed, and the useful next move is to open the listing
  /// they already have rather than to tell them no.
  String? get existingListingId => _existingListingId;

  static String? _listingIdFromConflict(Object error) {
    if (error is! ApiException) return null;
    final body = error.errors;
    if (body is! Map) return null;
    if (body['code']?.toString() != 'LISTING_EXISTS') return null;
    final id = body['listing_id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Approves a booking request. Returns true when it went through.
  Future<bool> approveBooking(String bookingId) =>
      _decide(bookingId, () => _service.approveBooking(bookingId));

  /// Declines a booking request. Returns true when it went through.
  Future<bool> rejectBooking(String bookingId, {String? reason}) => _decide(
    bookingId,
    () => _service.rejectBooking(bookingId, reason: reason),
  );

  Future<bool> _decide(
    String bookingId,
    Future<ShortLetBooking> Function() action,
  ) async {
    _decidingBookingIds.add(bookingId);
    clearFailure();
    notifyListeners();

    try {
      _upsertBooking(await action());
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _decidingBookingIds.remove(bookingId);
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ tenant

  Future<void> loadBrowseListings() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final dates = _searchDates;
      final results = await _service.browseListings(
        location: _searchQuery,
        latitude: _latitude,
        longitude: _longitude,
        checkIn: dates == null ? null : shortLetIsoDate(dates.start),
        checkOut: dates == null ? null : shortLetIsoDate(dates.end),
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        minBedrooms: _minBedrooms,
      );
      _browseListings = _applyBedroomsFilter(results);
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kBrowseKey);
      notifyListeners();
    }
  }

  /// Searches by typed area name, dropping any nearby search in the process.
  ///
  /// [query] arrives already debounced from the search field.
  Future<void> searchBrowseListings(String query) async {
    final trimmed = query.trim();
    if (trimmed == _searchQuery && !isSearchingNearby) return;
    _searchQuery = trimmed;
    _latitude = null;
    _longitude = null;
    await loadBrowseListings();
  }

  /// Switches to distance-sorted results around [latitude]/[longitude],
  /// clearing the typed search so only one narrowing is ever in effect.
  Future<void> searchNearby({
    required double latitude,
    required double longitude,
  }) async {
    _latitude = latitude;
    _longitude = longitude;
    _searchQuery = '';
    await loadBrowseListings();
  }

  /// Checks the list against a stay, or clears the dates when [dates] is null.
  ///
  /// Keeps wherever the tenant was searching: dates and place are independent,
  /// and picking a weekend should not throw away the area they had chosen.
  Future<void> setSearchDates(DateTimeRange? dates) async {
    if (dates?.start == _searchDates?.start &&
        dates?.end == _searchDates?.end) {
      return;
    }
    _searchDates = dates;
    await loadBrowseListings();
  }

  /// Re-applies the bedrooms filter to what the backend returned.
  ///
  /// Belt and braces, and deliberately so. `min_bedrooms` is a new query
  /// parameter (`backend_change_spec_v11.md` §3); until it ships, a
  /// deployment that does not recognise it ignores it and returns
  /// everything, which would leave the control on screen visibly doing
  /// nothing.
  ///
  /// The guard matters as much as the filter: it only runs when the response
  /// actually carries bedroom counts. A backend that omits `bedrooms`
  /// entirely parses to 0 on every listing, and filtering on that would empty
  /// the list rather than fail to narrow it: the worse of the two failures,
  /// because an empty list looks like there is nowhere to stay.
  List<ShortLetListing> _applyBedroomsFilter(List<ShortLetListing> listings) {
    final minimum = _minBedrooms;
    if (minimum == null || listings.isEmpty) return listings;
    final countsAreKnown = listings.any((listing) => listing.bedrooms > 0);
    if (!countsAreKnown) return listings;
    return listings.where((listing) => listing.bedrooms >= minimum).toList();
  }

  /// Narrows the browse list to places with at least [minBedrooms] bedrooms,
  /// or clears it when null.
  ///
  /// Its own axis, like price and dates: how many rooms somebody needs says
  /// nothing about where or when they are looking, so setting it leaves the
  /// rest of the search alone.
  Future<void> setBedroomsFilter(int? minBedrooms) async {
    if (minBedrooms == _minBedrooms) return;
    _minBedrooms = minBedrooms;
    await loadBrowseListings();
  }

  /// Sets the price range narrowing the browse list. Either bound may be
  /// null to leave it open. [minPrice]/[maxPrice] are decimal strings, not
  /// naira-formatted text: the caller (a numeric-only field) owns turning
  /// what the tenant typed into digits before this is called.
  ///
  /// Kept as its own axis, same as dates: a price range does not touch where
  /// or when the tenant is searching, so setting one leaves the others alone.
  Future<void> setPriceFilter({String? minPrice, String? maxPrice}) async {
    if (minPrice == _minPrice && maxPrice == _maxPrice) return;
    _minPrice = minPrice;
    _maxPrice = maxPrice;
    await loadBrowseListings();
  }

  /// Back to every listing: no coordinates, no typed area, no price range,
  /// no bedroom floor.
  ///
  /// Leaves the dates alone. They are not what emptied the list: the backend
  /// returns unavailable stays rather than withholding them, so clearing
  /// them here would silently discard a choice the tenant still wants.
  Future<void> clearBrowseSearch() async {
    if (!isBrowseNarrowed) return;
    _searchQuery = '';
    _latitude = null;
    _longitude = null;
    _minPrice = null;
    _maxPrice = null;
    _minBedrooms = null;
    await loadBrowseListings();
  }

  Future<void> loadMyBookings() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _bookings = await _service.getMyBookings();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kBookingsKey);
      notifyListeners();
    }
  }

  /// Requests dates on a listing, returning the booking or null on failure.
  Future<ShortLetBooking?> requestBooking({
    required String listingId,
    required String checkIn,
    required String checkOut,
    required int guestCount,
    String message = '',
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      final booking = await _service.requestBooking(
        listingId: listingId,
        checkIn: checkIn,
        checkOut: checkOut,
        guestCount: guestCount,
        message: message,
      );
      _upsertBooking(booking);
      return booking;
    } catch (e) {
      captureFailure(e);
      final friendly = _friendlyDateClash(e);
      if (friendly != null) setFailureMessage(friendly);
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// A plain sentence for the one booking refusal guests actually hit, or
  /// null when the failure was something else.
  ///
  /// The backend rejects a clash per field, so what reached the guest was
  /// `check_in: These dates are already booked.`. A field name they have
  /// never seen, a full stop mid-sentence, and no hint that the fix is to
  /// pick other dates. Every other refusal keeps the backend's own wording:
  /// it knows about house rules, windows and limits that the app does not.
  static String? _friendlyDateClash(Object error) {
    if (error is! ApiException) return null;

    // Matched on what the refusal says, not on which field it names. A
    // `check_in` error can just as easily be "must be in the future", and
    // that one has a different fix: telling the guest to pick other dates
    // when the real problem is the year they typed would send them round in
    // circles.
    final message = error.message.toLowerCase();
    final readsAsClash =
        message.contains('already booked') ||
        message.contains('already reserved') ||
        message.contains('not available') ||
        message.contains('unavailable');
    if (!readsAsClash) return null;

    return 'Someone has already booked those nights. Pick different dates, '
        'the calendar shows what is still free.';
  }

  /// Withdraws a booking request. Returns true when it went through.
  Future<bool> cancelBooking(String bookingId, {String? reason}) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      _upsertBooking(await _service.cancelBooking(bookingId, reason: reason));
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Bookings currently having their cancellation refund looked up, so the
  /// button can show a spinner without disabling the rest of the list.
  final Set<String> _previewingCancelIds = {};
  bool isPreviewingCancellation(String bookingId) =>
      _previewingCancelIds.contains(bookingId);

  /// Quotes the current refund for [bookingId] and merges it onto the local
  /// copy of that booking, so the confirmation dialog can show the backend's
  /// real numbers instead of a placeholder.
  ///
  /// Quiet on failure: a preview that could not be fetched is not a reason to
  /// block cancelling. The dialog just falls back to its generic wording,
  /// and the cancel call itself still carries the backend's final word.
  Future<ShortLetBooking?> previewCancellation(String bookingId) async {
    _previewingCancelIds.add(bookingId);
    notifyListeners();

    try {
      final json = await _service.getCancelPreview(bookingId);
      if (json.isEmpty) return null;
      final index = _bookings.indexWhere((b) => b.id == bookingId);
      if (index == -1) return null;
      final merged = _bookings[index].withCancelPreview(json);
      _bookings[index] = merged;
      return merged;
    } catch (_) {
      return null;
    } finally {
      _previewingCancelIds.remove(bookingId);
      notifyListeners();
    }
  }

  /// The host's own withdrawal from a booking. Returns true when it went
  /// through.
  Future<bool> cancelBookingAsHost(
    String bookingId, {
    required String reason,
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      _upsertBooking(
        await _service.cancelBookingAsHost(
          bookingId: bookingId,
          reason: reason,
        ),
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Pays for an approved booking.
  ///
  /// For a vault payment, returns the booking only when the backend confirmed
  /// it: there is no checkout to fall back on, so anything else is a failure
  /// with a message on the controller. For a card payment, returns the booking
  /// carrying the checkout to open; the stay is not paid for until
  /// [verifyPayment] says so.
  Future<ShortLetBooking?> payForBooking(
    String bookingId, {
    required bool fromVault,
    String? vaultPin,
  }) async {
    _isSubmitting = true;
    _vaultShortfall = null;
    _vaultBalanceFellShort = false;
    clearFailure();
    notifyListeners();

    // One key per booking, kept until the payment settles, so a request that
    // times out and is retried is charged once.
    final key = _paymentKeys.putIfAbsent(
      bookingId,
      () => 'sl-$bookingId-${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      final booking = await _service.payForBooking(
        bookingId: bookingId,
        idempotencyKey: key,
        fromVault: fromVault,
        vaultPin: vaultPin,
      );
      _upsertBooking(booking);
      _pendingPayment = booking;

      if (fromVault) {
        if (!booking.status.isPaid) {
          // The backend accepted the request but the stay is not paid for.
          // Say so rather than sending the guest off with a confirmation.
          setFailureMessage(
            'That payment did not complete, so your booking is not confirmed '
            'yet. Your vault has not been charged.',
          );
          return null;
        }
        // One intent, one charge: the key is only spent once money moved.
        _paymentKeys.remove(bookingId);
      }
      return booking;
    } on InsufficientVaultBalanceException catch (e) {
      captureFailure(e);
      _vaultBalanceFellShort = true;
      _vaultShortfall = e.shortfall;
      return null;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Confirms a card payment after checkout closes.
  ///
  /// Returns null when there was nothing to verify or the call failed. The app
  /// never marks a booking paid on its own.
  Future<ShortLetBooking?> verifyPendingPayment() async {
    final pending = _pendingPayment;
    final paymentId = pending?.paymentId;
    if (pending == null || paymentId == null || paymentId.isEmpty) {
      setFailureMessage(
        'This booking has no payment to check yet. Try paying again.',
      );
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      final verified = await _service.verifyPayment(
        paymentId: paymentId,
        reference: pending.paymentReference,
      );
      _upsertBooking(verified);
      _pendingPayment = verified;
      if (verified.status.isPaid) _paymentKeys.remove(verified.id);
      return verified;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Raises a dispute on a paid stay. Returns true when it was recorded.
  ///
  /// Keyed on the payment rather than the booking, because that is what the
  /// backend holds the money against: a booking with no payment id has
  /// nothing in escrow to dispute.
  Future<bool> disputeBooking(ShortLetBooking booking, {String? reason}) async {
    final paymentId = booking.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      setFailureMessage(
        'This stay has no payment on record yet, so there is nothing to '
        'dispute. Pull down to refresh and try again.',
      );
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      _upsertBooking(
        await _service.disputePayment(paymentId: paymentId, reason: reason),
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Marks a payout-blocking dispute settled, so the host payout can release.
  /// Returns true when it went through.
  Future<bool> resolveDispute(ShortLetBooking booking, {String? note}) async {
    final paymentId = booking.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      setFailureMessage(
        'This stay has no payment on record yet. Pull down to refresh and '
        'try again.',
      );
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      _upsertBooking(
        await _service.resolveDispute(paymentId: paymentId, note: note),
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Host claims some or all of a checked-out stay's caution fee. Returns
  /// true when the claim was recorded.
  ///
  /// Does not attempt to parse or hold onto the created claim: the response
  /// shape is undocumented, and there is no GET to list claims back anyway.
  /// The caller refreshes the booking list instead.
  Future<bool> openCautionClaim({
    required String bookingId,
    String? claimedAmount,
    required String reason,
    List<String> evidence = const [],
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      await _service.openCautionClaim(
        bookingId: bookingId,
        claimedAmount: claimedAmount,
        reason: reason,
        evidence: evidence,
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Tenant answers a caution-fee claim. Returns true when it was recorded.
  Future<bool> respondToCautionClaim({
    required String claimId,
    required String response,
    String? counterAmount,
    String? note,
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      await _service.respondToCautionClaim(
        claimId: claimId,
        response: response,
        counterAmount: counterAmount,
        note: note,
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Starts a fresh payment intent, so a new deliberate attempt is never
  /// merged with the previous one server-side.
  void beginPaymentIntent(String bookingId) {
    _paymentKeys.remove(bookingId);
    _pendingPayment = null;
  }

  /// Replaces a booking in the list, or adds it when it is new.
  ///
  /// A response with no id is ignored rather than inserted: it would render as
  /// a blank row and could never be matched against later.
  void _upsertBooking(ShortLetBooking booking) {
    if (booking.id.isEmpty) return;
    final index = _bookings.indexWhere((item) => item.id == booking.id);
    if (index == -1) {
      _bookings.insert(0, booking);
    } else {
      _bookings[index] = booking;
    }
  }
}
