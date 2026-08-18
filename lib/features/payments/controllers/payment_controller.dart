import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/session_scope.dart';
import '../../agreements/models/agreement_model.dart';
import '../models/payment_model.dart';
import '../services/payment_service.dart';

class PaymentController extends ChangeNotifier
    implements SessionScopedController {
  final PaymentService _paymentService;

  PaymentController({PaymentService? paymentService})
    : _paymentService = paymentService ?? PaymentService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<PaymentModel> _payments = [];
  List<PaymentModel> get payments => _payments;

  PaymentModel? _selectedReceipt;
  PaymentModel? get selectedReceipt => _selectedReceipt;

  @override
  void resetSessionState() {
    _payments = [];
    _selectedReceipt = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Load payments
  Future<void> loadPayments() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _payments = await _paymentService.getPayments();
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates the backend payment record and receives Paystack checkout data.
  Future<PaymentModel?> initializePayment(
    TenancyAgreementModel agreement,
  ) async {
    if (!agreement.canPayRent) {
      _errorMessage =
          'Rent payment is locked until the agreement is executed by both parties.';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final payment = await _paymentService.initializePayment(agreement.id);
      _upsertPayment(payment);
      _selectedReceipt = payment;
      return payment;
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Verifies the provider outcome. The backend is the source of truth for
  /// whether a payment is in escrow; Flutter never marks it paid locally.
  Future<PaymentModel?> verifyPayment(PaymentModel payment) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final verified = await _paymentService.verifyPayment(payment);
      _upsertPayment(verified);
      _selectedReceipt = verified;
      return verified;
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Release Escrow Payment (Landlord)
  Future<bool> releaseEscrow(String paymentId) async {
    _isLoading = true;
    _errorMessage = null;
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
      _errorMessage = friendlyErrorMessage(e);
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
      _errorMessage = friendlyErrorMessage(e);
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
    _errorMessage = null;
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
      _errorMessage = friendlyErrorMessage(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get Payment Receipt.
  ///
  /// The receipt payload is a superset of the escrow one — it carries the
  /// escrow/dispute fields *plus* property, unit, and landlord email — so
  /// screens needing the full picture should prefer this over
  /// [refreshEscrowStatus].
  Future<PaymentModel?> loadReceipt(String paymentId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final receipt = await _paymentService.getPaymentReceipt(paymentId);
      _upsertPayment(receipt);
      _selectedReceipt = receipt;
      return receipt;
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
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
