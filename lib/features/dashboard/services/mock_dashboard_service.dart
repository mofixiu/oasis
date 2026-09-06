import '../models/portfolio_summary.dart';
import '../models/property_unit.dart';
import 'i_dashboard_service.dart';

/// Mock implementation of the IDashboardService that returns realistic dummy data
/// after an artificial delay to simulate network latency.
class MockDashboardService implements IDashboardService {
  @override
  Future<PortfolioSummary> getPortfolioSummary() async {
    // Simulate a 2-second network request delay
    await Future.delayed(const Duration(seconds: 2));

    return PortfolioSummary(
      totalRentCollected: 12450000,
      rentGrowthPercentage: 8.5,
      activeLeases: 24,
      pendingRenewals: 2,
      outstandingDues: 850000,
      outstandingUnitsCount: 3,
    );
  }

  @override
  Future<List<PropertyUnit>> getActiveUnits() async {
    // Simulate a 2-second network request delay
    await Future.delayed(const Duration(seconds: 2));

    return [
      PropertyUnit(
        id: '1',
        name: 'Unit 4B, Lekki Phase 1',
        tenantName: 'Adebayo Okafor',
        rentAmount: 2500000,
        nextDueDate: 'Oct 12, 2024',
        status: UnitStatus.paid,
        imagePath:
            'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&w=400&q=80',
      ),
      PropertyUnit(
        id: '2',
        name: 'Villa 12, Victoria Island',
        tenantName: 'Chika Nwosu',
        rentAmount: 4200000,
        nextDueDate: 'Sep 01, 2024',
        status: UnitStatus.pending,
        imagePath:
            'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=400&q=80',
      ),
      PropertyUnit(
        id: '3',
        name: 'Apt 2A, Ikoyi',
        tenantName: 'Emeka Johnson',
        rentAmount: 6000000,
        nextDueDate: 'Nov 30, 2024',
        status: UnitStatus.paid,
        imagePath:
            'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=400&q=80',
      ),
      PropertyUnit(
        id: '4',
        name: 'Unit 8, Banana Island',
        tenantName: 'Tunde Bakare',
        rentAmount: 12000000,
        nextDueDate: 'Dec 15, 2024',
        status: UnitStatus.pending,
        imagePath:
            'https://images.unsplash.com/photo-1600607687940-4e20035af6e3?auto=format&fit=crop&w=400&q=80',
      ),
      PropertyUnit(
        id: '5',
        name: 'Flat 3, Surulere',
        tenantName: 'Sola Shobowale',
        rentAmount: 1200000,
        nextDueDate: 'Jan 01, 2025',
        status: UnitStatus.paid,
        imagePath:
            'https://images.unsplash.com/photo-1493809842364-78817add7ffb?auto=format&fit=crop&w=400&q=80',
      ),
    ];
  }
}
