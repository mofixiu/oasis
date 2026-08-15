/// Represents the high-level financial and occupancy summary for a landlord.
class PortfolioSummary {
  final double totalRentCollected;
  final double rentGrowthPercentage;
  final int activeLeases;
  final int pendingRenewals;
  final double outstandingDues;
  final int outstandingUnitsCount;

  PortfolioSummary({
    required this.totalRentCollected,
    required this.rentGrowthPercentage,
    required this.activeLeases,
    required this.pendingRenewals,
    required this.outstandingDues,
    required this.outstandingUnitsCount,
  });
}
