import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/features/shortlets/controllers/shortlet_controller.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';
import 'package:oasis_app/features/shortlets/services/shortlet_service.dart';
import 'package:oasis_app/features/shortlets/views/widgets/shortlet_booking_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The booking card is the one surface both roles read a booking from, so
/// these pin what it must never misstate: the number of nights, whose money is
/// at stake, and whether a stay is confirmed.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a guest sees the stay, not the guest list', (tester) async {
    await _pumpCard(tester, isLandlord: false, status: 'APPROVED');

    expect(find.text('Approved, pay to confirm'), findsOneWidget);
    expect(find.textContaining('2 nights'), findsOneWidget);
    expect(find.textContaining('₦105,000'), findsOneWidget);
    // A guest's own note back to them is noise.
    expect(find.text('Weekend stay.'), findsNothing);
  });

  testWidgets('a host sees who is asking and what they said', (tester) async {
    await _pumpCard(tester, isLandlord: true, status: 'PENDING');

    expect(find.text('Needs your decision'), findsOneWidget);
    expect(find.textContaining('ada@example.com'), findsOneWidget);
    expect(find.text('Weekend stay.'), findsOneWidget);
  });

  testWidgets('check-in details appear only once paid', (tester) async {
    await _pumpCard(tester, isLandlord: false, status: 'APPROVED');
    expect(find.textContaining('Gate code 4417'), findsNothing);

    await _pumpCard(tester, isLandlord: false, status: 'PAID');
    expect(find.textContaining('Gate code 4417'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('an unknown status confirms nothing', (tester) async {
    await _pumpCard(tester, isLandlord: false, status: 'SOMETHING_NEW');

    // "Status unclear", not the old "Processing". The old word described a
    // payment moving through a provider, which is not what this state is:
    // it is the app failing to read the backend's answer, and it sent people
    // hunting through Paystack for a bug that was in the Flutter enum.
    expect(find.text('Status unclear'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
  });

  testWidgets('an unreadable status names the word the server used', (
    tester,
  ) async {
    await _pumpCard(tester, isLandlord: false, status: 'PAYMENT_FAILED');

    // The card has no buttons in this state, so the explanation is the only
    // thing standing between the guest and a silent dead end, and the raw
    // word is what makes it actionable for whoever they tell.
    expect(
      find.textContaining('"Payment failed"'),
      findsOneWidget,
      reason: 'the backend word is quotable by the guest',
    );
    expect(find.textContaining('does not recognise'), findsOneWidget);
  });

  testWidgets('a booking with no status at all says so differently', (
    tester,
  ) async {
    await _pumpCard(tester, isLandlord: false, status: '');

    // Nothing to quote, so the sentence changes rather than rendering an
    // empty pair of quotation marks.
    expect(find.textContaining('without a status'), findsOneWidget);
  });
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required bool isLandlord,
  required String status,
}) async {
  final booking = ShortLetBooking.fromJson({
    'id': 'booking-1',
    'property_name': 'Sunset House',
    'unit_number': 'A1',
    'check_in': '2026-10-01',
    'check_out': '2026-10-03',
    'guest_count': 2,
    'message': 'Weekend stay.',
    'status': status,
    'total_amount': '105000.00',
    'tenant_email': 'ada@example.com',
    'check_in_notes': 'Gate code 4417.',
  });

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ShortLetController(
        service: ShortLetService(
          apiClient: ApiClient(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode(const []),
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          ),
        ),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShortLetBookingCard(
              booking: booking,
              isLandlord: isLandlord,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
