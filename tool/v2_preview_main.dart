// Local design preview for the v2 short-stay app. Not shipped.
//
// Runs the v2 shell signed in as a sample guest, with every API call answered
// from the sample data below, so screens can be checked without a backend.
//
//   flutter run -t tool/v2_preview_main.dart \
//     --dart-define=APP_VARIANT=v2 \
//     --dart-define=PREVIEW_PHOTOS=/absolute/path/to/photos
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/core/theme/theme_controller.dart';
import 'package:oasis_app/core/widgets/v2_main_scaffold.dart';
import 'package:oasis_app/features/agreements/controllers/agreement_controller.dart';
import 'package:oasis_app/features/auth/controllers/auth_controller.dart';
import 'package:oasis_app/features/auth/models/user_model.dart';
import 'package:oasis_app/features/auth/services/mock_auth_service.dart';
import 'package:oasis_app/features/auth/views/sign_in_screen.dart';
import 'package:oasis_app/features/auth/views/sign_up_screen.dart';
import 'package:oasis_app/features/auth/views/welcome_screen.dart';
import 'package:oasis_app/features/fix/controllers/fix_controller.dart';
import 'package:oasis_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:oasis_app/features/messaging/controllers/messaging_controller.dart';
import 'package:oasis_app/features/messaging/models/conversation_models.dart';
import 'package:oasis_app/features/messaging/views/conversation_screen.dart';
import 'package:oasis_app/features/profile/views/v2_edit_profile_screen.dart';
import 'package:oasis_app/features/profile/views/v2_profile_screen.dart';
import 'package:oasis_app/features/support/views/v2_terms_screen.dart';
import 'package:oasis_app/features/support/views/v2_help_screen.dart';
import 'package:oasis_app/features/notifications/controllers/notification_controller.dart';
import 'package:oasis_app/features/payments/controllers/payment_controller.dart';
import 'package:oasis_app/features/payouts/controllers/payout_controller.dart';
import 'package:oasis_app/features/properties/controllers/landlord_controller.dart';
import 'package:oasis_app/features/reviews/controllers/review_controller.dart';
import 'package:oasis_app/features/shortlets/controllers/saved_shortlets_controller.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';
import 'package:oasis_app/features/shortlets/views/landlord_shortlets_screen.dart';
import 'package:oasis_app/features/shortlets/views/my_shortlet_bookings_screen.dart';
import 'package:oasis_app/features/shortlets/views/shortlet_browse_screen.dart';
import 'package:oasis_app/features/shortlets/views/shortlet_listing_screen.dart';
import 'package:oasis_app/features/shortlets/views/v2/v2_saved_screen.dart';
import 'package:oasis_app/features/shortlets/views/v2/v2_booking_details_screen.dart';
import 'package:oasis_app/features/vault/controllers/vault_controller.dart';
import 'package:provider/provider.dart';

const _photoDir = String.fromEnvironment('PREVIEW_PHOTOS');
const _photoHost = 'preview-photos.test';
const _darkMode = bool.fromEnvironment('PREVIEW_DARK');

String _photo(String name) => 'https://$_photoHost/hq/$name.jpg';

/// Which screen the preview opens on: write `welcome`, `signin`, `signup`,
/// `trips`, `claim`, `booking`, `search`, `listing`, `listing-new`, `chat`,
/// `profile`, `edit-profile`, `saved`, `help`, `terms`, `host`,
/// `host-stays`, `host-new` or `host-profile` into
/// `preview_start.txt`, then hot restart. `host…` signs in as a host instead
/// of a guest; `host-new` is one with nothing listed yet. Anything else, or
/// no file, opens the signed-in guest app.
String _readStartMode() {
  // The app's own temp folder first (`xcrun simctl get_app_container … data`,
  // then `tmp/preview_start.txt`), since a simulator cannot always read the
  // Mac's folders; then next to the photos.
  for (final path in [
    '${Directory.systemTemp.path}/preview_start.txt',
    '$_photoDir/start.txt',
  ]) {
    try {
      final file = File(path);
      if (file.existsSync()) return file.readAsStringSync().trim();
    } catch (e) {
      debugPrint('[PREVIEW] cannot read $path: $e');
    }
  }
  return '';
}

