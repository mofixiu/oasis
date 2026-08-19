import 'package:flutter/foundation.dart';
import '../models/portfolio_summary.dart';
import '../models/property_unit.dart';
import '../services/i_dashboard_service.dart';
import '../../../core/network/load_failure.dart';

/// Manages the state for the Landlord Dashboard feature.
/// Communicates with the service layer and notifies listeners (the UI) of state changes.
class LandlordDashboardController extends ChangeNotifier with LoadFailureState {
  final IDashboardService _dashboardService;

  LandlordDashboardController({required IDashboardService dashboardService})
    : _dashboardService = dashboardService;

  bool _isLoading = false;

  /// Whether dashboard data is currently being fetched.
  bool get isLoading => _isLoading;

  PortfolioSummary? _portfolioSummary;

  /// The loaded portfolio summary data.
  PortfolioSummary? get portfolioSummary => _portfolioSummary;

  List<PropertyUnit>? _activeUnits;

  /// The loaded list of active properties.
  List<PropertyUnit>? get activeUnits => _activeUnits;

  /// Loads both the portfolio summary and the active units concurrently.
  Future<void> loadDashboardData() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      // Execute both futures concurrently
      final results = await Future.wait([
        _dashboardService.getPortfolioSummary(),
        _dashboardService.getActiveUnits(),
      ]);

      _portfolioSummary = results[0] as PortfolioSummary;
      _activeUnits = results[1] as List<PropertyUnit>;
    } catch (e) {
      // captureFailure keeps the offline/server distinction the dashboard's
      // retry state needs; the old fixed string threw that away.
      captureFailure(e);
      debugPrint('Error loading dashboard data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
