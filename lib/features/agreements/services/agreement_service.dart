import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/agreement_model.dart';
import '../models/tenancy_import.dart';

class AgreementService {
  final ApiClient _apiClient;

  AgreementService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// List agreements for landlord or tenant
  Future<List<TenancyAgreementModel>> getAgreements() async {
    debugPrint(
      '[AGREEMENT SERVICE] Fetching tenancy agreements GET ${ApiConstants.agreementsEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.agreementsEndpoint);
    if (response is List) {
      final agreements = response
          .map((item) => TenancyAgreementModel.fromJson(item))
          .toList();
      debugPrint(
        '[AGREEMENT SERVICE] Loaded ${agreements.length} tenancy agreements',
      );
      return agreements;
    }
    return [];
  }

  /// Create tenancy agreement (Landlord)
  /// [rentPlan] is how often rent falls due. `rent_amount` stays the annual
  /// figure whatever the plan: the backend splits it into instalments and
  /// returns the result as `rent_schedule`. Omitting the plan lets the backend
  /// apply its own default (`ANNUAL`) rather than having one asserted here.
  Future<TenancyAgreementModel> createAgreement({
    required String unitId,
    required String tenantId,
    required String rentAmount,
    required String startDate,
    required String endDate,
    required String rules,
    RentPlan rentPlan = RentPlan.unknown,
  }) async {
    debugPrint(
      '[AGREEMENT SERVICE] Creating tenancy agreement POST ${ApiConstants.agreementsEndpoint}',
    );
    debugPrint(
      'Unit: $unitId | Tenant: $tenantId | Rent: ₦$rentAmount/yr '
      '| Plan: ${rentPlan.apiValue ?? 'backend default'}',
    );

    final response = await _apiClient.post(
      ApiConstants.agreementsEndpoint,
      body: {
        'unit': unitId,
        'tenant': tenantId,
        'rent_amount': rentAmount,
        'start_date': startDate,
        'end_date': endDate,
        'rules': rules,
        if (rentPlan.apiValue != null) 'rent_plan': rentPlan.apiValue,
      },
    );
    final agreement = TenancyAgreementModel.fromJson(response);
    debugPrint(
      '[AGREEMENT SERVICE] Agreement created: ID=${agreement.id}, Status=${agreement.status.label}',
    );
    return agreement;
  }

  /// Records tenancies that already exist off-platform (Landlord).
  ///
  /// Tries the batch route first and falls back to one `POST /agreements/`
  /// per row on a routing answer. The batch route is the one that can do the
  /// whole job: it invites tenants who have no Oasis account yet, which
  /// `POST /agreements/` rejects outright, so the fallback is a degraded
  /// mode, not an equal alternative. See §1 of `backend_change_spec_v6.md`.
  ///
  /// Never throws for a row. A landlord entering seven tenancies will get one
  /// wrong, and losing the other six to a single 400 would make them retype
  /// the lot; every row comes back with its own verdict instead.
  Future<TenancyImportReport> importTenancies(
    List<TenancyImportRow> rows,
  ) async {
    if (rows.isEmpty) return const TenancyImportReport([]);
    debugPrint(
      '[AGREEMENT SERVICE] Importing ${rows.length} existing tenancy(ies) '
      'POST ${ApiConstants.landlordTenancyImportEndpoint}',
    );

    try {
      final response = await _apiClient.post(
        ApiConstants.landlordTenancyImportEndpoint,
        body: {'tenancies': rows.map((row) => row.toJson()).toList()},
      );
      return _reportFromBatch(response, rows);
    } on ApiException catch (e) {
      // Only a routing answer is worth retrying elsewhere. A 400 means the
      // route exists and rejected the payload, and hiding that behind a
      // per-row loop would report the wrong reason seven times.
      if (e.statusCode != 404 && e.statusCode != 403 && e.statusCode != 405) {
        rethrow;
      }
      debugPrint(
        '[AGREEMENT SERVICE] Import route unavailable (${e.statusCode}); '
        'writing agreements one at a time.',
      );
      return _importOneByOne(rows);
    }
  }

  /// Reads the batch response, tolerating both the documented
  /// `{"results": [...]}` envelope and a bare list.
  ///
  /// Results are matched to rows by position. The spec requires the backend to
  /// answer in request order for exactly this reason: a result that cannot be
  /// tied back to a row cannot be shown against the flat it belongs to.
  TenancyImportReport _reportFromBatch(
    dynamic response,
    List<TenancyImportRow> rows,
  ) {
    final results = response is Map<String, dynamic>
        ? (response['results'] ?? response['tenancies'])
        : response;
    if (results is! List) {
      // A 2xx with an unreadable body: the writes probably happened, so this
      // must not be reported as a failure the landlord should retry.
      debugPrint(
        '[AGREEMENT SERVICE] Import returned an unreadable body; '
        'reporting rows as sent.',
      );
      return TenancyImportReport([
        for (final row in rows) TenancyImportOutcome(row: row),
      ]);
    }

    final outcomes = <TenancyImportOutcome>[];
    for (var index = 0; index < rows.length; index++) {
      final entry = index < results.length ? results[index] : null;
      outcomes.add(
        entry is Map<String, dynamic>
            ? TenancyImportOutcome.fromJson(entry, rows[index])
            : TenancyImportOutcome(row: rows[index]),
      );
    }
    debugPrint(
      '[AGREEMENT SERVICE] Imported '
      '${outcomes.where((o) => o.succeeded).length}/${rows.length}',
    );
    return TenancyImportReport(outcomes);
  }

  /// The fallback: one agreement per row, each failing on its own.
  Future<TenancyImportReport> _importOneByOne(
    List<TenancyImportRow> rows,
  ) async {
    final outcomes = <TenancyImportOutcome>[];
    for (final row in rows) {
      try {
        final response = await _apiClient.post(
          ApiConstants.agreementsEndpoint,
          body: row.toJson(),
        );
        outcomes.add(
          TenancyImportOutcome(
            row: row,
            agreement: TenancyAgreementModel.fromJson(response),
          ),
        );
      } on ApiException catch (e) {
        outcomes.add(TenancyImportOutcome(row: row, error: e.message));
      } catch (e) {
        // A network drop mid-batch. Named as itself rather than as a
        // rejection of this particular tenancy, which it is not.
        outcomes.add(
          TenancyImportOutcome(
            row: row,
            error: 'Could not reach Oasis. Try this one again.',
          ),
        );
        debugPrint('[AGREEMENT SERVICE] Row ${row.unitLabel} failed: $e');
      }
    }
    return TenancyImportReport(outcomes);
  }

  /// Sign tenancy agreement (Tenant or Landlord)
  Future<TenancyAgreementModel> signAgreement(String agreementId) async {
    final endpoint = ApiConstants.signAgreementEndpoint(agreementId);
    debugPrint(
      '[AGREEMENT SERVICE] Signing tenancy agreement ID $agreementId POST $endpoint',
    );

    final response = await _apiClient.post(endpoint, body: {});
    final agreement = TenancyAgreementModel.fromJson(response);
    debugPrint(
      '[AGREEMENT SERVICE] Agreement signed successfully! New Status=${agreement.status.label}, PayRentUnlocked=${agreement.payRentUnlocked}',
    );
    return agreement;
  }
}