final String _startMode = () {
  final mode = _readStartMode();
  debugPrint('[PREVIEW] temp=${Directory.systemTemp.path} start="$mode"');
  return mode;
}();
bool get _asHost => _startMode.startsWith('host');

Widget _startScreen() {
  final start = _startMode;
  return switch (start) {
    'welcome' => const WelcomeScreen(),
    'signin' => const SignInScreen(),
    'signup' => const SignUpScreen(),
    // Single screens, for screenshots without navigating.
    'trips' => const MyShortLetBookingsScreen(isV2: true, isTabRoot: true),
    'claim' => V2BookingDetailsScreen(
      booking: ShortLetBooking.fromJson(
        _bookings().firstWhere((b) => b['caution_claim'] != null),
      ),
      onRespondToClaim: (_) async {},
    ),
    'host-stays' || 'host-new' => const LandlordShortLetsScreen(isV2: true),
    'help' => const V2HelpScreen(),
    'terms' => const V2TermsScreen(),
    'search' => const ShortLetBrowseScreen(isV2: true, isSearch: true),
    'listing' || 'listing-new' => ShortLetListingScreen(
      listing: ShortLetListing.fromJson(
        _listings.firstWhere(
          (l) => l['id'] == (start == 'listing' ? 'l-1' : 'l-new-1'),
        ),
      ),
      isV2: true,
    ),
    'booking' => V2BookingDetailsScreen(
      booking: ShortLetBooking.fromJson(_bookings().first),
    ),
    'chat' => ConversationScreen(
      conversation: Conversation.fromJson(_conversations().first),
    ),
    'profile' || 'host-profile' => const V2ProfileScreen(),
    'edit-profile' => const V2EditProfileScreen(),
    'saved' => const V2SavedScreen(),
    _ => const V2MainScaffold(),
  };
}

/// Reaches the real network. Only used to let the app's Google Fonts and map
/// tiles through. An `IOClient`, because `http.Client()` made inside the mocked zone
/// would be the mock again and call itself forever.
final http.Client _network = IOClient();

/// Bundled stand-ins when a preview photo is not on disk.
const _fallbackPhotos = [
  'assets/images/quality_hero.png',
  'assets/images/room_interior.png',
];

void main() {
  http.runWithClient(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>(create: (_) => _PreviewAuth()),
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => LandlordController()),
          ChangeNotifierProvider(create: (_) => AgreementController()),
          ChangeNotifierProvider(create: (_) => PaymentController()),
          ChangeNotifierProvider(create: (_) => NotificationController()),
          ChangeNotifierProvider(create: (_) => MarketplaceController()),
          ChangeNotifierProvider(create: (_) => PayoutController()),
          ChangeNotifierProvider(create: (_) => VaultController()),
          ChangeNotifierProvider(create: (_) => MessagingController()),
          ChangeNotifierProvider(create: (_) => ShortLetController()),
          ChangeNotifierProvider(create: (_) => SavedShortLetsController()),
          ChangeNotifierProvider(create: (_) => FixController()),
          ChangeNotifierProvider(create: (_) => ReviewController()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
          home: _startScreen(),
        ),
      ),
    );
  }, () => MockClient(_respond));
}

class _PreviewAuth extends AuthController {
  _PreviewAuth() : super(authService: MockAuthService());

  final _user = UserModel(
    id: _asHost ? 'host-1' : 'guest-1',
    email: _asHost ? 'tolu@example.test' : 'jemima@example.test',
    // Verified users get their name from the ID check.
    fullName: _asHost ? 'Tolu Adeyemi' : 'Jemima Daniels',
    phone: '+2348123456789',
    role: _asHost ? UserRole.owner : UserRole.tenant,
    verificationStatus: VerificationStatus.verified,
  );

  @override
  bool get isAuthenticated => true;

  @override
  UserModel? get currentUser => _user;

  @override
  UserRole get currentRole => _user.role;
}

