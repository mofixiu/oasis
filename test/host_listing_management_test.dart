import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_details.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';
import 'package:oasis_app/features/shortlets/services/shortlet_service.dart';
import 'package:oasis_app/features/shortlets/views/edit_nightly_price_sheet.dart';
import 'package:oasis_app/features/shortlets/views/v2/v2_payout_setup_intro.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a host does to a place after listing it: change it, pause it, and
/// get paid for it. The save endpoint replaces the whole listing, so the
/// failure these guard against is a small edit quietly wiping the rest.
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

  const details = ShortLetDetails(
    placeType: ShortLetPlaceType.penthouse,
    amenities: {ShortLetAmenity.wifi, ShortLetAmenity.pool},
    bestFor: {ShortLetOccasion.birthday},
    checkInTime: '15:00',
    checkOutTime: '11:00',
    petsAllowed: true,
  );

  const listing = ShortLetListing(
    id: 'listing-1',
    unitId: 'unit-1',
    propertyName: 'The Lumière',
    nightlyPrice: '280000.00',
    cautionFee: '50000.00',
    minimumNights: 2,
    maximumGuests: 6,
    description: 'A penthouse with a pool.',
    blockedDates: ['2026-12-24'],
    houseRules: 'Quiet after 11pm.',
    checkInNotes: 'Gate code on arrival.',
    details: details,
  );

  /// A controller whose every request is recorded, answering each write
  /// with the listing and each read with a list holding it.
  ({ShortLetController controller, List<http.Request> requests}) recorder() {
    final requests = <http.Request>[];
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            requests.add(request);
            final body = {'id': 'listing-1', 'unit': 'unit-1'};
            return http.Response(
              jsonEncode(request.method == 'GET' ? [body] : body),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      ),
    );
    return (controller: controller, requests: requests);
  }

  Map<String, dynamic> firstWrite(List<http.Request> requests) =>
      jsonDecode(requests.firstWhere((r) => r.method == 'PATCH').body)
          as Map<String, dynamic>;

  test('pausing a place changes only is_active', () async {
    final (:controller, :requests) = recorder();

    final ok = await controller.setListingActive(listing, false);

    expect(ok, isTrue);
    final patch = requests.firstWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, '/api/users/landlord/short-lets/listing-1/');
    final body = firstWrite(requests);
    expect(body['is_active'], isFalse);
    // Everything else goes back exactly as it was.
    expect(body['nightly_price'], '280000.00');
    expect(body['caution_fee'], '50000.00');
    expect(body['minimum_nights'], 2);
    expect(body['house_rules'], 'Quiet after 11pm.');
    expect(body['check_in_notes'], 'Gate code on arrival.');
    expect(body['blocked_dates'], ['2026-12-24']);
    expect(body['property_type'], 'PENTHOUSE');
    expect(body['amenities'], unorderedEquals(['WIFI', 'POOL']));
    expect(body['best_for'], ['BIRTHDAY']);
    expect(body['check_in_time'], '15:00');
    expect(body['pets_allowed'], isTrue);
  });

  test('resuming a place sends is_active true', () async {
    final (:controller, :requests) = recorder();

    await controller.setListingActive(listing, true);

    expect(firstWrite(requests)['is_active'], isTrue);
  });

  testWidgets('changing only the price keeps the listing details', (
    tester,
  ) async {
    final (:controller, :requests) = recorder();
    await tester.pumpWidget(
      ChangeNotifierProvider<ShortLetController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      openEditNightlyPriceSheet(context, listing: listing),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '300000');
    await tester.pump();
    await tester.tap(find.text('Save new price'));
    await tester.pumpAndSettle();

    final body = firstWrite(requests);
    expect(body['nightly_price'], '300000.00');
    expect(body['property_type'], 'PENTHOUSE');
    expect(body['amenities'], unorderedEquals(['WIFI', 'POOL']));
    expect(body['best_for'], ['BIRTHDAY']);
    expect(body['pets_allowed'], isTrue);
    // Lets the success toast run out before the test ends.
    await tester.pump(const Duration(seconds: 6));
  });

  group('a listing knows its property', () {
    test('from property_id', () {
      final listing = ShortLetListing.fromJson({
        'id': 'l1',
        'property_id': 'p1',
      });
      expect(listing.propertyId, 'p1');
    });

    test('from a nested property', () {
      final listing = ShortLetListing.fromJson({
        'id': 'l1',
        'property': {'id': 'p2', 'name': 'Sunset House'},
      });
      expect(listing.propertyId, 'p2');
    });

    test('from a unit that names its property', () {
      final listing = ShortLetListing.fromJson({
        'id': 'l1',
        'unit': {'id': 'u1', 'property': 'p3'},
      });
      expect(listing.propertyId, 'p3');
    });

    test('empty when nothing says', () {
      expect(ShortLetListing.fromJson({'id': 'l1'}).propertyId, isEmpty);
    });
  });

  testWidgets('the payout intro explains the steps and offers both ways on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(828, 1792);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    var setUp = 0;
    var later = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: V2PayoutSetupIntro(
            onSetUp: () => setUp++,
            onLater: () => later++,
          ),
        ),
      ),
    );

    expect(find.text('Get paid for your stays'), findsOneWidget);
    for (final step in [
      '1. A guest books and pays',
      '2. Oasis holds the money',
      '3. Paid into your vault',
      '4. Withdraw to your bank',
    ]) {
      expect(find.text(step), findsOneWidget);
    }

    await tester.scrollUntilVisible(find.text('Not now'), 200);
    await tester.tap(find.text('Add bank account'));
    await tester.tap(find.text('Not now'));
    expect(setUp, 1);
    expect(later, 1);
  });
}
