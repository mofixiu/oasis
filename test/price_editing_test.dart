import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/core/widgets/oasis_pressable.dart';
import 'package:oasis_app/features/properties/controllers/landlord_controller.dart';
import 'package:oasis_app/features/properties/models/property_model.dart';
import 'package:oasis_app/features/properties/services/property_service.dart';
import 'package:oasis_app/features/properties/views/widgets/edit_unit_rent_sheet.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';
import 'package:oasis_app/features/shortlets/services/shortlet_service.dart';
import 'package:oasis_app/features/shortlets/views/edit_nightly_price_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A price is the only thing on a listing a landlord changes because the
/// world changed rather than because they got it wrong. A flat sitting empty
/// for two months is usually a flat priced for a market that has moved, and
/// until these sheets existed the app had no answer to that at all: a unit's
/// rent was fixed at the moment it was typed.
///
/// Two things are worth pinning, and neither is about the arithmetic being
/// right. The first is that a monthly quote becomes the annual figure the
/// backend stores, because getting that wrong is a rent twelve times too
/// large on a public listing. The second is that a price-only edit leaves
/// everything else alone: the short-let save endpoint *replaces* a listing,
/// so a field this sheet forgets to carry through is a house rule silently
/// deleted or a blocked calendar wiped.
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

  UnitModel unit({String rent = '1200000.00', bool occupied = false}) =>
      UnitModel(
        id: 'unit-1',
        unitNumber: 'A1',
        bedrooms: 2,
        bathrooms: 1,
        rentAmount: rent,
        isOccupied: occupied,
        createdAt: '2026-01-01',
      );

  group("a unit's rent", () {
    testWidgets('a monthly quote is saved as the year it comes to', (
      tester,
    ) async {
      Map<String, dynamic>? sentBody;
      String? sentPath;
      String? sentMethod;

      final controller = LandlordController(
        propertyService: PropertyService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method == 'PATCH') {
                sentMethod = request.method;
                sentPath = request.url.path;
                sentBody = jsonDecode(request.body) as Map<String, dynamic>;
                return _json({
                  'id': 'unit-1',
                  'unit_number': 'A1',
                  'rent_amount': '3000000.00',
                });
              }
              // The property refetch that follows the save.
              return _json({'id': 'property-1', 'units': <dynamic>[]});
            }),
          ),
        ),
      );

      await tester.pumpWidget(
        _host(controller, (context) async {
          await openEditUnitRentSheet(
            context,
            unit: unit(),
            propertyId: 'property-1',
          );
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // ₦250,000 a month.
      await tester.enterText(find.byType(TextField), '250000');
      await tester.pump();
      // Open the interval dropdown, then pick the month.
      await tester.tap(find.text('/year').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('/month').last);
      await tester.pumpAndSettle();

      // Said out loud before it is saved. A landlord who types a monthly
      // figure is owed the multiplication in front of them.
      expect(find.textContaining('Saved as'), findsOneWidget);
      expect(find.textContaining('3,000,000'), findsOneWidget);

      await tester.tap(find.text('Save new rent'));
      await tester.pumpAndSettle();
      // Lets the success toast retire; it holds a timer the test would
      // otherwise fail on.
      await tester.pump(const Duration(seconds: 4));

      expect(sentMethod, 'PATCH');
      expect(sentPath, '/api/users/units/unit-1/');
      // Rent alone. A mis-wired call must not be able to rewrite the unit
      // number or the room count while it is in there.
      expect(sentBody, {'rent_amount': '3000000.00'});
    });

    testWidgets('a sitting tenant is not repriced by it', (tester) async {
      final controller = LandlordController(
        propertyService: PropertyService(
          apiClient: ApiClient(client: MockClient((_) async => _json({}))),
        ),
      );

      await tester.pumpWidget(
        _host(controller, (context) async {
          await openEditUnitRentSheet(
            context,
            unit: unit(occupied: true),
            propertyId: 'property-1',
          );
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The one thing a landlord must not misread on this screen. A signed
      // tenancy is a contract at an agreed price; this field is what the
      // *next* tenant is quoted.
      expect(find.textContaining('Someone is living here'), findsOneWidget);
      expect(find.textContaining('keeps the rent they agreed'), findsOneWidget);
    });

    testWidgets('a server without the endpoint says so in plain words', (
      tester,
    ) async {
      final controller = LandlordController(
        propertyService: PropertyService(
          apiClient: ApiClient(
            client: MockClient(
              // What a Django deployment that has not shipped the route
              // actually answers with.
              (_) async => _json({'detail': 'Not found.'}, status: 404),
            ),
          ),
        ),
      );

      final saved = await controller.updateUnitRent(
        propertyId: 'property-1',
        unitId: 'unit-1',
        rentAmount: '1350000.00',
      );

      expect(saved, isFalse);
      // "Not found." shown as written reads to a landlord as their flat
      // having vanished. What is actually true is that nothing happened.
      expect(controller.errorMessage, isNot(contains('Not found')));
      expect(controller.errorMessage, contains('cannot change a rent yet'));
      expect(controller.errorMessage, contains('unchanged'));
    });

    testWidgets('a real rejection is shown as the backend sent it', (
      tester,
    ) async {
      // The other half of the rule: once the endpoint exists, its opinion
      // about the rent is the useful thing and must not be swallowed.
      final controller = LandlordController(
        propertyService: PropertyService(
          apiClient: ApiClient(
            client: MockClient(
              (_) async => _json({
                'errors': {
                  'rent_amount': ['Rent cannot be lower than ₦50,000.'],
                },
              }, status: 400),
            ),
          ),
        ),
      );

      await controller.updateUnitRent(
        propertyId: 'property-1',
        unitId: 'unit-1',
        rentAmount: '100.00',
      );

      expect(controller.errorMessage, contains('cannot be lower'));
    });

    testWidgets('saving is refused until the number actually moves', (
      tester,
    ) async {
      final controller = LandlordController(
        propertyService: PropertyService(
          apiClient: ApiClient(client: MockClient((_) async => _json({}))),
        ),
      );

      await tester.pumpWidget(
        _host(controller, (context) async {
          await openEditUnitRentSheet(
            context,
            unit: unit(),
            propertyId: 'property-1',
          );
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Seeded with the rent as it stands, so the button starts disabled:
      // a save that changes nothing would spend a request to announce it.
      OasisPressable pressable() => tester.widget<OasisPressable>(
        find
            .ancestor(
              of: find.text('Save new rent'),
              matching: find.byType(OasisPressable),
            )
            .first,
      );
      expect(pressable().onTap, isNull);

      // And it wakes up the moment the number actually moves.
      await tester.enterText(find.byType(TextField).first, '1350000');
      await tester.pump();
      expect(pressable().onTap, isNotNull);
    });
  });

  group("a stay's nightly price", () {
    const listingJson = {
      'id': 'listing-1',
      'unit': 'unit-9',
      'nightly_price': '50000.00',
      'caution_fee': '25000.00',
      'minimum_nights': 2,
      'maximum_guests': 4,
      'description': 'A quiet flat near the airport.',
      'cancellation_policy': 'MODERATE',
      'available_from': '2026-09-01',
      'available_to': '2026-12-31',
      'blocked_dates': ['2026-10-10'],
      'house_rules': 'No parties.',
      'check_in_notes': 'Code shared after payment.',
      'is_active': true,
    };

    testWidgets('changing it leaves the rest of the listing alone', (
      tester,
    ) async {
      Map<String, dynamic>? sentBody;
      String? sentPath;
      String? sentMethod;
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method == 'PATCH') {
                sentMethod = request.method;
                sentPath = request.url.path;
                sentBody = jsonDecode(request.body) as Map<String, dynamic>;
                return _json(listingJson, status: 200);
              }
              // The listings refetch the save triggers.
              return _json([listingJson]);
            }),
          ),
        ),
      );

      await tester.pumpWidget(
        _host(controller, (context) async {
          await openEditNightlyPriceSheet(
            context,
            listing: ShortLetListing.fromJson(listingJson),
          );
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '42000');
      await tester.pump();
      await tester.tap(find.text('Save new price'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));

      // An edit is a PATCH of the listing's own path. It used to be a second
      // POST to the collection, which the backend accepted as an edit; API
      // guide 18 refuses that with 409 LISTING_EXISTS, so sending an edit as
      // a create now fails outright.
      expect(sentMethod, 'PATCH');
      expect(sentPath, '/api/users/landlord/short-lets/listing-1/');
      // `unit` is not sent on an edit: the listing already knows its unit,
      // and the API offers no way to move one between units.
      expect(sentBody?.containsKey('unit'), isFalse);

      // The price moved.
      expect(sentBody?['nightly_price'], '42000.00');
      // Everything else came through untouched. The save endpoint replaces
      // the listing, so an omitted key here is a house rule deleted and a
      // blocked calendar wiped: by a sheet the host opened to change one
      // number.
      expect(sentBody?['caution_fee'], '25000.00');
      expect(sentBody?['minimum_nights'], 2);
      expect(sentBody?['maximum_guests'], 4);
      expect(sentBody?['description'], 'A quiet flat near the airport.');
      expect(sentBody?['cancellation_policy'], 'MODERATE');
      expect(sentBody?['available_from'], '2026-09-01');
      expect(sentBody?['available_to'], '2026-12-31');
      expect(sentBody?['blocked_dates'], ['2026-10-10']);
      expect(sentBody?['house_rules'], 'No parties.');
      expect(sentBody?['check_in_notes'], 'Code shared after payment.');
      expect(sentBody?['is_active'], true);
    });

    testWidgets('the deposit can be cleared, not only changed', (tester) async {
      Map<String, dynamic>? sentBody;
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method == 'PATCH') {
                sentBody = jsonDecode(request.body) as Map<String, dynamic>;
                return _json(listingJson, status: 200);
              }
              return _json([listingJson]);
            }),
          ),
        ),
      );

      await tester.pumpWidget(
        _host(controller, (context) async {
          await openEditNightlyPriceSheet(
            context,
            listing: ShortLetListing.fromJson(listingJson),
          );
        }),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Emptying the field is how a host drops a deposit. Sent as "0.00"
      // rather than omitted, because an omitted key would leave the old
      // deposit live and the host would never know.
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump();
      await tester.tap(find.text('Save new price'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));

      expect(sentBody?['caution_fee'], '0.00');
      expect(sentBody?['nightly_price'], '50000.00');
    });
  });
}

/// A screen with one button that runs [onOpen] with a live context.
///
/// The sheets under test are opened from a screen, and pumping them directly
/// would skip the route they actually live on, which is where the provider
/// lookup and the pop-with-a-result both happen.
Widget _host<T extends ChangeNotifier>(
  T controller,
  Future<void> Function(BuildContext context) onOpen,
) => ChangeNotifierProvider<T>.value(
  value: controller,
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onOpen(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
