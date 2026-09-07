import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_sheet.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';

/// Takes a property off Landa: ask, then prove it is you.
///
/// Two stages in one sheet, because they are one decision. Removing a
/// property is the most destructive thing a landlord can do in this app and
/// it is deliberately not a single tap:
///
/// * **It can be refused.** A property with a running tenancy, money in
///   escrow, a booked stay or a pending application cannot be removed at all,
///   and the backend answers with the reasons *per unit* — which is what the
///   landlord has to act on. "Cannot delete" names nothing; "Unit A1 has a
///   running tenancy" names the flat to deal with.
/// * **It needs the password.** Not a typed "DELETE" confirmation, which
///   proves only that somebody can read: the account password proves it is
///   the account holder, which is the actual risk here (a borrowed, unlocked
///   phone).
/// * **It is reversible for seven days.** The property goes invisible to
///   tenants immediately and stays fully the landlord's until it archives, so
///   the sheet says that rather than implying the button is final.
///
/// Nothing is ever hard-deleted. An archived property still resolves, so the
/// agreements and payments that point at it keep working — which is why this
/// can be offered at all. See API guide 19 §6.
Future<bool> openRemovePropertySheet(
  BuildContext context, {
  required PropertyModel property,
}) async {
  final removed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height;
      final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: keyboard > 0 ? height * 0.94 : height * 0.75,
        ),
        child: _RemovePropertySheet(property: property),
      );
    },
  );
  return removed ?? false;
}

enum _Stage { reason, confirm }

class _RemovePropertySheet extends StatefulWidget {
  final PropertyModel property;

  const _RemovePropertySheet({required this.property});

  @override
  State<_RemovePropertySheet> createState() => _RemovePropertySheetState();
}

class _RemovePropertySheetState extends State<_RemovePropertySheet> {
  final _reasonController = TextEditingController();
  final _passwordController = TextEditingController();

  _Stage _stage = _Stage.reason;

  /// The request the backend created, once the reason has been accepted.
  PropertyRemovalRequest? _request;

  @override
  void dispose() {
    _reasonController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _requestRemoval() async {
    final reason = _reasonController.text.trim();
    if (reason.length < 4) {
      LandaToast.error(context, 'Say why you are removing this property.');
      return;
    }
    final controller = context.read<LandlordController>();
    final request = await controller.requestPropertyRemoval(
      propertyId: widget.property.id,
      reason: reason,
    );
    if (!mounted) return;

    if (request == null) {
      // Blocked is rendered inline, per unit, by the body below. Anything
      // else is a plain failure and gets the backend's own sentence.
      if (controller.removalBlockers.isEmpty) {
        LandaToast.error(
          context,
          controller.errorMessage ??
              'Could not start the removal. Try again in a moment.',
        );
      }
      return;
    }
    setState(() {
      _request = request;
      _stage = _Stage.confirm;
    });
  }

  Future<void> _confirmRemoval() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      LandaToast.error(context, 'Enter your account password to confirm.');
      return;
    }
    final request = _request;
    if (request == null) return;

    // Captured before the await: this sheet pops itself on success.
    final navigator = Navigator.of(context);
    final controller = context.read<LandlordController>();
    final confirmed = await controller.confirmPropertyRemoval(
      propertyId: widget.property.id,
      requestId: request.id,
      password: password,
    );
    if (!navigator.mounted) return;

    if (confirmed == null) {
      LandaToast.error(
        navigator.context,
        controller.errorMessage ??
            'That password was not accepted. Try again.',
      );
      return;
    }
    navigator.pop(true);
    LandaToast.success(
      navigator.context,
      '${widget.property.name} is hidden from tenants. You can undo this '
      'until it is archived.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LandlordController>();
    return switch (_stage) {
      _Stage.reason => _reasonStage(controller),
      _Stage.confirm => _confirmStage(controller),
    };
  }

  // ------------------------------------------------------------- stage one

