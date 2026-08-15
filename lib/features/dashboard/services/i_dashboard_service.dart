import '../models/portfolio_summary.dart';
import '../models/property_unit.dart';

/// Abstract interface for the dashboard data operations.
/// Controllers depend on this interface, allowing easy swapping of implementations
/// (e.g., from mock data to a real Supabase/API backend later).
abstract class IDashboardService {
  /// Fetches the high-level portfolio summary statistics.
  Future<PortfolioSummary> getPortfolioSummary();

  /// Fetches the list of active rental units with their current payment status.
  Future<List<PropertyUnit>> getActiveUnits();
}
