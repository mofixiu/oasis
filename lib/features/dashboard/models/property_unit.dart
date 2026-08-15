/// Status of the unit's rent payment.
enum UnitStatus { paid, pending }

/// Represents an individual rental unit in the landlord's portfolio.
class PropertyUnit {
  final String id;
  final String name;
  final String tenantName;
  final double rentAmount;
  final String nextDueDate;
  final UnitStatus status;
  final String imagePath; // Path to property thumbnail

  PropertyUnit({
    required this.id,
    required this.name,
    required this.tenantName,
    required this.rentAmount,
    required this.nextDueDate,
    required this.status,
    required this.imagePath,
  });
}
