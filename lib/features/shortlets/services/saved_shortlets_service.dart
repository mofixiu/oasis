import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/shortlet_models.dart';

/// A guest's saved shortlets on the server (spec v16 §1).
class SavedShortLetsService {
  final ApiClient _apiClient;

  SavedShortLetsService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Saved listings, newest first. Accepts a bare list or a paginated
  /// `{results: [...]}` envelope.
  Future<List<ShortLetListing>> getSaved() async {
    final response = await _apiClient.get(ApiConstants.savedShortLetsEndpoint);
    final rows = response is List
        ? response
        : response is Map<String, dynamic> && response['results'] is List
        ? response['results'] as List
        : const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ShortLetListing.fromJson)
        .toList();
  }

  Future<void> save(String listingId) => _apiClient.post(
    ApiConstants.savedShortLetsEndpoint,
    body: {'listing_id': listingId},
  );

  Future<void> unsave(String listingId) =>
      _apiClient.delete(ApiConstants.savedShortLetEndpoint(listingId));
}