  Widget _reasonStage(LandlordController controller) {
    final blockers = controller.removalBlockers;
    return LandaSheet(
      icon: Icons.domain_disabled_outlined,
      title: 'Remove ${widget.property.name}?',
      subtitle:
          'It stops being visible to tenants straight away. Nothing is '
          'deleted — your past agreements and payments keep working, and you '
          'have seven days to undo it.',
      accent: AppTheme.logoutColor,
      footer: LandaSheetButton(
        label: 'Continue',
        icon: Icons.arrow_forward_rounded,
        color: AppTheme.logoutColor,
        isLoading: controller.isRemoving,
        onPressed: controller.isRemoving ? null : _requestRemoval,
      ),
      children: [
        if (blockers.isNotEmpty) ...[
          _BlockedNotice(blockers: blockers),
          const SizedBox(height: 18),
        ],
        const LandaFieldLabel('Why are you removing it?'),
        TextField(
          controller: _reasonController,
          maxLines: 3,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: AppTheme.bodyText(context),
          decoration: landaInputDecoration(
            context,
            hint: 'Sold the building, taking it off the market…',
          ),
        ),
        const SizedBox(height: 16),
        const _RuleList(),
      ],
    );
  }

  // ------------------------------------------------------------- stage two

  Widget _confirmStage(LandlordController controller) {
    final blockers = controller.removalBlockers;
    return LandaSheet(
      icon: Icons.lock_outline_rounded,
      title: 'Confirm it is you',
      subtitle:
          'Re-enter your account password. This is the last step — after it, '
          '${widget.property.name} is hidden from tenants and archives in '
          'seven days unless you undo it.',
      accent: AppTheme.logoutColor,
      footer: LandaSheetButton(
        label: 'Remove this property',
        icon: Icons.domain_disabled_outlined,
        color: AppTheme.logoutColor,
        isLoading: controller.isRemoving,
        onPressed: controller.isRemoving ? null : _confirmRemoval,
      ),
      children: [
        // Re-checked at confirmation time, because a tenant can apply between
        // the request and the password.
        if (blockers.isNotEmpty) ...[
          _BlockedNotice(blockers: blockers),
          const SizedBox(height: 18),
        ],
        const LandaFieldLabel('Account password'),
        TextField(
          controller: _passwordController,
          obscureText: true,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirmRemoval(),
          style: AppTheme.cardTitle(context),
          decoration: landaInputDecoration(
            context,
            hint: 'Your password',
            prefixIcon: Icons.lock_outline,
          ),
        ),
      ],
    );
  }
}

/// The per-unit reasons a removal was refused.
class _BlockedNotice extends StatelessWidget {
  final List<PropertyRemovalBlocker> blockers;

  const _BlockedNotice({required this.blockers});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.disputeSurface(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(
        color: AppTheme.disputeColor.withValues(alpha: 0.35),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.block_rounded,
              size: 18,
              color: AppTheme.disputeColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'This property cannot be removed yet',
                style: AppTheme.cardTitle(
                  context,
                  color: AppTheme.disputeColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final blocker in blockers) ...[
          Text(blocker.label, style: AppTheme.cardTitle(context)),
          for (final reason in blocker.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text('· $reason', style: AppTheme.bodyText(context)),
            ),
          const SizedBox(height: 8),
        ],
        Text(
          'End or wait out each of these, then try again.',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ],
    ),
  );
}

/// What removal actually does, said before the landlord commits rather than
/// discovered afterwards.
class _RuleList extends StatelessWidget {
  const _RuleList();

  static const _rules = <(IconData, String)>[
    (
      Icons.visibility_off_outlined,
      'Tenants stop seeing it immediately. You keep full access.',
    ),
    (
      Icons.history_rounded,
      'Past agreements, payments and receipts are untouched.',
    ),
    (
      Icons.undo_rounded,
      'You can undo it any time in the next seven days.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (icon, text) in _rules)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: AppTheme.mutedTextColor(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: AppTheme.bodyText(context)),
              ),
            ],
          ),
        ),
    ],
  );
}
