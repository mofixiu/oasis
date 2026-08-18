import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/session_scope.dart';
import '../models/agreement_model.dart';
import '../services/agreement_service.dart';

class AgreementController extends ChangeNotifier
    implements SessionScopedController {
  final AgreementService _agreementService;

  AgreementController({AgreementService? agreementService})
      : _agreementService = agreementService ?? AgreementService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<TenancyAgreementModel> _agreements = [];
  List<TenancyAgreementModel> get agreements => _agreements;

  TenancyAgreementModel? get primaryAgreement =>
      _agreements.isNotEmpty ? _agreements.first : null;

  @override
  void resetSessionState() {
    _agreements = [];
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Load agreements for user
  Future<void> loadAgreements() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _agreements = await _agreementService.getAgreements();
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create Tenancy Agreement (Landlord)
  Future<TenancyAgreementModel?> createAgreement({
    required String unitId,
    required String tenantId,
    required String rentAmount,
    required String startDate,
    required String endDate,
    required String rules,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newAgreement = await _agreementService.createAgreement(
        unitId: unitId,
        tenantId: tenantId,
        rentAmount: rentAmount,
        startDate: startDate,
        endDate: endDate,
        rules: rules,
      );
      _agreements.insert(0, newAgreement);
      return newAgreement;
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign Tenancy Agreement (Tenant or Landlord)
  Future<bool> signAgreement(String agreementId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await _agreementService.signAgreement(agreementId);
      final index = _agreements.indexWhere((a) => a.id == agreementId);
      if (index != -1) {
        _agreements[index] = updated;
      } else {
        _agreements.insert(0, updated);
      }
      return true;
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
