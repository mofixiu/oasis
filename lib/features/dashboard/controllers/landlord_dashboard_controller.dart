import 'package:flutter/foundation.dart';
import '../models/portfolio_summary.dart';
import '../models/property_unit.dart';
import '../services/i_dashboard_service.dart';

/// Manages the state for the Landlord Dashboard feature.
/// Communicates with the service layer and notifies listeners (the UI) of state changes.
class LandlordDashboardController extends ChangeNotifier {
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

  String? _errorMessage;
  /// Contains the error message if a fetch operation failed.
  String? get errorMessage => _errorMessage;

  /// Loads both the portfolio summary and the active units concurrently.
  Future<void> loadDashboardData() async {
    _isLoading = true;
    _errorMessage = null;
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
      _errorMessage = 'Failed to load dashboard data. Please try again later.';
      debugPrint('Error loading dashboard data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
