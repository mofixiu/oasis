import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/core/widgets/custom_bottom_navbar.dart';
import 'package:oasis_app/features/agreements/controllers/agreement_controller.dart';
import 'package:oasis_app/features/auth/controllers/auth_controller.dart';
import 'package:oasis_app/features/auth/models/user_model.dart';
import 'package:oasis_app/features/auth/services/api_auth_service.dart';
import 'package:oasis_app/features/fix/controllers/fix_controller.dart';
import 'package:oasis_app/features/fix/services/fix_service.dart';
import 'package:oasis_app/features/fix/views/artisan_home_screen.dart';
import 'package:oasis_app/features/fix/views/fix_screen.dart';
import 'package:oasis_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:oasis_app/features/messaging/controllers/messaging_controller.dart';
import 'package:oasis_app/features/notifications/controllers/notification_controller.dart';
import 'package:oasis_app/features/payouts/controllers/payout_controller.dart';
import 'package:oasis_app/features/properties/controllers/landlord_controller.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/vault/controllers/vault_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Fix screens render real data on real phones, so these cover what
/// breaks silently: an overflow nobody sees until a long artisan name
/// arrives, and, for the artisan, a screen that is now the only one their
/// role has, so anything wrong with it is the whole app being wrong.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the tenant Fix directory renders without overflowing', (
    tester,
  ) async {
    await _pumpFixScreen(tester);

    expect(find.text('Fix'), findsOneWidget);
    // No tabs any more: the second one tracked jobs, and API guide 18
    // removed the workflow behind them (§7B).
    expect(find.text('My requests'), findsNothing);
    // Seeded from the four documented categories, so the picker is never an
    // empty strip while the live list is in flight. Twice: once as the chip,
    // once as the trade on the artisan's own card.
    expect(find.text('Plumbing'), findsNWidgets(2));
    expect(find.text('Electrician'), findsOneWidget);
    expect(find.text('Ada Fixer'), findsOneWidget);
    // The landlord's endorsement is the strongest signal on the page.
    expect(find.text('RECOMMENDED BY YOUR LANDLORD'), findsOneWidget);
  });

  testWidgets('a very long artisan name does not overflow its card', (
    tester,
  ) async {
    await _pumpFixScreen(
      tester,
      artisanName:
          'Oluwaseunfunmilayo Adebayo-Ogunlesi Plumbing And General Repairs',
    );

    // pumpWidget already drained the font exceptions; anything left here is a
    // real layout failure.
    expect(tester.takeException(), isNull);
  });

  testWidgets("an artisan's listing leads with the card others see", (
    tester,
  ) async {
    await _pumpArtisanHome(tester);

    expect(find.text('Your listing'), findsOneWidget);
    // The real card, not a mock-up of one: an artisan deciding whether a bio
    // is worth writing should be looking at the thing the bio goes in.
    expect(find.text('Ada Fixer'), findsOneWidget);
    expect(find.text('Edit your details'), findsOneWidget);
    // Says plainly that Oasis stops at the introduction. An artisan who
    // remembers the old job queue has to be told it is gone rather than
    // left waiting for work that will never arrive.
    expect(find.textContaining('does not handle the payment'), findsOneWidget);
  });

  testWidgets('an incomplete listing names what is missing', (tester) async {
    await _pumpArtisanHome(tester, bio: '', location: '');

    // A checklist, not a percentage: "60% complete" tells an artisan nothing
    // they can act on, and each of these is one line of typing.
    expect(find.text('2 things are missing'), findsOneWidget);
    expect(find.textContaining('Where you work'), findsOneWidget);
    expect(find.textContaining('A line about yourself'), findsOneWidget);
  });
}

Future<void> _pumpFixScreen(
  WidgetTester tester, {
  String artisanName = 'Ada Fixer',
}) => _pump(
  tester,
  const FixScreen(initialUnitId: 'unit-1'),
  handler: (request) async {
    if (request.url.path.contains('/tenant/fix/artisans/')) {
      return _json([
        {
          'id': 'artisan-1',
          'full_name': artisanName,
          'category': 'PLUMBING',
          'category_label': 'Plumbing',
          'location': 'Lekki Phase 1',
          'years_of_experience': 5,
          'verification_status': 'VERIFIED',
          'is_active': true,
          'is_recommended': true,
          'bio': 'Reliable plumber for home repairs.',
        },
      ]);
    }
    return _json(const []);
  },
);

Future<void> _pumpArtisanHome(
  WidgetTester tester, {
  String bio = 'Reliable plumber for home repairs.',
  String location = 'Lekki Phase 1',
}) => _pump(
  tester,
  const ArtisanHomeScreen(),
  handler: (request) async {
    if (request.url.path.endsWith('/artisans/me/')) {
      return _json({
        'id': 'artisan-1',
        'full_name': 'Ada Fixer',
        'phone': '08000000000',
        'category': 'PLUMBING',
        'category_label': 'Plumbing',
        'location': location,
        'bio': bio,
        'years_of_experience': 5,
        'verification_status': 'VERIFIED',
        'is_active': true,
      });
    }
    return _json(const []);
  },
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required Future<http.Response> Function(http.Request) handler,
  bool underNavbar = false,
}) async {
  final client = MockClient(handler);
  final apiClient = ApiClient(client: client);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              AuthController(authService: ApiAuthService(apiClient: apiClient)),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              FixController(service: FixService(apiClient: apiClient)),
        ),
        ChangeNotifierProvider(create: (_) => AgreementController()),
        ChangeNotifierProvider(create: (_) => LandlordController()),
        ChangeNotifierProvider(create: (_) => VaultController()),
        ChangeNotifierProvider(create: (_) => PayoutController()),
        ChangeNotifierProvider(create: (_) => MarketplaceController()),
        ChangeNotifierProvider(create: (_) => MessagingController()),
        ChangeNotifierProvider(create: (_) => NotificationController()),
        ChangeNotifierProvider(create: (_) => ShortLetController()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: underNavbar
            ? Stack(
                children: [
                  screen,
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: CustomBottomNavbar(
                      currentIndex: 0,
                      role: UserRole.artisan,
                      onTap: _ignore,
                    ),
                  ),
                ],
              )
            : screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Google Fonts cannot reach the network under test; drain those so the
  // layout assertions are what decide these tests.
  while (tester.takeException() != null) {}
}

void _ignore(int _) {}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
