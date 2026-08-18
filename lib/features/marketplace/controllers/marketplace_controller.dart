import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/session/session_scope.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';

class MarketplaceController extends ChangeNotifier
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

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<MarketplaceProperty> _listings = [];
  List<MarketplaceProperty> get listings => _listings;

  List<RentalApplication> _tenantApplications = [];
  List<RentalApplication> get tenantApplications => _tenantApplications;

  List<RentalApplication> _landlordApplications = [];
  List<RentalApplication> get landlordApplications => _landlordApplications;

  MarketplaceFilters _filters = const MarketplaceFilters();
  MarketplaceFilters get filters => _filters;

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
      .where((a) => a.status.isPending || a.status == ApplicationStatus.approved)
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
    _landlordStatusFilter = null;
    _applyingUnitId = null;
    _errorMessage = null;
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
    _errorMessage = null;
    notifyListeners();
    try {
      _listings = await _service.getMarketplace(filters: _filters);
      // Needed to know which units are already applied for.
      _tenantApplications = await _service.getTenantApplications();
      _hasLoadedTenantApplications = true;
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
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

  Future<void> loadTenantApplications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _tenantApplications = await _service.getTenantApplications();
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
    } finally {
      _hasLoadedTenantApplications = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns the application on success, or null with [errorMessage] set.
  Future<RentalApplication?> applyForUnit(String unitId) async {
    _applyingUnitId = unitId;
    _errorMessage = null;
    notifyListeners();
    try {
      final application = await _service.applyForUnit(unitId);
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
      _errorMessage = friendlyErrorMessage(e);
      return null;
    } finally {
      _applyingUnitId = null;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------- landlord

  Future<void> loadLandlordApplications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _landlordApplications = await _service.getLandlordApplications(
        status: _landlordStatusFilter,
      );
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
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
    _isLoading = true;
    _errorMessage = null;
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
      _errorMessage = friendlyErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> rejectApplication(String applicationId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _service.rejectApplication(applicationId);
      await loadLandlordApplications();
      return true;
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
