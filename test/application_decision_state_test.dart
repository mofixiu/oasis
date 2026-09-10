import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:oasis_app/features/marketplace/services/marketplace_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression cover for the landlord inbox's Approve/Reject buttons.
///
/// They used to be bound to the controller's shared `isLoading`, so any
/// background list refresh, and the dashboard preloads this list, so there is
/// always one right after signing in: greyed them out until it finished.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(
      access: 'test-access-token',
      refresh: 'test-refresh-token',
    );
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() {
    ApiConstants.baseUrl = originalBaseUrl;
  });

  http.Response applicationsResponse() => http.Response(
    jsonEncode([
      {
        'id': 'application-1',
        'unit': 'unit-1',
        'unit_number': 'A1',
        'status': 'PENDING',
        'created_at': '2026-08-17T09:00:00Z',
      },
    ]),
    200,
    headers: {'content-type': 'application/json'},
  );

  test('refreshing the list never disables the decision buttons', () async {
    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((_) async => applicationsResponse()),
        ),
      ),
    );

    final busyDuringLoad = <bool>[];
    controller.addListener(
      () => busyDuringLoad.add(controller.isDecidingApplication),
    );

    await controller.loadLandlordApplications();
    // Second load with the list already populated: the exact case that used
    // to grey out Approve/Reject on entering the screen.
    await controller.loadLandlordApplications();

    expect(controller.landlordApplications, hasLength(1));
    expect(busyDuringLoad, isNotEmpty);
    expect(busyDuringLoad.every((busy) => busy == false), isTrue);
  });

  test('a decision in flight disables only that application', () async {
    final approvalGate = Completer<void>();

    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              await approvalGate.future;
              return http.Response(
                jsonEncode({
                  'id': 'application-1',
                  'unit': 'unit-1',
                  'unit_number': 'A1',
                  'status': 'APPROVED',
                  'created_at': '2026-08-17T09:00:00Z',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return applicationsResponse();
          }),
        ),
      ),
    );

    await controller.loadLandlordApplications();

    final approval = controller.approveApplication(
      applicationId: 'application-1',
      startDate: '2026-09-01',
      endDate: '2027-08-31',
    );

    // Let the controller mark itself busy before the request resolves.
    await Future<void>.delayed(Duration.zero);
    expect(controller.decidingApplicationId, 'application-1');
    expect(controller.decidingIsApproval, isTrue);

    approvalGate.complete();
    expect(await approval, isTrue);

    // Cleared in a finally, so a failed decision cannot strand the buttons.
    expect(controller.decidingApplicationId, isNull);
    expect(controller.isDecidingApplication, isFalse);
  });

  test('a failed decision releases the buttons again', () async {
    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              return http.Response('{"detail": "Already settled."}', 400);
            }
            return applicationsResponse();
          }),
        ),
      ),
    );

    await controller.loadLandlordApplications();
    final rejected = await controller.rejectApplication('application-1');

    expect(rejected, isFalse);
    expect(controller.errorMessage, 'Already settled.');
    expect(controller.isDecidingApplication, isFalse);
  });
}
