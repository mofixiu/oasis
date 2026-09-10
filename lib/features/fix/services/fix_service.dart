import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/fix_models.dart';

/// Talks to the Artisan Fix endpoints.
///
/// Fix is a **directory**. It was a marketplace: a tenant raised a request,
/// an artisan accepted and quoted it, the tenant paid into escrow, and
/// confirming the work released the money, and API guide 18 removed every
/// endpoint behind that (§7B). Oasis no longer brokers repairs or artisan
/// payments.
///
/// What is left: find a verified artisan, see their phone number, ring them.
/// The phone number is the point. It used to be released only once a job was
/// accepted, and most of the vanished workflow existed to gate it; now it is
/// on the card, and the repair is arranged off-app like every repair was
/// before Oasis existed.
///
/// Still role-branched, for the one reason that survives: a tenant and a
/// landlord read the same directory from different paths, and a landlord
/// calling the tenant route is refused.
class FixService {
  final ApiClient _apiClient;

  FixService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  // ------------------------------------------------------------------ shared

  /// The trades the backend recognises. Served to every role.
  Future<List<ArtisanCategory>> getCategories() async {
    debugPrint(
      '[FIX SERVICE] Fetching categories GET ${ApiConstants.artisanCategoriesEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.artisanCategoriesEndpoint,
    );
    final categories = _listOf(
      response,
      ArtisanCategory.fromJson,
    ).where((category) => category.value.isNotEmpty).toList();
    debugPrint('[FIX SERVICE] ${categories.length} categorie(s)');
    return categories;
  }

  // ------------------------------------------------------------------ tenant

  /// Verified, active artisans in [category], as a tenant sees them.
  ///
  /// [unitId] is what makes the landlord's recommendation visible: pass the
  /// tenant's own unit and each artisan comes back with `is_recommended`. Omit
  /// it and the list is the same artisans with nothing singled out.
  ///
  /// [location] is a typed area name. It narrows the list without disturbing
  /// the recommendation: the backend still sorts landlord-recommended
  /// artisans first when [unitId] is sent, so searching cannot bury the one
  /// person the tenant's landlord vouched for.
  Future<List<ArtisanProfile>> browseArtisans({
    required String category,
    String? unitId,
    String? location,
  }) async {
    final query = location?.trim();
    debugPrint(
      '[FIX SERVICE] Browsing artisans GET ${ApiConstants.tenantFixArtisansEndpoint} '
      '(category=$category, unit=${unitId ?? '-'}, '
      'location=${query?.isNotEmpty == true ? query : '-'})',
    );
    final response = await _apiClient.get(
      ApiConstants.tenantFixArtisansEndpoint,
      queryParameters: {
        'category': category,
        if (unitId != null && unitId.isNotEmpty) 'unit': unitId,
        'location': (query?.isEmpty ?? true) ? null : query,
      },
    );
    final artisans = _listOf(response, ArtisanProfile.fromJson);
    debugPrint(
      '[FIX SERVICE] ${artisans.length} artisan(s), '
      '${artisans.where((a) => a.isRecommended).length} recommended',
    );
    return artisans;
  }

  // ----------------------------------------------------------------- artisan

