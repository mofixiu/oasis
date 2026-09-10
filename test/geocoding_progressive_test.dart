import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:oasis_app/core/utils/nigeria_locations.dart';
import 'package:oasis_app/features/properties/services/geocoding_service.dart';

/// The address lookup gives up detail rather than giving up.
///
/// A tester in Ibadan typed "Kolapo Ishola" — a real, well-known GRA — and
/// the map stayed on its Lagos default, because the single all-or-nothing
/// query found nothing and returned null. Their conclusion was that the
/// estate name had to be exact. It did not: Nigerian estates are thinly
/// mapped in OpenStreetMap, and one missing street was taking the whole state
/// down with it.
void main() {
  _bundledCentres();

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

/// The bundled state centres, which are what make the map work when the
/// lookup service will not.
void _bundledCentres() {
  group('every state has somewhere to open the map', () {
    test('all 37 canonical states carry a centre', () {
      // A state in the picker with no centre is a landlord who selects their
      // state and watches the map stay in Lagos — the original bug, back
      // again for one state instead of all of them.
      final missing = NigeriaLocations.states
          .where((s) => NigeriaLocations.stateCentres[s] == null)
          .toList();
      expect(missing, isEmpty, reason: 'no map centre for: $missing');
      expect(NigeriaLocations.stateCentres, hasLength(37));
    });

    test('every centre is actually inside Nigeria', () {
      // Guards a transposed pair or a dropped minus sign, which would put a
      // landlord in the Gulf of Guinea with no error to explain it.
      NigeriaLocations.stateCentres.forEach((state, centre) {
        expect(
          centre.$1,
          inInclusiveRange(4.0, 14.0),
          reason: '$state latitude looks wrong',
        );
        expect(
          centre.$2,
          inInclusiveRange(2.5, 14.8),
          reason: '$state longitude looks wrong',
        );
      });
    });

    test('centres resolve through the spellings the picker accepts', () {
      // The lookup goes via canonicalState, so the aliases must work too.
      expect(NigeriaLocations.centreOf('Oyo')!.$1, closeTo(7.377, 0.01));
      expect(NigeriaLocations.centreOf('oyo state')!.$1, closeTo(7.377, 0.01));
      expect(NigeriaLocations.centreOf('FCT')!.$1, closeTo(9.076, 0.01));
      expect(
        NigeriaLocations.centreOf('federal capital territory')!.$2,
        closeTo(7.398, 0.01),
      );
      expect(NigeriaLocations.centreOf('Atlantis'), isNull);
    });

    test('Oyo opens on Ibadan, not Lagos', () {
      // The tester's exact case, as a one-line assertion.
      final oyo = NigeriaLocations.centreOf('Oyo')!;
      final lagos = NigeriaLocations.centreOf('Lagos')!;
      expect(oyo, isNot(lagos));
      // Ibadan sits well north of Lagos — roughly 95km inland.
      expect(oyo.$1, greaterThan(lagos.$1));
    });
  });
}
