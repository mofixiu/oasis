import 'package:flutter/foundation.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/agreement_group.dart';
import '../models/agreement_model.dart';
import '../models/tenancy_import.dart';
import '../services/agreement_service.dart';

class AgreementController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  final AgreementService _agreementService;

  AgreementController({AgreementService? agreementService})
    : _agreementService = agreementService ?? AgreementService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<TenancyAgreementModel> _agreements = [];
  List<TenancyAgreementModel> get agreements => _agreements;

  TenancyAgreementModel? get primaryAgreement =>
      _agreements.isNotEmpty ? _agreements.first : null;

  /// Agreements still waiting on somebody's signature.
  ///
  /// This is the dashboard's list: the dashboard is a place for things to do,
  /// and an agreement stops being a task the moment it is fully signed.
  List<TenancyAgreementModel> get actionRequiredAgreements =>
      _agreements.where((a) => a.needsSignature).toList();

  /// Signed, expired or voided agreements: the archive's record list.
  ///
  /// Kept out of the dashboard deliberately: once signed, an agreement is
  /// something you look up, not something you act on.
  List<TenancyAgreementModel> get completedAgreements =>
      _agreements.where((a) => a.isCompleted).toList();

  /// The archive, grouped into properties and then units.
  ///
  /// A flat list works while there are three of these and fails badly at
  /// thirty: a landlord accumulates one per unit per term. Grouping by unit
  /// rather than by agreement means a renewal chain reads as one tenancy with
  /// a history, which is how people actually think about it.
  List<PropertyAgreementGroup> get signedAgreementsByProperty =>
      AgreementGrouping.byProperty(completedAgreements);

  /// Every unit this user holds, one entry each, newest agreement first.
  ///
  /// The backend's `GET /tenant/assigned-unit/` answers with *the first* unit
  /// a tenant is assigned, so a tenant with two homes appears to have one.
  /// Their agreements do not have that limit, there is one per unit, so the
  /// list of places someone actually lives is derived from those instead.
  ///
  /// Built from every agreement rather than only signed ones: a unit whose
  /// agreement is still waiting on a signature is somewhere the tenant is
  /// about to live, and hiding it until they sign would make the dashboard
  /// disagree with the agreement sitting right below it.
  List<TenancyGroup> get tenancies => AgreementGrouping.byUnit(_agreements);

  /// Executed agreements the tenant can still pay rent on. These drive the
  /// rent-due row on the payments screen, which is where paying rent lives
  /// now that signed agreements have left the dashboard.
  List<TenancyAgreementModel> get payableAgreements =>
      _agreements.where((a) => a.canPayRent).toList();

  /// Executed agreements with rent still ahead of them, owed now or falling
  /// due later, soonest first.
  ///
  /// This is the tenant dashboard's list once there is nothing left to sign.
  /// A tenancy with no signature outstanding is not "nothing to do": it is a
  /// rent bill with a date on it, and seeing that date early is the whole
  /// point of having somewhere to save.
  List<TenancyAgreementModel> get upcomingRentAgreements {
    final withRent = _agreements.where((a) => a.upcomingRent != null).toList();
    withRent.sort((a, b) {
      // Undated bills are ones the backend has not scheduled yet; they sort
      // last rather than pretending to be imminent.
      final left = a.upcomingRent!.daysUntilDue ?? 1 << 30;
      final right = b.upcomingRent!.daysUntilDue ?? 1 << 30;
      return left.compareTo(right);
    });
    return withRent;
  }

  @override
  void resetSessionState() {
    _agreements = [];
    resetLoadedState();
    clearFailure();
    _isLoading = false;
    notifyListeners();
  }

  /// Load agreements for user
  Future<void> loadAgreements() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _agreements = await _agreementService.getAgreements();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded();
      notifyListeners();
    }
  }

  /// Records tenancies the landlord already has off-platform (Landlord).
  ///
  /// Returns a report with a verdict per row, or null when the whole call
  /// failed (a rejected route, no network) with [errorMessage] set. A row
  /// that failed on its own is *not* a failure of this method: the report
  /// carries it, and the sheet shows it against the flat it belongs to.
  Future<TenancyImportReport?> importTenancies(
    List<TenancyImportRow> rows,
  ) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final report = await _agreementService.importTenancies(rows);
      // Newest first, matching where a freshly created agreement lands.
      _agreements.insertAll(
        0,
        report.succeeded
            .map((outcome) => outcome.agreement)
            .whereType<TenancyAgreementModel>(),
      );
      return report;
    } catch (e) {
      captureFailure(e);
      return null;
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
    RentPlan rentPlan = RentPlan.unknown,
  }) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final newAgreement = await _agreementService.createAgreement(
        unitId: unitId,
        tenantId: tenantId,
        rentAmount: rentAmount,
        startDate: startDate,
        endDate: endDate,
        rules: rules,
        rentPlan: rentPlan,
      );
      _agreements.insert(0, newAgreement);
      return newAgreement;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign Tenancy Agreement (Tenant or Landlord)
  Future<bool> signAgreement(String agreementId) async {
    _isLoading = true;
    clearFailure();
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
      captureFailure(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
