import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/marketplace_models.dart';

class MarketplaceService {
  final ApiClient _apiClient;

  MarketplaceService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Browse properties with units available to apply for (Tenant).
  ///
  /// [location] is the free-text search box: the backend matches it against
  /// property name, address, city and state, and it composes with [filters]
  /// rather than replacing them. Sent as `location`, which the backend
  /// accepts alongside the `search`/`q` aliases.
  ///
  /// [latitude]/[longitude] are the device's own position, and they replace
  /// [location] rather than joining it: a tenant who has just tapped Near me
  /// is asking about where they are standing, not about a place name they
  /// typed earlier. [radiusKm] is only meaningful with coordinates.
  ///
  /// These three are sent in the same spelling Stays uses, and the marketplace
  /// endpoint does not read them yet (see §2 of `backend_change_spec_v6.md`);
  /// DRF ignores unknown query parameters, so today they cost one harmless
  /// pair of keys and the controller does the ordering itself. The moment the
  /// backend starts filtering by radius and returning `distance_km`, this call
  /// is already asking for it.
  Future<List<MarketplaceProperty>> getMarketplace({
    MarketplaceFilters filters = const MarketplaceFilters(),
    String? location,
    double? latitude,
    double? longitude,
    int? radiusKm,
  }) async {
    final hasCoordinates = latitude != null && longitude != null;
    final query = location?.trim();
    debugPrint(
      '[MARKETPLACE SERVICE] Browsing marketplace GET ${ApiConstants.tenantMarketplaceEndpoint} '
      '(${hasCoordinates ? 'near $latitude,$longitude' : 'location=${query?.isNotEmpty == true ? query : '-'}'})',
    );
    final response = await _apiClient.get(
      ApiConstants.tenantMarketplaceEndpoint,
      queryParameters: {
        ...filters.toQueryParameters(),
        if (hasCoordinates) ...{
          'latitude': latitude.toStringAsFixed(6),
          'longitude': longitude.toStringAsFixed(6),
          'radius_km': radiusKm?.toString(),
        } else
          'location': (query?.isEmpty ?? true) ? null : query,
      },
    );
    if (response is List) {
      final listings = response
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceProperty.fromJson)
          .toList();
      debugPrint(
        '[MARKETPLACE SERVICE] Loaded ${listings.length} properties with available units',
      );
      return listings;
    }
    return const [];
  }

  /// Apply for an available unit (Tenant).
  ///
  /// Re-applying for the same unit while an application is still pending
  /// returns the existing application rather than creating a duplicate, so
  /// callers can treat this as idempotent.
  Future<RentalApplication> applyForUnit(
    String unitId, {
    String? message,
  }) async {
    debugPrint(
      '[MARKETPLACE SERVICE] Applying for unit $unitId POST ${ApiConstants.tenantApplicationsEndpoint}',
    );
    final trimmedMessage = message?.trim();
    final response = await _apiClient.post(
      ApiConstants.tenantApplicationsEndpoint,
      body: {
        'unit': unitId,
        if (trimmedMessage != null && trimmedMessage.isNotEmpty)
          'message': trimmedMessage,
      },
    );
    final application = RentalApplication.fromJson(response);
    debugPrint(
      '[MARKETPLACE SERVICE] Application ${application.id} status=${application.status.label}',
    );
    return application;
  }

  /// List the authenticated tenant's own applications.
  Future<List<RentalApplication>> getTenantApplications() async {
    debugPrint(
      '[MARKETPLACE SERVICE] Fetching tenant applications GET ${ApiConstants.tenantApplicationsEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.tenantApplicationsEndpoint,
    );
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(RentalApplication.fromJson)
          .toList();
    }
    return const [];
  }

  /// List applications received by the authenticated landlord.
  Future<List<RentalApplication>> getLandlordApplications({
    ApplicationStatus? status,
  }) async {
    debugPrint(
      '[MARKETPLACE SERVICE] Fetching landlord applications GET ${ApiConstants.landlordApplicationsEndpoint} '
      '(status=${status?.queryValue ?? 'any'})',
    );
    final response = await _apiClient.get(
      ApiConstants.landlordApplicationsEndpoint,
      queryParameters: {'status': status?.queryValue},
    );
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(RentalApplication.fromJson)
          .toList();
    }
    return const [];
  }

  /// Approve an application. The backend creates a PENDING tenancy agreement,
  /// marks the unit occupied, and auto-rejects other pending applications for
  /// that unit.
  Future<RentalApplication> approveApplication({
    required String applicationId,
    required String startDate,
    required String endDate,
    String? rules,
  }) async {
    final endpoint = ApiConstants.approveApplicationEndpoint(applicationId);
    debugPrint(
      '[MARKETPLACE SERVICE] Approving application $applicationId POST $endpoint',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {
        'start_date': startDate,
        'end_date': endDate,
        if (rules != null && rules.trim().isNotEmpty) 'rules': rules.trim(),
      },
    );
    return RentalApplication.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Reject a pending application.
  Future<RentalApplication> rejectApplication(String applicationId) async {
    final endpoint = ApiConstants.rejectApplicationEndpoint(applicationId);
    debugPrint(
      '[MARKETPLACE SERVICE] Rejecting application $applicationId POST $endpoint',
    );
    final response = await _apiClient.post(endpoint, body: const {});
    return RentalApplication.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }
}
