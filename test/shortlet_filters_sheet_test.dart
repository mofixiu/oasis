import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/features/auth/controllers/auth_controller.dart';
import 'package:oasis_app/features/auth/services/api_auth_service.dart';
import 'package:oasis_app/features/shortlets/controllers/saved_shortlets_controller.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/services/shortlet_service.dart';
import 'package:oasis_app/features/shortlets/views/shortlet_browse_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The guest Filters sheet now holds occasions, place types, amenities and
/// house rules as well as dates, price and bedrooms (API guide 22). It has
/// to fit a small phone and send what the guest picks.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every filter group fits on a small phone and is sent', (
    tester,
  ) async {
    // iPhone SE: the smallest screen the app supports.
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    Uri? lastUrl;
    final shortlets = ShortLetController(
      service: ShortLetService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            lastUrl = request.url;
            return http.Response(
              jsonEncode([
                {
                  'id': 'l1',
                  'property_name': 'Sunset House',
                  'nightly_price': '50000.00',
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
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
          ChangeNotifierProvider(create: (_) => SavedShortLetsController()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ShortLetBrowseScreen(isV2: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    final sheet = find.byType(SingleChildScrollView).last;
    for (final title in [
      'Best for',
      'Type of place',
      'Amenities',
      'House rules',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        200,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(title), findsOneWidget);
    }

    await tester.tap(find.text('Pool'));
    await tester.pumpAndSettle();
    expect(lastUrl?.queryParameters['amenities'], 'POOL');

    await tester.scrollUntilVisible(
      find.text('Pets welcome'),
      200,
      scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(lastUrl?.queryParameters['pets_allowed'], 'true');
    expect(lastUrl?.queryParameters['amenities'], 'POOL');

    // The button stays on screen below the scrolling groups.
    expect(find.textContaining('Show 1 shortlet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