  /// The signed-in artisan's own profile, including their phone number.
  ///
  /// This is now the whole of an artisan's app. Keeping it accurate is how
  /// they are found; there is nothing else for them to do here.
  Future<ArtisanProfile> getMyArtisanProfile() async {
    debugPrint(
      '[FIX SERVICE] Fetching artisan profile GET ${ApiConstants.artisanProfileEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.artisanProfileEndpoint);
    return ArtisanProfile.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Edits the signed-in artisan's profile. Every field is optional; only
  /// what is passed is sent.
  Future<ArtisanProfile> updateMyArtisanProfile({
    String? category,
    String? location,
    String? bio,
    int? yearsOfExperience,
  }) async {
    debugPrint(
      '[FIX SERVICE] Updating artisan profile PATCH ${ApiConstants.artisanProfileEndpoint}',
    );
    final response = await _apiClient.patch(
      ApiConstants.artisanProfileEndpoint,
      body: {
        if (category != null) 'category': category,
        if (location != null) 'location': location.trim(),
        if (bio != null) 'bio': bio.trim(),
        if (yearsOfExperience != null) 'years_of_experience': yearsOfExperience,
      },
    );
    return ArtisanProfile.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  // ---------------------------------------------------------------- landlord

  /// The directory as a landlord sees it, for choosing who to recommend.
  ///
  /// Its own route rather than the tenant one, and that is not a formality:
  /// a landlord calling `/tenant/fix/artisans/` is refused with a 403. The
  /// app used to guess this path as `/landlord/fix/artisans/` and fall back
  /// to the tenant route on a 404, which meant every landlord's picker came
  /// up empty and nobody could be recommended. API guide 18 documents the
  /// real path, so there is no fallback any more: a failure here is a
  /// failure worth reporting.
  Future<List<ArtisanProfile>> browseArtisansForLandlord({
    required String category,
    String? unitId,
    String? location,
  }) async {
    final query = location?.trim();
    debugPrint(
      '[FIX SERVICE] Browsing artisans (landlord) GET '
      '${ApiConstants.landlordArtisansEndpoint} '
      '(category=$category, unit=${unitId ?? '-'})',
    );
    final response = await _apiClient.get(
      ApiConstants.landlordArtisansEndpoint,
      queryParameters: {
        'category': category,
        if (unitId != null && unitId.isNotEmpty) 'unit': unitId,
        'location': (query?.isEmpty ?? true) ? null : query,
      },
    );
    return _listOf(response, ArtisanProfile.fromJson);
  }

  /// The artisans a landlord has vouched for on one unit.
  Future<List<ArtisanRecommendation>> getUnitRecommendations(
    String unitId,
  ) async {
    final endpoint = ApiConstants.unitArtisanRecommendationsEndpoint(unitId);
    debugPrint('[FIX SERVICE] Fetching recommendations GET $endpoint');
    final recommendations = _listOf(
      await _apiClient.get(endpoint),
      ArtisanRecommendation.fromJson,
    );
    debugPrint(
      '[FIX SERVICE] ${recommendations.length} recommendation(s) on $unitId',
    );
    return recommendations;
  }

  /// Names the artisan for one category on a unit.
  ///
  /// One endpoint creates and replaces: a unit holds a single recommendation
  /// per category, so posting again for the same category overwrites rather
  /// than adding a second. That is why there is no separate update call.
  Future<ArtisanRecommendation> recommendArtisan({
    required String unitId,
    required String category,
    required String artisanId,
  }) async {
    final endpoint = ApiConstants.unitArtisanRecommendationsEndpoint(unitId);
    debugPrint(
      '[FIX SERVICE] Recommending $artisanId for $category POST $endpoint',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {'category': category, 'artisan_id': artisanId},
    );
    return ArtisanRecommendation.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Drops the recommendation for one category. The category travels in the
  /// body because the path identifies only the unit.
  Future<void> removeRecommendation({
    required String unitId,
    required String category,
  }) async {
    final endpoint = ApiConstants.unitArtisanRecommendationsEndpoint(unitId);
    debugPrint(
      '[FIX SERVICE] Removing $category recommendation DELETE $endpoint',
    );
    await _apiClient.delete(endpoint, body: {'category': category});
  }

  /// Reads a list response in either shape the API uses: a bare array, or a
  /// paginated envelope with a `results` key.
  List<T> _listOf<T>(dynamic response, T Function(Map<String, dynamic>) parse) {
    if (response is List) {
      return response.whereType<Map<String, dynamic>>().map(parse).toList();
    }
    if (response is Map<String, dynamic> && response['results'] is List) {
      return (response['results'] as List)
          .whereType<Map<String, dynamic>>()
          .map(parse)
          .toList();
    }
    return const [];
  }
}
