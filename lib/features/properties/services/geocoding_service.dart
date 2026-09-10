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
/// How closely a lookup actually matched what was asked for.
///
/// The distinction matters because it decides whether the app may *place a
/// pin*. A street-level hit is a place; a state-level hit is a viewport.
/// Dropping a pin on the centroid of Oyo State and calling it a property is
/// exactly the "silently submitting a fallback city centre" failure the
/// picker was built to prevent.
enum GeocodePrecision {
  /// The street or estate itself was found.
  address,

  /// Only the town matched.
  city,

  /// Only the state matched.
  state,
}

class GeocodingService {
  static const _host = 'nominatim.openstreetmap.org';

  /// Nominatim's usage policy requires an identifying User-Agent.
  static const _headers = {
    'User-Agent': 'OasisApp/1.0 (com.oasis.oasisapp)',
    'Accept': 'application/json',
  };

  static const _timeout = Duration(seconds: 8);

  final http.Client _client;

  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  /// Finds the best point available for an address, giving up detail rather
  /// than giving up.
  ///
  /// Nigerian estates are thinly mapped in OpenStreetMap. "Kolapo Ishola",
  /// a real and well-known GRA in Ibadan, is not in it — and a single
  /// all-or-nothing query for "Kolapo Ishola, Ibadan, Oyo" therefore returned
  /// nothing at all, leaving the map sitting on its Lagos default while the
  /// form said Oyo. The landlord's reasonable conclusion was that the estate
  /// name had to be spelled exactly right. It did not; it simply was not
  /// there, and one missing street took the whole state down with it.
  ///
  /// So this asks three progressively vaguer questions and returns the first
  /// answer, tagged with [GeocodePrecision] so the caller knows whether it
  /// earned a pin or only a viewport:
  ///
  /// 1. the full address, free-text;
  /// 2. `city, state`, structured;
  /// 3. `state`, structured.
  ///
  /// Structured queries for 2 and 3 rather than more free text: Nominatim
  /// matches an explicit `city=Ibadan&state=Oyo` far more reliably than the
  /// same words in a `q`, where they compete with every road that contains
  /// them.
  Future<GeocodeSearchResult?> searchProgressive({
    String street = '',
    String city = '',
    String state = '',
  }) async {
    final trimmedStreet = street.trim();
    final trimmedCity = city.trim();
    final trimmedState = state.trim();

    if (trimmedStreet.isNotEmpty) {
      final full = [
        trimmedStreet,
        if (trimmedCity.isNotEmpty) trimmedCity,
        if (trimmedState.isNotEmpty) trimmedState,
      ].join(', ');
      final hit = await search(full);
      if (hit != null) {
        return GeocodeSearchResult(hit, GeocodePrecision.address);
      }
    }

    if (trimmedCity.isNotEmpty) {
      final hit = await _structured(city: trimmedCity, state: trimmedState);
      if (hit != null) return GeocodeSearchResult(hit, GeocodePrecision.city);
    }

    if (trimmedState.isNotEmpty) {
      final hit = await _structured(state: trimmedState);
      if (hit != null) return GeocodeSearchResult(hit, GeocodePrecision.state);
    }
    return null;
  }

  /// A structured Nominatim lookup, which is what the city and state levels
  /// use.
  ///
  /// The app's own state names are its picker's, not necessarily OSM's: it
  /// stores the federal capital as "Abuja (FCT)", which matches nothing. The
  /// parenthetical is stripped here rather than in the picker, because the
  /// picker's spelling is the one the *backend* validates against and must
  /// not drift.
  Future<GeocodeResult?> _structured({
    String? city,
    String? state,
  }) async {
    final cleanedState = state
        ?.replaceAll(RegExp(r'\s*\(.*\)\s*'), '')
        .trim();
    final uri = Uri.https(_host, '/search', {
      if (city != null && city.isNotEmpty) 'city': city,
      if (cleanedState != null && cleanedState.isNotEmpty)
        'state': cleanedState,
      'country': 'Nigeria',
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '1',
    });
    final body = await _get(uri);
    return _firstResult(body);
  }

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
    return _firstResult(await _get(uri));
  }

  /// Reads the first usable row out of a Nominatim search response.
  GeocodeResult? _firstResult(dynamic body) {
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

  /// Splits Nominatim's `address` block into the fields an Oasis property
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

/// A geocode hit plus how precise it turned out to be.
class GeocodeSearchResult {
  final GeocodeResult result;
  final GeocodePrecision precision;

  const GeocodeSearchResult(this.result, this.precision);

  /// Whether this is specific enough to place a pin on.
  ///
  /// Only a street-level hit is. A town or state hit is somewhere to *look*,
  /// and pinning one would put a property at the centroid of Ibadan.
  bool get isPinnable => precision == GeocodePrecision.address;

  /// The zoom that suits this precision: close on a street, wide on a state.
  double get zoom => switch (precision) {
    GeocodePrecision.address => 17,
    GeocodePrecision.city => 13,
    GeocodePrecision.state => 9,
  };
}
