import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../../agreements/models/agreement_model.dart';
import '../models/payment_model.dart';
import '../services/payment_service.dart';

class PaymentController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  final PaymentService _paymentService;

  PaymentController({PaymentService? paymentService})
    : _paymentService = paymentService ?? PaymentService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<PaymentModel> _payments = [];
  List<PaymentModel> get payments => _payments;

  PaymentModel? _selectedReceipt;
  PaymentModel? get selectedReceipt => _selectedReceipt;

  bool _isPayingFromVault = false;

  /// True while a vault-funded rent payment is in flight, so a second tap
  /// cannot start a second debit.
  bool get isPayingFromVault => _isPayingFromVault;

  /// Idempotency key for the vault payment currently being made. Held per
  /// agreement so retrying one rent bill cannot be merged with another.
  final Map<String, String> _vaultPaymentKeys = {};

  bool _vaultBalanceFellShort = false;

  /// Whether the last vault-funded rent payment was refused because the
  /// balance did not cover it.
  ///
  /// Kept apart from [errorMessage] because this failure has an obvious next
  /// step attached, top up and try again, where the others can only be
  /// reported.
  bool get vaultBalanceFellShort => _vaultBalanceFellShort;

  String? _vaultShortfall;

  /// How much more was needed, as a decimal string, when the backend quotes
  /// it. Null when it did not, including when the failure was something other
  /// than a short balance, so callers must read [vaultBalanceFellShort] for
  /// the fact and treat this only as the figure.
  String? get vaultShortfall => _vaultShortfall;

  @override
  void resetSessionState() {
    _payments = [];
    _selectedReceipt = null;
    _vaultPaymentKeys.clear();
    _vaultShortfall = null;
    _vaultBalanceFellShort = false;
    resetLoadedState();
    clearFailure();
    _isLoading = false;
    _isPayingFromVault = false;
    notifyListeners();
  }

  /// Load payments
  Future<void> loadPayments() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _payments = await _paymentService.getPayments();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded();
      notifyListeners();
    }
  }

  /// Creates the backend payment record and receives Paystack checkout data.
  Future<PaymentModel?> initializePayment(
    TenancyAgreementModel agreement,
  ) async {
    if (!agreement.canPayRent) {
      setFailureMessage(
        'Rent payment is locked until the agreement is executed by both parties.',
      );
      notifyListeners();
      return null;
    }

    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final payment = await _paymentService.initializePayment(agreement.id);
      _upsertPayment(payment);
      _selectedReceipt = payment;
      return payment;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pays rent straight out of the tenant's vault balance.
  ///
  /// Returns the payment only when the backend put it in escrow. Any other
  /// outcome is a failure with a message on the controller: there is no
  /// checkout to fall back to here, and a vault payment that did not settle
  /// must never be reported as one that did.
  ///
  /// [vaultPin] is the tenant's 4-digit vault PIN, which the backend requires
  /// on every vault-funded payment.
  Future<PaymentModel?> payRentFromVault(
    TenancyAgreementModel agreement, {
    required String vaultPin,
  }) async {
    if (!agreement.canPayRent) {
      setFailureMessage(
        'Rent payment is locked until the agreement is executed by both parties.',
      );
      notifyListeners();
      return null;
    }

    _isPayingFromVault = true;
    _vaultShortfall = null;
    _vaultBalanceFellShort = false;
    clearFailure();
    notifyListeners();

    // One key per agreement, kept until the payment settles, so a request
    // that times out and is retried debits the vault once.
    final key = _vaultPaymentKeys.putIfAbsent(
      agreement.id,
      () => 'vp-${agreement.id}-${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      final payment = await _paymentService.payFromVault(
        agreementId: agreement.id,
        idempotencyKey: key,
        vaultPin: vaultPin,
      );
      _upsertPayment(payment);
      _selectedReceipt = payment;

      if (payment.status != PaymentStatus.escrow) {
        // The backend accepted the request but the money is not held. Say so
        // rather than showing a receipt for a payment that did not happen.
        setFailureMessage(
          'This payment did not complete. It is ${payment.status.userFriendlyTitle.toLowerCase()}. '
          'Your vault has not been charged.',
        );
        return null;
      }

      _vaultPaymentKeys.remove(agreement.id);
      return payment;
    } on InsufficientVaultBalanceException catch (e) {
      captureFailure(e);
      // The backend quotes the gap when it can; when it does not, the screen
      // works it out from the balance it already holds so the top-up offer
      // still has a figure on it.
      _vaultBalanceFellShort = true;
      _vaultShortfall = e.shortfall;
      return null;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isPayingFromVault = false;
      notifyListeners();
    }
  }

  /// Verifies the provider outcome. The backend is the source of truth for
  /// whether a payment is in escrow; Flutter never marks it paid locally.
  Future<PaymentModel?> verifyPayment(PaymentModel payment) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final verified = await _paymentService.verifyPayment(payment);
      _upsertPayment(verified);
      _selectedReceipt = verified;
      return verified;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Release Escrow Payment (Landlord)
  Future<bool> releaseEscrow(String paymentId) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final updated = await _paymentService.releaseEscrow(
        paymentId,
        demoOverride: true,
      );
      final index = _payments.indexWhere((p) => p.id == paymentId);
      if (index != -1) {
        _payments[index] = updated;
      }
      _selectedReceipt = updated;
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh escrow status/countdown for a payment. Used to keep the receipt
  /// screen in step with the backend-owned dispute window.
  Future<PaymentModel?> refreshEscrowStatus(String paymentId) async {
    try {
      final updated = await _paymentService.getEscrowStatus(paymentId);
      _upsertPayment(updated);
      _selectedReceipt = updated;
      notifyListeners();
      return updated;
    } catch (e) {
      captureFailure(e);
      notifyListeners();
      return null;
    }
  }

  /// Raise a dispute against an escrow payment (Tenant).
  Future<PaymentModel?> disputePayment(
    String paymentId, {
    String? reason,
  }) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final disputed = await _paymentService.disputePayment(
        paymentId,
        reason: reason,
      );
      _upsertPayment(disputed);
      _selectedReceipt = disputed;
      return disputed;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get Payment Receipt.
  ///
  /// The receipt payload is a superset of the escrow one, carrying the
  /// escrow/dispute fields *plus* property, unit, and landlord email, so
  /// screens needing the full picture should prefer this over
  /// [refreshEscrowStatus].
  Future<PaymentModel?> loadReceipt(String paymentId) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final receipt = await _paymentService.getPaymentReceipt(paymentId);
      _upsertPayment(receipt);
      _selectedReceipt = receipt;
      return receipt;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _upsertPayment(PaymentModel payment) {
    final existingIndex = _payments.indexWhere((item) => item.id == payment.id);
    if (existingIndex == -1) {
      _payments.insert(0, payment);
    } else {
      _payments[existingIndex] = payment;
    }
  }
}
