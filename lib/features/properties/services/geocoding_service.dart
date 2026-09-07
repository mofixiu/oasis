import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/utils/nigeria_locations.dart';

/// The parts of an address, as opposed to a line of text describing it.
///
/// The picker used to hand back only a display label, which meant a landlord
/// who dropped a pin still had to type the street, the city and the state
/// underneath it: the app knew all three and said none of them. This is what
/// the form fills itself from.
///
/// Every field is nullable and independently so. Nominatim's coverage of
/// Nigeria is uneven: a pin in Lekki usually resolves a road and a suburb but
/// no house number, and one on an unmapped estate road may resolve nothing
/// below the state. Filling in what is known and leaving the rest is right;
/// inventing a street is not.
class GeocodeAddress {
  /// House number and road, joined: "12 Admiralty Way".
  final String? street;

  /// The neighbourhood or suburb, where Nominatim has one: "Lekki Phase 1".
  final String? area;

  /// The town or city an address would name: "Lekki", "Ikeja", "Port
  /// Harcourt". Canonicalised against [NigeriaLocations] when it matches a
  /// town we know, so it agrees with what the city picker offers.
  final String? city;

  /// The state, canonicalised the same way, so "Federal Capital Territory"
  /// and "FCT" both arrive as the one spelling the app uses.
  final String? state;

  const GeocodeAddress({this.street, this.area, this.city, this.state});

  /// What belongs in the form's street-address box: the road, with the
  /// neighbourhood behind it when the two are different. The city and state
  /// are deliberately excluded, because they have boxes of their own and
  /// repeating them there is what produces "Lekki, Lekki, Lagos".
  String? get addressLine {
    final parts = [
      if (street != null && street!.isNotEmpty) street,
      if (area != null &&
          area!.isNotEmpty &&
          area!.toLowerCase() != street?.toLowerCase() &&
          area!.toLowerCase() != city?.toLowerCase())
        area,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// True when there is nothing here worth writing into a form.
  bool get isEmpty =>
      (street ?? '').isEmpty &&
      (area ?? '').isEmpty &&
      (city ?? '').isEmpty &&
      (state ?? '').isEmpty;
}

/// A place resolved from OpenStreetMap's Nominatim service.
class GeocodeResult {
  final LatLng point;

  /// Short one-line label, e.g. "12 Admiralty Way, Lekki".
  final String label;

  /// The full comma-separated address Nominatim returned, when we have it.
  final String? fullAddress;

  /// The same address broken into fields, for filling a form in.
  final GeocodeAddress address;

  const GeocodeResult({
    required this.point,
    required this.label,
    this.fullAddress,
    this.address = const GeocodeAddress(),
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
      address: _addressFrom(first['address']),
    );
  }

  /// Turns a dropped pin back into something a human recognises.
  ///
  /// Returns the label *and* the parts, because the caller wants both: the
  /// label goes in the map's read-out, the parts go into the form. Null only
  /// when the lookup failed outright.
  Future<GeocodeResult?> describe(LatLng point) async {
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
    final address = _addressFrom(body['address']);
    // Nothing usable came back at all: a caller showing "Pin dropped" is
    // better served by null than by an empty string it has to test for.
    if (label.isEmpty && address.isEmpty) return null;
    return GeocodeResult(
      point: point,
      label: label,
      fullAddress: body['display_name'] as String?,
      address: address,
    );
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

  /// Splits Nominatim's `address` block into the fields a Landa property
  /// form actually has.
  ///
  /// Nominatim names the same thing differently depending on how a place is
  /// mapped, which is why each field reads a chain of keys rather than one:
  /// a Lagos address may carry `suburb` and no `neighbourhood`, and a town
  /// may arrive as `city`, `town`, `village` or `county` with nothing to
  /// distinguish them but which key is present.
  ///
  /// `state` is left as the *state*, never fallen back to the city. The city
  /// chain deliberately stops before `state` for the same reason: a form that
  /// silently writes "Lagos" into both boxes because the pin resolved only a
  /// state is a form that looks filled in and is not.
  GeocodeAddress _addressFrom(dynamic address) {
    if (address is! Map<String, dynamic>) return const GeocodeAddress();

    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = address[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    final street = [
      address['house_number'],
      address['road'] ?? address['pedestrian'] ?? address['footway'],
    ].whereType<String>().join(' ').trim();

    final area = pick([
      'neighbourhood',
      'suburb',
      'quarter',
      'residential',
      'city_district',
    ]);
    final rawState = pick(['state', 'region']);
    final state = NigeriaLocations.canonicalState(rawState) ?? rawState;
    final rawCity = pick(['city', 'town', 'village', 'municipality', 'county']);
    // Prefer the app's own spelling where the town is one it lists, so the
    // filled-in value is the same string the city picker would have produced.
    final city =
        NigeriaLocations.canonicalCity(state: state, city: rawCity) ??
        NigeriaLocations.canonicalCity(state: state, city: area) ??
        rawCity;

    return GeocodeAddress(
      street: street.isEmpty ? null : street,
      area: area,
      city: city,
      state: state,
    );
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
