import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/theme/app_theme.dart';
import 'package:oasis_app/core/widgets/oasis_sheet.dart';
import 'package:oasis_app/features/fix/controllers/fix_controller.dart';
import 'package:oasis_app/features/properties/controllers/landlord_controller.dart';
import 'package:oasis_app/features/properties/models/property_model.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/agreements/controllers/agreement_controller.dart';
import 'package:oasis_app/features/agreements/services/agreement_service.dart';
import 'package:oasis_app/features/dashboard/views/widgets/add_property_modal.dart';
import 'package:oasis_app/features/dashboard/views/widgets/move_in_tenants_modal.dart';
import 'package:oasis_app/features/properties/views/widgets/add_units_modal.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adding a property used to end at a toast. The units sheet, which is also
/// where a landlord names the artisans they trust, was only reachable from My
/// properties, so a landlord who had just added a building never saw it, and
/// nothing on screen said it existed.
///
/// These hold the destination together: the sheet a new property now lands on,
/// the recommendation step inside it, and the step after it: recording the
/// tenants who are already living in the units the landlord just described.
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

  testWidgets('the units sheet offers to recommend artisans', (tester) async {
    await _pumpUnitsSheet(tester);

    expect(find.text('Add units'), findsOneWidget);
    expect(find.textContaining('Sunset House'), findsWidgets);
    // The thing a landlord was never being shown.
    expect(find.text('RECOMMENDED ARTISANS'), findsOneWidget);
    // And the thing that is now mandatory per unit: a tenant does not apply
    // for a flat they cannot see inside.
    expect(find.text('Add tour video'), findsOneWidget);
    expect(find.text('Required for every unit'), findsOneWidget);
    // Photos of the flat are required for the same reason as the video: a
    // tenant is choosing where to live, and pictures of the gate do not tell
    // them what the rooms look like.
    expect(
      find.textContaining('At least 2 photos of this flat'),
      findsOneWidget,
    );
  });

  testWidgets('recommending is offered before any unit exists', (tester) async {
    // The point of doing it here: the landlord is set up in one pass rather
    // than having to come back per unit once the building is created.
    await _pumpUnitsSheet(tester);

    expect(find.text('RECOMMENDED ARTISANS'), findsOneWidget);
    expect(find.text('Add a recommended artisan'), findsOneWidget);
    // Optional, and labelled as such: a landlord adding units at midnight is
    // not made to pick a plumber before they can save. It is now the only
    // optional section on the sheet: unit photos used to carry the same pill
    // and are required, because a listing with no pictures of the flat is
    // the one nobody applies for.
    expect(find.text('OPTIONAL'), findsOneWidget);
    expect(find.text('REQUIRED'), findsOneWidget);
  });

  testWidgets('moving in existing tenants offers only the vacant units', (
    tester,
  ) async {
    await _pumpMoveInSheet(tester);

    await tester.tap(find.text('Which unit?'));
    await tester.pumpAndSettle();

    // A1 is vacant. A2 already has somebody in it, and the backend refuses an
    // agreement on a unit that is already assigned: offering it here would
    // only produce a row that always fails.
    expect(find.textContaining('Unit A1'), findsWidgets);
    expect(find.textContaining('Unit A2'), findsNothing);
  });

  testWidgets('a half-filled tenancy cannot be sent', (tester) async {
    await _pumpMoveInSheet(tester);

    // Nothing typed yet: a backdated agreement with no move-in date is the
    // exact mistake this sheet exists to prevent, so the button must not be
    // live until the row says when the tenancy began.
    final button = tester.widget<OasisSheetButton>(
      find.byType(OasisSheetButton),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Record this tenancy'), findsOneWidget);
  });

  testWidgets('a tenancy that landed is not sent a second time', (
    tester,
  ) async {
    final createdUnits = <String>[];
    await _pumpMoveInSheet(
      tester,
      // Two empty flats, because this test fills two rows.
      bothVacant: true,
      // No import route on this backend, so the app writes one agreement per
      // row, and Unit A2's tenant has no Oasis account, which is exactly the
      // gap §1.4 of the v6 spec exists to close.
      client: MockClient((request) async {
        if (request.url.path.endsWith('/tenancies/import/')) {
          return _json({'detail': 'Not found.'}, status: 404);
        }
        if (request.url.path.endsWith('/agreements/')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['unit'] == 'unit-2') {
            return _json({
              'tenant': ['No tenant account matches that email.'],
            }, status: 400);
          }
          createdUnits.add(body['unit'] as String);
          return _json({
            'id': 'agreement-1',
            'unit': body['unit'],
            'status': 'PENDING',
          }, status: 201);
        }
        return _json(const {}, status: 404);
      }),
    );

    await _fillRow(tester, index: 0, unitLabel: 'Unit A1');
    await tester.tap(find.text('Add another tenant'));
    await tester.pumpAndSettle();
    await _fillRow(tester, index: 1, unitLabel: 'Unit A2');

    await tester.tap(find.text('Record 2 tenancies'));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    // One landed, one did not, and the sheet says which.
    expect(createdUnits, ['unit-1']);
    expect(find.text('1 of 2 recorded'), findsOneWidget);

    await tester.tap(find.text('Back to the list'));
    await tester.pumpAndSettle();

    // Only the failed row is still outstanding. Sending the whole list again
    // would write a second agreement for the tenant who is already in.
    expect(find.text('Record this tenancy'), findsOneWidget);
    expect(find.text('Recorded'), findsOneWidget);

    await tester.tap(find.text('Record this tenancy'));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(createdUnits, ['unit-1']);
  });

  testWidgets('the sheet says what backdating will do', (tester) async {
    await _pumpMoveInSheet(tester);

    // The landlord is signing their tenants up to something. Both halves of
    // that (an agreement to sign, and rent not being asked for twice) are
    // stated before they fill anything in.
    expect(find.textContaining('dated from when they'), findsOneWidget);
    expect(find.textContaining('not ask'), findsOneWidget);
  });

  group('the flow outlives the screen that started it', () {
    testWidgets('a shell swapping its body mid-flow does not kill it', (
      tester,
    ) async {
      // What this reproduces: `MainScaffold` replaces its entire body with
      // the verification screen the moment the profile stops reading
      // VERIFIED, and every request the add-property flow makes can come back
      // 403 VERIFICATION_REQUIRED and trigger exactly that. The dashboard
      // element that opened the flow is deactivated halfway through, and the
      // flow still has three sheets to present.
      //
      // Presented from that dead context, the next sheet threw "Looking up a
      // deactivated widget's ancestor is unsafe": a crash at the final step,
      // after the landlord had already uploaded a walkthrough and five
      // photos. `context.mounted` never caught it: a deactivated element is
      // still mounted, and the assertion fires in the window before it is
      // not.
      final showDashboard = ValueNotifier<bool>(true);
      addTearDown(showDashboard.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ValueListenableBuilder<bool>(
            valueListenable: showDashboard,
            builder: (context, isDashboard, _) => isDashboard
                ? Scaffold(
                    body: Center(
                      child: Builder(
                        builder: (innerContext) => ElevatedButton(
                          onPressed: () => openAddPropertyFlow(innerContext),
                          child: const Text('Add property'),
                        ),
                      ),
                    ),
                  )
                : const Scaffold(body: Center(child: Text('Verify identity'))),
          ),
        ),
      );

      await tester.tap(find.text('Add property'));
      await tester.pumpAndSettle();
      expect(find.text('What are you listing this for?'), findsOneWidget);

      // The shell swaps. The screen that opened the flow is gone.
      showDashboard.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Verify identity'), findsOneWidget);

      // Carry on anyway. The flow is anchored to the navigator, which is
      // still very much alive.
      await tester.tap(find.text('Short lets'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Add a place for stays'), findsOneWidget);

      // The sheet is still sized the way it was when the height came from
      // `constraints:` on the caller's MediaQuery. It is measured inside the
      // builder now, against the sheet's own context, and this is what
      // says the swap did not quietly change the layout.
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        tester.getSize(find.byType(AddPropertyModal)).height,
        moreOrLessEquals(screenHeight * 0.8, epsilon: 1),
      );
    });
  });
}

