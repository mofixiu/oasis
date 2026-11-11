import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/features/reviews/controllers/review_controller.dart';
import 'package:oasis_app/features/reviews/services/review_service.dart';
import 'package:oasis_app/features/shortlets/controllers/saved_shortlets_controller.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';
import 'package:oasis_app/features/shortlets/views/shortlet_listing_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a guest reads on a listing now that the backend returns the host's
/// brand and the richer listing details (API guide 22).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpListing(
    WidgetTester tester,
    Map<String, dynamic> json,
  ) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final reviews = ReviewController(
      service: ReviewService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              '[]',
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
          ChangeNotifierProvider(create: (_) => ShortLetController()),
          ChangeNotifierProvider(create: (_) => SavedShortLetsController()),
          ChangeNotifierProvider.value(value: reviews),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: ShortLetListingScreen(
            listing: ShortLetListing.fromJson(json),
            isV2: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a branded listing shows its host, details and rules', (
    tester,
  ) async {
    await pumpListing(tester, {
      'id': 'l1',
      'property_name': 'The Lumière',
      'city': 'Lekki',
      'state': 'Lagos',
      'nightly_price': '280000.00',
      'host_brand_name': 'Lekki Luxe Stays',
      'property_type': 'PENTHOUSE',
      'amenities': [
        'POOL',
        'WIFI',
        'POWER_24H',
        'KITCHEN',
        'PARKING',
        'SECURITY',
        'GYM',
      ],
      'best_for': ['BIRTHDAY', 'PARTY'],
      'check_in_time': '15:00:00',
      'check_out_time': '11:00:00',
      'pets_allowed': true,
      'parties_allowed': true,
      'house_rules': 'Quiet hours after 11pm.',
    });

    expect(find.text('Penthouse · Lekki, Lagos'), findsOneWidget);
    expect(
      find.textContaining('Lekki Luxe Stays', findRichText: true),
      findsOneWidget,
    );

    final list = find.byType(Scrollable).first;
    // Scrolls past the target too, so it clears the booking bar fixed to
    // the bottom of the screen and a tap lands on it rather than the bar.
    Future<void> reveal(Finder finder) async {
      await tester.scrollUntilVisible(finder, 250, scrollable: list);
      const clearOfBar = 667 - 170.0;
      final bottom = tester.getRect(finder.first).bottom;
      if (bottom > clearOfBar) {
        await tester.drag(list, Offset(0, clearOfBar - bottom - 20));
        await tester.pumpAndSettle();
      }
    }

    await reveal(find.text('What this place offers'));
    // Wi-Fi leads whatever order the server sent, and the seventh waits
    // behind "Show all".
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Gym'), findsNothing);
    await reveal(find.text('Show all 7 amenities'));
    await tester.tap(find.text('Show all 7 amenities'));
    await tester.pumpAndSettle();
    expect(find.text('Gym'), findsOneWidget);

    await reveal(find.text('Great for'));
    expect(find.text('Birthdays'), findsOneWidget);
    expect(find.text('Parties'), findsOneWidget);

    await reveal(find.text('Check-in and checkout'));
    expect(
      find.text('Check in from 3:00 PM, check out by 11:00 AM.'),
      findsOneWidget,
    );
    await reveal(find.textContaining('Pets welcome'));
    expect(
      find.text(
        'No smoking · Pets welcome · Parties allowed\n\n'
        'Quiet hours after 11pm.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a host with no brand is not given a blank one', (tester) async {
    await pumpListing(tester, {
      'id': 'l2',
      'property_name': 'Palm Court Studio',
      'city': 'Yaba',
      'state': 'Lagos',
      'nightly_price': '45000.00',
      'host_brand_name': '',
    });

    expect(find.textContaining('Hosted by', findRichText: true), findsNothing);
    expect(find.text('What this place offers'), findsNothing);
    expect(find.text('Great for'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
