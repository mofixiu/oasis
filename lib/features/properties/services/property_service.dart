import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/property_model.dart';

class PropertyService {
  final ApiClient _apiClient;

  PropertyService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// List landlord properties
  Future<List<PropertyModel>> getProperties() async {
    debugPrint(
      '🏢 [PROPERTY SERVICE] Fetching landlord properties GET ${ApiConstants.propertiesEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.propertiesEndpoint);
    if (response is List) {
      final properties = response
          .map((item) => PropertyModel.fromJson(item))
          .toList();
      debugPrint(
        '🏢 [PROPERTY SERVICE] Loaded ${properties.length} properties',
      );
      return properties;
    }
    return [];
  }

  /// Get single property detail with nested units
  Future<PropertyDetail> getPropertyDetail(String propertyId) async {
    final endpoint = ApiConstants.propertyDetailEndpoint(propertyId);
    debugPrint(
      '🏢 [PROPERTY SERVICE] Fetching property detail GET $endpoint',
    );
    final response = await _apiClient.get(endpoint);
    if (response is Map<String, dynamic>) {
      final property = PropertyModel.fromJson(response);
      final units = response['units'] is List
          ? (response['units'] as List)
                .map((item) => UnitModel.fromJson(item))
                .toList()
          : <UnitModel>[];
      debugPrint(
        '🏢 [PROPERTY SERVICE] Property detail loaded: ID=${property.id}, Units=${units.length}',
      );
      return PropertyDetail(property: property, units: units);
    }
    throw ApiException('Unexpected property detail response from the server.');
  }

  /// Create property
  Future<PropertyModel> createProperty({
    required String name,
    required String address,
    required String city,
    required String state,
    required double latitude,
    required double longitude,
    required File verificationVideo,
    required File deedFile,
    List<File> photos = const [],
  }) async {
    debugPrint(
      '🏢 [PROPERTY SERVICE] Creating verified property POST ${ApiConstants.propertiesEndpoint} (Name: $name)',
    );
    final response = await _apiClient.postMultipartFiles(
      ApiConstants.propertiesEndpoint,
      fields: {
        'name': name,
        'address': address,
        'city': city,
        'state': state,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'verification_method': 'LIVE_VIDEO_AND_DEED',
      },
      files: [
        ...photos.map(
          (photo) => MultipartUpload(fieldName: 'photos', file: photo),
        ),
        MultipartUpload(
          fieldName: 'verification_video',
          file: verificationVideo,
        ),
        MultipartUpload(fieldName: 'deed', file: deedFile),
      ],
    );
    final prop = PropertyModel.fromJson(response);
    debugPrint(
      '🏢 [PROPERTY SERVICE] Property created: ID=${prop.id}, Name=${prop.name}',
    );
    return prop;
  }

  /// Creates all supplied units atomically. The backend rejects the full batch if a row is invalid.
  Future<List<UnitModel>> createUnitsBatch({
    required String propertyId,
    required List<Map<String, dynamic>> units,
  }) async {
    final endpoint = ApiConstants.propertyUnitsBatchEndpoint(propertyId);
    debugPrint(
      '🏠 [PROPERTY SERVICE] Creating ${units.length} units POST $endpoint',
    );
    final response = await _apiClient.post(endpoint, body: {'units': units});
    if (response is List) {
      return response.map((item) => UnitModel.fromJson(item)).toList();
    }
    if (response is Map<String, dynamic> && response['units'] is List) {
      return (response['units'] as List)
          .map((item) => UnitModel.fromJson(item))
          .toList();
    }
    return const [];
  }

  /// List units for property
  Future<List<UnitModel>> getUnits(String propertyId) async {
    final endpoint = ApiConstants.propertyUnitsEndpoint(propertyId);
    debugPrint(
      '🏠 [PROPERTY SERVICE] Fetching units for property ID $propertyId GET $endpoint',
    );
    final response = await _apiClient.get(endpoint);
    if (response is List) {
      final units = response.map((item) => UnitModel.fromJson(item)).toList();
      debugPrint(
        '🏠 [PROPERTY SERVICE] Loaded ${units.length} units for property $propertyId',
      );
      return units;
    }
    return [];
  }

  /// Create unit for property
  Future<UnitModel> createUnit({
    required String propertyId,
    required String unitNumber,
    required int bedrooms,
    required int bathrooms,
    required String rentAmount,
  }) async {
    final endpoint = ApiConstants.propertyUnitsEndpoint(propertyId);
    debugPrint(
      '🏠 [PROPERTY SERVICE] Creating unit for property $propertyId POST $endpoint (Unit: $unitNumber, Rent: $rentAmount)',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {
        'unit_number': unitNumber,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'rent_amount': rentAmount,
      },
    );
    final unit = UnitModel.fromJson(response);
    debugPrint(
      '🏠 [PROPERTY SERVICE] Unit created: ID=${unit.id}, Unit=${unit.unitNumber}',
    );
    return unit;
  }

  /// Assign tenant to unit
  Future<UnitModel> assignTenant({
    required String unitId,
    required String tenantId,
  }) async {
    final endpoint = ApiConstants.assignTenantEndpoint(unitId);
    debugPrint(
      '👤 [PROPERTY SERVICE] Assigning tenant $tenantId to unit $unitId PATCH $endpoint',
    );
    final response = await _apiClient.patch(
      endpoint,
      body: {'tenant_id': tenantId},
    );
    final unit = UnitModel.fromJson(response);
    debugPrint(
      '👤 [PROPERTY SERVICE] Tenant assigned successfully to unit ${unit.unitNumber}',
    );
    return unit;
  }

  /// Get assigned unit for tenant
  Future<UnitModel?> getTenantAssignedUnit() async {
    debugPrint(
      '🏠 [PROPERTY SERVICE] Fetching tenant assigned unit GET ${ApiConstants.tenantAssignedUnitEndpoint}',
    );
    try {
      final response = await _apiClient.get(
        ApiConstants.tenantAssignedUnitEndpoint,
      );
      if (response is Map<String, dynamic>) {
        final unit = UnitModel.fromJson(response);
        debugPrint(
          '🏠 [PROPERTY SERVICE] Tenant assigned unit found: Unit ${unit.unitNumber} at ${unit.property?.name}',
        );
        return unit;
      }
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        debugPrint(
          'ℹ️ [PROPERTY SERVICE] No assigned unit found for tenant (404 Not Found)',
        );
        return null;
      }
      rethrow;
    }
  }
}

/// Result of GET /properties/{property_id}/: property fields plus its nested units.
class PropertyDetail {
  final PropertyModel property;
  final List<UnitModel> units;

  const PropertyDetail({required this.property, required this.units});
}
