import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/payout_controller.dart';
import 'bank_picker_sheet.dart';
import '../../../core/widgets/landa_busy.dart';

/// Payout setup, for whoever is withdrawing. Reachable from Settings, and
/// pushed directly when an action is blocked for want of a verified account:
/// a landlord's escrow release, or either role's vault withdrawal.
///
/// Pops `true` once the provider has verified the account, so a caller that
/// arrived here from a blocked action can retry it.
class PayoutAccountScreen extends StatefulWidget {
  /// Short explanation of what this is unblocking, shown as a banner when the
  /// user was sent here by a blocked action rather than from Settings.
  final String? blockedReason;

  const PayoutAccountScreen({super.key, this.blockedReason});

  @override
  State<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends State<PayoutAccountScreen>
    with AutoRefreshMixin<PayoutAccountScreen> {
  final _accountNumberController = TextEditingController();
  String? _bankName;

  /// Re-read on return and on resume as well as on mount. Verification of a
  /// bank account is the provider's to finish, not the app's, so the standing
  /// shown here can change while the landlord is looking at something else,
  /// and it used to sit on whatever the one opening fetch returned.
  @override
  Future<void> onAutoRefresh() async {
    final controller = context.read<PayoutController>();
    await controller.loadPayoutAccount();
    if (!mounted) return;
    // Prefill from the saved account so "update" is an edit, not a retype.
    // The account number arrives masked, so it is deliberately left blank:
    // the backend needs the real number again to re-verify. Only ever fills
    // a blank field, so a refresh landing mid-edit cannot move the bank the
    // landlord is part-way through choosing.
    final account = controller.account;
    if (account != null && account.hasDetails && _bankName == null) {
      setState(() => _bankName = account.bankName);
    }
    await controller.loadBanks();
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    super.dispose();
  }

  /// Asks the bank who owns the typed account number.
  ///
  /// Runs as soon as a bank is chosen and ten digits are entered, so the
  /// user confirms a name instead of typing one: the mismatch between a
  /// typed name and the bank's own spelling is what makes this step fail
  /// otherwise.
  Future<void> _maybeResolve() async {
    final controller = context.read<PayoutController>();
    final bank = _bankName;
    final number = _accountNumberController.text.trim();

    if (bank == null || bank.isEmpty || number.length != 10) {
      controller.clearResolution();
      return;
    }
    await controller.resolveAccount(bankName: bank, accountNumber: number);
  }

  Future<void> _pickBank() async {
    final controller = context.read<PayoutController>();
    await controller.loadBanks();
    if (!mounted) return;

    if (controller.banks.isEmpty) {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not load the bank list. Check your connection and try again.',
      );
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          BankPickerSheet(banks: controller.banks, selected: _bankName),
    );
    if (picked != null && mounted) {
      setState(() => _bankName = picked);
      // A different bank means the confirmed name no longer describes what is
      // on screen.
      controller.clearResolution();
      _maybeResolve();
    }
  }

