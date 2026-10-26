import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';
import 'package:oasis_app/features/shortlets/services/shortlet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A short let takes real money for a real trip, so these cover what would
/// actually cost someone: being charged twice, being told a stay is confirmed
/// when it is not, and a guest travelling to a place that was never booked.
void main() {
  /// The URL of the most recent browse request, captured so the query the
  /// app actually sends can be asserted on rather than assumed.
  Uri? lastBrowseUrl;

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

  test('a listing is created with the documented body', () async {
    Map<String, dynamic>? sentBody;
    String? sentPath;
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentPath = request.url.path;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'id': 'listing-1',
            'unit': 'UNIT_UUID',
            'nightly_price': '50000.00',
            'rental_plan': 'DAILY',
          }, status: 201);
        }),
      ),
    );

    await service.saveListing(
      unitId: 'UNIT_UUID',
      nightlyPrice: '50000.00',
      minimumNights: 2,
      maximumGuests: 3,
      description: 'A quiet two-bedroom flat near the airport.',
      availableFrom: '2026-09-01',
      availableTo: '2026-12-31',
      blockedDates: const ['2026-10-10'],
      houseRules: 'No parties.',
      checkInNotes: 'Code shared after payment.',
    );

    // A create is a POST to the collection and carries the unit.
    expect(sentPath, '/api/users/landlord/short-lets/');
    expect(sentBody, {
      'unit': 'UNIT_UUID',
      'nightly_price': '50000.00',
      'minimum_nights': 2,
      'maximum_guests': 3,
      // The host's write-up of the place. Sent on every save, so deleting it
      // clears the paragraph rather than leaving the old one live.
      'description': 'A quiet two-bedroom flat near the airport.',
      // Always sent, even at zero: it is how a host turns a deposit back off.
      'caution_fee': '0.00',
      // The optional host choice defaults to Flexible, but is still explicit
      // so editing a listing cannot leave old cancellation terms behind.
      'cancellation_policy': 'FLEXIBLE',
      'available_from': '2026-09-01',
      'available_to': '2026-12-31',
      'blocked_dates': ['2026-10-10'],
      'house_rules': 'No parties.',
      'check_in_notes': 'Code shared after payment.',
      'is_active': true,
      // Spec v18 details, sent with their defaults when the host set none.
      'amenities': <String>[],
      'best_for': <String>[],
      'check_in_time': '14:00',
      'check_out_time': '12:00',
      'smoking_allowed': false,
      'pets_allowed': false,
      'parties_allowed': false,
    });
  });

  test('a stay uses the nested unit cover photo and photo-object URLs', () {
    final listing = ShortLetListing.fromJson({
      'id': 'listing-1',
      'unit': {
        'id': 'unit-1',
        // A compact listing can send the selected cover without repeating
        // the complete photo collection.
        'cover_photo_url': '/media/unit_photos/cover.jpg',
        'photo_urls': [
          {'image_url': '/media/unit_photos/cover.jpg'},
          {'url': 'https://cdn.example.test/bedroom.jpg'},
        ],
      },
    });

    expect(
      listing.coverPhotoUrl,
      'https://api.example.test/media/unit_photos/cover.jpg',
    );
    expect(listing.photoUrls, [
      'https://api.example.test/media/unit_photos/cover.jpg',
      'https://cdn.example.test/bedroom.jpg',
    ]);
  });

  test('a host taking bookings any time sends explicit null dates', () async {
    // The window is optional in the UI and has to be optional on the wire.
    // Omitting the keys would leave a previously-set window in place on an
    // edit, so "any dates" is said rather than left unsaid.
    Map<String, dynamic>? sentBody;
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'id': 'listing-1'}, status: 201);
        }),
      ),
    );

    await service.saveListing(
      unitId: 'UNIT_UUID',
      nightlyPrice: '50000.00',
      minimumNights: 1,
      maximumGuests: 2,
      cautionFee: '25000.00',
    );

    expect(sentBody!.containsKey('available_from'), isTrue);
    expect(sentBody!['available_from'], isNull);
    expect(sentBody!['available_to'], isNull);
    expect(sentBody!['caution_fee'], '25000.00');
    expect(sentBody!['cancellation_policy'], 'FLEXIBLE');
  });

  test(
    'an open-ended listing retries once when the server demands dates',
    () async {
      // The window is optional in the app and meant to be optional in the API.
      // Until that ships, a host who chose "any dates" must still be able to
      // list, and must be told their listing now carries a bound they did not
      // pick. This is the workaround, and it deletes itself: the first attempt
      // succeeds the day the backend accepts null.
      final bodies = <Map<String, dynamic>>[];
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method == 'GET') return _json([]);
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              bodies.add(body);
              if (body['available_from'] == null) {
                return _json({
                  'available_from': ['This field may not be null.'],
                }, status: 400);
              }
              return _json({'id': 'listing-1'}, status: 201);
            }),
          ),
        ),
      );

      final listing = await controller.saveListing(
        unitId: 'UNIT_UUID',
        nightlyPrice: '45000.00',
        minimumNights: 1,
        maximumGuests: 2,
      );

      expect(listing, isNotNull);
      expect(bodies, hasLength(2));
      // Honest first.
      expect(bodies.first['available_from'], isNull);
      // Then the widest window the backend can be told about.
      expect(bodies.last['available_from'], isNotNull);
      expect(bodies.last['available_to'], isNotNull);
      // And the host is told, rather than left to wonder.
      expect(controller.windowWasWidened, isTrue);
    },
  );

  test('a host who chose dates keeps the rejection they were given', () async {
    // The workaround must never overwrite a window the host actually set.
    var attempts = 0;
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'GET') return _json([]);
            attempts++;
            return _json({
              'available_from': ['Must not be in the past.'],
            }, status: 400);
          }),
        ),
      ),
    );

    final listing = await controller.saveListing(
      unitId: 'UNIT_UUID',
      nightlyPrice: '45000.00',
      minimumNights: 1,
      maximumGuests: 2,
      availableFrom: '2020-01-01',
      availableTo: '2020-12-31',
    );

    expect(listing, isNull);
    expect(attempts, 1, reason: 'no silent retry over a deliberate choice');
    expect(controller.windowWasWidened, isFalse);
    expect(controller.hasError, isTrue);
  });

  test('a booking request sends the dates the guest picked', () async {
    Map<String, dynamic>? sentBody;
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'id': 'booking-1',
            'status': 'PENDING',
            'check_in': '2026-10-01',
            'check_out': '2026-10-03',
          }, status: 201);
        }),
      ),
    );

    final booking = await service.requestBooking(
      listingId: 'LISTING_UUID',
      checkIn: '2026-10-01',
      checkOut: '2026-10-03',
      guestCount: 2,
      message: 'Weekend stay.',
    );

    expect(sentBody, {
      'listing': 'LISTING_UUID',
      'check_in': '2026-10-01',
      'check_out': '2026-10-03',
      'guest_count': 2,
      'message': 'Weekend stay.',
    });
    // Requesting is not booking: it starts as pending and nothing is owed.
    expect(booking.status, ShortLetBookingStatus.pending);
    expect(booking.status.needsPayment, isFalse);
    expect(booking.nights, 2);
  });

  test('paying from the vault sends the PIN and an idempotency key', () async {
    Map<String, dynamic>? sentBody;
    String? sentKey;
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          sentKey = request.headers['Idempotency-Key'];
          return _json({'id': 'booking-1', 'status': 'PAID'});
        }),
      ),
    );

    await service.payForBooking(
      bookingId: 'booking-1',
      idempotencyKey: 'sl-1',
      fromVault: true,
      vaultPin: '1234',
    );

    expect(sentBody, {'source': 'VAULT', 'vault_pin': '1234'});
    expect(sentKey, 'sl-1');
  });

  test('a card payment never carries the vault PIN', () async {
    // The PIN guards money leaving the vault. Attaching it to a card charge
    // would put it on the wire for nothing.
    Map<String, dynamic>? sentBody;
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'id': 'booking-1', 'status': 'APPROVED'});
        }),
      ),
    );

    await service.payForBooking(
      bookingId: 'booking-1',
      idempotencyKey: 'sl-1',
      fromVault: false,
      vaultPin: '1234',
    );

    expect(sentBody, {'source': 'CARD'});
    expect(sentBody!.containsKey('vault_pin'), isFalse);
  });

  test('a retried payment reuses the same key', () async {
    // A tap that fails and is tried again is one charge, not two.
    final keys = <String>[];
    var shouldFail = true;
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            keys.add(request.headers['Idempotency-Key'] ?? '');
            if (shouldFail) {
              return _json({'detail': 'Upstream hiccup'}, status: 502);
            }
            return _json({'id': 'booking-1', 'status': 'PAID'});
          }),
        ),
      ),
    );

    expect(
      await controller.payForBooking(
        'booking-1',
        fromVault: true,
        vaultPin: '1234',
      ),
      isNull,
    );
    shouldFail = false;
    expect(
      await controller.payForBooking(
        'booking-1',
        fromVault: true,
        vaultPin: '1234',
      ),
      isNotNull,
    );

    expect(keys.length, 2);
    expect(
      keys.first,
      keys.last,
      reason: 'the retry is the same intent and must not charge twice',
    );
  });

  test('a fresh payment intent gets a new key', () async {
    final keys = <String>[];
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            keys.add(request.headers['Idempotency-Key'] ?? '');
            return _json({'id': 'booking-1', 'status': 'PAID'});
          }),
        ),
      ),
    );

    await controller.payForBooking('booking-1', fromVault: true, vaultPin: '1');
    controller.beginPaymentIntent('booking-1');
    await controller.payForBooking('booking-1', fromVault: true, vaultPin: '1');

    expect(keys.length, 2);
    expect(keys.first, isNot(keys.last));
  });

  test('a vault payment that did not settle is not reported as paid', () async {
    // There is no checkout to fall back on here: if the backend did not mark
    // it paid, the stay is not confirmed and the guest must not be told it is.
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({'id': 'booking-1', 'status': 'APPROVED'}),
          ),
        ),
      ),
    );

    final result = await controller.payForBooking(
      'booking-1',
      fromVault: true,
      vaultPin: '1234',
    );

    expect(result, isNull);
    expect(controller.errorMessage, contains('not confirmed'));
  });

  test('a short vault balance is told apart from any other refusal', () async {
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({
              'code': 'INSUFFICIENT_VAULT_BALANCE',
              'detail': 'Your vault balance does not cover this stay.',
              'shortfall': '25000.00',
            }, status: 400),
          ),
        ),
      ),
    );

    await controller.payForBooking(
      'booking-1',
      fromVault: true,
      vaultPin: '1234',
    );

    expect(controller.vaultBalanceFellShort, isTrue);
    expect(controller.vaultShortfall, '25000.00');
  });

  test('an unknown status never unlocks payment or confirms a stay', () {
    // Both would cost someone: one offers a charge that cannot succeed, the
    // other sends a guest to a place that was never booked.
    final unknown = ShortLetBookingStatus.fromString('SOMETHING_NEW');
    expect(unknown, ShortLetBookingStatus.unknown);
    expect(unknown.needsPayment, isFalse);
    expect(unknown.isPaid, isFalse);
    expect(unknown.needsLandlordDecision, isFalse);
    expect(unknown.isCancellableByTenant, isFalse);
  });

  test('a paid booking cannot be cancelled from the app', () {
    // V1 leaves paid cancellations to support, so the button must not appear.
    expect(ShortLetBookingStatus.paid.isCancellableByTenant, isFalse);
    expect(ShortLetBookingStatus.pending.isCancellableByTenant, isTrue);
    expect(ShortLetBookingStatus.approved.isCancellableByTenant, isTrue);
  });

  test('nights count sleeps, not calendar days touched', () {
    final booking = ShortLetBooking.fromJson({
      'id': 'b',
      'check_in': '2026-10-01',
      'check_out': '2026-10-03',
    });
    // 1–3 October is two nights, not three days.
    expect(booking.nights, 2);
  });

  test('availability excludes blocked nights but not the checkout day', () {
    final listing = ShortLetListing.fromJson({
      'id': 'l',
      'available_from': '2026-10-01',
      'available_to': '2026-10-31',
      'blocked_dates': ['2026-10-05'],
    });

    // Nobody sleeps there on the checkout day, so a stay ending on a blocked
    // date is still fine: blocking on it would refuse back-to-back stays.
    expect(
      listing.coversStay(DateTime(2026, 10, 3), DateTime(2026, 10, 5)),
      isTrue,
    );
    // A stay that sleeps through the blocked night is not.
    expect(
      listing.coversStay(DateTime(2026, 10, 4), DateTime(2026, 10, 7)),
      isFalse,
    );
    // Outside the host's window either way.
    expect(
      listing.coversStay(DateTime(2026, 11, 1), DateTime(2026, 11, 3)),
      isFalse,
    );
  });

  test('a listing with no is_active flag is treated as live', () {
    // Hiding a listing the backend is serving would quietly lose the host
    // bookings; the flag's absence is not evidence it is paused.
    final listing = ShortLetListing.fromJson({'id': 'l'});
    expect(listing.isActive, isTrue);
  });

  test('a booking with no quoted total is not shown as free', () {
    final booking = ShortLetBooking.fromJson({
      'id': 'b',
      'amount': '100000.00',
    });
    expect(booking.totalAmount, '100000.00');
  });

  test('the landlord and tenant routes are kept apart', () async {
    // The two roles see different things about the same booking, so a call
    // must never land on the other role's route.
    final paths = <String>[];
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return _json({'results': []});
        }),
      ),
    );

    await service.getLandlordListings();
    await service.getLandlordBookings();
    await service.browseListings();
    await service.getMyBookings();

    expect(paths, [
      '/api/users/landlord/short-lets/',
      '/api/users/landlord/short-let-bookings/',
      '/api/users/tenant/short-lets/',
      '/api/users/tenant/short-let-bookings/',
    ]);
  });

  test('approve, reject, cancel and verify hit their own paths', () async {
    final paths = <String>[];
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return _json({'id': 'booking-1', 'status': 'APPROVED'});
        }),
      ),
    );

    await service.approveBooking('booking-1');
    await service.rejectBooking('booking-1', reason: 'Already booked.');
    await service.cancelBooking('booking-1');
    await service.verifyPayment(paymentId: 'payment-1', reference: 'SL-REF');

    expect(paths, [
      '/api/users/landlord/short-let-bookings/booking-1/approve/',
      '/api/users/landlord/short-let-bookings/booking-1/reject/',
      '/api/users/tenant/short-let-bookings/booking-1/cancel/',
      '/api/users/tenant/short-let-payments/payment-1/verify/',
    ]);
  });

  test('verifying without a payment id never reports a stay as paid', () async {
    // A booking the backend has not attached a payment to has nothing to
    // verify. Calling anyway would either 404 or, worse, verify something else.
    var called = false;
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((_) async {
            called = true;
            return _json({'id': 'booking-1', 'status': 'PAID'});
          }),
        ),
      ),
    );

    expect(await controller.verifyPendingPayment(), isNull);
    expect(called, isFalse);
    expect(controller.errorMessage, isNotNull);
  });

  test('a dispute is keyed on the payment, not the booking', () async {
    // The backend holds the money against the payment, so that is what the
    // dispute route addresses.
    String? path;
    Map<String, dynamic>? body;
    final service = ShortLetService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          path = request.url.path;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'id': 'booking-1', 'status': 'DISPUTED'});
        }),
      ),
    );

    final booking = await service.disputePayment(
      paymentId: 'payment-1',
      reason: 'The unit was not accessible.',
    );

    expect(path, '/api/users/tenant/short-let-payments/payment-1/dispute/');
    expect(body, {'reason': 'The unit was not accessible.'});
    expect(booking.status, ShortLetBookingStatus.disputed);
  });

  test('a booking with no payment is never sent to dispute', () async {
    // Calling anyway would address someone else's payment or 404; either way
    // the guest would be told something untrue about their money.
    var called = false;
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((_) async {
            called = true;
            return _json({'id': 'booking-1', 'status': 'DISPUTED'});
          }),
        ),
      ),
    );

    final raised = await controller.disputeBooking(
      ShortLetBooking.fromJson({'id': 'booking-1', 'status': 'PAID'}),
    );

    expect(raised, isFalse);
    expect(called, isFalse);
    expect(controller.errorMessage, contains('nothing to dispute'));
  });

  test('a disputed stay is still paid for, and no longer disputable', () {
    // The guest went and the money moved; what a dispute changes is whether
    // the host receives it. Offering "report a problem" twice would be noise.
    const disputed = ShortLetBookingStatus.disputed;
    expect(disputed.isPaid, isTrue);
    expect(disputed.isDisputable, isFalse);
    expect(
      disputed.isClosed,
      isFalse,
      reason: 'someone is still working on it',
    );
    expect(ShortLetBookingStatus.paid.isDisputable, isTrue);
    // Nothing has been charged on these, so there is nothing to hold.
    expect(ShortLetBookingStatus.approved.isDisputable, isFalse);
    expect(ShortLetBookingStatus.cancelled.isDisputable, isFalse);
  });

  test('signing out forgets every booking and listing', () async {
    // These carry addresses, guest names and check-in codes. Left behind, the
    // next person to sign in on the phone would see them.
    final controller = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json([
              {'id': 'booking-1', 'status': 'PENDING'},
            ]),
          ),
        ),
      ),
    );

    await controller.loadMyBookings();
    expect(controller.bookings, isNotEmpty);

    controller.resetSessionState();
    expect(controller.bookings, isEmpty);
    expect(controller.listings, isEmpty);
    expect(controller.browseListings, isEmpty);
    expect(controller.pendingPayment, isNull);
  });

  group('the 2026-09-03 search update', () {
    test('a price range rides alongside the other browse params', () async {
      Uri? sentUri;
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            sentUri = request.url;
            return _json([]);
          }),
        ),
      );

      await service.browseListings(
        location: 'Lekki',
        minPrice: '30000',
        maxPrice: '100000',
      );

      // min_price/max_price, not min_rent/max_rent: short lets never had
      // rent params, but the name has to match the marketplace's for the
      // shared query-parameter contract to mean anything.
      expect(sentUri?.queryParameters['min_price'], '30000');
      expect(sentUri?.queryParameters['max_price'], '100000');
      expect(sentUri?.queryParameters['location'], 'Lekki');
    });

    test('an unset price range sends neither bound', () async {
      Uri? sentUri;
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            sentUri = request.url;
            return _json([]);
          }),
        ),
      );

      await service.browseListings(location: 'Lekki');

      expect(sentUri?.queryParameters.containsKey('min_price'), isFalse);
      expect(sentUri?.queryParameters.containsKey('max_price'), isFalse);
    });
  });

  group('the 2026-09-03 payout, cancellation and dispute update', () {
    test('a paid booking prefers host_* payout fields over landlord_*', () {
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'PAID',
        'host_payout': '95000.00',
        'host_payout_status': 'HELD',
        'host_payout_status_label': 'Scheduled for payout',
        'host_payout_status_description':
            'Payment received. Host payout will be released on the '
            'check-in date if no issue is reported.',
        'host_payout_release_at': '2026-10-01T11:00:00Z',
        // Present too, and must lose to the host_* fields above: these are
        // only read when host_* is absent.
        'landlord_payout': '1.00',
        'landlord_payout_status': 'RELEASED',
      });

      expect(booking.hostPayout, '95000.00');
      expect(booking.hostPayoutStatus, HostPayoutStatus.held);
      expect(booking.resolvedHostPayoutLabel, 'Scheduled for payout');
      expect(
        booking.resolvedHostPayoutDescription,
        contains('released on the'),
      );
    });

    test('landlord_* aliases still work when host_* is absent', () {
      // The backend dev's own words: "Temporary landlord_* aliases still
      // exist for compatibility." Some payload, somewhere, will only have
      // these.
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'PAID',
        'landlord_payout': '95000.00',
        'landlord_payout_status': 'HELD',
        'landlord_paid_at': null,
      });

      expect(booking.hostPayout, '95000.00');
      expect(booking.hostPayoutStatus, HostPayoutStatus.held);
    });

    test('a missing backend label falls back to a local guess', () {
      final booking = ShortLetBooking.fromJson(const {
        'id': 'b1',
        'status': 'PAID',
        'host_payout_status': 'BLOCKED',
        // No host_payout_status_label sent.
      });

      expect(booking.resolvedHostPayoutLabel, 'Payout paused');
    });

    test(
      'cancel-preview merges refund fields without touching identity',
      () async {
        const original = ShortLetBooking(
          id: 'b1',
          status: ShortLetBookingStatus.paid,
          totalAmount: '130000.00',
        );

        final merged = original.withCancelPreview(const {
          'accommodation_refund_amount': '80000.00',
          'platform_fee_refund_amount': '0.00',
          'caution_fee_refund_amount': '25000.00',
          'total_refund_amount': '105000.00',
          'cancellation_policy': 'MODERATE',
        });

        // The preview changed the numbers...
        expect(merged.totalRefundAmount, '105000.00');
        expect(merged.hasRefundQuote, isTrue);
        expect(merged.cancellationPolicy, ShortLetCancellationPolicy.moderate);
        // ...and left everything the preview did not mention alone.
        expect(merged.id, 'b1');
        expect(merged.status, ShortLetBookingStatus.paid);
        expect(merged.totalAmount, '130000.00');
      },
    );

    test('the tenant cancel-preview lookup hits the right endpoint', () async {
      String? path;
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            path = request.url.path;
            return _json({'total_refund_amount': '105000.00'});
          }),
        ),
      );

      final preview = await service.getCancelPreview('booking-1');

      expect(
        path,
        '/api/users/tenant/short-let-bookings/booking-1/cancel-preview/',
      );
      expect(preview['total_refund_amount'], '105000.00');
    });

    test('a host cancellation requires and sends a reason', () async {
      Map<String, dynamic>? sentBody;
      String? path;
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            path = request.url.path;
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'id': 'booking-1', 'status': 'CANCELLED'});
          }),
        ),
      );

      await service.cancelBookingAsHost(
        bookingId: 'booking-1',
        reason: 'Emergency maintenance.',
      );

      expect(path, '/api/users/landlord/short-let-bookings/booking-1/cancel/');
      expect(sentBody?['reason'], 'Emergency maintenance.');
    });

    test(
      'resolving a dispute hits the resolve endpoint, not dispute again',
      () async {
        String? path;
        final service = ShortLetService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              path = request.url.path;
              return _json({'id': 'booking-1', 'status': 'PAID'});
            }),
          ),
        );

        await service.resolveDispute(
          paymentId: 'payment-1',
          note: 'Fixed now.',
        );

        expect(
          path,
          '/api/users/tenant/short-let-payments/payment-1/resolve-dispute/',
        );
      },
    );

    test(
      'a caution claim defaults to the full amount when none is given',
      () async {
        Map<String, dynamic>? sentBody;
        final service = ShortLetService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              sentBody = jsonDecode(request.body) as Map<String, dynamic>;
              return _json({});
            }),
          ),
        );

        await service.openCautionClaim(
          bookingId: 'booking-1',
          reason: 'Broken lamp.',
        );

        // No claimed_amount key at all: the backend's own rule, from the API
        // guide, is that its absence means "claim the whole thing".
        expect(sentBody?.containsKey('claimed_amount'), isFalse);
        expect(sentBody?['reason'], 'Broken lamp.');
      },
    );

    test('a tenant counter-claim sends the response and the amount', () async {
      Map<String, dynamic>? sentBody;
      String? path;
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            path = request.url.path;
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({});
          }),
        ),
      );

      await service.respondToCautionClaim(
        claimId: 'claim-1',
        response: 'COUNTER',
        counterAmount: '5000.00',
        note: 'I agree to a smaller cleaning fee.',
      );

      expect(
        path,
        '/api/users/tenant/short-let-caution-claims/claim-1/respond/',
      );
      expect(sentBody?['response'], 'COUNTER');
      expect(sentBody?['counter_amount'], '5000.00');
    });

    test(
      'previewing a cancellation merges into the matching booking only',
      () async {
        final controller = ShortLetController(
          service: ShortLetService(
            apiClient: ApiClient(
              client: MockClient((request) async {
                if (request.method == 'GET' &&
                    request.url.path.contains('cancel-preview')) {
                  return _json({'total_refund_amount': '105000.00'});
                }
                return _json([
                  {
                    'id': 'booking-1',
                    'status': 'PAID',
                    'total_amount': '130000.00',
                  },
                  {
                    'id': 'booking-2',
                    'status': 'PAID',
                    'total_amount': '50000.00',
                  },
                ]);
              }),
            ),
          ),
        );
        await controller.loadMyBookings();

        final result = await controller.previewCancellation('booking-1');

        expect(result?.totalRefundAmount, '105000.00');
        final untouched = controller.bookings.firstWhere(
          (b) => b.id == 'booking-2',
        );
        expect(untouched.hasRefundQuote, isFalse);
        expect(controller.isPreviewingCancellation('booking-1'), isFalse);
      },
    );
  });

  group('listing a unit that is already listed', () {
    test('the unit a listing already exists on is found by id', () async {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient(
              (request) async => _json([
                {
                  'id': 'listing-1',
                  'unit': {'id': 'unit-1', 'unit_number': 'A1'},
                  'nightly_price': '50000.00',
                },
              ]),
            ),
          ),
        ),
      );

      await controller.loadLandlordListings();

      // What stops the same flat being listed twice. The backend keys a
      // listing to its unit and would silently edit the first one, replacing
      // a live price and calendar with whatever was in the new form.
      expect(controller.listingForUnit('unit-1')?.id, 'listing-1');
      expect(controller.listingForUnit('unit-2'), isNull);
      // An empty id is not a match against anything: a unit the payload did
      // not name must not be reported as already listed.
      expect(controller.listingForUnit(''), isNull);
    });
  });

  group('a booking request that clashes', () {
    test('a taken-dates refusal is rewritten in plain words', () async {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient(
              (request) async => _json({
                'check_in': ['These dates are already booked.'],
              }, status: 400),
            ),
          ),
        ),
      );

      final booking = await controller.requestBooking(
        listingId: 'listing-1',
        checkIn: '2026-10-01',
        checkOut: '2026-10-04',
        guestCount: 2,
      );

      expect(booking, isNull);
      // The field name and the backend's clipped sentence are what the guest
      // used to be shown. What they need is the next move.
      expect(controller.errorMessage, isNot(contains('check_in')));
      expect(controller.errorMessage, contains('already booked those nights'));
      expect(controller.errorMessage, contains('Pick different dates'));
    });

    test('every other refusal keeps the backend wording', () async {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient(
              (request) async => _json({
                'check_in': ['Check-in cannot be in the past.'],
              }, status: 400),
            ),
          ),
        ),
      );

      await controller.requestBooking(
        listingId: 'listing-1',
        checkIn: '2020-10-01',
        checkOut: '2020-10-04',
        guestCount: 2,
      );

      // A different problem with a different fix. Telling this guest to pick
      // other dates would be true but useless: they need to know the dates
      // they picked have already gone by.
      expect(controller.errorMessage, contains('cannot be in the past'));
    });
  });

  group('a stay listing describes itself', () {
    test('the description survives the round trip, unit copy included', () {
      final written = ShortLetListing.fromJson({
        'id': 'listing-1',
        'description': '  Quiet two-bedroom flat near the airport.  ',
      });
      expect(written.hasDescription, isTrue);
      expect(written.description, 'Quiet two-bedroom flat near the airport.');

      // A host who wrote the flat up when they added it should not have to
      // write it again to let it by the night.
      final fromUnit = ShortLetListing.fromJson({
        'id': 'listing-2',
        'unit': {'id': 'u1', 'description': 'Sea-facing studio.'},
      });
      expect(fromUnit.description, 'Sea-facing studio.');

      // Nothing written is not an empty paragraph to render.
      final blank = ShortLetListing.fromJson({'id': 'listing-3'});
      expect(blank.hasDescription, isFalse);
    });
  });

  group('filtering stays by bedrooms', () {
    ShortLetController buildController(List<Map<String, dynamic>> rows) =>
        ShortLetController(
          service: ShortLetService(
            apiClient: ApiClient(
              client: MockClient((request) async {
                lastBrowseUrl = request.url;
                return _json(rows);
              }),
            ),
          ),
        );

    test('the floor is sent to the backend and narrows the list', () async {
      final controller = buildController([
        {'id': 'a', 'bedrooms': 1},
        {'id': 'b', 'bedrooms': 2},
        {'id': 'c', 'bedrooms': 4},
      ]);

      await controller.setBedroomsFilter(2);

      // Sent as a floor, not an exact count: nobody who needs two bedrooms
      // rules out a four-bedroom flat.
      expect(lastBrowseUrl?.queryParameters['min_bedrooms'], '2');
      expect(controller.browseListings.map((l) => l.id), ['b', 'c']);
      expect(controller.hasBedroomsFilter, isTrue);
      expect(controller.isBrowseNarrowed, isTrue);
    });

    test('a backend with no bedroom counts is left alone', () async {
      // `min_bedrooms` is new (backend_change_spec_v11 §3). Against a
      // deployment that neither honours it nor sends `bedrooms`, every
      // listing parses to zero, and filtering on that would empty the list
      // rather than fail to narrow it, which is the worse of the two
      // failures: an empty list reads as "there is nowhere to stay".
      final controller = buildController([
        {'id': 'a'},
        {'id': 'b'},
      ]);

      await controller.setBedroomsFilter(3);

      expect(controller.browseListings, hasLength(2));
    });

    test('clearing the search drops the floor with everything else', () async {
      final controller = buildController([
        {'id': 'a', 'bedrooms': 3},
      ]);
      await controller.setBedroomsFilter(3);
      expect(controller.isBrowseNarrowed, isTrue);

      await controller.clearBrowseSearch();

      expect(controller.minBedrooms, isNull);
      expect(controller.isBrowseNarrowed, isFalse);
    });
  });

  group('creating versus editing a listing', () {
    test('an edit is a PATCH of the listing, not a second create', () async {
      // The two used to be one POST: the backend keyed a listing to its unit
      // and quietly treated a second post as an edit. API guide 18 ends that:
      // a second POST for a unit that already has a listing is refused
      // with 409, so an edit sent as a create now fails outright.
      String? sentPath;
      String? sentMethod;
      Map<String, dynamic>? sentBody;
      final service = ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            sentMethod = request.method;
            sentPath = request.url.path;
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({'id': 'listing-1', 'nightly_price': '60000.00'});
          }),
        ),
      );

      await service.saveListing(
        unitId: 'UNIT_UUID',
        listingId: 'listing-1',
        nightlyPrice: '60000.00',
        minimumNights: 2,
        maximumGuests: 3,
      );

      expect(sentMethod, 'PATCH');
      expect(sentPath, '/api/users/landlord/short-lets/listing-1/');
      // The listing already knows its unit, and there is no way to move one
      // between units: sending it would only invite a rejection.
      expect(sentBody?.containsKey('unit'), isFalse);
      expect(sentBody?['nightly_price'], '60000.00');
    });

    test('a duplicate create hands back the listing that exists', () async {
      // 409 LISTING_EXISTS carries a `listing_id`, which is the difference
      // between a dead end and a way forward: the host meant that unit to be
      // let by the night, and it is.
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient(
              (_) async => _json({
                'code': 'LISTING_EXISTS',
                'detail': 'This unit is already listed for short stays.',
                'listing_id': 'listing-7',
              }, status: 409),
            ),
          ),
        ),
      );

      final saved = await controller.saveListing(
        unitId: 'UNIT_UUID',
        nightlyPrice: '50000.00',
        minimumNights: 1,
        maximumGuests: 2,
      );

      expect(saved, isNull);
      expect(controller.existingListingId, 'listing-7');
      // The backend's own sentence is already worth reading, so it is shown
      // rather than replaced.
      expect(controller.errorMessage, contains('already listed'));
    });

    test('an ordinary failure is not mistaken for a duplicate', () async {
      final controller = ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient(
              (_) async => _json({
                'errors': {
                  'nightly_price': ['Enter a valid amount.'],
                },
              }, status: 400),
            ),
          ),
        ),
      );

      await controller.saveListing(
        unitId: 'UNIT_UUID',
        nightlyPrice: 'nonsense',
        minimumNights: 1,
        maximumGuests: 2,
      );

      // Offering to open a listing that does not exist would be worse than
      // the error itself.
      expect(controller.existingListingId, isNull);
      expect(controller.errorMessage, contains('valid amount'));
    });
  });
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
