import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:landa_app/features/properties/services/geocoding_service.dart';

/// The address lookup gives up detail rather than giving up.
///
/// A tester in Ibadan typed "Kolapo Ishola" — a real, well-known GRA — and
/// the map stayed on its Lagos default, because the single all-or-nothing
/// query found nothing and returned null. Their conclusion was that the
/// estate name had to be exact. It did not: Nigerian estates are thinly
/// mapped in OpenStreetMap, and one missing street was taking the whole state
/// down with it.
void main() {
  http.Response jsonBody(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {
        'content-type': 'application/json',
      });

  List<Map<String, Object>> hitAt(String name) => [
    {'lat': '7.3775', 'lon': '3.9470', 'display_name': name, 'address': {}},
  ];

  test('a findable street is pinnable', () async {
    final service = GeocodingService(
      client: MockClient((_) async => jsonBody(hitAt('Admiralty Way, Lekki'))),
    );

    final hit = await service.searchProgressive(
      street: 'Admiralty Way',
      city: 'Lekki',
      state: 'Lagos',
    );

    expect(hit, isNotNull);
    expect(hit!.precision, GeocodePrecision.address);
    expect(hit.isPinnable, isTrue);
  });

  test('an unmapped estate still lands in the right town', () async {
    // The regression. The street query misses; the city query answers.
    final paths = <String>[];
    final service = GeocodingService(
      client: MockClient((request) async {
        paths.add(request.url.query);
        // Free-text street lookup finds nothing…
        if (request.url.queryParameters.containsKey('q')) {
          return jsonBody(const <Map<String, Object>>[]);
        }
        // …the structured city lookup does.
        return jsonBody(hitAt('Ibadan, Oyo'));
      }),
    );

    final hit = await service.searchProgressive(
      street: 'Kolapo Ishola',
      city: 'Ibadan',
      state: 'Oyo',
    );

    expect(hit, isNotNull);
    expect(hit!.precision, GeocodePrecision.city);
    // Crucially NOT pinnable: a town centroid is somewhere to look, not a
    // property. Pinning it would put the flat in the middle of Ibadan and
    // call it verified.
    expect(hit.isPinnable, isFalse);
    expect(hit.zoom, lessThan(17));
    // It tried the street first rather than skipping straight to the town.
    expect(paths.first, contains('q='));
  });

  test('with no city it still falls back to the state', () async {
    var call = 0;
    final service = GeocodingService(
      client: MockClient((_) async {
        call++;
        return call == 1
            ? jsonBody(const <Map<String, Object>>[])
            : jsonBody(hitAt('Oyo'));
      }),
    );

    final hit = await service.searchProgressive(
      street: 'Nowhere Road',
      state: 'Oyo',
    );

    expect(hit!.precision, GeocodePrecision.state);
    expect(hit.isPinnable, isFalse);
  });

  test('the FCT is asked for by a name OSM recognises', () async {
    // The app stores the capital as "Abuja (FCT)" because that is what the
    // backend validates against. Sent to Nominatim verbatim it matches
    // nothing, so the parenthetical is stripped at the request — silently
    // breaking every Abuja landlord's fallback otherwise.
    String? sentState;
    final service = GeocodingService(
      client: MockClient((request) async {
        sentState = request.url.queryParameters['state'];
        return jsonBody(hitAt('Abuja'));
      }),
    );

    await service.searchProgressive(city: 'Wuse', state: 'Abuja (FCT)');

    expect(sentState, 'Abuja');
  });

  test('nothing anywhere returns null rather than a wrong guess', () async {
    final service = GeocodingService(
      client: MockClient((_) async => jsonBody(const <Map<String, Object>>[])),
    );

    expect(
      await service.searchProgressive(
        street: 'Nowhere',
        city: 'Nowhere',
        state: 'Nowhere',
      ),
      isNull,
    );
  });
}
