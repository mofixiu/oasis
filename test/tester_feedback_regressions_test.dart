import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/core/utils/nigeria_locations.dart';
import 'package:landa_app/features/agreements/models/agreement_model.dart';
import 'package:landa_app/features/properties/models/property_model.dart';
import 'package:landa_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:landa_app/features/shortlets/services/shortlet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cover for the bugs a round of Android testers found, each pinned at the
/// layer it was actually wrong in.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(access: 'token', refresh: 'refresh');
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() => ApiConstants.baseUrl = originalBaseUrl);

  group('listing a unit for short stays', () {
    /// "It showed an error but it still listed."
    ///
    /// The save and the list refresh that follows it used to share one `try`,
    /// so a listing that was created perfectly well and then hit a failing
    /// `GET` came back as null — which the sheet reads as "it did not save".
    test('a failed refresh after a successful save is not an error', () async {
      var listCalls = 0;
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method == 'POST') {
                return _json(_listingJson, status: 201);
              }
              // The refetch. Down, slow, rate-limited: it does not matter
              // which, only that it must not undo the answer above.
              listCalls++;
              return _json({'detail': 'Service unavailable.'}, status: 503);
            }),
          ),
        ),
      );

      final saved = await controller.saveListing(
        unitId: 'unit-9',
        nightlyPrice: '42000.00',
        minimumNights: 1,
        maximumGuests: 2,
        availableFrom: '2026-09-01',
        availableTo: '2026-12-31',
      );

      expect(listCalls, 1, reason: 'the refresh was still attempted');
      expect(
        saved,
        isNotNull,
        reason: 'the listing exists on the backend, so the save succeeded',
      );
      expect(
        controller.hasError,
        isFalse,
        reason: 'a failed convenience refresh must not be reported as a '
            'failed save',
      );
      // The newly saved listing is patched in locally so the screen the host
      // lands on is not empty; the next auto-refresh reconciles it.
      expect(controller.listings.map((l) => l.id), contains('listing-1'));
    });

    test('a genuinely failed save is still an error', () async {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method == 'POST') {
                return _json({
                  'nightly_price': ['This field is required.'],
                }, status: 400);
              }
              return _json([]);
            }),
          ),
        ),
      );

      final saved = await controller.saveListing(
        unitId: 'unit-9',
        nightlyPrice: '0.00',
        minimumNights: 1,
        maximumGuests: 2,
        availableFrom: '2026-09-01',
        availableTo: '2026-12-31',
      );

      expect(saved, isNull);
      expect(controller.hasError, isTrue);
    });
  });

  group('moving into a yearly property', () {
    /// "I was able to enter the yearly property without paying the first
    /// rent." Enforcing it is a backend rule (occupancy is granted on
    /// approval, and execution needs only two signatures) — see
    /// `backend docs/backend_change_spec_v14.md` §2. What the app owes
    /// meanwhile is not *saying* the tenancy has started.
    TenancyAgreementModel agreement(Map<String, dynamic> extra) =>
        TenancyAgreementModel.fromJson({
          'id': 'agreement-1',
          'unit': 'unit-1',
          'unit_number': 'A1',
          'status': 'EXECUTED',
          'rent_amount': '450000.00',
          'start_date': '2026-09-01',
          'end_date': '2027-08-31',
          'pay_rent_unlocked': true,
          ...extra,
        });

    test('signed with rent due and nothing paid is not a live tenancy', () {
      final signed = agreement({
        'rent_payment': {'status': 'DUE', 'total_amount': '472500.00'},
      });
      expect(signed.awaitingFirstRent, isTrue);
    });

    test('rent in escrow starts the tenancy', () {
      final paid = agreement({
        'rent_payment': {'status': 'IN_ESCROW', 'total_amount': '472500.00'},
        'rent_schedule': {'plan': 'ANNUAL', 'instalments_paid': 1},
      });
      expect(paid.awaitingFirstRent, isFalse);
    });

    test('a tenancy imported with rent already collected is not accused', () {
      // The landlord moved an existing tenant across and took the rent
      // off-platform months ago. NOT_DUE is how the backend says so, and a
      // false positive here would tell a paid-up tenant they owe money.
      final imported = agreement({
        'rent_payment': {'status': 'NOT_DUE', 'total_amount': '472500.00'},
        'rent_schedule': {'plan': 'ANNUAL', 'next_due_date': '2027-08-31'},
      });
      expect(imported.awaitingFirstRent, isFalse);
    });

    test('a payload with no rent block says nothing either way', () {
      expect(agreement(const {}).awaitingFirstRent, isFalse);
    });

    test('an unsigned agreement is not the case this is for', () {
      final pending = agreement({
        'status': 'PENDING',
        'rent_payment': {'status': 'DUE'},
      });
      expect(pending.awaitingFirstRent, isFalse);
    });
  });

  group('a property keeps the photos it has', () {
    /// "They can see the property but they cant see any picture in it."
    ///
    /// `POST /properties/` answers with `photo_urls`, `cover_photo_url`,
    /// `photo_count`, `needs_photos` and `video_url`; `GET /properties/` is
    /// documented with `photo_urls` and none of the rest. So the list
    /// refresh that rebuilds the landlord's portfolio was overwriting a
    /// freshly created property with a thinner description of itself.
    PropertyModel created() => PropertyModel.fromJson(const {
      'id': 'property-1',
      'name': 'Sunset House',
      'address': '12 Listing Road',
      'city': 'Lekki',
      'state': 'Lagos',
      'latitude': '6.428055',
      'longitude': '3.421944',
      'photo_urls': ['https://example.test/front.jpg'],
      'cover_photo_url': 'https://example.test/front.jpg',
      'photo_count': 4,
      'needs_photos': false,
      'video_url': 'https://example.test/tour.mp4',
    });

    test('a thinner list payload does not blank them', () {
      final fromList = PropertyModel.fromJson(const {
        'id': 'property-1',
        'name': 'Sunset House',
        'address': '12 Listing Road',
        'city': 'Lekki',
        'state': 'Lagos',
        'photo_urls': <String>[],
        'verification_status': 'VERIFIED',
      });

      final merged = fromList.withMediaFrom(created());

      expect(merged.photoUrls, ['https://example.test/front.jpg']);
      expect(merged.coverPhotoUrl, 'https://example.test/front.jpg');
      expect(merged.videoUrl, 'https://example.test/tour.mp4');
      expect(merged.photoCount, 4);
      expect(merged.needsPhotos, isFalse);
      // Everything the list payload *does* own still wins.
      expect(merged.verificationStatus, 'VERIFIED');
    });

    test('a payload that carries photos replaces them', () {
      final withNewPhotos = PropertyModel.fromJson(const {
        'id': 'property-1',
        'name': 'Sunset House',
        'photo_urls': ['https://example.test/back.jpg'],
        'photo_count': 1,
      });

      final merged = withNewPhotos.withMediaFrom(created());

      // A refresh may add media and may never remove it — but a set it
      // genuinely carries is the newer truth.
      expect(merged.photoUrls, ['https://example.test/back.jpg']);
      expect(merged.photoCount, 1);
    });

    test('a unit keeps its walkthrough through a refresh', () {
      final known = UnitModel.fromJson(const {
        'id': 'unit-1',
        'unit_number': 'A1',
        'photo_urls': ['https://example.test/unit-front.jpg'],
        'video_url': 'https://example.test/unit-tour.mp4',
      });
      // What the marketplace and the batch-create response actually carry:
      // a count of pictures and no pictures.
      final fromList = UnitModel.fromJson(const {
        'id': 'unit-1',
        'unit_number': 'A1',
        'is_occupied': true,
        'photo_count': 2,
      });

      final merged = fromList.withMediaFrom(known);

      expect(merged.photoUrls, ['https://example.test/unit-front.jpg']);
      expect(merged.videoUrl, 'https://example.test/unit-tour.mp4');
      expect(merged.needsTourVideo, isFalse);
      expect(merged.isOccupied, isTrue);
    });

    test('the first time a property is seen there is nothing to merge', () {
      final fresh = created();
      expect(fresh.withMediaFrom(null).photoUrls, fresh.photoUrls);
    });
  });

  group('states and cities', () {
    /// Both sides of the marketplace filter compare strings, so the app
    /// needs one spelling of each place. The geocoder answers with the
    /// formal name and people type the short one.
    test('the FCT arrives as one name however it is spelled', () {
      for (final spelling in [
        'FCT',
        'F.C.T',
        'Federal Capital Territory',
        'Abuja',
        'abuja',
      ]) {
        expect(
          NigeriaLocations.canonicalState(spelling),
          'Abuja (FCT)',
          reason: 'from "$spelling"',
        );
      }
    });

    test('decoration and casing do not make a different state', () {
      expect(NigeriaLocations.canonicalState('lagos state'), 'Lagos');
      expect(NigeriaLocations.canonicalState('Akwa-Ibom'), 'Akwa Ibom');
      expect(NigeriaLocations.canonicalState('NASSARAWA'), 'Nasarawa');
    });

    test('a state we do not have is not guessed at', () {
      expect(NigeriaLocations.canonicalState('Wakanda'), isNull);
      expect(NigeriaLocations.canonicalState(''), isNull);
      expect(NigeriaLocations.canonicalState(null), isNull);
    });

    test('a city is only canonicalised inside its own state', () {
      expect(
        NigeriaLocations.canonicalCity(state: 'Lagos', city: 'lekki'),
        'Lekki',
      );
      // Lekki is not in Rivers, and answering with a near-miss would silently
      // move somebody's property.
      expect(
        NigeriaLocations.canonicalCity(state: 'Rivers', city: 'Lekki'),
        isNull,
      );
      expect(
        NigeriaLocations.canonicalCity(state: 'Rivers', city: 'Port Harcourt'),
        'Port Harcourt',
      );
    });

    test('every state carries at least one place to pick', () {
      for (final state in NigeriaLocations.states) {
        expect(
          NigeriaLocations.citiesIn(state),
          isNotEmpty,
          reason: '$state has no cities listed',
        );
      }
      // All 36 states plus the FCT.
      expect(NigeriaLocations.states, hasLength(37));
    });
  });
}

const Map<String, dynamic> _listingJson = {
  'id': 'listing-1',
  'unit': {'id': 'unit-9', 'unit_number': 'B2'},
  'nightly_price': '42000.00',
  'caution_fee': '25000.00',
  'minimum_nights': 1,
  'maximum_guests': 2,
  'is_active': true,
};

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
