import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../payouts/views/payout_account_screen.dart';
import '../controllers/payment_controller.dart';
import '../models/payment_model.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/landa_busy.dart';

class PaymentReceiptModal extends StatefulWidget {
  final PaymentModel payment;

  const PaymentReceiptModal({super.key, required this.payment});

  @override
  State<PaymentReceiptModal> createState() => _PaymentReceiptModalState();
}

class _PaymentReceiptModalState extends State<PaymentReceiptModal> {
  late PaymentModel _payment = widget.payment;

  /// Local mirror of the backend countdown, ticked down for a smooth display.
  /// The backend remains the source of truth for whether a dispute is still
  /// allowed: this only drives the visible timer.
  int? _secondsRemaining;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = _payment.escrowSecondsRemaining;
    // List payloads omit escrow, property, and unit details, so always pull
    // the full receipt when this opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshReceipt());
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _secondsRemaining;
      if (remaining == null || remaining <= 0) return;
      if (!mounted) return;
      setState(() => _secondsRemaining = remaining - 1);
      // Window just elapsed: re-sync so can_dispute/is_ready_for_release
      // reflect the backend rather than our local guess.
      if (remaining - 1 <= 0) _refreshReceipt();
    });
  }

  /// Re-reads the full receipt. Deliberately not the escrow endpoint: that
  /// payload omits property/unit, so swapping it in would blank those rows.
  Future<void> _refreshReceipt() async {
    final updated = await context.read<PaymentController>().loadReceipt(
      _payment.id,
    );
    if (!mounted || updated == null) return;
    setState(() {
      _payment = updated;
      _secondsRemaining = updated.escrowSecondsRemaining;
    });
  }

  Future<void> _raiseDispute() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DisputeReasonDialog(),
    );
    if (reason == null || !mounted) return;

    final controller = context.read<PaymentController>();
    final disputed = await controller.disputePayment(
      _payment.id,
      reason: reason,
    );
    if (!mounted) return;

    if (disputed != null) {
      setState(() {
        _payment = disputed;
        _secondsRemaining = disputed.escrowSecondsRemaining;
      });
      LandaToast.success(
        context,
        'Dispute submitted. Your landlord has been notified and this payment is on hold.',
      );
      // The dispute response is not documented to carry property/unit, so
      // re-read the full receipt to keep those rows populated.
      await _refreshReceipt();
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  /// Releases escrow, handling the landlord payout gate.
  ///
  /// The backend initiates the provider transfer before marking the payment
  /// released, so it rejects this outright without verified payout details.
  /// Treat that as a prompt and retry once the account verifies.
  Future<void> _releaseEscrow() async {
    final controller = context.read<PaymentController>();
    final success = await controller.releaseEscrow(_payment.id);
    if (!mounted) return;

    if (success) {
      LandaToast.success(context, 'Escrow released successfully!');
      Navigator.pop(context);
      return;
    }

    if (controller.errorNeedsPayoutAccount) {
      final verified = await Navigator.push<bool>(
        context,
        FadePageRoute(
          page: const PayoutAccountScreen(
            blockedReason:
                'Add and verify your payout account before releasing escrow. '
                'This is the account the rent is transferred into.',
          ),
        ),
      );
      if (!mounted || verified != true) return;
      await _releaseEscrow();
      return;
    }

    if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().currentUser;
    final isLandlord = user?.role == UserRole.owner;
    final primaryTextColor = AppTheme.primaryTextColor(context);

    final status = _payment.status;
    final isReleased = status == PaymentStatus.released;
    final isEscrow = status == PaymentStatus.escrow;
    final isDisputed = status == PaymentStatus.disputed;
    final isFailed = status == PaymentStatus.failed;

    final statusColor = isDisputed
        ? AppTheme.disputeColor
        : isReleased || isEscrow
        ? AppTheme.successColor
        : isFailed
        ? Colors.red
        : AppTheme.primaryColor;

    final statusSurface = isDisputed
        ? AppTheme.disputeSurface(context)
        : isReleased || isEscrow
        ? AppTheme.successSurface(context)
        : isFailed
        ? Colors.red.shade50
        : AppTheme.vacantSurface(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isDisputed
                          ? Icons.gavel_outlined
                          : isFailed
                          ? Icons.error_outline
                          : isEscrow || isReleased
                          ? Icons.verified_outlined
                          : Icons.hourglass_top_outlined,
                      color: statusColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Payment Receipt',
                      style: AppTheme.sectionTitle(
                        context,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Text(
                    LandaCurrency.format(_payment.amount),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (isEscrow && _secondsRemaining != null)
              _EscrowCountdownCard(secondsRemaining: _secondsRemaining!),

            if (isDisputed) _DisputeNoticeCard(payment: _payment),

            const SizedBox(height: 8),
            Divider(color: AppTheme.borderColor(context)),
            const SizedBox(height: 12),
            _receiptRow(context, 'Transaction Ref:', _payment.reference),
            if (_payment.provider.isNotEmpty)
              _receiptRow(
                context,
                'Provider:',
                _payment.provider.toUpperCase(),
              ),
            _receiptRow(
              context,
              'Rent amount:',
              LandaCurrency.format(_payment.amount),
            ),
            _receiptRow(
              context,
              'Platform fee:',
              LandaCurrency.format(_payment.platformFee),
            ),
            _receiptRow(
              context,
              'Total paid:',
              LandaCurrency.format(_payment.totalAmount),
            ),

            // Property/unit context, returned by GET /payments/{id}/.
            if (_payment.property != null) ...[
              _receiptDivider(context),
              _receiptRow(context, 'Property:', _payment.property!.name),
              _receiptRow(
                context,
                'Address:',
                [
                  _payment.property!.address,
                  _payment.property!.city,
                  _payment.property!.state,
                ].where((part) => part.isNotEmpty).join(', '),
              ),
            ],
            if (_payment.unit != null) ...[
              _receiptRow(context, 'Unit:', _payment.unit!.unitNumber),
              _receiptRow(
                context,
                'Layout:',
                '${_payment.unit!.bedrooms} bed · ${_payment.unit!.bathrooms} bath',
              ),
            ],
            if (_payment.property != null || _payment.unit != null)
              _receiptDivider(context),

            _receiptRow(context, 'Tenant Email:', _payment.tenantEmail),
            if (_payment.landlordEmail != null &&
                _payment.landlordEmail!.isNotEmpty)
              _receiptRow(context, 'Landlord Email:', _payment.landlordEmail!),
            if (_payment.agreementStatus.isNotEmpty)
              _receiptRow(context, 'Agreement:', _payment.agreementStatus),
            if (_payment.paidAt.isNotEmpty)
              _receiptRow(context, 'Paid At:', _formatDate(_payment.paidAt)),
            if (_payment.escrowReleaseAt.isNotEmpty)
              _receiptRow(
                context,
                'Escrow Auto Release:',
                _formatDate(_payment.escrowReleaseAt),
              ),
            if (_payment.releasedAt != null)
              _receiptRow(
                context,
                'Released At:',
                _formatDate(_payment.releasedAt!),
              ),
            const SizedBox(height: 24),

            // Tenant: raise a dispute while the backend says the window is open.
            if (!isLandlord && _payment.canDispute)
              Consumer<PaymentController>(
                builder: (context, controller, _) => SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: controller.isLoading ? null : _raiseDispute,
                    icon: const Icon(Icons.gavel_outlined),
                    label: const Text('Raise a dispute'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.disputeColor,
                      side: BorderSide(
                        color: AppTheme.disputeColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),

            // Landlord: release is blocked by the backend while disputed.
            if (isLandlord && isDisputed)
              _NoticeBanner(
                icon: Icons.lock_outline,
                color: AppTheme.disputeColor,
                message:
                    'This payment is disputed. Escrow cannot be released until the dispute is resolved.',
              ),

            if (isLandlord && isEscrow)
              Consumer<PaymentController>(
                builder: (context, controller, _) {
                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: controller.isLoading ? null : _releaseEscrow,
                      icon: controller.isLoading
                          ? const SizedBox()
                          : const Icon(Icons.key, color: Colors.white),
                      label: controller.isLoading
                          ? const LandaBusyDots(color: Colors.white, size: 6)
                          : const Text(
                              'Release Escrow (Demo Override)',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.actionColor,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _receiptDivider(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Divider(color: AppTheme.borderColor(context), height: 1),
  );

  Widget _receiptRow(BuildContext context, String label, String value) {
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: secondaryTextColor, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String value) =>
      value.split('.').first.replaceAll('T', ' ');
}

/// Live 48-hour escrow countdown.
class _EscrowCountdownCard extends StatelessWidget {
  final int secondsRemaining;

  const _EscrowCountdownCard({required this.secondsRemaining});

  @override
  Widget build(BuildContext context) {
    final elapsed = secondsRemaining <= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.successSurface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_clock_outlined,
                size: 18,
                color: AppTheme.successColor,
              ),
              const SizedBox(width: 6),
              Text(
                elapsed ? 'Escrow window closed' : 'Held safely in escrow',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.successColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            elapsed ? 'Ready for release' : _format(secondsRemaining),
            style: TextStyle(
              fontSize: elapsed ? 16 : 26,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (!elapsed) ...[
            const SizedBox(height: 4),
            Text(
              'until funds are released to your landlord',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _format(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }
}

class _DisputeNoticeCard extends StatelessWidget {
  final PaymentModel payment;

  const _DisputeNoticeCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.disputeSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.disputeColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.gavel_outlined,
                size: 18,
                color: AppTheme.disputeColor,
              ),
              SizedBox(width: 6),
              Text(
                'Dispute raised',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.disputeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'These funds are on hold and cannot be released while the dispute is open.',
            style: TextStyle(fontSize: 12, color: AppTheme.disputeColor),
          ),
          if (payment.disputeReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${payment.disputeReason}',
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.disputeColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _NoticeBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Collects an optional short reason before submitting a dispute.
class _DisputeReasonDialog extends StatefulWidget {
  @override
  State<_DisputeReasonDialog> createState() => _DisputeReasonDialogState();
}

class _DisputeReasonDialogState extends State<_DisputeReasonDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.disputeSurface(context),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.gavel_outlined,
              size: 20,
              color: AppTheme.disputeColor,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Raise a dispute',
            style: AppTheme.sectionTitle(context, color: AppTheme.primaryColor),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your landlord will be notified and these funds stay on hold until the dispute is resolved.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            maxLength: 300,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'WHAT WENT WRONG?',
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: AppTheme.mutedTextColor(context),
              ),
              hintText: 'e.g. The unit was not handed over as agreed.',
              hintStyle: TextStyle(
                fontSize: 13,
                color: AppTheme.mutedTextColor(context),
              ),
              filled: true,
              fillColor: AppTheme.inputFillColor(context),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.borderColor(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppTheme.disputeColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.secondaryTextColor(context),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(context, _reasonController.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.disputeColor,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            'Submit dispute',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
