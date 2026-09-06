import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../payments/controllers/payment_controller.dart';
import '../../payments/models/payment_model.dart';
import '../../payments/views/payment_receipt_modal.dart';
import '../../payouts/views/payout_account_screen.dart';
import '../controllers/agreement_controller.dart';
import '../models/agreement_model.dart';
import 'widgets/rent_plan_picker.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/landa_busy.dart';

class CreateAgreementModal extends StatefulWidget {
  final String unitId;
  final String unitNumber;
  final String? assignedTenantId;

  const CreateAgreementModal({
    super.key,
    required this.unitId,
    required this.unitNumber,
    this.assignedTenantId,
  });

  @override
  State<CreateAgreementModal> createState() => _CreateAgreementModalState();
}

class _CreateAgreementModalState extends State<CreateAgreementModal> {
  final _tenantIdController = TextEditingController();
  final _rentAmountController = TextEditingController(text: '450000.00');
  final _startDateController = TextEditingController(text: '2026-09-01');
  final _endDateController = TextEditingController(text: '2027-08-31');
  final _rulesController = TextEditingController(
    text: 'No illegal activity. Keep shared areas clean.',
  );

  /// Matches the backend's own default, so leaving the picker alone sends the
  /// tenancy everyone expects.
  RentPlan _rentPlan = RentPlan.fallback;

  @override
  void initState() {
    super.initState();
    if (widget.assignedTenantId != null) {
      _tenantIdController.text = widget.assignedTenantId!;
    }
  }

