import 'package:flutter/foundation.dart';

import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';

class MarketplaceController extends ChangeNotifier
    with LoadFailureState
    implements SessionScopedController {
  final MarketplaceService _service;

  MarketplaceController({MarketplaceService? service})
    : _service = service ?? MarketplaceService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Separate from [_isLoading] so tapping Apply on one card doesn't blank
  /// the whole listing behind a full-screen spinner.
  String? _applyingUnitId;
  String? get applyingUnitId => _applyingUnitId;

  /// Id of the application currently being approved/rejected. Separate from
  /// [_isLoading] so the landlord's Approve/Reject buttons only disable for a
  /// real decision in flight, not for every background list refresh (the
  /// dashboard preloads this list, so the inbox's own reload used to grey the
  /// buttons out for a moment on every visit).
  String? _decidingApplicationId;
  String? get decidingApplicationId => _decidingApplicationId;
  bool get isDecidingApplication => _decidingApplicationId != null;

  /// Which decision is running, so only the button that was pressed shows a
  /// spinner instead of both.
  bool _decidingIsApproval = false;
  bool get decidingIsApproval => _decidingIsApproval;

  List<MarketplaceProperty> _listings = [];
  List<MarketplaceProperty> get listings => _listings;

  List<RentalApplication> _tenantApplications = [];
  List<RentalApplication> get tenantApplications => _tenantApplications;

  List<RentalApplication> _landlordApplications = [];
  List<RentalApplication> get landlordApplications => _landlordApplications;

  MarketplaceFilters _filters = const MarketplaceFilters();
  MarketplaceFilters get filters => _filters;

  /// The free-text area search, kept apart from [_filters] because the two are
  /// separate controls with separate reset buttons: "Clear filters" should not
  /// wipe what the tenant typed in the search bar, and clearing the search bar
  /// should not silently widen their rent range back out.
  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  bool get hasSearchQuery => _searchQuery.isNotEmpty;

  /// Where the tenant is, while they are browsing by distance.
  ///
  /// An alternative to [_searchQuery] rather than a companion to it: one or
  /// the other narrows the list, never both, so tapping Near me empties the
  /// search box and typing an area drops the coordinates.
  double? _latitude;
  double? _longitude;

  bool get isSearchingNearby => _latitude != null && _longitude != null;

  /// Whether anything at all is narrowing the list: what the empty state
  /// needs to know to offer "widen your search" rather than "check back
  /// later".
  bool get isNarrowed =>
      !_filters.isEmpty || hasSearchQuery || isSearchingNearby;

  ApplicationStatus? _landlordStatusFilter;
  ApplicationStatus? get landlordStatusFilter => _landlordStatusFilter;

  // "Never loaded" must be distinguishable from "loaded and genuinely empty".
  // Screens mount and paint their first frame before `initState`'s
  // post-frame callback starts the fetch, so without these a freshly reset
  // controller renders the empty state for a frame instead of the skeleton.
  bool _hasLoadedMarketplace = false;
  bool get hasLoadedMarketplace => _hasLoadedMarketplace;

  bool _hasLoadedTenantApplications = false;
  bool get hasLoadedTenantApplications => _hasLoadedTenantApplications;

  bool _hasLoadedLandlordApplications = false;
  bool get hasLoadedLandlordApplications => _hasLoadedLandlordApplications;

  /// Unit ids the tenant already has a live application for, so the UI can
  /// show "Applied" instead of offering a duplicate apply.
  Set<String> get appliedUnitIds => _tenantApplications
      .where(
        (a) => a.status.isPending || a.status == ApplicationStatus.approved,
      )
      .map((a) => a.unitId)
      .toSet();

  int get pendingLandlordApplicationCount =>
      _landlordApplications.where((a) => a.status.isPending).length;

  @override
  void resetSessionState() {
    _listings = [];
    _tenantApplications = [];
    // Drives the red dot on the landlord nav bar.
    _landlordApplications = [];
    _filters = const MarketplaceFilters();
    _searchQuery = '';
    _latitude = null;
    _longitude = null;
    _landlordStatusFilter = null;
    _applyingUnitId = null;
    _decidingApplicationId = null;
    clearFailure();
    _isLoading = false;
    // Back to "never loaded", so the next screen shows a skeleton rather than
    // briefly claiming the new user has no applications.
    _hasLoadedMarketplace = false;
    _hasLoadedTenantApplications = false;
    _hasLoadedLandlordApplications = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- tenant

  Future<void> loadMarketplace() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();
    try {
      _listings = _orderByDistance(
        await _service.getMarketplace(
          filters: _filters,
          location: _searchQuery,
          latitude: _latitude,
          longitude: _longitude,
        ),
      );
      // Needed to know which units are already applied for.
      _tenantApplications = await _service.getTenantApplications();
      _hasLoadedTenantApplications = true;
    } catch (e) {
      captureFailure(e);
    } finally {
      // Set even on failure: the attempt is over, so the screen should show
      // its error/empty state rather than shimmering forever.
      _hasLoadedMarketplace = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> applyFilters(MarketplaceFilters filters) async {
    _filters = filters;
    await loadMarketplace();
  }

  Future<void> clearFilters() async {
    _filters = const MarketplaceFilters();
    await loadMarketplace();
  }

  /// Searches by area name, dropping any nearby search in the process.
  ///
  /// [query] is already debounced by the search field, so this reloads on
  /// every call it receives.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed == _searchQuery && !isSearchingNearby) return;
    _searchQuery = trimmed;
    _latitude = null;
    _longitude = null;
    await loadMarketplace();
  }

  /// Switches to distance-ordered results around [latitude]/[longitude],
  /// clearing the typed search so only one narrowing is ever in effect.
  ///
  /// The filters are deliberately left standing: rent and bedrooms describe
  /// the home a tenant wants, and distance describes where. The two compose,
  /// and dropping a budget because someone asked for "near me" would show
  /// them places they cannot afford.
  Future<void> searchNearby({
    required double latitude,
    required double longitude,
  }) async {
    _latitude = latitude;
    _longitude = longitude;
    _searchQuery = '';
    await loadMarketplace();
  }

  /// Back to every listing: no coordinates, no typed area, no filters.
  ///
  /// The single "start over" the empty state offers when nothing matched.
  Future<void> clearSearchAndFilters() async {
    _searchQuery = '';
    _latitude = null;
    _longitude = null;
    _filters = const MarketplaceFilters();
    await loadMarketplace();
  }

  /// Back to every listing, keeping the filters. What the Near me toggle
  /// undoes itself with, and what the search box's clear button leaves behind.
  Future<void> clearLocationSearch() async {
    if (!hasSearchQuery && !isSearchingNearby) return;
    _searchQuery = '';
    _latitude = null;
    _longitude = null;
    await loadMarketplace();
  }

  /// Measures each listing from the tenant and sorts nearest first.
  ///
  /// A no-op unless this was a nearby search. It exists because
  /// `GET /tenant/marketplace/` does not read coordinates yet: see §2 of
  /// `backend_change_spec_v6.md`, so without it "Near me" would reorder
  /// nothing and the tenant would be told the list was sorted when it was
  /// not.
  ///
  /// Properties the landlord never pinned have no distance, and they sort to
  /// the end rather than being dropped: an unpinned property is missing a
  /// coordinate, not far away, and hiding a home someone could rent because
  /// of a gap in its record is the worse failure. Once the backend filters by
  /// radius they will not be in the payload at all, and this becomes the
  /// no-op it is written to be.
  List<MarketplaceProperty> _orderByDistance(
    List<MarketplaceProperty> listings,
  ) {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) return listings;

    final measured = listings
        .map(
          (listing) => listing.withDistanceFrom(
            latitude: latitude,
            longitude: longitude,
          ),
        )
        .toList();
    measured.sort((a, b) {
      final left = a.distanceKm;
      final right = b.distanceKm;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    return measured;
  }

  Future<void> loadTenantApplications() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();
    try {
      _tenantApplications = await _service.getTenantApplications();
    } catch (e) {
      captureFailure(e);
    } finally {
      _hasLoadedTenantApplications = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns the application on success, or null with [errorMessage] set.
  /// Applies for a unit, drawing the application before the server has it.
  ///
  /// [unitNumber] and [rentAmount] are only used to populate the provisional
  /// row, so My applications reads properly in the seconds before the real
  /// record arrives. Everything about the outcome still comes from the
  /// backend: the optimistic row is replaced by what it returns, or removed
  /// if it refuses.
  Future<RentalApplication?> applyForUnit(
    String unitId, {
    String? message,
    String unitNumber = '',
    String? rentAmount,
  }) async {
    _applyingUnitId = unitId;
    clearFailure();

    // Drawn now. The tenant has decided; making them watch a spinner to find
    // out whether the app noticed is what made this feel remote.
    final optimistic = RentalApplication.optimistic(
      unitId: unitId,
      unitNumber: unitNumber,
      rentAmount: rentAmount,
      message: message ?? '',
    );
    final alreadyListed = _tenantApplications.any((a) => a.unitId == unitId);
    if (!alreadyListed) _tenantApplications.insert(0, optimistic);
    notifyListeners();

    try {
      final application = await _service.applyForUnit(unitId, message: message);
      _tenantApplications.removeWhere((a) => a.id == optimistic.id);
      final index = _tenantApplications.indexWhere(
        (a) => a.id == application.id,
      );
      if (index == -1) {
        _tenantApplications.insert(0, application);
      } else {
        // Re-applying returns the existing record rather than a duplicate.
        _tenantApplications[index] = application;
      }
      return application;
    } catch (e) {
      // Rolled back in full. A button that stays flipped to "Applied" after a
      // failed request is worse than one that never flipped: the tenant walks
      // away believing they applied for a home they did not.
      _tenantApplications.removeWhere((a) => a.id == optimistic.id);
      captureFailure(e);
      return null;
    } finally {
      _applyingUnitId = null;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------- landlord

  Future<void> loadLandlordApplications() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();
    try {
      _landlordApplications = await _service.getLandlordApplications(
        status: _landlordStatusFilter,
      );
    } catch (e) {
      captureFailure(e);
    } finally {
      _hasLoadedLandlordApplications = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setLandlordStatusFilter(ApplicationStatus? status) async {
    _landlordStatusFilter = status;
    await loadLandlordApplications();
  }

  Future<bool> approveApplication({
    required String applicationId,
    required String startDate,
    required String endDate,
    String? rules,
  }) async {
    _decidingApplicationId = applicationId;
    _decidingIsApproval = true;
    clearFailure();

    // Approving cascades server-side: the unit becomes occupied, rival
    // applications are rejected, an agreement is written, so the refetch
    // below is still the authority. This only stops the row sitting in
    // "pending" while all of that happens.
    final rollback = _optimisticallySetStatus(
      applicationId,
      ApplicationStatus.approved,
    );
    notifyListeners();

    try {
      await _service.approveApplication(
        applicationId: applicationId,
        startDate: startDate,
        endDate: endDate,
        rules: rules,
      );
      // Approving cascades server-side (unit occupied, sibling applications
      // rejected, agreement created), so re-read rather than patching locally.
      await loadLandlordApplications();
      return true;
    } catch (e) {
      rollback();
      captureFailure(e);
      return false;
    } finally {
      _decidingApplicationId = null;
      notifyListeners();
    }
  }

  /// Moves one application to [next] in the local list, and hands back the
  /// undo.
  ///
  /// Every optimistic change in this controller is paired with its own
  /// rollback rather than a blanket refetch, because a failure is exactly the
  /// moment the network is unreliable: asking it for the truth again is the
  /// least likely thing to work.
  VoidCallback _optimisticallySetStatus(
    String applicationId,
    ApplicationStatus next,
  ) {
    final index = _landlordApplications.indexWhere(
      (a) => a.id == applicationId,
    );
    if (index == -1) return () {};
    final previous = _landlordApplications[index];
    _landlordApplications[index] = previous.withStatus(next);
    return () {
      final at = _landlordApplications.indexWhere((a) => a.id == applicationId);
      if (at != -1) _landlordApplications[at] = previous;
    };
  }

  Future<bool> rejectApplication(String applicationId) async {
    _decidingApplicationId = applicationId;
    _decidingIsApproval = false;
    clearFailure();

    // Settled on screen straight away. A decline has no cascade to wait for:
    // the row moves out of the pending pile the moment the landlord says no,
    // and the refetch below confirms it.
    final rollback = _optimisticallySetStatus(
      applicationId,
      ApplicationStatus.rejected,
    );
    notifyListeners();

    try {
      await _service.rejectApplication(applicationId);
      await loadLandlordApplications();
      return true;
    } catch (e) {
      rollback();
      captureFailure(e);
      return false;
    } finally {
      _decidingApplicationId = null;
      notifyListeners();
    }
  }
}
