import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/agreement_model.dart';

class AgreementService {
  final ApiClient _apiClient;

  AgreementService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// List agreements for landlord or tenant
  Future<List<TenancyAgreementModel>> getAgreements() async {
    debugPrint('📝 [AGREEMENT SERVICE] Fetching tenancy agreements GET ${ApiConstants.agreementsEndpoint}');
    final response = await _apiClient.get(ApiConstants.agreementsEndpoint);
    if (response is List) {
      final agreements = response.map((item) => TenancyAgreementModel.fromJson(item)).toList();
      debugPrint('📝 [AGREEMENT SERVICE] Loaded ${agreements.length} tenancy agreements');
      return agreements;
    }
    return [];
  }

  /// Create tenancy agreement (Landlord)
  Future<TenancyAgreementModel> createAgreement({
    required String unitId,
    required String tenantId,
    required String rentAmount,
    required String startDate,
    required String endDate,
    required String rules,
  }) async {
    debugPrint('📝 [AGREEMENT SERVICE] Creating tenancy agreement POST ${ApiConstants.agreementsEndpoint}');
    debugPrint('   Unit: $unitId | Tenant: $tenantId | Rent: ₦$rentAmount');

    final response = await _apiClient.post(
      ApiConstants.agreementsEndpoint,
      body: {
        'unit': unitId,
        'tenant': tenantId,
        'rent_amount': rentAmount,
        'start_date': startDate,
        'end_date': endDate,
        'rules': rules,
      },
    );
    final agreement = TenancyAgreementModel.fromJson(response);
    debugPrint('📝 [AGREEMENT SERVICE] Agreement created: ID=${agreement.id}, Status=${agreement.status.label}');
    return agreement;
  }

  /// Sign tenancy agreement (Tenant or Landlord)
  Future<TenancyAgreementModel> signAgreement(String agreementId) async {
    final endpoint = ApiConstants.signAgreementEndpoint(agreementId);
    debugPrint('✍️ [AGREEMENT SERVICE] Signing tenancy agreement ID $agreementId POST $endpoint');

    final response = await _apiClient.post(
      endpoint,
      body: {},
    );
    final agreement = TenancyAgreementModel.fromJson(response);
    debugPrint('✍️ [AGREEMENT SERVICE] Agreement signed successfully! New Status=${agreement.status.label}, PayRentUnlocked=${agreement.payRentUnlocked}');
    return agreement;
  }
}