/// Fills one row: picks its unit, names a tenant, and accepts today as the
/// move-in date. The rent comes prefilled from the unit.
///
/// Everything is scrolled into view first: a sheet holding two tenancies is
/// taller than the test viewport, and a tap on an off-screen widget lands
/// somewhere else entirely.
Future<void> _fillRow(
  WidgetTester tester, {
  required int index,
  required String unitLabel,
}) async {
  await _tapLast(tester, find.text('Which unit?'));
  await _tapLast(tester, find.textContaining(unitLabel));

  final contactField = find
      .widgetWithText(TextField, 'Their email or phone number')
      .last;
  await tester.ensureVisible(contactField);
  await tester.pumpAndSettle();
  await tester.enterText(contactField, 'tenant$index@example.test');
  await tester.pumpAndSettle();

  await _tapLast(tester, find.text('Moved in'));
  // The picker opens on today, which is the date this row wants.
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// Scrolls the last match into view, taps it, and settles.
Future<void> _tapLast(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
}

/// The move-in sheet over a property with one vacant unit and one occupied.
Future<void> _pumpMoveInSheet(
  WidgetTester tester, {
  MockClient? client,
  bool bothVacant = false,
}) async {
  tester.view.physicalSize = const Size(828, 1800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final property = PropertyModel.fromJson(const {
    'id': 'property-1',
    'name': 'Sunset House',
    'address': '12 Ikeja Road',
    'city': 'Ikeja',
    'state': 'Lagos',
  });
  final landlordController = LandlordController();
  landlordController.propertyUnits[property.id] = [
    UnitModel.fromJson(const {
      'id': 'unit-1',
      'unit_number': 'A1',
      'bedrooms': 2,
      'bathrooms': 1,
      'rent_amount': '450000.00',
      'is_occupied': false,
    }),
    UnitModel.fromJson({
      'id': 'unit-2',
      'unit_number': 'A2',
      'bedrooms': 2,
      'bathrooms': 1,
      'rent_amount': '500000.00',
      'is_occupied': !bothVacant,
    }),
  ];

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: landlordController),
        ChangeNotifierProvider(
          create: (_) => AgreementController(
            agreementService: client == null
                ? AgreementService()
                : AgreementService(apiClient: ApiClient(client: client)),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: MoveInTenantsModal(property: property)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  while (tester.takeException() != null) {}
}

Future<void> _pumpUnitsSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(828, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LandlordController()),
        ChangeNotifierProvider(create: (_) => FixController()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AddUnitsModal(
            property: PropertyModel.fromJson(const {
              'id': 'property-1',
              'name': 'Sunset House',
              'address': '12 Ikeja Road',
              'city': 'Ikeja',
              'state': 'Lagos',
            }),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  while (tester.takeException() != null) {}
}

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
