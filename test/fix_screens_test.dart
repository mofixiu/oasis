import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/core/theme/app_theme.dart';
import 'package:landa_app/features/fix/models/fix_models.dart';
import 'package:landa_app/features/fix/views/widgets/artisan_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The artisan card is now the whole of Fix on screen. API guide 18 removed
/// the job workflow the other cards belonged to (§7B), so these pin the two
/// claims it makes that a tenant acts on: who their landlord vouched for, and
/// who the backend has actually verified.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a landlord recommendation is stated in words', (tester) async {
    await _pumpArtisan(tester, isRecommended: true);
    expect(find.text('RECOMMENDED BY YOUR LANDLORD'), findsOneWidget);

    await _pumpArtisan(tester, isRecommended: false);
    expect(find.text('RECOMMENDED BY YOUR LANDLORD'), findsNothing);
  });

  testWidgets('an unverified artisan carries no verified tick', (tester) async {
    await _pumpArtisan(tester, verified: false);
    expect(find.byIcon(Icons.verified_rounded), findsNothing);

    await _pumpArtisan(tester, verified: true);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });
}

Future<void> _pumpArtisan(
  WidgetTester tester, {
  bool isRecommended = false,
  bool verified = true,
}) async {
  final artisan = ArtisanProfile.fromJson({
    'id': 'artisan-1',
    'full_name': 'Ada Fixer',
    'category': 'PLUMBING',
    'category_label': 'Plumbing',
    'location': 'Lekki Phase 1',
    'years_of_experience': 5,
    'verification_status': verified ? 'VERIFIED' : 'PENDING',
    'is_recommended': isRecommended,
  });

  await _pump(tester, ArtisanCard(artisan: artisan));
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  // Google Fonts cannot reach the network under test; drain those so the
  // assertions are what decide these tests.
  while (tester.takeException() != null) {}
}
