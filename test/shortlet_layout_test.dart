import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/app_variant.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/core/widgets/custom_bottom_navbar.dart';
import 'package:oasis_app/features/auth/models/user_model.dart';
import 'package:oasis_app/core/widgets/oasis_sheet.dart';
import 'package:oasis_app/features/auth/controllers/auth_controller.dart';
import 'package:oasis_app/features/auth/services/api_auth_service.dart';
import 'package:oasis_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:oasis_app/features/messaging/controllers/messaging_controller.dart';
import 'package:oasis_app/features/notifications/controllers/notification_controller.dart';
import 'package:oasis_app/features/properties/controllers/landlord_controller.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/services/shortlet_service.dart';
import 'package:oasis_app/features/shortlets/views/create_shortlet_sheet.dart';
import 'package:oasis_app/features/shortlets/views/landlord_shortlets_screen.dart';
import 'package:oasis_app/features/shortlets/views/shortlet_browse_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bottom bar is an overlay in MainScaffold's Stack rather than a
/// Scaffold's own `bottomNavigationBar`, so nothing beneath it is inset
/// automatically. That has already put one button behind the bar where it
/// could not be tapped; these hold the clearance in place.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the List a place button sits clear of the bottom bar', (
    tester,
  ) async {
    await _pumpUnderNavbar(tester, const LandlordShortLetsScreen());

    final fab = tester.getRect(find.byType(FloatingActionButton));
    final bar = tester.getRect(find.byType(CustomBottomNavbar));

    expect(
      fab.bottom,
      lessThanOrEqualTo(bar.top),
      reason: 'the button overlaps the bar and cannot be tapped',
    );
  });

  testWidgets('the Stays list leaves room below it for the bar', (
    tester,
  ) async {
    // A list that stops at the screen edge leaves its last row permanently
    // under the bar, unreachable however far you scroll.
    await _pumpUnderNavbar(tester, const ShortLetBrowseScreen());

    final list = tester.widget<ListView>(find.byType(ListView));
    final bottom = list.padding!.resolve(TextDirection.ltr).bottom;

    expect(
      bottom,
      greaterThanOrEqualTo(CustomBottomNavbar.reservedHeight),
      reason: 'the last listing would sit under the bar',
    );
  });

  testWidgets('the listing sheet is capped, and yields to the keyboard', (
    tester,
  ) async {
    // iPhone SE: the tightest screen a fixed-height sheet has to survive.
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ShortLetController()),
          ChangeNotifierProvider(create: (_) => LandlordController()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => openCreateShortLetSheet(context),
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
    while (tester.takeException() != null) {}

    // Idle: the sheet leaves the top third of the screen alone, so its title
    // never lands under the status bar and the backdrop stays tappable.
    const screenHeight = 667.0;
    final sheet = tester.getRect(find.byType(OasisSheet));
    expect(
      tester
          .getRect(
            find.text(isOasisV2 ? 'List a place' : 'List for short stays'),
          )
          .top,
      greaterThan(screenHeight * 0.25),
      reason: 'the sheet has grown past its cap and reached the status bar',
    );
    expect(sheet.height, lessThanOrEqualTo(screenHeight * 0.7 + 1));

    // Keyboard up: the cap has to lift, or the footer's own keyboard padding
    // has nowhere to go and the sheet overflows.
    tester.view.viewInsets = const FakeViewPadding(bottom: 520);
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'the sheet overflows once the keyboard is up',
    );
  });
}

/// Composes a screen exactly as MainScaffold does: bar over screen, not
/// beside it, so the geometry under test is the geometry that ships.
Future<void> _pumpUnderNavbar(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(828, 1500);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final shortlets = ShortLetController(
    service: ShortLetService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'id': 'l1',
                'property_name': 'Sunset House',
                'unit_number': 'A1',
                'nightly_price': '50000.00',
                'minimum_nights': 2,
                'maximum_guests': 3,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    ),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: shortlets),
        ChangeNotifierProvider(
          create: (_) => AuthController(authService: ApiAuthService()),
        ),
        ChangeNotifierProvider(create: (_) => MarketplaceController()),
        ChangeNotifierProvider(create: (_) => NotificationController()),
        ChangeNotifierProvider(create: (_) => MessagingController()),
        ChangeNotifierProvider(create: (_) => LandlordController()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Stack(
          children: [
            screen,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomBottomNavbar(
                currentIndex: 2,
                role: UserRole.owner,
                onTap: (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Google Fonts cannot reach the network under test; drain those so the
  // layout assertions are what decide these tests.
  while (tester.takeException() != null) {}
}