  @override
  void dispose() {
    _tenantIdController.dispose();
    _rentAmountController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  void _submit() async {
    final tenantId = _tenantIdController.text.trim();
    final rent = _rentAmountController.text.trim();
    final startDate = _startDateController.text.trim();
    final endDate = _endDateController.text.trim();
    final rules = _rulesController.text.trim();

    if (tenantId.isEmpty ||
        rent.isEmpty ||
        startDate.isEmpty ||
        endDate.isEmpty) {
      LandaToast.error(context, 'Please fill in all required fields.');
      return;
    }

    if (double.tryParse(rent) == null || double.parse(rent) <= 0) {
      LandaToast.error(context, 'Rent amount must be greater than zero.');
      return;
    }

    final parsedStartDate = DateTime.tryParse(startDate);
    final parsedEndDate = DateTime.tryParse(endDate);
    if (parsedStartDate == null ||
        parsedEndDate == null ||
        !parsedEndDate.isAfter(parsedStartDate)) {
      LandaToast.error(
        context,
        'Use YYYY-MM-DD dates with an end date after the start date.',
      );
      return;
    }

    final controller = context.read<AgreementController>();
    final newAgreement = await controller.createAgreement(
      unitId: widget.unitId,
      tenantId: tenantId,
      rentAmount: rent,
      startDate: startDate,
      endDate: endDate,
      rules: rules,
      rentPlan: _rentPlan,
    );

    if (!mounted) return;

    if (newAgreement != null) {
      LandaToast.success(
        context,
        'Agreement created as PENDING. The tenant can now review and sign it.',
      );
      Navigator.pop(context, true);
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
                Text(
                  'Create Agreement (${widget.unitNumber})',
                  style: AppTheme.sectionTitle(
                    context,
                    color: AppTheme.primaryColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tenantIdController,
              decoration: const InputDecoration(
                labelText: 'TENANT EMAIL, PHONE, OR UUID',
                hintText: 'e.g. tenant@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rentAmountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // Redraws the plan picker's instalment preview as the annual
              // figure is typed.
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'RENT AMOUNT (₦ / YEAR)',
                hintText: '450000.00',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Directly under the amount: the figure above is the year's rent,
            // and this decides how the tenant is asked for it.
            Text(
              'HOW OFTEN RENT IS DUE',
              style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
            ),
            const SizedBox(height: 10),
            RentPlanPicker(
              selected: _rentPlan,
              annualRent: _rentAmountController.text.trim(),
              onChanged: (plan) => setState(() => _rentPlan = plan),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startDateController,
                    decoration: const InputDecoration(
                      labelText: 'START DATE',
                      hintText: '2026-09-01',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endDateController,
                    decoration: const InputDecoration(
                      labelText: 'END DATE',
                      hintText: '2027-08-31',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rulesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'TENANCY RULES',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: Consumer<AgreementController>(
                builder: (context, controller, _) {
                  return ElevatedButton(
                    onPressed: controller.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                    ),
                    child: controller.isLoading
                        ? const LandaBusyDots(color: Colors.white, size: 6)
                        : const Text(
                            'Send Tenancy Agreement',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ViewAgreementModal extends StatelessWidget {
  final TenancyAgreementModel agreement;

  const ViewAgreementModal({super.key, required this.agreement});

  void _showPaystackPaymentModal(BuildContext mainContext) {
    showModalBottomSheet(
      context: mainContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        PaymentModel? payment;
        bool isBusy = false;
        String? errorMessage;
        // Tracks whether checkout was actually opened, so an unrelated
        // app-resume (e.g. a notification) doesn't trigger a verify call.
        bool hasOpenedCheckout = false;
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> showReceipt(PaymentModel confirmedPayment) async {
              await mainContext.read<PaymentController>().loadPayments();
              if (!mainContext.mounted) return;
              Navigator.pop(ctx);
              LandaToast.success(
                mainContext,
                'Payment confirmed and held in escrow.',
              );
              showModalBottomSheet(
                context: mainContext,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (_) => PaymentReceiptModal(payment: confirmedPayment),
              );
            }

            Future<void> openCheckout() async {
              final url = payment?.authorizationUrl;
              final checkoutUri = url == null ? null : Uri.tryParse(url);
              if (checkoutUri == null || !checkoutUri.hasScheme) {
                setState(() {
                  errorMessage =
                      'The backend did not return a valid Paystack checkout URL.';
                });
                return;
              }
              setState(() {
                isBusy = true;
                errorMessage = null;
              });
              // Keep checkout inside the app (SFSafariViewController on iOS,
              // Custom Tabs on Android) instead of switching out to Safari.
              final opened = await launchUrl(
                checkoutUri,
                mode: LaunchMode.inAppWebView,
                webViewConfiguration: const WebViewConfiguration(
                  enableJavaScript: true,
                  enableDomStorage: true,
                ),
              );
              if (!ctx.mounted) return;
              setState(() {
                isBusy = false;
                hasOpenedCheckout = opened;
                if (!opened) {
                  errorMessage =
                      'Unable to open Paystack checkout. Please try again.';
                }
              });
            }

            Future<void> initializeAndOpen() async {
              setState(() {
                isBusy = true;
                errorMessage = null;
              });
              final initialized = await mainContext
                  .read<PaymentController>()
                  .initializePayment(agreement);
              if (!ctx.mounted) return;
              if (initialized == null) {
                setState(() {
                  isBusy = false;
                  errorMessage =
                      mainContext.read<PaymentController>().errorMessage ??
                      'Unable to start payment. Please try again.';
                });
                return;
              }
              setState(() {
                isBusy = false;
                payment = initialized;
              });
              if (initialized.status == PaymentStatus.escrow) {
                await showReceipt(initialized);
              } else if (initialized.status == PaymentStatus.pending) {
                await openCheckout();
              }
            }

            // [silent] is used for the automatic check on app-resume: it
            // still confirms a successful payment (and shows the receipt),
            // but doesn't surface a "still pending" error for what is just
            // a background poll rather than an explicit user action.
            Future<void> verifyCheckout({bool silent = false}) async {
              if (payment == null || isBusy) return;
              setState(() {
                isBusy = true;
                if (!silent) errorMessage = null;
              });
              final verified = await mainContext
                  .read<PaymentController>()
                  .verifyPayment(payment!);
              if (!ctx.mounted) return;
              setState(() => isBusy = false);
              if (verified == null) {
                if (!silent) {
                  setState(() {
                    errorMessage =
                        mainContext.read<PaymentController>().errorMessage ??
                        'Unable to verify payment. Please try again.';
                  });
                }
                return;
              }
              setState(() => payment = verified);
              if (verified.status == PaymentStatus.escrow) {
                await showReceipt(verified);
              } else if (verified.status == PaymentStatus.pending) {
                if (!silent) {
                  setState(() {
                    errorMessage =
                        'Payment is still pending. Complete checkout, then verify again.';
                  });
                }
              } else {
                setState(() {
                  errorMessage =
                      'Paystack did not confirm this payment. You can start again.';
                });
              }
            }

            return _AppResumeListener(
              onResume: () {
                // Paystack checkout runs in an in-app browser, not a
                // separate app, so there's no redirect callback into
                // Flutter when it closes. Re-check the payment the moment
                // the user comes back instead of waiting for them to find
                // the manual "Verify payment" button.
                if (hasOpenedCheckout &&
                    payment != null &&
                    payment!.status == PaymentStatus.pending &&
                    !isBusy) {
                  verifyCheckout(silent: true);
                }
              },
              child: Padding(
                padding: EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
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
                              Icons.shield_outlined,
                              color: AppTheme.actionColor,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Landa Escrow Payment',
                              style: AppTheme.sectionTitle(
                                context,
                                color: AppTheme.primaryColor,
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
                    const SizedBox(height: 8),
                    Text(
                      'Pay securely with Paystack. Confirmed rent is held in 48-hour escrow.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.secondaryTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleSurfaceColor(context),
                        borderRadius: AppTheme.cornerMd,
                        border: Border.all(
                          color: AppTheme.borderColor(context),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Property Unit:',
                                style: TextStyle(
                                  color: AppTheme.secondaryTextColor(context),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Unit ${agreement.unitNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                agreement.plan == RentPlan.unknown
                                    ? 'Rent Amount:'
                                    : 'Rent (${agreement.plan.label.toLowerCase()}):',
                                style: TextStyle(
                                  color: AppTheme.secondaryTextColor(context),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                LandaCurrency.perYear(agreement.rentAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Escrow Release Period:',
                                style: TextStyle(
                                  color: AppTheme.secondaryTextColor(context),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '48 Hours',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (payment != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          children: [
                            _paymentSummaryRow(
                              'Rent',
                              LandaCurrency.format(payment!.amount),
                            ),
                            const SizedBox(height: 8),
                            _paymentSummaryRow(
                              'Platform fee',
                              LandaCurrency.format(payment!.platformFee),
                            ),
                            const Divider(height: 20),
                            _paymentSummaryRow(
                              'Total to pay',
                              LandaCurrency.format(payment!.totalAmount),
                              emphasized: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (errorMessage != null) ...[
                      Text(
                        errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isBusy
                            ? null
                            : payment == null
                            ? initializeAndOpen
                            : openCheckout,
                        icon: isBusy
                            ? const SizedBox()
                            : const Icon(
                                Icons.open_in_new,
                                color: Colors.white,
                                size: 18,
                              ),
                        label: isBusy
                            ? const LandaBusyDots(color: Colors.white, size: 6)
                            : Text(
                                payment == null
                                    ? 'Continue to Paystack'
                                    : 'Open Paystack Checkout',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.actionColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    if (payment?.status == PaymentStatus.pending) ...[
                      const SizedBox(height: 12),
                      Text(
                        'After checkout closes or you return to Landa, verify the payment below.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: isBusy ? null : verifyCheckout,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text(
                            'I completed checkout, verify payment',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Signs, and handles the landlord payout gate.
  ///
  /// A landlord can reach final signing without payout details: the backend
  /// deliberately allows everything up to execution, so a `403
  /// PAYOUT_ACCOUNT_REQUIRED` here is a prompt, not an error. Offer setup,
  /// then retry the same call once the account verifies.
  Future<void> _signAgreement(
    BuildContext context,
    AgreementController controller, {
    required bool isTenantSigning,
  }) async {
    final success = await controller.signAgreement(agreement.id);
    if (!context.mounted) return;

    if (success) {
      LandaToast.success(
        context,
        isTenantSigning
            ? 'Agreement signed. Waiting for your landlord to counter-sign.'
            : 'Agreement executed. Rent payment is now unlocked.',
      );
      Navigator.pop(context);
      return;
    }

    if (controller.errorNeedsPayoutAccount) {
      final verified = await Navigator.push<bool>(
        context,
        FadePageRoute(
          page: PayoutAccountScreen(
            blockedReason:
                'Add and verify your payout account to execute this agreement. '
                'Rent released from escrow is paid into this account.',
          ),
        ),
      );
      if (!context.mounted || verified != true) return;
      // Payout verified: retry the exact action that was blocked.
      await _signAgreement(
        context,
        controller,
        isTenantSigning: isTenantSigning,
      );
      return;
    }

    if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  Widget _paymentSummaryRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: emphasized ? FontWeight.bold : null),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: emphasized ? 16 : 14,
            color: emphasized ? AppTheme.primaryColor : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().currentUser;
    final isTenant = user?.role == UserRole.tenant;
    final isExecuted = agreement.isExecuted;

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
                Text(
                  'Tenancy Bridge Agreement',
                  style: AppTheme.sectionTitle(
                    context,
                    color: AppTheme.primaryColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isExecuted
                    ? Colors.green.shade100
                    : Colors.amber.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                agreement.progressTitle.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isExecuted
                      ? Colors.green.shade800
                      : Colors.amber.shade900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _infoRow(
              context,
              'Property Unit:',
              '${agreement.property?.name ?? "Property"} - Unit ${agreement.unitNumber}',
            ),
            _infoRow(context, 'Landlord:', agreement.landlordEmail),
            _infoRow(context, 'Tenant:', agreement.tenantEmail),
            _infoRow(
              context,
              'Rent Amount:',
              LandaCurrency.perYear(agreement.rentAmount),
            ),
            if (agreement.plan != RentPlan.unknown)
              _infoRow(context, 'Paid:', agreement.plan.label),
            _infoRow(
              context,
              'Lease Term:',
              '${agreement.startDate} to ${agreement.endDate}',
            ),
            _infoRow(
              context,
              'Tenant signature:',
              agreement.hasTenantSigned ? 'Signed' : 'Awaiting tenant',
            ),
            _infoRow(
              context,
              'Landlord signature:',
              agreement.hasLandlordSigned ? 'Signed' : 'Awaiting landlord',
            ),
            _infoRow(
              context,
              'Rent payment:',
              agreement.canPayRent ? 'Unlocked' : 'Locked until execution',
            ),
            const SizedBox(height: 16),
            Text('AGREEMENT RULES & TERMS', style: AppTheme.labelText(context)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // Themed rather than a fixed near-white: this panel used to be
                // grey.shade50 with default-coloured text on it, which in dark
                // mode is white on near-white, leaving the terms of the
                // agreement invisible.
                color: AppTheme.subtleSurfaceColor(context),
                borderRadius: AppTheme.cornerSm,
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Text(
                agreement.rules.isNotEmpty
                    ? agreement.rules
                    : 'Standard terms apply.',
                style: AppTheme.bodyText(
                  context,
                  color: AppTheme.readingTextColor(context),
                ).copyWith(height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            Consumer<AgreementController>(
              builder: (context, controller, _) {
                if (isTenant && agreement.canPayRent) {
                  return Column(
                    children: [
                      _stateNotice(
                        icon: Icons.verified,
                        color: Colors.green,
                        message:
                            'Both parties have signed. Rent payment is unlocked.',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Popping this bottom sheet deactivates `context`
                            // shortly after this callback returns. Capture
                            // the Navigator's own (stable, still-mounted)
                            // context first so the Paystack modal (and the
                            // Provider reads inside its async callbacks)
                            // keep working after the pop finishes.
                            final navigatorContext = Navigator.of(
                              context,
                            ).context;
                            Navigator.pop(context);
                            _showPaystackPaymentModal(navigatorContext);
                          },
                          icon: const Icon(Icons.payments, color: Colors.white),
                          label: Text(
                            'Pay Rent into Escrow (${LandaCurrency.format(agreement.rentAmount)})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.actionColor,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (isTenant && !agreement.canTenantSign) {
                  return _stateNotice(
                    icon: agreement.hasTenantSigned
                        ? Icons.hourglass_top
                        : Icons.lock_outline,
                    color: Colors.amber.shade800,
                    message: agreement.hasTenantSigned
                        ? 'You have signed. The agreement remains pending until your landlord counter-signs.'
                        : 'This agreement is not available for signing.',
                  );
                }

                if (!isTenant && !agreement.canLandlordSign) {
                  return _stateNotice(
                    icon: agreement.isExecuted
                        ? Icons.verified
                        : Icons.hourglass_top,
                    color: agreement.isExecuted
                        ? Colors.green
                        : Colors.amber.shade800,
                    message: agreement.isExecuted
                        ? 'This agreement has been executed and rent payment is unlocked.'
                        : 'Waiting for the tenant to sign before you can counter-sign.',
                  );
                }

                final isTenantSigning = isTenant;
                return SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: controller.isLoading
                        ? null
                        : () => _signAgreement(
                            context,
                            controller,
                            isTenantSigning: isTenantSigning,
                          ),
                    icon: controller.isLoading
                        ? const SizedBox()
                        : const Icon(Icons.draw, color: Colors.white),
                    label: controller.isLoading
                        ? const LandaBusyDots(color: Colors.white, size: 6)
                        : Text(
                            isTenantSigning
                                ? 'Sign Tenancy Agreement'
                                : 'Counter-Sign & Execute Agreement',
                            style: const TextStyle(
                              fontSize: 16,
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

  Widget _stateNotice({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.secondaryTextColor(context),
              fontSize: 13,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppTheme.primaryTextColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calls [onResume] whenever the app returns to the foreground while
/// [child] is mounted. Used to re-check payment status the moment the user
/// comes back from the in-app Paystack checkout browser.
class _AppResumeListener extends StatefulWidget {
  final VoidCallback onResume;
  final Widget child;

  const _AppResumeListener({required this.onResume, required this.child});

  @override
  State<_AppResumeListener> createState() => _AppResumeListenerState();
}

class _AppResumeListenerState extends State<_AppResumeListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.onResume();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