Future<http.Response> _respond(http.Request request) async {
  final url = request.url;
  if (url.host == _photoHost) {
    final file = File('$_photoDir${url.path}');
    if (file.existsSync()) {
      return http.Response.bytes(
        await file.readAsBytes(),
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    }
    final asset =
        _fallbackPhotos[url.path.hashCode.abs() % _fallbackPhotos.length];
    final bytes = await rootBundle.load(asset);
    return http.Response.bytes(
      bytes.buffer.asUint8List(),
      200,
      headers: {'content-type': 'image/png'},
    );
  }
  if (url.host.contains('gstatic.com') || url.host.contains('googleapis.com')) {
    return _network.get(url);
  }
  // Map tiles and address lookups, so the pin map shows a real map. Their
  // own headers go along: OpenStreetMap refuses requests without the app's
  // user agent.
  if (url.host.endsWith('openstreetmap.org')) {
    return _network.get(url, headers: request.headers);
  }

  final path = url.path;
  if (path.contains('/saved-short-lets/')) {
    if (request.method == 'DELETE') return http.Response('', 204);
    if (request.method == 'POST') {
      return http.Response(
        jsonEncode({'listing_id': jsonDecode(request.body)['listing_id']}),
        201,
        headers: {'content-type': 'application/json'},
      );
    }
  }
  Object body = const [];
  if (path.endsWith('/tenant/saved-short-lets/')) {
    body = [
      for (final listing in _listings.take(2))
        {...listing, 'is_saved': true, 'saved_at': _at(60 * 24)},
    ];
  } else if (path.endsWith('/host/listings/')) {
    // The normal listing, with property and unit nested, and no photos yet.
    final sent = jsonDecode(request.body) as Map<String, dynamic>;
    return http.Response(
      jsonEncode({
        'id': 'l-new',
        'property': {
          'id': 'p-new',
          'name': sent['property_name'],
          'city': sent['city'],
          'state': sent['state'],
          'verification_status': 'PENDING_REVIEW',
        },
        'unit': {
          'id': 'u-new',
          'unit_number': sent['unit_number'],
          'bedrooms': sent['bedrooms'],
          'bathrooms': sent['bathrooms'],
        },
        'property_name': sent['property_name'],
        'city': sent['city'],
        'state': sent['state'],
        'nightly_price': sent['nightly_price'],
        'is_active': true,
        'photo_urls': <String>[],
        'cover_photo_url': null,
      }),
      201,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  } else if (_startMode == 'host-new' &&
      (path.endsWith('/landlord/short-lets/') ||
          path.endsWith('/landlord/short-let-bookings/'))) {
    // A host who has not listed anything yet.
    body = const [];
  } else if (path.endsWith('/tenant/short-lets/') ||
      path.endsWith('/landlord/short-lets/')) {
    body = _listings;
  } else if (path.endsWith('/tenant/short-let-bookings/')) {
    body = _bookings();
  } else if (path.endsWith('/landlord/short-let-bookings/')) {
    body = _hostBookings();
  } else if (path.endsWith('/unread-count/')) {
    body = {'unread_count': path.contains('notifications') ? 2 : 1};
  } else if (path.contains('/conversations/') && path.endsWith('/messages/')) {
    body = request.method == 'POST'
        ? _message(
            'm-new',
            jsonDecode(request.body)['body'] as String,
            'TENANT',
            0,
          )
        : _messages();
  } else if (path.endsWith('/conversations/')) {
    body = _conversations();
  } else if (path.endsWith('/vault/')) {
    body = {
      'id': 'vault-1',
      'currency': 'NGN',
      'available_balance': '250000.00',
      'pending_withdrawal_balance': '0.00',
      'total_credited': '1140000.00',
      'total_withdrawn': '0.00',
      'total_spent': '890000.00',
      'updated_at': _at(60),
    };
  } else if (path.endsWith('/vault/transactions/')) {
    body = {
      'results': [
        _txn('t-1', 'CREDIT', '150000.00', 'Added from card', 60 * 5),
        _txn('t-2', 'DEBIT', '890000.00', 'Paid for The Lumière', 60 * 30),
        _txn('t-3', 'CREDIT', '500000.00', 'Added from card', 60 * 50),
        _txn('t-4', 'CREDIT', '490000.00', 'Added from card', 60 * 24 * 9),
      ],
    };
  } else if (path.endsWith('/vault/pin/')) {
    body = {'is_set': true};
  } else if (path.endsWith('/notifications/')) {
    body = [
      {
        'id': 'n-1',
        'notification_type': 'VAULT_TOPUP_SUCCEEDED',
        'title': 'Money added to your vault',
        'message': '₦150,000 is now in your vault.',
        'is_read': false,
        'created_at': _at(60 * 5),
      },
      {
        'id': 'n-2',
        'notification_type': 'SHORT_LET_MESSAGE_RECEIVED',
        'title': 'New message from Tolu',
        'message': 'Yes, it’s possible depending on availability.',
        'is_read': false,
        'created_at': _at(25),
      },
      {
        'id': 'n-3',
        'notification_type': 'SHORT_LET_PAYMENT_RECORDED',
        'title': 'Booking confirmed',
        'data': {},
        'message': 'Your payment for The Lumière went through.',
        'is_read': true,
        'created_at': _at(60 * 30),
      },
    ];
  } else if (path.endsWith('/app-config/')) {
    // As staging serves it today: every value still waiting on the business.
    body = {
      'support_email': '',
      'support_phone': '',
      'support_whatsapp': '',
      'support_hours': '',
      'terms_url': '',
      'privacy_url': '',
    };
  } else if (path.endsWith('/support/tickets/')) {
    body = {'id': 't-1', 'reference': 'OAS-1042'};
  } else if (path.endsWith('/block/')) {
    body = {'status': 'CLOSED'};
  }
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, Object?> _listing({
  required String id,
  required String name,
  required String city,
  required String price,
  required List<String> photos,
  double? rating,
  int reviews = 0,
  int bedrooms = 2,
  int guests = 4,
}) => {
  'id': id,
  'unit': 'u-$id',
  'property_name': name,
  'unit_number': '',
  'city': city,
  'state': 'Lagos',
  'address': '12 Admiralty Way, $city, Lagos',
  'nightly_price': price,
  'caution_fee': '50000.00',
  'cancellation_policy': 'MODERATE',
  'minimum_nights': 1,
  'maximum_guests': guests,
  'description':
      'A stylish, modern apartment in the heart of $city, perfect for '
      'birthdays, staycations and good company. Spacious rooms, a private '
      'pool and a beautiful city view.',
  'average_rating': rating,
  'review_count': reviews,
  'bedrooms': bedrooms,
  'bathrooms': bedrooms,
  'house_rules': 'No smoking indoors. Quiet hours after 11pm.',
  'is_active': true,
  'photo_urls': photos.map(_photo).toList(),
  'cover_photo_url': photos.isEmpty ? null : _photo(photos.first),
  'created_at': '2026-09-01T10:00:00Z',
};

final _listings = [
  // Just listed: live before its photos, as the backend allows today.
  _listing(
    id: 'l-new-1',
    name: 'Palm Court Studio',
    city: 'Yaba',
    price: '45000.00',
    photos: const [],
    bedrooms: 1,
    guests: 2,
  ),
  _listing(
    id: 'l-1',
    name: 'The Lumière',
    city: 'Lekki',
    price: '280000.00',
    photos: ['lumiere', 'horizon', 'maison'],
    rating: 4.8,
    reviews: 32,
    bedrooms: 3,
    guests: 6,
  ),
  _listing(
    id: 'l-2',
    name: 'The Palms',
    city: 'Victoria Island',
    price: '320000.00',
    photos: ['pool', 'hero'],
    rating: 4.9,
    reviews: 28,
  ),
  _listing(
    id: 'l-3',
    name: 'The Solace Apartment',
    city: 'Lekki',
    price: '180000.00',
    photos: ['solace', 'maison'],
    rating: 4.7,
    reviews: 120,
  ),
  _listing(
    id: 'l-4',
    name: 'Elysian Loft',
    city: 'Ikoyi',
    price: '250000.00',
    photos: ['elysian', 'birthday'],
  ),
];

String _day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

List<Map<String, Object?>> _bookings() => [
  {
    'id': 'b-7f3a91c2',
    'listing': 'l-1',
    'property_name': 'The Lumière',
    'address': '12 Admiralty Way, Lekki, Lagos',
    'check_in': _day(56),
    'check_out': _day(59),
    'guest_count': 2,
    'status': 'PAID',
    'amount': '840000.00',
    'caution_fee': '50000.00',
    'caution_fee_escrow_status': 'IN_ESCROW',
    'total_amount': '890000.00',
    'cancellation_policy': 'MODERATE',
    'check_in_notes': 'Gate code 4417. Concierge holds the key after 2pm.',
  },
  {
    'id': 'b-2c81d044',
    'listing': 'l-2',
    'property_name': 'The Palms',
    'address': '4 Ozumba Mbadiwe, Victoria Island, Lagos',
    'check_in': _day(95),
    'check_out': _day(97),
    'guest_count': 4,
    'status': 'APPROVED',
    'amount': '640000.00',
    'total_amount': '640000.00',
    'cancellation_policy': 'FLEXIBLE',
    'payment_deadline': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 5))
        .toIso8601String(),
  },
  {
    'id': 'b-9e00ab17',
    'listing': 'l-3',
    'property_name': 'The Solace Apartment',
    'address': 'Lekki Phase 1, Lagos',
    'check_in': _day(-30),
    'check_out': _day(-27),
    'guest_count': 2,
    'status': 'COMPLETED',
    'amount': '540000.00',
    'caution_fee': '50000.00',
    'caution_fee_escrow_status': 'REFUNDED',
    'caution_fee_refunded_at': _at(60 * 24 * 26),
    'total_amount': '590000.00',
    'cancellation_policy': 'STRICT',
  },
  {
    'id': 'b-4d21e7aa',
    'listing': 'l-4',
    'property_name': 'Elysian Loft',
    'address': 'Ikoyi, Lagos',
    'check_in': _day(-3),
    'check_out': _day(-1),
    'guest_count': 2,
    'status': 'CHECKED_OUT',
    'amount': '500000.00',
    'caution_fee': '50000.00',
    'caution_fee_escrow_status': 'IN_ESCROW',
    'caution_fee_release_ready_at': _inMinutes(60 * 9),
    'total_amount': '550000.00',
    'cancellation_policy': 'FLEXIBLE',
    'caution_claim': {
      'id': 'cl-1',
      'status': 'OPEN',
      'claimed_amount': '15000.00',
      'reason': 'Wine stain on the living room rug.',
      'created_at': _at(90),
    },
  },
  {
    'id': 'b-55aa0f31',
    'listing': 'l-4',
    'property_name': 'Elysian Loft',
    'address': 'Ikoyi, Lagos',
    'check_in': _day(-60),
    'check_out': _day(-58),
    'guest_count': 3,
    'status': 'CANCELLED',
    'amount': '500000.00',
    'total_amount': '500000.00',
    'cancellation_policy': 'FLEXIBLE',
  },
];

String _inMinutes(int minutes) =>
    DateTime.now().toUtc().add(Duration(minutes: minutes)).toIso8601String();

/// The host's side: one checkout to inspect, one claim already sent, one new
/// request.
List<Map<String, Object?>> _hostBookings() => [
  {
    'id': 'h-1',
    'listing': 'l-1',
    'property_name': 'The Lumière',
    'check_in': _day(-2),
    'check_out': _day(0),
    'guest_count': 2,
    'guest_name': 'Jemima D.',
    'status': 'CHECKED_OUT',
    'amount': '560000.00',
    'host_payout': '532000.00',
    // Held until a day after checkout (API guide 20), like the caution fee.
    'host_payout_status': 'HELD',
    'host_payout_release_at': _inMinutes(60 * 18 + 20),
    'caution_fee': '50000.00',
    'caution_fee_escrow_status': 'IN_ESCROW',
    'caution_fee_release_ready_at': _inMinutes(60 * 18 + 20),
    'total_amount': '610000.00',
    'cancellation_policy': 'MODERATE',
  },
  {
    'id': 'h-2',
    'listing': 'l-4',
    'property_name': 'Elysian Loft',
    'check_in': _day(-3),
    'check_out': _day(-1),
    'guest_count': 2,
    'guest_name': 'Ada O.',
    'status': 'CHECKED_OUT',
    'amount': '500000.00',
    'host_payout': '475000.00',
    'host_payout_status': 'HELD',
    'host_payout_release_at': _inMinutes(60 * 9),
    'caution_fee': '50000.00',
    'caution_fee_escrow_status': 'IN_ESCROW',
    'caution_fee_release_ready_at': _inMinutes(60 * 9),
    'total_amount': '550000.00',
    'cancellation_policy': 'FLEXIBLE',
    'caution_claim': {
      'id': 'cl-1',
      'status': 'OPEN',
      'claimed_amount': '15000.00',
      'reason': 'Wine stain on the living room rug.',
    },
  },
  {
    'id': 'h-3',
    'listing': 'l-2',
    'property_name': 'The Palms',
    'check_in': _day(20),
    'check_out': _day(22),
    'guest_count': 4,
    'guest_name': 'Kunle B.',
    'message': 'Celebrating a birthday with three friends.',
    'status': 'PENDING',
    'amount': '640000.00',
    'total_amount': '640000.00',
    'cancellation_policy': 'FLEXIBLE',
  },
];

String _at(int minutesAgo) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutesAgo))
    .toIso8601String();

