import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:oasis_app/features/marketplace/models/marketplace_models.dart';
import 'package:oasis_app/features/marketplace/services/marketplace_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drawing a change before the server confirms it is the difference between an
/// app that feels immediate and one that feels remote. It is also the easiest
/// way to lie to somebody: a button that stays flipped to "Applied" after a
/// failed request sends a tenant away believing they applied for a home they
/// did not. Every optimistic path here is tested in both directions.
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

  MarketplaceController controllerWith(MockClient client) =>
      MarketplaceController(
        service: MarketplaceService(apiClient: ApiClient(client: client)),
      );

  group('applying for a unit', () {
    test('the unit reads as applied for before the server answers', () async {
      // Held open so the optimistic state can be inspected mid-flight, which
      // is the only moment it exists.
      final gate = Completer<void>();
      final controller = controllerWith(
        MockClient((request) async {
          await gate.future;
          return _json({
            'id': 'application-1',
            'unit': 'unit-1',
            'unit_number': 'A1',
            'status': 'PENDING',
            'created_at': '2026-09-04T10:00:00Z',
          }, status: 201);
        }),
      );

      final pending = controller.applyForUnit(
        'unit-1',
        unitNumber: 'A1',
        rentAmount: '450000.00',
      );

      // Drawn immediately: the Apply button has already flipped, and My
      // applications already has a row in it.
      expect(controller.appliedUnitIds, contains('unit-1'));
      expect(controller.tenantApplications.single.isOptimistic, isTrue);
      expect(controller.tenantApplications.single.unitNumber, 'A1');

      gate.complete();
      await pending;

      // Replaced by the real record, not left alongside it.
      expect(controller.tenantApplications, hasLength(1));
      expect(controller.tenantApplications.single.id, 'application-1');
      expect(controller.tenantApplications.single.isOptimistic, isFalse);
    });

    test('a refused application is rolled back in full', () async {
      final controller = controllerWith(
        MockClient(
          (request) async =>
              _json({'detail': 'You have already applied.'}, status: 400),
        ),
      );

      final result = await controller.applyForUnit('unit-1', unitNumber: 'A1');

      // The whole point of pairing every optimistic write with its undo. A
      // button left reading "Applied" after this would be the app telling the
      // tenant something that is not true.
      expect(result, isNull);
      expect(controller.tenantApplications, isEmpty);
      expect(controller.appliedUnitIds, isEmpty);
      expect(controller.errorMessage, contains('already applied'));
    });
  });

  group('deciding on an application', () {
    /// One pending application, then whatever the decision endpoint answers.
    MockClient decidingClient({required int decisionStatus}) => MockClient((
      request,
    ) async {
      if (request.method == 'GET') {
        return _json([
          {
            'id': 'application-1',
            'unit': 'unit-1',
            'unit_number': 'A1',
            'status': 'PENDING',
            'created_at': '2026-09-04T10:00:00Z',
          },
        ]);
      }
      return _json(
        decisionStatus >= 400 ? {'detail': 'Already settled.'} : {'ok': true},
        status: decisionStatus,
      );
    });

    test('a refused rejection puts the application back to pending', () async {
      final controller = controllerWith(decidingClient(decisionStatus: 400));
      await controller.loadLandlordApplications();
      expect(controller.landlordApplications.single.status.isPending, isTrue);

      final ok = await controller.rejectApplication('application-1');

      // The row was moved to rejected on tap and has to come back, because
      // the decision did not happen, and a landlord who reads it as declined
      // will never look at the applicant again.
      expect(ok, isFalse);
      expect(controller.landlordApplications.single.status.isPending, isTrue);
      expect(controller.pendingLandlordApplicationCount, 1);
    });

    test('a successful rejection takes the backend list as final', () async {
      final controller = controllerWith(decidingClient(decisionStatus: 200));
      await controller.loadLandlordApplications();

      final ok = await controller.rejectApplication('application-1');

      // The refetch is the authority; the optimistic status was only there to
      // cover the round trip. Here the stub still answers PENDING, and that
      // is what must win.
      expect(ok, isTrue);
      expect(controller.landlordApplications.single.status.isPending, isTrue);
    });
  });

  group('the provisional application row', () {
    test('is marked so screens can hold back actions needing a real id', () {
      final optimistic = RentalApplication.optimistic(
        unitId: 'unit-1',
        unitNumber: 'A1',
      );

      expect(optimistic.isOptimistic, isTrue);
      expect(optimistic.status, ApplicationStatus.pending);
      expect(optimistic.unitId, 'unit-1');
    });
  });
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
