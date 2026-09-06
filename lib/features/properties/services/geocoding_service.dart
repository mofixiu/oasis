import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A place resolved from OpenStreetMap's Nominatim service.
class GeocodeResult {
  final LatLng point;

  /// Short one-line label, e.g. "12 Admiralty Way, Lekki".
  final String label;

  /// The full comma-separated address Nominatim returned, when we have it.
  final String? fullAddress;

  const GeocodeResult({
    required this.point,
    required this.label,
    this.fullAddress,
  });
}

/// Thin wrapper over Nominatim, the geocoder that pairs with the OpenStreetMap
/// tiles the pin map already renders.
///
/// Every lookup is best-effort: the picker still works with raw coordinates if
/// the service is slow, rate-limited or unreachable, so failures return null
/// rather than throwing.
class GeocodingService {
  static const _host = 'nominatim.openstreetmap.org';

  /// Nominatim's usage policy requires an identifying User-Agent.
  static const _headers = {
    'User-Agent': 'LandaApp/1.0 (com.landa.landa_app)',
    'Accept': 'application/json',
  };

  static const _timeout = Duration(seconds: 8);

  final http.Client _client;

  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  /// Turns a typed address into a point. [countryCode] biases results to
  /// Nigeria so "Admiralty Way" does not land in another country.
  Future<GeocodeResult?> search(
    String query, {
    String? countryCode = 'ng',
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 4) return null;
    final uri = Uri.https(_host, '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '1',
      if (countryCode != null) 'countrycodes': countryCode,
    });
    final body = await _get(uri);
    if (body is! List || body.isEmpty) return null;
    final first = body.first;
    if (first is! Map<String, dynamic>) return null;
    final lat = double.tryParse('${first['lat']}');
    final lon = double.tryParse('${first['lon']}');
    if (lat == null || lon == null) return null;
    final display = first['display_name'] as String?;
    return GeocodeResult(
      point: LatLng(lat, lon),
      label: _labelFrom(first['address'], display),
      fullAddress: display,
    );
  }

  /// Turns a dropped pin back into something a human recognises.
  Future<String?> describe(LatLng point) async {
    final uri = Uri.https(_host, '/reverse', {
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'format': 'jsonv2',
      'addressdetails': '1',
      // Street-level detail; house numbers are rarely mapped in Nigeria.
      'zoom': '18',
    });
    final body = await _get(uri);
    if (body is! Map<String, dynamic>) return null;
    final label = _labelFrom(body['address'], body['display_name'] as String?);
    return label.isEmpty ? null : label;
  }

  Future<dynamic> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('[GEOCODING] ${response.statusCode} for ${uri.path}');
        return null;
      }
      return jsonDecode(response.body);
    } catch (error) {
      debugPrint('[GEOCODING] ${uri.path} failed: $error');
      return null;
    }
  }

  /// Builds "road, area, city" from Nominatim's address parts, falling back to
  /// the first few chunks of the display name when the parts are missing.
  String _labelFrom(dynamic address, String? displayName) {
    if (address is Map<String, dynamic>) {
      final road = [
        address['house_number'],
        address['road'] ?? address['pedestrian'] ?? address['footway'],
      ].whereType<String>().join(' ').trim();
      final area =
          (address['neighbourhood'] ??
                  address['suburb'] ??
                  address['quarter'] ??
                  address['village'] ??
                  address['city_district'])
              as String?;
      final city =
          (address['city'] ?? address['town'] ?? address['state']) as String?;
      final parts = [
        if (road.isNotEmpty) road,
        if (area != null && area.isNotEmpty) area,
        if (city != null && city.isNotEmpty) city,
      ];
      if (parts.isNotEmpty) return parts.take(3).join(', ');
    }
    if (displayName == null || displayName.isEmpty) return '';
    return displayName.split(',').take(3).map((part) => part.trim()).join(', ');
  }
}