Map<String, Object?> _txn(
  String id,
  String type,
  String amount,
  String description,
  int minutesAgo,
) => {
  'id': id,
  'transaction_type': type,
  'amount': amount,
  'balance_after': '250000.00',
  'description': description,
  'created_at': _at(minutesAgo),
};

Map<String, Object?> _message(
  String id,
  String body,
  String role,
  int minutesAgo,
) => {
  'id': id,
  'body': body,
  'sender_role': role,
  'sender_name': role == 'OWNER' ? 'Tolu' : 'Jemima',
  'created_at': _at(minutesAgo),
  'read_at': _at(minutesAgo - 1),
};

List<Map<String, Object?>> _messages() => [
  _message(
    'm-1',
    'Hi Jemima! Your booking is confirmed. Let me know if you have any '
        'questions before your arrival.',
    'OWNER',
    60 * 26,
  ),
  _message(
    'm-2',
    'Hi! Thank you. What time is check-in?',
    'TENANT',
    60 * 26 - 2,
  ),
  _message(
    'm-3',
    'Check-in is from 2:00 PM. We’ll send you the access details a few hours '
        'before arrival.',
    'OWNER',
    35,
  ),
  _message(
    'm-4',
    'Okay perfect. Is early check-in available if we get there earlier?',
    'TENANT',
    30,
  ),
  _message(
    'm-5',
    'Yes, it’s possible depending on availability. I’ll confirm on the day '
        'and let you know.',
    'OWNER',
    25,
  ),
];

