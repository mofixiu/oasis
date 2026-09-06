import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_sheet.dart';
import '../../../core/widgets/landa_toast.dart';
import '../controllers/shortlet_controller.dart';

/// Answers a host's caution-fee claim: accept it, reject it, or counter with
/// a smaller amount.
///
/// Reached only from the notification that announced the claim
/// (`SHORT_LET_CAUTION_FEE_CLAIM`): there is no endpoint to list open claims,
/// so the claim id, the amount and the host's reason all come from that
/// notification's payload rather than from anywhere this sheet can fetch on
/// its own.
///
/// Resolves true once a response was recorded.
Future<bool> openRespondToCautionClaimSheet(
  BuildContext context, {
  required String claimId,
  String? claimedAmount,
  String? hostReason,
}) async {
  final responded = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RespondToClaimSheet(
      claimId: claimId,
      claimedAmount: claimedAmount,
      hostReason: hostReason,
    ),
  );
  return responded ?? false;
}

enum _ClaimResponse { accept, reject, counter }

class _RespondToClaimSheet extends StatefulWidget {
  final String claimId;
  final String? claimedAmount;
  final String? hostReason;

  const _RespondToClaimSheet({
    required this.claimId,
    this.claimedAmount,
    this.hostReason,
  });

  @override
  State<_RespondToClaimSheet> createState() => _RespondToClaimSheetState();
}

class _RespondToClaimSheetState extends State<_RespondToClaimSheet> {
  final _counterController = TextEditingController();
  final _noteController = TextEditingController();
  _ClaimResponse _choice = _ClaimResponse.accept;

  @override
  void dispose() {
    _counterController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = context.read<ShortLetController>();

    if (_choice == _ClaimResponse.counter &&
        _counterController.text.trim().isEmpty) {
      LandaToast.error(context, 'Enter the amount you think is fair.');
      return;
    }

    final ok = await controller.respondToCautionClaim(
      claimId: widget.claimId,
      response: switch (_choice) {
        _ClaimResponse.accept => 'ACCEPT',
        _ClaimResponse.reject => 'REJECT',
        _ClaimResponse.counter => 'COUNTER',
      },
      counterAmount: _choice == _ClaimResponse.counter
          ? '${_counterController.text.trim()}.00'
          : null,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    if (!mounted) return;

    if (!ok) {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not send that response. Try again in a moment.',
      );
      return;
    }
    Navigator.pop(context, true);
    LandaToast.success(
      context,
      _choice == _ClaimResponse.accept
          ? 'Sent. The claimed amount goes to the host.'
          : 'Sent. A team member will look at this before anything moves.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = context.select<ShortLetController, bool>(
      (c) => c.isSubmitting,
    );

    return LandaSheet(
      icon: Icons.shield_outlined,
      title: 'Caution fee claim',
      subtitle: widget.claimedAmount == null
          ? 'Your host has asked to keep some of your deposit.'
          : 'Your host has asked to keep ₦${widget.claimedAmount} of your '
                'deposit.',
      footer: LandaSheetButton(
        label: 'Send response',
        icon: Icons.send_rounded,
        isLoading: isSubmitting,
        onPressed: isSubmitting ? null : _submit,
      ),
      children: [
        if (widget.hostReason != null && widget.hostReason!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: AppTheme.cornerMd,
            ),
            child: Text(widget.hostReason!, style: AppTheme.bodyText(context)),
          ),
          const SizedBox(height: 18),
        ],

        _ChoiceTile(
          selected: _choice == _ClaimResponse.accept,
          title: 'Accept',
          subtitle: 'The claimed amount goes to your host.',
          onTap: () => setState(() => _choice = _ClaimResponse.accept),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          selected: _choice == _ClaimResponse.reject,
          title: 'Reject',
          subtitle: 'You disagree entirely. Support will look into it.',
          onTap: () => setState(() => _choice = _ClaimResponse.reject),
        ),
        const SizedBox(height: 10),
        _ChoiceTile(
          selected: _choice == _ClaimResponse.counter,
          title: 'Offer a smaller amount',
          subtitle: 'You agree something is fair, just not that much.',
          onTap: () => setState(() => _choice = _ClaimResponse.counter),
        ),

        if (_choice == _ClaimResponse.counter) ...[
          const SizedBox(height: 16),
          const LandaFieldLabel('Your offer'),
          TextField(
            controller: _counterController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTheme.cardTitle(context),
            decoration: landaInputDecoration(
              context,
              hint: '5000',
              prefixIcon: Icons.currency_exchange_outlined,
            ),
          ),
        ],

        const SizedBox(height: 16),
        const LandaFieldLabel('Note (optional)'),
        TextField(
          controller: _noteController,
          maxLines: 3,
          style: AppTheme.bodyText(context),
          decoration: landaInputDecoration(
            context,
            hint: 'Say why, if it helps.',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'A rejection or a counter pauses the claim for a team member '
                'to review rather than settling it here.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.actionColor;
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.cornerMd,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.08)
              : AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.4)
                : AppTheme.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? accent : AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.cardTitle(context)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
