import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/core/widgets/landa_search_field.dart';
import 'package:landa_app/features/auth/controllers/auth_controller.dart';
import 'package:landa_app/features/auth/services/api_auth_service.dart';
import 'package:landa_app/features/fix/services/fix_service.dart';
import 'package:landa_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:landa_app/features/marketplace/models/marketplace_models.dart';
import 'package:landa_app/features/marketplace/services/marketplace_service.dart';
import 'package:landa_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:landa_app/features/shortlets/models/shortlet_models.dart';
import 'package:landa_app/features/shortlets/services/shortlet_service.dart';
import 'package:landa_app/features/shortlets/views/shortlet_browse_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Search is how a tenant narrows three different lists, and every one of them
/// hides listings when it is on. These cover what would actually mislead
/// someone: a query that never reaches the backend, a coordinate search and a
/// typed search both claiming to be in effect, or a search bar still showing a
/// place name after the results stopped being filtered by it.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(
      access: 'test-access-token',
      refresh: 'test-refresh-token',
    );
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() => ApiConstants.baseUrl = originalBaseUrl);

  // ---------------------------------------------------------- marketplace

  test('marketplace search rides alongside the existing filters', () async {
    Uri? sentUri;
    final service = MarketplaceService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentUri = request.url;
          return _json(const []);
        }),
      ),
    );

    await service.getMarketplace(
      filters: const MarketplaceFilters(bedrooms: 2, minRent: '200000'),
      location: '  Lekki  ',
    );

    expect(sentUri?.path, '/api/users/tenant/marketplace/');
    expect(sentUri?.queryParameters, {
      // min_price, not min_rent: the 2026-09-03 search update unified the
      // param name across rentals and short lets. The backend still accepts
      // min_rent, but there is no reason to send the old one too.
      'min_price': '200000',
      'bedrooms': '2',
      // Trimmed: a trailing space is not part of the place name.
      'location': 'Lekki',
    });
  });

  test('an empty marketplace search sends no location at all', () async {
    Uri? sentUri;
    final service = MarketplaceService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentUri = request.url;
          return _json(const []);
        }),
      ),
    );

    await service.getMarketplace(location: '   ');

    expect(sentUri?.queryParameters.containsKey('location'), isFalse);
  });

  test('clearing the marketplace search drops the filters too', () async {
    final uris = <Uri>[];
    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            uris.add(request.url);
            return _json(const []);
          }),
        ),
      ),
    );

    await controller.applyFilters(const MarketplaceFilters(bedrooms: 3));
    await controller.search('Yaba');
    expect(controller.isNarrowed, isTrue);

    await controller.clearSearchAndFilters();

    expect(controller.searchQuery, isEmpty);
    expect(controller.isNarrowed, isFalse);
    // Last marketplace call carries neither the search nor the filter.
    final last = uris.lastWhere(
      (uri) => uri.path == '/api/users/tenant/marketplace/',
    );
    expect(last.queryParameters, isEmpty);
  });

  // ----------------------------------------------------------------- stays

  test(
    'a nearby stays search sends coordinates and no typed location',
    () async {
      Uri? sentUri;
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            sentUri = request.url;
            return _json(const []);
          }),
        ),
      );

      await service.browseListings(latitude: 6.445, longitude: 3.472);

      expect(sentUri?.path, '/api/users/tenant/short-lets/');
      expect(sentUri?.queryParameters, {
        'latitude': '6.445000',
        'longitude': '3.472000',
      });
      // Left to the backend's own 10km default rather than hard-coded here.
      expect(sentUri?.queryParameters.containsKey('radius_km'), isFalse);
    },
  );

  test('coordinates and a typed area are never both in effect', () async {
    final uris = <Uri>[];
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            uris.add(request.url);
            return _json(const []);
          }),
        ),
      ),
    );

    await controller.searchNearby(latitude: 6.445, longitude: 3.472);
    expect(controller.isSearchingNearby, isTrue);
    expect(controller.searchQuery, isEmpty);

    // Typing replaces the coordinate search rather than stacking onto it.
    await controller.searchBrowseListings('Lekki');
    expect(controller.isSearchingNearby, isFalse);
    expect(uris.last.queryParameters, {'location': 'Lekki'});

    await controller.clearBrowseSearch();
    expect(controller.isBrowseNarrowed, isFalse);
    expect(uris.last.queryParameters, isEmpty);
  });

  test(
    'searched dates ride alongside wherever the tenant is looking',
    () async {
      final uris = <Uri>[];
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            uris.add(request.url);
            return _json(const []);
          }),
        ),
      );

      // Dates are a separate axis from place: they annotate results rather than
      // filtering them, so they must survive both kinds of search.
      await service.browseListings(
        location: 'Lekki',
        checkIn: '2026-10-10',
        checkOut: '2026-10-12',
      );
      expect(uris.last.queryParameters, {
        'location': 'Lekki',
        'check_in': '2026-10-10',
        'check_out': '2026-10-12',
      });

      await service.browseListings(
        latitude: 6.445,
        longitude: 3.472,
        checkIn: '2026-10-10',
        checkOut: '2026-10-12',
      );
      expect(uris.last.queryParameters, {
        'latitude': '6.445000',
        'longitude': '3.472000',
        'check_in': '2026-10-10',
        'check_out': '2026-10-12',
      });

      // One date alone describes no period, so neither is sent.
      await service.browseListings(checkIn: '2026-10-10');
      expect(uris.last.queryParameters.containsKey('check_in'), isFalse);
    },
  );

  test('clearing where you are looking keeps when', () async {
    final uris = <Uri>[];
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            uris.add(request.url);
            return _json(const []);
          }),
        ),
      ),
    );

    await controller.setSearchDates(
      DateTimeRange(start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 12)),
    );
    await controller.searchBrowseListings('Lekki');
    expect(uris.last.queryParameters, {
      'location': 'Lekki',
      'check_in': '2026-10-10',
      'check_out': '2026-10-12',
    });

    // Dates never hid a listing, so "See all" must not silently discard them.
    await controller.clearBrowseSearch();
    expect(controller.hasSearchDates, isTrue);
    expect(uris.last.queryParameters, {
      'check_in': '2026-10-10',
      'check_out': '2026-10-12',
    });
  });

  test('an unavailable stay is kept, not dropped', () async {
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json([
              {'id': 'free', 'is_available_for_period': true},
              {
                'id': 'taken',
                'is_available_for_period': false,
                'unavailable_reason': 'One or more selected dates are blocked.',
              },
            ]),
          ),
        ),
      ),
    );

    await controller.setSearchDates(
      DateTimeRange(start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 12)),
    );

    // The backend asks that unavailable stays be shown with their reason,
    // never filtered out.
    expect(controller.browseListings.length, 2);
    expect(controller.unavailableForDates.map((l) => l.id), ['taken']);
    expect(
      controller.browseListings.last.unavailableLabel,
      'One or more selected dates are blocked.',
    );
  });

  test('only an explicit false means unavailable', () {
    // Null is "no dates were searched". Reading it as unavailable would mark
    // every ordinary browse result as booked up.
    final unchecked = ShortLetListing.fromJson({'id': 'l'});
    expect(unchecked.isAvailableForPeriod, isNull);
    expect(unchecked.isUnavailableForPeriod, isFalse);

    final available = ShortLetListing.fromJson({
      'id': 'l',
      'is_available_for_period': true,
    });
    expect(available.isUnavailableForPeriod, isFalse);

    final taken = ShortLetListing.fromJson({
      'id': 'l',
      'is_available_for_period': false,
    });
    expect(taken.isUnavailableForPeriod, isTrue);
    // Refused without a reason still has to say something.
    expect(taken.unavailableLabel, isNotEmpty);
  });

  test('distance only shows when the backend measured one', () {
    final measured = ShortLetListing.fromJson({
      'id': 'listing-1',
      'distance_km': 2.41,
    });
    expect(measured.distanceLabel, '2.4 km away');

    // Under a kilometre reads in metres; a long way out drops the decimal.
    expect(
      ShortLetListing.fromJson({'id': 'l', 'distance_km': 0.4}).distanceLabel,
      '400 m away',
    );
    expect(
      ShortLetListing.fromJson({'id': 'l', 'distance_km': 23.6}).distanceLabel,
      '24 km away',
    );

    // A browse without coordinates measures nothing, and must not read as
    // "zero away".
    final unmeasured = ShortLetListing.fromJson({'id': 'listing-2'});
    expect(unmeasured.distanceKm, isNull);
    expect(unmeasured.distanceLabel, isNull);
  });

  // ------------------------------------------------------------------- fix

  test('an artisan search keeps the category and the unit', () async {
    Uri? sentUri;
    final service = FixService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentUri = request.url;
          return _json(const []);
        }),
      ),
    );

    await service.browseArtisans(
      category: 'PLUMBING',
      unitId: 'UNIT_UUID',
      location: 'Lekki',
    );

    // The unit has to survive the search: it is what puts the landlord's
    // recommended artisan at the top of the list.
    expect(sentUri?.queryParameters, {
      'category': 'PLUMBING',
      'unit': 'UNIT_UUID',
      'location': 'Lekki',
    });
  });

  // ---------------------------------------------------------- search field

  testWidgets('typing a word is one request, not one per letter', (
    tester,
  ) async {
    final queries = <String>[];
    final textController = TextEditingController();
    addTearDown(textController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandaSearchField(
            controller: textController,
            hintText: 'Search by area',
            debounce: const Duration(milliseconds: 200),
            onChanged: queries.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'L');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'Le');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'Lekki');
    // Nothing has been searched for yet: typing has not settled.
    expect(queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 250));
    expect(queries, ['Lekki']);
  });

  testWidgets('clearing the box searches again immediately', (tester) async {
    final queries = <String>[];
    final textController = TextEditingController(text: 'Lekki');
    addTearDown(textController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandaSearchField(
            controller: textController,
            hintText: 'Search by area',
            onChanged: queries.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    // No debounce on clear: the tenant wants the full list back now.
    expect(queries, ['']);
    expect(textController.text, isEmpty);
  });

  testWidgets('the screen can empty the box from outside', (tester) async {
    final textController = TextEditingController(text: 'Lekki');
    addTearDown(textController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandaSearchField(
            controller: textController,
            hintText: 'Search by area',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('Clear search'), findsOneWidget);

    // What "Near me" and the empty state's "Clear search" do: a stale place
    // name left in the box would claim to be filtering results it is not.
    textController.clear();
    await tester.pump();

    expect(find.text('Lekki'), findsNothing);
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets('a stay that is taken is shown with its reason', (tester) async {
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json([
              {
                'id': 'taken',
                'property_name': 'Sunset House',
                'unit_number': 'A1',
                'nightly_price': '50000.00',
                'minimum_nights': 2,
                'is_available_for_period': false,
                'unavailable_reason': 'One or more selected dates are blocked.',
              },
            ]),
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider(
            create: (_) => AuthController(authService: ApiAuthService()),
          ),
        ],
        child: const MaterialApp(home: ShortLetBrowseScreen()),
      ),
    );
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    // The whole point of the backend change: the listing is on screen, and
    // the tenant is told why those dates will not work rather than being
    // shown a shorter list with no explanation.
    expect(find.textContaining('Sunset House'), findsOneWidget);
    expect(
      find.text('One or more selected dates are blocked.'),
      findsOneWidget,
    );
    expect(find.text('NOT FREE THEN'), findsOneWidget);
  });

  testWidgets('Stays still works when location is refused', (tester) async {
    // No geolocator in a test binding, which is the same shape as a tenant
    // who says no: the screen must come to rest showing the typed search
    // rather than spinning on a fix that is never coming.
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json([
              {
                'id': 'l1',
                'property_name': 'Sunset House',
                'unit_number': 'A1',
                'city': 'Lagos',
                'nightly_price': '50000.00',
                'minimum_nights': 2,
              },
            ]),
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider(
            create: (_) => AuthController(authService: ApiAuthService()),
          ),
        ],
        child: const MaterialApp(home: ShortLetBrowseScreen()),
      ),
    );
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(find.byType(LandaSearchField), findsOneWidget);
    expect(find.text('Near me'), findsOneWidget);
    // The listing still came through: a refused location narrows nothing.
    expect(find.textContaining('Sunset House'), findsOneWidget);
    expect(controller.isSearchingNearby, isFalse);
    expect(controller.isBrowseNarrowed, isFalse);
  });
  // ------------------------------------------------- marketplace near me

  test(
    'a nearby marketplace search sends coordinates, not a place name',
    () async {
      Uri? sentUri;
      final service = MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            sentUri = request.url;
            return _json(const []);
          }),
        ),
      );

      await service.getMarketplace(
        // Both supplied: coordinates must win, because a tenant who has just
        // tapped Near me is asking about where they are standing.
        location: 'Lekki',
        latitude: 6.445,
        longitude: 3.472,
      );

      expect(sentUri?.queryParameters['latitude'], '6.445000');
      expect(sentUri?.queryParameters['longitude'], '3.472000');
      expect(sentUri?.queryParameters.containsKey('location'), isFalse);
    },
  );

  test('a nearby search orders the marketplace by distance', () async {
    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/applications/')) {
              return _json(const []);
            }
            return _json([
              _marketplaceProperty(
                name: 'Far House',
                latitude: 6.6,
                longitude: 3.6,
              ),
              _marketplaceProperty(
                name: 'Near House',
                latitude: 6.4451,
                longitude: 3.4721,
              ),
            ]);
          }),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.searchNearby(latitude: 6.445, longitude: 3.472);

    // The backend does not sort these yet: this is the app doing it, and the
    // whole point of the Near me notice is that it is telling the truth.
    expect(controller.isSearchingNearby, isTrue);
    expect(controller.listings.first.property.name, 'Near House');
    expect(controller.listings.first.distanceKm, lessThan(1));
    expect(controller.listings.last.property.name, 'Far House');
  });

  test('an unpinned property sorts last rather than vanishing', () async {
    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/applications/')) {
              return _json(const []);
            }
            return _json([
              // No coordinates at all, and the (0, 0) that an un-geocoded
              // record turns into: neither is "700km away".
              _marketplaceProperty(name: 'Unpinned House'),
              _marketplaceProperty(
                name: 'Null Island House',
                latitude: 0,
                longitude: 0,
              ),
              _marketplaceProperty(
                name: 'Pinned House',
                latitude: 6.45,
                longitude: 3.47,
              ),
            ]);
          }),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.searchNearby(latitude: 6.445, longitude: 3.472);

    expect(controller.listings.length, 3);
    expect(controller.listings.first.property.name, 'Pinned House');
    expect(controller.listings[1].distanceKm, isNull);
    expect(controller.listings[2].distanceKm, isNull);
  });

  test(
    'a server-sent distance is preferred over the app measuring it',
    () async {
      final controller = MarketplaceController(
        service: MarketplaceService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.url.path.endsWith('/applications/')) {
                return _json(const []);
              }
              return _json([
                {
                  ..._marketplaceProperty(
                    name: 'Sunset House',
                    latitude: 6.6,
                    longitude: 3.6,
                  ),
                  'distance_km': 0.4,
                },
              ]);
            }),
          ),
        ),
      );
      addTearDown(controller.dispose);

      await controller.searchNearby(latitude: 6.445, longitude: 3.472);

      // The backend measures against whatever it holds as the property's
      // position, and that is the authority. Two numbers for one distance is
      // the failure this guards.
      expect(controller.listings.single.distanceKm, 0.4);
      expect(controller.listings.single.distanceLabel, '400 m away');
    },
  );

  test('typing an area drops a running nearby search', () async {
    final requestedUris = <Uri>[];
    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            requestedUris.add(request.url);
            return _json(const []);
          }),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.searchNearby(latitude: 6.445, longitude: 3.472);
    await controller.search('Yaba');

    expect(controller.isSearchingNearby, isFalse);
    final last = requestedUris.lastWhere(
      (uri) => uri.path.endsWith('/marketplace/'),
    );
    expect(last.queryParameters['location'], 'Yaba');
    expect(last.queryParameters.containsKey('latitude'), isFalse);
  });
}

/// A marketplace payload row, with an optional pin.
Map<String, dynamic> _marketplaceProperty({
  required String name,
  double? latitude,
  double? longitude,
}) => {
  'id': 'property-$name',
  'name': name,
  'address': '1 Test Road',
  'city': 'Lagos',
  'state': 'Lagos',
  if (latitude != null) 'latitude': latitude,
  if (longitude != null) 'longitude': longitude,
  'available_units': const [
    {
      'id': 'unit-1',
      'unit_number': 'A1',
      'bedrooms': 2,
      'bathrooms': 1,
      'rent_amount': '450000.00',
      'is_occupied': false,
    },
  ],
};

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
