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
      '[PROPERTY SERVICE] Fetching landlord properties GET ${ApiConstants.propertiesEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.propertiesEndpoint);
    if (response is List) {
      final properties = response
          .map((item) => PropertyModel.fromJson(item))
          .toList();
      debugPrint('[PROPERTY SERVICE] Loaded ${properties.length} properties');
      return properties;
    }
    return [];
  }

  /// Get single property detail with nested units
  Future<PropertyDetail> getPropertyDetail(String propertyId) async {
    final endpoint = ApiConstants.propertyDetailEndpoint(propertyId);
    debugPrint('[PROPERTY SERVICE] Fetching property detail GET $endpoint');
    final response = await _apiClient.get(endpoint);
    if (response is Map<String, dynamic>) {
      final property = PropertyModel.fromJson(response);
      final units = response['units'] is List
          ? (response['units'] as List)
                .map((item) => UnitModel.fromJson(item))
                .toList()
          : <UnitModel>[];
      debugPrint(
        '[PROPERTY SERVICE] Property detail loaded: ID=${property.id}, Units=${units.length}',
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
    File? deedFile,
    List<File> photos = const [],
  }) async {
    debugPrint(
      '[PROPERTY SERVICE] Creating verified property POST ${ApiConstants.propertiesEndpoint} (Name: $name)',
    );
    final response = await _apiClient.postMultipartFiles(
      ApiConstants.propertiesEndpoint,
      fields: {
        'name': name,
        'address': address,
        'city': city,
        'state': state,
        // Six places, matching the field the backend declares and what Stays
        // and the marketplace already send. A pin dropped on a map is a raw
        // double: `toString()` on it yields 6.428055123456789, and a
        // DecimalField with six places rejects the extra precision, which
        // reads at this end as a plain "some details are missing or invalid"
        // after the whole evidence bundle has finished uploading.
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
        // Names what is actually attached. A short let is let by the night
        // and never signs a tenancy, so its host is not asked for a deed:
        // saying LIVE_VIDEO_AND_DEED anyway would describe evidence that is
        // not in the request.
        'verification_method': deedFile == null
            ? 'LIVE_VIDEO'
            : 'LIVE_VIDEO_AND_DEED',
      },
      files: [
        ...photos.map(
          (photo) => MultipartUpload(fieldName: 'photos', file: photo),
        ),
        MultipartUpload(
          fieldName: 'verification_video',
          file: verificationVideo,
        ),
        if (deedFile != null)
          MultipartUpload(fieldName: 'deed', file: deedFile),
        // No listing video here any more. The public walkthrough moved onto
        // the unit, where it belongs: a tenant applies for a flat, and one
        // video of a block told them nothing about the one they would live in.
      ],
    );
    final prop = PropertyModel.fromJson(response);
    debugPrint(
      '[PROPERTY SERVICE] Property created: ID=${prop.id}, Name=${prop.name}',
    );
    return prop;
  }

  // ------------------------------------------------------- listing media

  /// List a property's listing photos.
  Future<List<PropertyPhoto>> getPropertyPhotos(String propertyId) async {
    final endpoint = ApiConstants.propertyPhotosEndpoint(propertyId);
    debugPrint('[PROPERTY SERVICE] Fetching listing photos GET $endpoint');
    final response = await _apiClient.get(endpoint);
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(PropertyPhoto.fromJson)
          .toList();
    }
    return const [];
  }

  /// Upload one or more listing photos. Returns the created records.
  Future<List<PropertyPhoto>> uploadPropertyPhotos({
    required String propertyId,
    required List<File> photos,
  }) async {
    final endpoint = ApiConstants.propertyPhotosEndpoint(propertyId);
    debugPrint(
      '[PROPERTY SERVICE] Uploading ${photos.length} listing photos POST $endpoint',
    );
    final response = await _apiClient.postMultipartFiles(
      endpoint,
      fields: const {},
      files: photos
          .map((photo) => MultipartUpload(fieldName: 'photos', file: photo))
          .toList(),
    );
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(PropertyPhoto.fromJson)
          .toList();
    }
    // A single-object response is still a valid create result.
    if (response is Map<String, dynamic>) {
      return [PropertyPhoto.fromJson(response)];
    }
    return const [];
  }

  /// Delete one listing photo.
  Future<void> deletePropertyPhoto({
    required String propertyId,
    required String photoId,
  }) async {
    final endpoint = ApiConstants.propertyPhotoDetailEndpoint(
      propertyId,
      photoId,
    );
    debugPrint('[PROPERTY SERVICE] Deleting listing photo DELETE $endpoint');
    await _apiClient.delete(endpoint);
  }

  /// Current listing video URL, or null when the property has none.
  Future<String?> getPropertyVideo(String propertyId) async {
    final endpoint = ApiConstants.propertyVideoEndpoint(propertyId);
    debugPrint('[PROPERTY SERVICE] Fetching listing video GET $endpoint');
    final response = await _apiClient.get(endpoint);
    if (response is Map<String, dynamic>) {
      final url = response['video_url']?.toString();
      return (url == null || url.isEmpty) ? null : url;
    }
    return null;
  }

  /// Upload or replace the single listing video. Returns the new URL.
  Future<String?> uploadPropertyVideo({
    required String propertyId,
    required File video,
  }) async {
    final endpoint = ApiConstants.propertyVideoEndpoint(propertyId);
    debugPrint('[PROPERTY SERVICE] Uploading listing video POST $endpoint');
    final response = await _apiClient.postMultipartFiles(
      endpoint,
      fields: const {},
      files: [MultipartUpload(fieldName: 'video', file: video)],
    );
    if (response is Map<String, dynamic>) {
      final url = response['video_url']?.toString();
      return (url == null || url.isEmpty) ? null : url;
    }
    return null;
  }

  /// Delete the listing video.
  Future<void> deletePropertyVideo(String propertyId) async {
    final endpoint = ApiConstants.propertyVideoEndpoint(propertyId);
    debugPrint('[PROPERTY SERVICE] Deleting listing video DELETE $endpoint');
    await _apiClient.delete(endpoint);
  }

  // ---------------------------------------------------------- unit media

  /// List one unit's photos.
  Future<List<PropertyPhoto>> getUnitPhotos(String unitId) async {
    final endpoint = ApiConstants.unitPhotosEndpoint(unitId);
    debugPrint('[PROPERTY SERVICE] Fetching unit photos GET $endpoint');
    final response = await _apiClient.get(endpoint);
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(PropertyPhoto.fromJson)
          .toList();
    }
    return const [];
  }

  /// Upload photos of one unit. Returns the created records.
  Future<List<PropertyPhoto>> uploadUnitPhotos({
    required String unitId,
    required List<File> photos,
  }) async {
    final endpoint = ApiConstants.unitPhotosEndpoint(unitId);
    debugPrint(
      '[PROPERTY SERVICE] Uploading ${photos.length} unit photos POST $endpoint',
    );
    final response = await _apiClient.postMultipartFiles(
      endpoint,
      fields: const {},
      files: photos
          .map((photo) => MultipartUpload(fieldName: 'photos', file: photo))
          .toList(),
    );
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(PropertyPhoto.fromJson)
          .toList();
    }
    if (response is Map<String, dynamic>) {
      return [PropertyPhoto.fromJson(response)];
    }
    return const [];
  }

  /// Delete one unit photo.
  Future<void> deleteUnitPhoto({
    required String unitId,
    required String photoId,
  }) async {
    final endpoint = ApiConstants.unitPhotoDetailEndpoint(unitId, photoId);
    debugPrint('[PROPERTY SERVICE] Deleting unit photo DELETE $endpoint');
    await _apiClient.delete(endpoint);
  }

  /// Upload or replace a unit's single tour video. Returns the new URL.
  ///
  /// One per unit, replaced rather than appended: a tenant deciding whether to
  /// apply wants the walkthrough, not a playlist, and a second video would
  /// only ever raise the question of which one is current.
  Future<String?> uploadUnitVideo({
    required String unitId,
    required File video,
  }) async {
    final endpoint = ApiConstants.unitVideoEndpoint(unitId);
    debugPrint('[PROPERTY SERVICE] Uploading unit video POST $endpoint');
    final response = await _apiClient.postMultipartFiles(
      endpoint,
      fields: const {},
      files: [MultipartUpload(fieldName: 'video', file: video)],
    );
    if (response is Map<String, dynamic>) {
      final url = response['video_url']?.toString();
      return (url == null || url.isEmpty) ? null : url;
    }
    return null;
  }

  /// Delete a unit's tour video.
  Future<void> deleteUnitVideo(String unitId) async {
    final endpoint = ApiConstants.unitVideoEndpoint(unitId);
    debugPrint('[PROPERTY SERVICE] Deleting unit video DELETE $endpoint');
    await _apiClient.delete(endpoint);
  }

  /// Creates all supplied units atomically. The backend rejects the full batch if a row is invalid.
  Future<List<UnitModel>> createUnitsBatch({
    required String propertyId,
    required List<Map<String, dynamic>> units,
  }) async {
    final endpoint = ApiConstants.propertyUnitsBatchEndpoint(propertyId);
    debugPrint(
      '[PROPERTY SERVICE] Creating ${units.length} units POST $endpoint',
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
      '[PROPERTY SERVICE] Fetching units for property ID $propertyId GET $endpoint',
    );
    final response = await _apiClient.get(endpoint);
    if (response is List) {
      final units = response.map((item) => UnitModel.fromJson(item)).toList();
      debugPrint(
        '[PROPERTY SERVICE] Loaded ${units.length} units for property $propertyId',
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
      '[PROPERTY SERVICE] Creating unit for property $propertyId POST $endpoint (Unit: $unitNumber, Rent: $rentAmount)',
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
      '[PROPERTY SERVICE] Unit created: ID=${unit.id}, Unit=${unit.unitNumber}',
    );
    return unit;
  }

  /// Changes what a unit costs.
  ///
  /// Rent only. A unit's number, its bedroom count and its photos describe
  /// what the flat *is* and are fixed once tenants are looking at it; the
  /// price is the one thing a landlord legitimately changes week to week, and
  /// keeping the PATCH to that one field means a mis-wired call can never
  /// silently rewrite the rest of the listing.
  ///
  /// [rentAmount] is a year's rent as a decimal string, the same figure
  /// `POST /properties/{id}/units/` takes: the app converts a monthly quote
  /// before it gets here, because the backend stores one number.
  Future<UnitModel> updateUnitRent({
    required String unitId,
    required String rentAmount,
  }) async {
    final endpoint = ApiConstants.unitDetailEndpoint(unitId);
    debugPrint(
      '[PROPERTY SERVICE] Updating rent for unit $unitId PATCH $endpoint '
      '(Rent: $rentAmount)',
    );
    final response = await _apiClient.patch(
      endpoint,
      body: {'rent_amount': rentAmount},
    );
    return UnitModel.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Assign tenant to unit
  Future<UnitModel> assignTenant({
    required String unitId,
    required String tenantId,
  }) async {
    final endpoint = ApiConstants.assignTenantEndpoint(unitId);
    debugPrint(
      '[PROPERTY SERVICE] Assigning tenant $tenantId to unit $unitId PATCH $endpoint',
    );
    final response = await _apiClient.patch(
      endpoint,
      body: {'tenant_id': tenantId},
    );
    final unit = UnitModel.fromJson(response);
    debugPrint(
      '[PROPERTY SERVICE] Tenant assigned successfully to unit ${unit.unitNumber}',
    );
    return unit;
  }

  /// Get assigned unit for tenant
  Future<UnitModel?> getTenantAssignedUnit() async {
    debugPrint(
      '[PROPERTY SERVICE] Fetching tenant assigned unit GET ${ApiConstants.tenantAssignedUnitEndpoint}',
    );
    try {
      final response = await _apiClient.get(
        ApiConstants.tenantAssignedUnitEndpoint,
      );
      if (response is Map<String, dynamic>) {
        final unit = UnitModel.fromJson(response);
        debugPrint(
          '[PROPERTY SERVICE] Tenant assigned unit found: Unit ${unit.unitNumber} at ${unit.property?.name}',
        );
        return unit;
      }
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        debugPrint(
          'ℹ [PROPERTY SERVICE] No assigned unit found for tenant (404 Not Found)',
        );
        return null;
      }
      rethrow;
    }
  }

  // -------------------------------------------------------- removing one

  /// Asks to take a property off Landa.
  ///
  /// Returns the created request, or throws [PropertyRemovalBlocked] when
  /// the backend refuses because something on the property is still live.
  /// That refusal is a `409` carrying a per-unit list of reasons, and it is
  /// modelled as its own exception rather than a null return because the
  /// reasons are the whole answer: the landlord has to go and end a tenancy
  /// or wait out an escrow, and "no" on its own tells them nothing.
  Future<PropertyRemovalRequest> requestRemoval({
    required String propertyId,
    required String reason,
  }) async {
    final endpoint = ApiConstants.propertyRemovalRequestEndpoint(propertyId);
    debugPrint('[PROPERTY SERVICE] Requesting removal POST $endpoint');
    try {
      final response = await _apiClient.post(
        endpoint,
        body: {'reason': reason.trim()},
      );
      final request = PropertyRemovalRequest.fromJson(response);
      if (request == null) {
        throw ApiException('Could not read the removal request.');
      }
      return request;
    } on ApiException catch (e) {
      final blockers = _blockersFrom(e);
      if (blockers != null) throw PropertyRemovalBlocked(blockers);
      rethrow;
    }
  }

  /// Confirms a removal by re-entering the account password, which starts
  /// the cooling-off window.
  Future<PropertyRemovalRequest> confirmRemoval({
    required String propertyId,
    required String requestId,
    required String password,
  }) async {
    final endpoint = ApiConstants.propertyRemovalConfirmEndpoint(
      propertyId,
      requestId,
    );
    debugPrint('[PROPERTY SERVICE] Confirming removal POST $endpoint');
    try {
      final response = await _apiClient.post(
        endpoint,
        body: {'password': password},
      );
      final request = PropertyRemovalRequest.fromJson(response);
      if (request == null) {
        throw ApiException('Could not read the removal request.');
      }
      return request;
    } on ApiException catch (e) {
      // The blocking conditions are re-checked at confirmation time, because
      // a tenant can apply between the request and the password.
      final blockers = _blockersFrom(e);
      if (blockers != null) throw PropertyRemovalBlocked(blockers);
      rethrow;
    }
  }

  /// Calls off a removal, any time before the property is archived.
  Future<void> cancelRemoval({
    required String propertyId,
    required String requestId,
  }) async {
    final endpoint = ApiConstants.propertyRemovalCancelEndpoint(
      propertyId,
      requestId,
    );
    debugPrint('[PROPERTY SERVICE] Cancelling removal DELETE $endpoint');
    await _apiClient.delete(endpoint);
  }

  /// Reads the per-unit blocking reasons out of a refusal, or null when the
  /// error was something else entirely.
  List<PropertyRemovalBlocker>? _blockersFrom(ApiException error) {
    final body = error.errors;
    if (body is! Map) return null;
    if (body['blocked'] != true) return null;
    final reasons = body['reasons'];
    if (reasons is! List) return const [];
    return reasons
        .map(PropertyRemovalBlocker.fromJson)
        .whereType<PropertyRemovalBlocker>()
        .toList();
  }
}

/// Thrown when a property cannot be removed because something on it is live.
///
/// Carries the reasons per unit, which is what the sheet renders: the
/// landlord's next move is on a specific flat, not on the property.
class PropertyRemovalBlocked implements Exception {
  final List<PropertyRemovalBlocker> blockers;

  const PropertyRemovalBlocked(this.blockers);

  @override
  String toString() =>
      'PropertyRemovalBlocked(${blockers.length} unit(s) blocking)';
}

/// Result of GET /properties/{property_id}/: property fields plus its nested units.
class PropertyDetail {
  final PropertyModel property;
  final List<UnitModel> units;

  const PropertyDetail({required this.property, required this.units});
}