  Future<void> _submit() async {
    final bank = _bankName;
    final number = _accountNumberController.text.trim();

    if (bank == null || bank.isEmpty) {
      LandaToast.error(context, 'Choose your bank.');
      return;
    }
    if (number.length != 10 || int.tryParse(number) == null) {
      LandaToast.error(context, 'Account number must be 10 digits.');
      return;
    }

    final controller = context.read<PayoutController>();
    // The confirmed resolution is the entire request. The backend rejects a
    // typed account name outright, so there is nothing to fall back to.
    if (controller.resolution == null) {
      LandaToast.error(context, 'Confirm your account details before saving.');
      return;
    }
    final verified = await controller.submitPayoutAccount();
    if (!mounted) return;

    if (verified) {
      // The capability flags live on the profile, so refresh it before
      // returning: the caller may immediately retry a gated action.
      await context.read<AuthController>().refreshProfile();
      if (!mounted) return;
      LandaToast.success(context, 'Payout account verified.');
      Navigator.pop(context, true);
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not verify this account. Check the details and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PayoutController>();
    final account = controller.account;
    final isUpdate = account != null && account.hasDetails;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        title: Text('Payout account', style: AppTheme.cardTitle(context)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LandaEntrance(
                    index: 0,
                    child: Column(
                      children: [
                        Container(
                          height: 72,
                          width: 72,
                          decoration: BoxDecoration(
                            color:
                                (controller.isVerified
                                        ? AppTheme.successColor
                                        : AppTheme.actionColor)
                                    .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            controller.isVerified
                                ? Icons.account_balance_rounded
                                : Icons.account_balance_outlined,
                            size: 30,
                            color: controller.isVerified
                                ? AppTheme.successColor
                                : AppTheme.actionColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isUpdate
                              ? 'Update payout account'
                              : 'Where should rent be paid?',
                          textAlign: TextAlign.center,
                          style: AppTheme.screenTitle(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isUpdate
                              ? 'We re-verify with your bank before replacing your saved details.'
                              : 'Rent released from escrow is transferred here. We verify the account with your bank before saving.',
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyText(
                            context,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (widget.blockedReason != null) ...[
                    const SizedBox(height: 20),
                    LandaEntrance(
                      index: 1,
                      child: _Banner(
                        icon: Icons.lock_outline,
                        color: AppTheme.disputeColor,
                        surface: AppTheme.disputeSurface(context),
                        message: widget.blockedReason!,
                      ),
                    ),
                  ],

                  if (controller.isVerified && account != null) ...[
                    const SizedBox(height: 20),
                    LandaEntrance(
                      index: 1,
                      child: _Banner(
                        icon: Icons.verified_rounded,
                        color: AppTheme.successColor,
                        surface: AppTheme.successSurface(context),
                        message:
                            'Verified. Paying out to ${account.bankName} ${account.accountNumber}.',
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  LandaEntrance(
                    index: 2,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor(context),
                        borderRadius: AppTheme.cornerLg,
                        border: Border.all(
                          color: AppTheme.borderColor(context),
                        ),
                        boxShadow: AppTheme.cardShadow(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel('BANK'),
                          const SizedBox(height: 8),
                          LandaPressable(
                            onTap: controller.isSubmitting ? null : _pickBank,
                            pressedScale: 0.995,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.inputFillColor(context),
                                borderRadius: AppTheme.cornerSm,
                                border: Border.all(
                                  color: AppTheme.borderColor(context),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_outlined,
                                    size: 19,
                                    color: AppTheme.mutedTextColor(context),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _bankName ?? 'Choose your bank',
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.bodyText(
                                        context,
                                        color: _bankName == null
                                            ? AppTheme.mutedTextColor(context)
                                            : AppTheme.primaryTextColor(
                                                context,
                                              ),
                                      ),
                                    ),
                                  ),
                                  if (controller.isLoading &&
                                      controller.banks.isEmpty)
                                    LandaBusyDots(
                                      color: AppTheme.mutedTextColor(context),
                                      size: 4,
                                    )
                                  else
                                    Icon(
                                      Icons.expand_more_rounded,
                                      color: AppTheme.mutedTextColor(context),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),
                          _FieldLabel('ACCOUNT NUMBER'),
                          const SizedBox(height: 8),
                          _PayoutField(
                            controller: _accountNumberController,
                            hint: isUpdate
                                ? 'Re-enter your 10-digit number'
                                : '10-digit account number',
                            icon: Icons.pin_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            onChanged: (_) => _maybeResolve(),
                          ),

                          // The bank tells us the name and the user
                          // confirms it. There is deliberately no field to
                          // type one in: the backend rejects a
                          // client-supplied account name, and typing it is
                          // what used to make correct details fail.
                          if (controller.isResolving) ...[
                            const SizedBox(height: 18),
                            const _ResolvingRow(),
                          ] else if (controller.resolution != null) ...[
                            const SizedBox(height: 18),
                            _ResolvedAccountCard(
                              accountName: controller.resolution!.accountName,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),
                  LandaEntrance(
                    index: 3,
                    child: LandaButton(
                      label: isUpdate
                          ? 'Verify & update account'
                          : 'Verify & save account',
                      icon: Icons.shield_outlined,
                      isBusy: controller.isSubmitting,
                      onPressed: controller.isSubmitting ? null : _submit,
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'We check the account with your bank and show you the name '
                    'they have on file. Nothing is saved until you confirm it.',
                    textAlign: TextAlign.center,
                    style: AppTheme.labelText(
                      context,
                    ).copyWith(letterSpacing: 0, fontSize: 11.5, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTheme.labelText(context));
}

class _PayoutField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// Fires on every keystroke. The account-number field uses it to ask the
  /// bank who owns the number as soon as the tenth digit lands.
  final ValueChanged<String>? onChanged;

  const _PayoutField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    style: AppTheme.bodyText(
      context,
      color: AppTheme.primaryTextColor(context),
    ),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.bodyText(
        context,
        color: AppTheme.mutedTextColor(context),
      ),
      prefixIcon: Icon(icon, size: 19, color: AppTheme.mutedTextColor(context)),
      filled: true,
      fillColor: AppTheme.inputFillColor(context),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppTheme.cornerSm,
        borderSide: BorderSide(color: AppTheme.borderColor(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppTheme.cornerSm,
        borderSide: const BorderSide(color: AppTheme.actionColor, width: 1.5),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color surface;
  final String message;

  const _Banner({
    required this.icon,
    required this.color,
    required this.surface,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: color.withValues(alpha: 0.28)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: AppTheme.bodyText(context, color: color)),
        ),
      ],
    ),
  );
}

/// Shown while the bank is being asked to confirm an account number.
class _ResolvingRow extends StatelessWidget {
  const _ResolvingRow();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      LandaBusyDots(color: AppTheme.mutedTextColor(context)),
      const SizedBox(width: 12),
      Text('Checking with your bank…', style: AppTheme.labelText(context)),
    ],
  );
}

/// The name the bank returned, for the user to recognise.
///
/// Banks store names surname-first and often abbreviate, so this rarely
/// matches how someone would write their own name, which is exactly why it
/// is shown for confirmation rather than compared against typed text.
class _ResolvedAccountCard extends StatelessWidget {
  final String accountName;

  const _ResolvedAccountCard({required this.accountName});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.successSurface(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 19,
          color: AppTheme.successColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ACCOUNT CONFIRMED',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.successColor,
                ).copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: 3),
              Text(accountName, style: AppTheme.cardTitle(context)),
            ],
          ),
        ),
      ],
    ),
  );
}
