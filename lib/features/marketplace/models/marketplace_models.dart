import '../../../core/utils/geo_distance.dart';
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

  /// How far this property is from the tenant, when the list was asked for
  /// with coordinates. Null on every other search.
  ///
  /// Read from `distance_km` where the backend sends one: it does for Stays
  /// and not yet for the marketplace, and otherwise computed by the
  /// controller from the property's own pin. Either way the card shows one
  /// number from one field, so the day the backend starts answering, nothing
  /// on screen changes shape.
  final double? distanceKm;

  const MarketplaceProperty({
    required this.property,
    required this.availableUnits,
    this.distanceKm,
  });

  String get id => property.id;

  /// "1.2 km away", or null when this was not a nearby search.
  String? get distanceLabel => GeoDistance.label(distanceKm);

  /// The same listing with [distanceKm] measured from the tenant's position.
  ///
  /// Server-sent distance is left alone: it is computed against whatever the
  /// backend holds as the property's location, which is the authority.
  MarketplaceProperty withDistanceFrom({
    required double latitude,
    required double longitude,
  }) => MarketplaceProperty(
    property: property,
    availableUnits: availableUnits,
    distanceKm:
        distanceKm ??
        GeoDistance.betweenOrNull(
          fromLatitude: latitude,
          fromLongitude: longitude,
          toLatitude: property.latitude,
          toLongitude: property.longitude,
        ),
  );

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
      distanceKm: _asDouble(json['distance_km']),
    );
  }
}

/// Tolerant number read, for a field the marketplace serializer does not send
/// today and may send as either a number or a decimal string when it does.
double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
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
        // Never assume PENDING for an unrecognised status, that would offer
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

  /// Whether this application has earned a conversation.
  ///
  /// Applying is the relationship, not approval and not payment. A tenant
  /// deciding whether to apply for somewhere to live has questions:
  /// inspection dates, what the service charge covers, whether the landlord
  /// takes the rent monthly, and answering them after the decision has been
  /// made is answering them too late. So the thread opens as soon as an
  /// application exists, and it opens for both sides: a landlord can ask an
  /// applicant about their move-in date without approving them first.
  ///
  /// Settled applications are excluded. A rejected or withdrawn application
  /// is not a live relationship, and re-opening a channel on one would let a
  /// declined applicant keep writing.
  ///
  /// The backend has the final word, where it still answers
  /// `403 NO_RELATIONSHIP` for a pending application, its own sentence is
  /// what the tenant sees, rather than the button being hidden and the
  /// question going unasked.
  bool get canMessage =>
      this == ApplicationStatus.approved || this == ApplicationStatus.pending;
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

  /// Applicant's identity-verification status, shown to the landlord.
  final String? tenantVerificationStatus;

  /// Optional note the tenant attached when applying (max 1000 chars).
  final String message;
  final String? rentAmount;

  /// Set once approved: the tenancy agreement the approval created.
  final String? agreementId;
  final String? decidedAt;
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
    this.tenantVerificationStatus,
    this.message = '',
    this.rentAmount,
    this.agreementId,
    this.decidedAt,
    this.property,
  });

  /// Prefix on the id of an application the app has drawn before the backend
  /// has confirmed it. Never sent anywhere: it exists so the optimistic row
  /// can be found again and replaced or removed.
  static const String optimisticIdPrefix = 'optimistic:';

  /// A pending application drawn the instant Apply is tapped.
  ///
  /// Waiting on a round trip to redraw a button is what makes an app feel
  /// remote: the tenant has decided, the outcome is not in doubt, and the
  /// screen should say so immediately. The real record replaces this one when
  /// it lands, and [MarketplaceController] removes it if the request fails.
  factory RentalApplication.optimistic({
    required String unitId,
    required String unitNumber,
    String? rentAmount,
    String message = '',
  }) => RentalApplication(
    id: '$optimisticIdPrefix$unitId',
    unitId: unitId,
    unitNumber: unitNumber,
    status: ApplicationStatus.pending,
    createdAt: DateTime.now().toIso8601String(),
    rentAmount: rentAmount,
    message: message,
  );

  /// Whether this row is the app's own guess rather than the backend's
  /// record. Screens use it to hold back actions that need a real id.
  bool get isOptimistic => id.startsWith(optimisticIdPrefix);

  /// The same application with a different status, for a decision the app has
  /// drawn before the server has confirmed it.
  RentalApplication withStatus(ApplicationStatus next) => RentalApplication(
    id: id,
    unitId: unitId,
    unitNumber: unitNumber,
    status: next,
    createdAt: createdAt,
    tenantName: tenantName,
    tenantEmail: tenantEmail,
    tenantPhone: tenantPhone,
    tenantVerificationStatus: tenantVerificationStatus,
    message: message,
    rentAmount: rentAmount,
    agreementId: agreementId,
    decidedAt: decidedAt,
    property: property,
  );

  bool get hasMessage => message.trim().isNotEmpty;

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
      unitNumber: (json['unit_number'] ?? nestedUnit?['unit_number'] ?? '')
          .toString(),
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
        if (rawTenant is! Map && !_isUuid(rawTenant?.toString())) rawTenant,
      ]),
      tenantPhone: _firstNonEmpty([
        json['tenant_phone'],
        json['tenant_phone_number'],
        nestedTenant?['phone_number'],
        nestedTenant?['phone'],
      ]),
      tenantVerificationStatus: _firstNonEmpty([
        json['tenant_verification_status'],
        nestedTenant?['verification_status'],
      ]),
      message: json['message']?.toString() ?? '',
      rentAmount: (json['rent_amount'] ?? nestedUnit?['rent_amount'])
          ?.toString(),
      agreementId: _firstNonEmpty([json['agreement_id'], json['agreement']]),
      decidedAt: _firstNonEmpty([json['decided_at']]),
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
    // min_price/max_price per the 2026-09-03 search update: the shared
    // param name across rentals and short lets. The backend still accepts
    // the older min_rent/max_rent, but there is no reason to send both.
    'min_price': (minRent?.isEmpty ?? true) ? null : minRent,
    'max_price': (maxRent?.isEmpty ?? true) ? null : maxRent,
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