Map<String, Object?> _conversation(
  String id,
  String property,
  String photo,
  String host,
  String last,
  int minutesAgo,
  int unread,
) => {
  'id': id,
  'status': 'OPEN',
  'context_type': 'SHORT_LET',
  'context_id': switch (id) {
    'c-1' => 'b-7f3a91c2',
    // Approved and not paid yet, so the host's number is still blank.
    'c-4' => 'b-2c81d044',
    _ => 'b-$id',
  },
  'property': {
    'id': 'p-$id',
    'name': property,
    'cover_photo_url': _photo(photo),
  },
  'counterparty': {
    'id': 'u-$id',
    'full_name': host,
    'role': 'OWNER',
    'verification_status': 'VERIFIED',
    if (id == 'c-1') 'phone': '+2348011112222',
  },
  'last_message': _message('last-$id', last, 'OWNER', minutesAgo),
  'unread_count': unread,
  'created_at': _at(minutesAgo + 100),
};

List<Map<String, Object?>> _conversations() => [
  _conversation(
    'c-1',
    'The Lumière',
    'lumiere',
    'Tolu Adeyemi',
    'Yes, it’s possible depending on availability.',
    25,
    1,
  ),
  _conversation(
    'c-4',
    'The Palms',
    'palms',
    'Femi Ajayi',
    'Approved! Pay when you’re ready and I’ll send the details.',
    50,
    1,
  ),
  _conversation(
    'c-2',
    'The Solace Apartment',
    'solace',
    'Ada Okafor',
    'Thank you for staying with us! We’d love a review.',
    60 * 27,
    0,
  ),
  _conversation(
    'c-3',
    'Elysian Loft',
    'elysian',
    'Kunle Bello',
    'No problem! See you then.',
    60 * 24 * 9,
    0,
  ),
];
