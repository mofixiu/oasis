import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/features/vault/controllers/vault_controller.dart';
import 'package:oasis_app/features/vault/services/vault_service.dart';
import 'package:oasis_app/features/vault/views/vault_pin_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The PIN prompt is the last screen before money leaves. These pin the three
/// things it must never get wrong: handing back a PIN that is not four digits,
/// asking for a PIN that was never created, and inviting an entry into a vault
/// that is already locked out.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a four-digit PIN is handed back to the caller', (tester) async {
    final result = await _prompt(tester, pinStatus: {'is_set': true});

    expect(find.text('Confirm withdrawal'), findsOneWidget);

    // Three digits is not a PIN: the action stays unavailable.
    await tester.enterText(find.byType(TextField).last, '123');
    await tester.pump();
    expect(result.value, isNull);

    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pumpAndSettle();

    expect(result.value, '1234');
  });

  testWidgets('a vault with no PIN asks for one instead of prompting', (
    tester,
  ) async {
    await _prompt(tester, pinStatus: {'is_set': false});

    // Prompting for a PIN that does not exist would spend an attempt on
    // something that cannot succeed.
    expect(find.text('Create your vault PIN'), findsOneWidget);
    expect(find.text('Create PIN and continue'), findsOneWidget);
    expect(find.text('ACCOUNT PASSWORD'), findsOneWidget);
  });

  testWidgets('a locked vault says so rather than taking an entry', (
    tester,
  ) async {
    await _prompt(
      tester,
      pinStatus: {
        'is_set': true,
        'locked_until': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
        'failed_attempts_remaining': 0,
      },
    );

    expect(find.textContaining('Too many wrong PINs'), findsOneWidget);
    // Reassurance matters here: a lock is not a loss.
    expect(find.textContaining('Your money is untouched'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('a status that could not be read offers a retry, not an entry', (
    tester,
  ) async {
    await _prompt(tester, pinStatus: null);

    // Taking a PIN we cannot judge would waste one of five attempts on what
    // is really a network fault.
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('nothing has been sent'), findsOneWidget);
  });
}

/// Opens the prompt over a bare scaffold and returns a holder for whatever it
/// eventually hands back.
Future<_Result> _prompt(
  WidgetTester tester, {
  required Map<String, dynamic>? pinStatus,
}) async {
  final controller = VaultController(
    vaultService: VaultService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => pinStatus == null
              ? http.Response('{"detail": "Server error."}', 500)
              : http.Response(
                  jsonEncode(pinStatus),
                  200,
                  headers: {'content-type': 'application/json'},
                ),
        ),
      ),
    ),
  );

  final result = _Result();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => result.value = await promptVaultPin(
                  context,
                  title: 'Confirm withdrawal',
                  subtitle: 'Enter your vault PIN.',
                ),
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
  return result;
}

class _Result {
  String? value;
}
