import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/features/agreements/controllers/agreement_controller.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';
import 'package:oasis_app/features/agreements/views/tenancy_agreement_modal.dart';
import 'package:oasis_app/features/auth/controllers/auth_controller.dart';
import 'package:oasis_app/features/auth/models/user_model.dart';
import 'package:oasis_app/features/auth/services/mock_auth_service.dart';
import 'package:oasis_app/features/payments/controllers/payment_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quoted blocks used to render as near-white on near-white in dark mode: the
/// terms of the tenancy on the screen where someone signs them, and the
/// applicant's own message on the screen where a landlord approves them.
///
/// These assert contrast rather than exact colours, so they keep catching the
/// fault if the palette is re-tuned.
void main() {
  const rules = 'No illegal activity. Keep shared areas clean.';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(access: 'token', refresh: 'refresh');
  });

  for (final brightness in Brightness.values) {
    testWidgets('the agreement rules are legible in ${brightness.name}', (
      tester,
    ) async {
      await _pumpModal(tester, brightness: brightness, rules: rules);

      final text = tester.widget<Text>(find.text(rules));
      final panel = tester.widget<Container>(
        find
            .ancestor(of: find.text(rules), matching: find.byType(Container))
            .first,
      );

      final foreground = text.style?.color;
      final background = (panel.decoration as BoxDecoration?)?.color;

      expect(
        foreground,
        isNotNull,
        reason: 'rules text has no explicit colour',
      );
      expect(background, isNotNull, reason: 'rules panel has no fill');
      // 4.5:1 is the AA floor for body text. The original bug measured ~1.05.
      expect(
        _contrastRatio(foreground!, background!),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  testWidgets('the rules panel is themed, not a fixed near-white', (
    tester,
  ) async {
    await _pumpModal(tester, brightness: Brightness.dark, rules: rules);

    final panel = tester.widget<Container>(
      find
          .ancestor(of: find.text(rules), matching: find.byType(Container))
          .first,
    );

    // The specific regression: a hard-coded light fill surviving into the
    // dark theme.
    expect(
      (panel.decoration as BoxDecoration?)?.color,
      isNot(Colors.grey.shade50),
    );
  });

  testWidgets('an applicant\'s message is legible in dark mode', (
    tester,
  ) async {
    const note = "I have 3 kids and I'm interested in renting this property";

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Container(
              // The exact pairing from the applications card: the quoted
              // block's fill, and the message drawn on it.
              decoration: BoxDecoration(color: AppTheme.vacantSurface(context)),
              child: Text(
                note,
                style: TextStyle(color: AppTheme.readingTextColor(context)),
              ),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(note));
    final panel = tester.widget<Container>(
      find
          .ancestor(of: find.text(note), matching: find.byType(Container))
          .first,
    );

    expect(
      _contrastRatio(
        text.style!.color!,
        (panel.decoration as BoxDecoration).color!,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });
}

Future<void> _pumpModal(
  WidgetTester tester, {
  required Brightness brightness,
  required String rules,
}) async {
  final auth = AuthController(authService: _TenantAuthService());
  await auth.checkAuthStatus();

  final agreement = TenancyAgreementModel.fromJson({
    'id': 'agreement-1',
    'unit_number': '4B',
    'rent_amount': '450000.00',
    'start_date': '2026-07-01',
    'end_date': '2027-06-30',
    'status': 'PENDING',
    'rules': rules,
    'landlord_email': 'landlord@example.test',
    'tenant_email': 'ada@example.test',
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => AgreementController()),
        ChangeNotifierProvider(create: (_) => PaymentController()),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: Scaffold(body: ViewAgreementModal(agreement: agreement)),
      ),
    ),
  );
  await tester.pump();
}

class _TenantAuthService extends MockAuthService {
  @override
  Future<UserModel> getProfile() async => UserModel(
    id: 'tenant-1',
    email: 'ada@example.test',
    phone: '+2348012345678',
    role: UserRole.tenant,
    verificationStatus: VerificationStatus.verified,
  );
}

/// WCAG relative-luminance contrast between two opaque colours.
double _contrastRatio(Color a, Color b) {
  final lighter = math.max(_luminance(a), _luminance(b));
  final darker = math.min(_luminance(a), _luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
