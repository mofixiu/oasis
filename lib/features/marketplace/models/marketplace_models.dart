import '../../properties/models/property_model.dart';

/// A property surfaced in the tenant marketplace, together with the units
/// that are currently available to apply for.
///
/// The guide documents the marketplace endpoints behaviourally but does not
/// pin an exact response schema, so parsing here accepts the plausible key
/// spellings the backend serializers use rather than assuming one.
class MarketplaceProperty {
  final PropertyModel property;
  final List<UnitModel> availableUnits;

  const MarketplaceProperty({
    required this.property,
    required this.availableUnits,
  });

  String get id => property.id;

  /// Lowest advertised rent across available units, used for the card summary.
  /// Returns null when no unit carries a parseable amount.
  double? get lowestRent {
    final amounts = availableUnits
        .map((unit) => double.tryParse(unit.rentAmount))
        .whereType<double>()
        .toList();
    if (amounts.isEmpty) return null;
    return amounts.reduce((a, b) => a < b ? a : b);
  }

  factory MarketplaceProperty.fromJson(Map<String, dynamic> json) {
    final rawUnits =
        json['available_units'] ?? json['units'] ?? const <dynamic>[];
    return MarketplaceProperty(
      property: PropertyModel.fromJson(
        // Some list endpoints nest the property, others flatten it.
        json['property'] is Map<String, dynamic>
            ? json['property'] as Map<String, dynamic>
            : json,
      ),
      availableUnits: rawUnits is List
          ? rawUnits
                .whereType<Map<String, dynamic>>()
                .map(UnitModel.fromJson)
                .toList()
          : const <UnitModel>[],
    );
  }
}

enum ApplicationStatus {
  pending,
  approved,
  rejected,
  withdrawn,
  unknown;

  static ApplicationStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'PENDING':
        return ApplicationStatus.pending;
      case 'APPROVED':
        return ApplicationStatus.approved;
      case 'REJECTED':
        return ApplicationStatus.rejected;
      case 'WITHDRAWN':
        return ApplicationStatus.withdrawn;
      default:
        // Never assume PENDING for an unrecognised status — that would offer
        // approve/reject actions on an application the backend considers
        // already settled.
        return ApplicationStatus.unknown;
    }
  }

  /// Wire value for the `?status=` filter.
  String? get queryValue {
    switch (this) {
      case ApplicationStatus.pending:
        return 'PENDING';
      case ApplicationStatus.approved:
        return 'APPROVED';
      case ApplicationStatus.rejected:
        return 'REJECTED';
      case ApplicationStatus.withdrawn:
        return 'WITHDRAWN';
      case ApplicationStatus.unknown:
        return null;
    }
  }

  String get label {
    switch (this) {
      case ApplicationStatus.pending:
        return 'PENDING';
      case ApplicationStatus.approved:
        return 'APPROVED';
      case ApplicationStatus.rejected:
        return 'REJECTED';
      case ApplicationStatus.withdrawn:
        return 'WITHDRAWN';
      case ApplicationStatus.unknown:
        return 'UNKNOWN';
    }
  }

  bool get isPending => this == ApplicationStatus.pending;
}

/// A tenant's application for an available unit.
class RentalApplication {
  final String id;
  final String unitId;
  final String unitNumber;
  final ApplicationStatus status;
  final String createdAt;
  final String? tenantName;
  final String? tenantEmail;
  final String? tenantPhone;
  final String? rentAmount;
  final PropertyModel? property;

  const RentalApplication({
    required this.id,
    required this.unitId,
    required this.unitNumber,
    required this.status,
    required this.createdAt,
    this.tenantName,
    this.tenantEmail,
    this.tenantPhone,
    this.rentAmount,
    this.property,
  });

  /// True when the payload carried nothing identifying the applicant, so the
  /// landlord UI can say so explicitly instead of silently omitting the row.
  bool get hasApplicantDetails =>
      (tenantName?.isNotEmpty ?? false) ||
      (tenantEmail?.isNotEmpty ?? false) ||
      (tenantPhone?.isNotEmpty ?? false);

  factory RentalApplication.fromJson(Map<String, dynamic> json) {
    // `unit` may be a bare UUID or a nested object depending on the serializer.
    final rawUnit = json['unit'];
    final nestedUnit = rawUnit is Map<String, dynamic> ? rawUnit : null;

    // Likewise the applicant: some serializers nest a `tenant`/`applicant`
    // object, others flatten `tenant_email` onto the application.
    final rawTenant = json['tenant'] ?? json['applicant'];
    final nestedTenant = rawTenant is Map<String, dynamic> ? rawTenant : null;

    return RentalApplication(
      id: json['id']?.toString() ?? '',
      unitId: (nestedUnit?['id'] ?? rawUnit)?.toString() ?? '',
      unitNumber:
          (json['unit_number'] ?? nestedUnit?['unit_number'] ?? '').toString(),
      status: ApplicationStatus.fromString(json['status']?.toString()),
      createdAt: (json['created_at'] ?? json['applied_at'] ?? '').toString(),
      tenantName: _firstNonEmpty([
        json['tenant_name'],
        json['tenant_full_name'],
        nestedTenant?['full_name'],
        nestedTenant?['name'],
        nestedTenant?['welcome_name'],
      ]),
      tenantEmail: _firstNonEmpty([
        json['tenant_email'],
        nestedTenant?['email'],
        // A bare `tenant` UUID is an identifier, not contact info.
        if (rawTenant is! Map && !_isUuid(rawTenant?.toString()))
          rawTenant,
      ]),
      tenantPhone: _firstNonEmpty([
        json['tenant_phone'],
        json['tenant_phone_number'],
        nestedTenant?['phone_number'],
        nestedTenant?['phone'],
      ]),
      rentAmount: (json['rent_amount'] ?? nestedUnit?['rent_amount'])
          ?.toString(),
      property: json['property'] is Map<String, dynamic>
          ? PropertyModel.fromJson(json['property'] as Map<String, dynamic>)
          : null,
    );
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static bool _isUuid(String? value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value ?? '');
}

/// Filters supported by `GET /tenant/marketplace/`.
class MarketplaceFilters {
  final String? city;
  final String? state;
  final String? minRent;
  final String? maxRent;
  final int? bedrooms;
  final int? bathrooms;

  const MarketplaceFilters({
    this.city,
    this.state,
    this.minRent,
    this.maxRent,
    this.bedrooms,
    this.bathrooms,
  });

  bool get isEmpty =>
      (city == null || city!.isEmpty) &&
      (state == null || state!.isEmpty) &&
      (minRent == null || minRent!.isEmpty) &&
      (maxRent == null || maxRent!.isEmpty) &&
      bedrooms == null &&
      bathrooms == null;

  Map<String, String?> toQueryParameters() => {
    'city': (city?.isEmpty ?? true) ? null : city,
    'state': (state?.isEmpty ?? true) ? null : state,
    'min_rent': (minRent?.isEmpty ?? true) ? null : minRent,
    'max_rent': (maxRent?.isEmpty ?? true) ? null : maxRent,
    'bedrooms': bedrooms?.toString(),
    'bathrooms': bathrooms?.toString(),
  };

  MarketplaceFilters copyWith({
    String? city,
    String? state,
    String? minRent,
    String? maxRent,
    int? bedrooms,
    int? bathrooms,
  }) => MarketplaceFilters(
    city: city ?? this.city,
    state: state ?? this.state,
    minRent: minRent ?? this.minRent,
    maxRent: maxRent ?? this.maxRent,
    bedrooms: bedrooms ?? this.bedrooms,
    bathrooms: bathrooms ?? this.bathrooms,
  );
}
