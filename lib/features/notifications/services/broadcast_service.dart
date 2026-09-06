import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/broadcast_model.dart';

/// Sends and lists landlord broadcasts.
class BroadcastService {
  final ApiClient _apiClient;

  BroadcastService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// Sends an announcement to the landlord's tenants.
  ///
  /// [propertyId] is required when [audience] is `PROPERTY` and ignored
  /// otherwise. The backend works out the recipients from live tenancies: the
  /// app never sends a tenant list, so a broadcast cannot be aimed at somebody
  /// who is not actually a tenant.
  Future<Broadcast> sendBroadcast({
    required BroadcastAudience audience,
    required String title,
    required String body,
    String? propertyId,
  }) async {
    debugPrint(
      '[BROADCAST SERVICE] Sending broadcast POST ${ApiConstants.landlordBroadcastsEndpoint} '
      '(audience=${audience.wireValue})',
    );
    final response = await _apiClient.post(
      ApiConstants.landlordBroadcastsEndpoint,
      body: {
        'audience': audience.wireValue,
        'title': title,
        'body': body,
        if (audience == BroadcastAudience.property && propertyId != null)
          'property': propertyId,
      },
    );
    final broadcast = Broadcast.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
    debugPrint(
      '[BROADCAST SERVICE] Delivered to ${broadcast.recipientCount} tenants',
    );
    return broadcast;
  }

  /// The landlord's sent history.
  Future<List<Broadcast>> getBroadcasts() async {
    debugPrint(
      '[BROADCAST SERVICE] Fetching broadcasts GET ${ApiConstants.landlordBroadcastsEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.landlordBroadcastsEndpoint,
    );
    final rows = response is Map<String, dynamic>
        ? response['results']
        : response;
    if (rows is List) {
      return rows
          .whereType<Map<String, dynamic>>()
          .map(Broadcast.fromJson)
          .toList();
    }
    return const [];
  }
}
