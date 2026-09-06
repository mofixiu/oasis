import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/payment_model.dart';

class PaymentService {
  final ApiClient _apiClient;

  PaymentService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// List payments for authenticated user
  Future<List<PaymentModel>> getPayments() async {
    debugPrint(
      '[PAYMENT SERVICE] Fetching payments GET ${ApiConstants.paymentsEndpoint}',
    );
    final response = await _apiClient.get(ApiConstants.paymentsEndpoint);
    if (response is List) {
      final payments = response
          .map((item) => PaymentModel.fromJson(item))
          .toList();
      debugPrint('[PAYMENT SERVICE] Loaded ${payments.length} payment records');
      return payments;
    }
    return [];
  }

  /// Starts the backend-owned Paystack checkout flow for an executed agreement.
  Future<PaymentModel> initializePayment(String agreementId) async {
    debugPrint(
      '[PAYMENT SERVICE] Initializing rent payment POST ${ApiConstants.paymentsEndpoint} for Agreement ID $agreementId',
    );
    final response = await _apiClient.post(
      ApiConstants.paymentsEndpoint,
      body: {'agreement': agreementId},
    );
    final payment = PaymentModel.fromJson(response);
    debugPrint(
      '[PAYMENT SERVICE] Payment initialized: Ref=${payment.reference}, Amount=₦${payment.totalAmount}, Status=${payment.status.label}',
    );
    return payment;
  }

  /// Pays rent out of the tenant's own vault balance instead of a card.
  ///
  /// There is no provider checkout and no verify step: the money is already
  /// inside Landa, so the backend debits the vault and puts the payment into
  /// escrow in one call. A response that is *not* in escrow therefore means
  /// the debit did not happen, and the caller must not report success.
  ///
  /// [idempotencyKey] is reused across retries of the same intent, so a call
  /// that times out and is tried again cannot debit the vault twice.
  ///
  /// [vaultPin] is the tenant's 4-digit vault PIN, which the backend requires
  /// on every payment funded from the vault. It is passed straight through,
  /// never stored, and never logged.
  Future<PaymentModel> payFromVault({
    required String agreementId,
    required String idempotencyKey,
    required String vaultPin,
  }) async {
    debugPrint(
      '[PAYMENT SERVICE] Paying rent from vault POST ${ApiConstants.paymentsEndpoint} for Agreement ID $agreementId',
    );
    final response = await _apiClient.post(
      ApiConstants.paymentsEndpoint,
      body: {
        'agreement': agreementId,
        'source': 'VAULT',
        'vault_pin': vaultPin,
      },
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    final payment = PaymentModel.fromJson(response);
    debugPrint(
      '[PAYMENT SERVICE] Vault payment: Ref=${payment.reference}, '
      'Amount=₦${payment.totalAmount}, Status=${payment.status.label}',
    );
    return payment;
  }

  /// Confirms the provider result with the backend after checkout closes.
  Future<PaymentModel> verifyPayment(PaymentModel payment) async {
    final endpoint = ApiConstants.verifyPaymentEndpoint(payment.id);
    debugPrint(
      '[PAYMENT SERVICE] Verifying payment ID ${payment.id} POST $endpoint',
    );
    final response = await _apiClient.post(
      endpoint,
      body: payment.providerReference.isEmpty
          ? <String, dynamic>{}
          : {'reference': payment.providerReference},
    );
    return PaymentModel.fromJson(response);
  }

  /// Release escrow payment (Landlord)
  Future<PaymentModel> releaseEscrow(
    String paymentId, {
    bool demoOverride = true,
  }) async {
    final endpoint = ApiConstants.releaseEscrowEndpoint(paymentId);
    debugPrint(
      '[PAYMENT SERVICE] Releasing escrow payment ID $paymentId POST $endpoint (Demo Override: $demoOverride)',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {'demo_override': demoOverride},
    );
    final payment = PaymentModel.fromJson(response);
    debugPrint(
      '[PAYMENT SERVICE] Escrow released successfully! Ref=${payment.reference}, Status=${payment.status.label}',
    );
    return payment;
  }

  /// Get escrow status, countdown, and dispute availability.
  ///
  /// The backend owns the dispute-window rules: use `escrowSecondsRemaining`
  /// and `canDispute` from this response rather than computing them locally.
  Future<PaymentModel> getEscrowStatus(String paymentId) async {
    final endpoint = ApiConstants.escrowStatusEndpoint(paymentId);
    debugPrint(
      '⏳ [PAYMENT SERVICE] Fetching escrow status ID $paymentId GET $endpoint',
    );
    final response = await _apiClient.get(endpoint);
    final payment = PaymentModel.fromJson(response);
    debugPrint(
      '⏳ [PAYMENT SERVICE] Escrow status: ${payment.status.label}, '
      'Remaining=${payment.escrowSecondsRemaining}s, CanDispute=${payment.canDispute}',
    );
    return payment;
  }

  /// Raise a dispute against an escrow payment (Tenant, during the window)
  Future<PaymentModel> disputePayment(
    String paymentId, {
    String? reason,
  }) async {
    final endpoint = ApiConstants.disputePaymentEndpoint(paymentId);
    debugPrint(
      '[PAYMENT SERVICE] Disputing payment ID $paymentId POST $endpoint',
    );
    final response = await _apiClient.post(
      endpoint,
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    final payment = PaymentModel.fromJson(response);
    debugPrint(
      '[PAYMENT SERVICE] Dispute recorded. Status=${payment.status.label}',
    );
    return payment;
  }

  /// Get payment receipt/details
  Future<PaymentModel> getPaymentReceipt(String paymentId) async {
    final endpoint = ApiConstants.paymentReceiptEndpoint(paymentId);
    debugPrint(
      '[PAYMENT SERVICE] Fetching payment receipt ID $paymentId GET $endpoint',
    );
    final response = await _apiClient.get(endpoint);
    final payment = PaymentModel.fromJson(response);
    debugPrint(
      '[PAYMENT SERVICE] Payment receipt retrieved: Ref=${payment.reference}',
    );
    return payment;
  }
}
