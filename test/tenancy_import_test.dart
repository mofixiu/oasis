import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';
import 'package:oasis_app/features/agreements/models/tenancy_import.dart';
import 'package:oasis_app/features/agreements/services/agreement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moving a landlord's existing building onto Oasis is the one flow where the
/// app writes history rather than starting it, and the two ways it can go
/// wrong are both silent: an agreement dated today instead of when the tenant
/// really moved in, and a paid-up tenant being billed again. These pin the
/// wire shape that prevents both, plus the partial-failure reporting a batch
/// of seven needs to be usable.
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

  test('an imported tenancy is dated from when the tenant moved in', () async {
    Map<String, dynamic>? sentBody;
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'results': _results(1)}, status: 201);
        }),
      ),
    );

    await service.importTenancies([_row()]);

    final tenancy = (sentBody!['tenancies'] as List).single;
    expect(tenancy['start_date'], '2025-03-01');
    // A year less a day, so the term ends the day before its anniversary
    // rather than overlapping the renewal.
    expect(tenancy['end_date'], '2026-02-28');
    expect(tenancy['is_existing_tenancy'], isTrue);
    // The whole point: rent is settled to the end of the running term, so the
    // tenant is not billed for months they paid in cash last year.
    expect(tenancy['rent_paid_until'], '2026-02-28');
  });

  test('a tenancy with rent still owed sends no settlement date', () async {
    Map<String, dynamic>? sentBody;
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'results': _results(1)}, status: 201);
        }),
      ),
    );

    await service.importTenancies([_row(rentAlreadyPaid: false)]);

    final tenancy = (sentBody!['tenancies'] as List).single;
    expect(tenancy.containsKey('rent_paid_until'), isFalse);
  });

  test('the import falls back to one agreement per row on a 404', () async {
    final calledPaths = <String>[];
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          calledPaths.add(request.url.path);
          if (request.url.path.endsWith('/tenancies/import/')) {
            return _json({'detail': 'Not found.'}, status: 404);
          }
          return _json(_agreement('agreement-1'), status: 201);
        }),
      ),
    );

    final report = await service.importTenancies([
      _row(unitId: 'unit-1'),
      _row(unitId: 'unit-2'),
    ]);

    expect(calledPaths.first, '/api/users/landlord/tenancies/import/');
    // One agreement per row, rather than the whole batch lost with the route.
    expect(
      calledPaths.where((path) => path.endsWith('/agreements/')).length,
      2,
    );
    expect(report.succeeded.length, 2);
  });

  test('a 400 from the import route is not retried row by row', () async {
    final calledPaths = <String>[];
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          calledPaths.add(request.url.path);
          return _json({'detail': 'Bad payload.'}, status: 400);
        }),
      ),
    );

    // The route exists and said no. Looping would report the wrong reason
    // once per row and write nothing.
    await expectLater(
      service.importTenancies([_row()]),
      throwsA(isA<ApiException>()),
    );
    expect(calledPaths.length, 1);
  });

  test('one bad row does not take the rest of the batch with it', () async {
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/tenancies/import/')) {
            return _json({'detail': 'Not found.'}, status: 404);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['unit'] == 'unit-2') {
            return _json({
              'tenant': ['No tenant account matches that email.'],
            }, status: 400);
          }
          return _json(_agreement('agreement-1'), status: 201);
        }),
      ),
    );

    final report = await service.importTenancies([
      _row(unitId: 'unit-1', unitLabel: 'Unit A1'),
      _row(unitId: 'unit-2', unitLabel: 'Unit A2'),
      _row(unitId: 'unit-3', unitLabel: 'Unit A3'),
    ]);

    expect(report.succeeded.length, 2);
    expect(report.failed.single.row.unitLabel, 'Unit A2');
    expect(report.failed.single.error, isNotNull);
    expect(report.isCompleteSuccess, isFalse);
    expect(report.isCompleteFailure, isFalse);
  });

  test('an invited tenant is reported as invited, not as failed', () async {
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => _json({
            'results': [
              {
                'tenant_status': 'INVITED',
                'agreement': _agreement('agreement-1'),
              },
            ],
          }, status: 201),
        ),
      ),
    );

    final report = await service.importTenancies([_row()]);

    expect(report.succeeded.length, 1);
    expect(report.invitedCount, 1);
    expect(report.failed, isEmpty);
  });

  test('results are matched to rows by position', () async {
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => _json({
            'results': [
              {'agreement': _agreement('agreement-1')},
              {'error': 'That unit already has a tenant.'},
            ],
          }, status: 201),
        ),
      ),
    );

    final report = await service.importTenancies([
      _row(unitId: 'unit-1', unitLabel: 'Unit A1'),
      _row(unitId: 'unit-2', unitLabel: 'Unit A2'),
    ]);

    // A verdict shown against the wrong flat is worse than no verdict.
    expect(report.succeeded.single.row.unitLabel, 'Unit A1');
    expect(report.failed.single.row.unitLabel, 'Unit A2');
  });
}

TenancyImportRow _row({
  String unitId = 'unit-1',
  String unitLabel = 'Unit A1',
  bool rentAlreadyPaid = true,
}) => TenancyImportRow(
  unitId: unitId,
  unitLabel: unitLabel,
  tenantContact: 'tenant@example.test',
  rentAmount: '450000.00',
  startDate: DateTime(2025, 3, 1),
  endDate: DateTime(2026, 3, 1).subtract(const Duration(days: 1)),
  rentPlan: RentPlan.annual,
  rules: 'No noise after 10 PM.',
  rentAlreadyPaid: rentAlreadyPaid,
);

List<Map<String, dynamic>> _results(int count) => [
  for (var index = 0; index < count; index++)
    {'agreement': _agreement('agreement-$index')},
];

Map<String, dynamic> _agreement(String id) => {
  'id': id,
  'unit': 'unit-1',
  'unit_number': 'A1',
  'rent_amount': '450000.00',
  'start_date': '2025-03-01',
  'end_date': '2026-02-28',
  'status': 'PENDING',
};

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
