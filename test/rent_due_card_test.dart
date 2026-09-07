import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/features/agreements/models/agreement_model.dart';
import 'package:landa_app/features/payments/controllers/payment_controller.dart';
import 'package:landa_app/features/payments/views/widgets/rent_due_card.dart';
import 'package:landa_app/features/vault/controllers/vault_controller.dart';
import 'package:landa_app/features/vault/services/vault_service.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rent card is the one screen element that decides whether a tenant is
/// offered a payment at all. These pin the decisions that would cost them:
/// being offered a vault payment the balance cannot cover, and a bill months
/// away being presented as payable.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a covered bill offers the vault first', (tester) async {
    await _pumpCard(
      tester,
      balance: '500000.00',
      schedule: {
        'next_due_date': '2026-08-01',
        'next_amount_due': '472500.00',
        'days_until_due': -26,
        'is_overdue': true,
      },
    );

    expect(find.textContaining('from vault'), findsOneWidget);
    // The card route stays available, just quieter.
    expect(find.text('Pay with card instead'), findsOneWidget);
    expect(find.textContaining('Overdue by 26 days'), findsOneWidget);
  });

  testWidgets('a short balance is never offered as a vault payment', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      balance: '472499.99',
      schedule: {
        'next_due_date': '2026-08-01',
        'next_amount_due': '472500.00',
        'days_until_due': 0,
        'is_overdue': false,
      },
    );

    // One kobo short. Offering the vault here would be a payment that is
    // promised and then declined.
    expect(find.textContaining('from vault'), findsNothing);
    expect(find.text('Pay rent into escrow'), findsOneWidget);
    expect(find.text('Add to vault'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
  });

  testWidgets('a bill months away is savings, not a payment', (tester) async {
    await _pumpCard(
      tester,
      balance: '500000.00',
      schedule: {
        'plan': 'SIX_MONTHLY',
        'next_due_date': '2027-06-30',
        'next_amount_due': '236250.00',
        'days_until_due': 307,
        'is_overdue': false,
        'instalments_paid': 1,
        'instalments_total': 2,
      },
    );

    // The vault covers it, but it is not due, so there is nothing to pay yet.
    expect(find.textContaining('from vault'), findsNothing);
    expect(find.text('Pay rent into escrow'), findsNothing);
    expect(find.text('Add to vault'), findsOneWidget);
    expect(find.textContaining('30 Jun 2027'), findsOneWidget);
    expect(find.text('Every 6 months'), findsOneWidget);
    expect(find.text('Payment 2 of 2'), findsOneWidget);
  });

  testWidgets('a bill inside the month shows the countdown', (tester) async {
    await _pumpCard(
      tester,
      balance: '0.00',
      schedule: {
        'next_due_date': '2026-09-10',
        'next_amount_due': '472500.00',
        'days_until_due': 14,
        'is_overdue': false,
      },
    );

    expect(find.textContaining('Due in 14 days'), findsOneWidget);
    // Still saving, so the progress towards the bill is worth showing.
    expect(find.textContaining('to go'), findsOneWidget);
  });
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required String balance,
  required Map<String, dynamic> schedule,
}) async {
  final vault = VaultController(
    vaultService: VaultService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => http.Response(
            '{"available_balance": "$balance"}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    ),
  );
  await vault.loadVault();

  final agreement = TenancyAgreementModel.fromJson({
    'id': 'agreement-1',
    'unit_number': '4B',
    'rent_amount': '450000.00',
    'status': 'EXECUTED',
    'pay_rent_unlocked': true,
    'rent_schedule': schedule,
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vault),
        ChangeNotifierProvider(create: (_) => PaymentController()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RentDueCard(agreement: agreement)),
        ),
      ),
    ),
  );
  await tester.pump();
}
