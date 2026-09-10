import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/agreements/controllers/agreement_controller.dart';
import 'package:oasis_app/features/agreements/services/agreement_service.dart';
import 'package:oasis_app/features/agreements/views/my_agreements_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The archive screen. These cover what a landlord with history actually
/// sees: one card per tenancy with the current term on it, renewals folded
/// away until asked for, and nothing missing.
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

  testWidgets('renewals are folded away behind the current term', (
    tester,
  ) async {
    await _pump(tester, [
      _json(id: 'current', unit: 'unit-1', number: 'A1', start: '2026-09-01'),
      _json(id: 'prior', unit: 'unit-1', number: 'A1', start: '2025-09-01'),
    ]);

    expect(find.text('SUNSET HOUSE'), findsOneWidget);
    expect(find.text('Unit A1'), findsOneWidget);
    // The current term is on the card; the older one is not on screen yet.
    expect(find.textContaining('Sep 2026'), findsOneWidget);
    expect(find.textContaining('Sep 2025'), findsNothing);
    expect(find.text('1 earlier term'), findsOneWidget);

    await tester.tap(find.text('1 earlier term'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sep 2025'), findsOneWidget);
    expect(find.text('Hide earlier terms'), findsOneWidget);
  });

  testWidgets('a tenancy with no history offers nothing to expand', (
    tester,
  ) async {
    await _pump(tester, [
      _json(id: 'only', unit: 'unit-1', number: '4B', start: '2026-09-01'),
    ]);

    expect(find.text('Unit 4B'), findsOneWidget);
    expect(find.textContaining('earlier term'), findsNothing);
  });

  testWidgets('an agreement with no property is shown, not lost', (
    tester,
  ) async {
    await _pump(tester, [
      _json(id: 'housed', unit: 'unit-1', number: 'A1', start: '2026-09-01'),
      _json(
        id: 'orphan',
        unit: 'unit-2',
        number: 'B7',
        start: '2026-09-01',
        property: null,
      ),
    ]);

    expect(find.text('SUNSET HOUSE'), findsOneWidget);
    expect(find.text('UNASSIGNED'), findsOneWidget);
    expect(find.text('Unit B7'), findsOneWidget);
    // And it says why, so a thin payload does not read as a bug.
    expect(find.textContaining('did not name a property'), findsOneWidget);
  });

  testWidgets('only signed agreements reach the archive', (tester) async {
    await _pump(tester, [
      _json(id: 'signed', unit: 'unit-1', number: 'A1', start: '2026-09-01'),
      _json(
        id: 'unsigned',
        unit: 'unit-2',
        number: 'A2',
        start: '2026-09-01',
        status: 'PENDING',
      ),
    ]);

    // An agreement awaiting a signature is a task and stays on the dashboard.
    expect(find.text('Unit A1'), findsOneWidget);
    expect(find.text('Unit A2'), findsNothing);
  });

  testWidgets('an empty archive explains itself', (tester) async {
    await _pump(tester, []);
    expect(find.text('No signed agreements yet'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> agreements,
) async {
  final controller = AgreementController(
    agreementService: AgreementService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(agreements),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    ),
  );

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: const MaterialApp(home: MyAgreementsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _json({
  required String id,
  required String unit,
  required String number,
  required String start,
  String status = 'EXECUTED',
  Map<String, dynamic>? property = const {
    'id': 'property-1',
    'name': 'Sunset House',
    'address': '123 Main Street',
    'city': 'Lagos',
  },
}) => {
  'id': id,
  'unit': unit,
  'unit_number': number,
  'rent_amount': '450000.00',
  'start_date': start,
  'end_date': '2027-08-31',
  'status': status,
  'pay_rent_unlocked': status == 'EXECUTED',
  if (property != null) 'property': property,
};
