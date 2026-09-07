import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../controllers/agreement_controller.dart';
import '../models/agreement_group.dart';
import '../models/agreement_model.dart';
import 'tenancy_agreement_modal.dart';

/// The signed-agreement archive, grouped by property and then by unit.
///
/// It used to be a flat run of rows on the profile, which is fine at three
/// agreements and unusable at thirty: a landlord accumulates one per unit per
/// term. Both roles get the same screen: a tenant with one tenancy sees a
/// single section with a single card, and the renewal chain underneath it when
/// there is one.
class MyAgreementsScreen extends StatefulWidget {
  const MyAgreementsScreen({super.key});

  @override
  State<MyAgreementsScreen> createState() => _MyAgreementsScreenState();
}

class _MyAgreementsScreenState extends State<MyAgreementsScreen>
    with AutoRefreshMixin<MyAgreementsScreen> {
  @override
  Future<void> onAutoRefresh() => _reload();

  Future<void> _reload() =>
      context.read<AgreementController>().loadAgreements();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AgreementController>();
    final groups = controller.signedAgreementsByProperty;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        title: Text('My agreements', style: AppTheme.cardTitle(context)),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _buildBody(context, controller, groups),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AgreementController controller,
    List<PropertyAgreementGroup> groups,
  ) {
    // "Never fetched" and "fetched and empty" look identical on an empty
    // list, so the first is asked about separately: otherwise the screen
    // claims there are no agreements before it has looked for any.
    if (!controller.hasLoaded() || (controller.isLoading && groups.isEmpty)) {
      return const LandaSkeletonList(count: 3);
    }

    // A failure with nothing to show is a dead page; a failure with records
    // already on screen is a banner over them.
    if (controller.hasError && groups.isEmpty) {
      return LandaErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }

    if (groups.isEmpty) {
      return LandaEmptyState(
        icon: Icons.folder_outlined,
        title: 'No signed agreements yet',
        message:
            'Once an agreement is signed by both parties it moves here, where '
            'you can look it up any time.',
        actionLabel: 'Check again',
        actionIcon: Icons.refresh_rounded,
        onAction: controller.loadAgreements,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (controller.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LandaErrorBanner(
              message: controller.errorMessage!,
              isConnectionError: controller.errorIsConnection,
              onRetry: _reload,
            ),
          ),
        for (final (index, group) in groups.indexed)
          LandaEntrance(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _PropertySection(group: group),
            ),
          ),
      ],
    );
  }
}

/// One property's heading and the tenancies beneath it.
class _PropertySection extends StatelessWidget {
  final PropertyAgreementGroup group;

  const _PropertySection({required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.propertyName.toUpperCase(),
                    style: AppTheme.labelText(
                      context,
                      color: group.isUnassigned
                          ? AppTheme.mutedTextColor(context)
                          : AppTheme.secondaryTextColor(context),
                    ).copyWith(letterSpacing: 0.9),
                  ),
                  if (group.propertyLocation.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      group.propertyLocation,
                      style: AppTheme.labelText(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Text('${group.agreementCount}', style: AppTheme.labelText(context)),
          ],
        ),
        // Says why these are here rather than under a building name, so an
        // agreement with a thin payload does not read as a bug.
        if (group.isUnassigned) ...[
          const SizedBox(height: 6),
          Text(
            'These agreements did not name a property. They are still valid. '
            'Open one to see its full terms.',
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ],
        const SizedBox(height: 10),
        for (final tenancy in group.tenancies)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TenancyCard(tenancy: tenancy),
          ),
      ],
    );
  }
}

/// One unit's current agreement, with its earlier terms folded underneath.
class _TenancyCard extends StatefulWidget {
  final TenancyGroup tenancy;

  const _TenancyCard({required this.tenancy});

  @override
  State<_TenancyCard> createState() => _TenancyCardState();
}

class _TenancyCardState extends State<_TenancyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tenancy = widget.tenancy;
    final latest = tenancy.latest;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        children: [
          LandaPressable(
            onTap: () => _open(context, latest),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                tenancy.label,
                                style: AppTheme.cardTitle(context),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(agreement: latest),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_term(latest)} · '
                          '${LandaCurrency.perYear(latest.rentAmount)}',
                          style: AppTheme.labelText(
                            context,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.mutedTextColor(context),
                  ),
                ],
              ),
            ),
          ),
          // Earlier terms on the same unit. Collapsed by default: the current
          // agreement is what anyone is looking for, and the chain behind it
          // matters far less often than it takes up room.
          if (tenancy.hasHistory) ...[
            Divider(height: 1, color: AppTheme.borderColor(context)),
            LandaPressable(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expanded
                            ? 'Hide earlier terms'
                            : '${tenancy.history.length} earlier '
                                  '${tenancy.history.length == 1 ? 'term' : 'terms'}',
                        style: AppTheme.labelText(
                          context,
                          color: AppTheme.actionColor,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppTheme.actionColor,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              for (final agreement in tenancy.history)
                _HistoryRow(
                  agreement: agreement,
                  onTap: () => _open(context, agreement),
                ),
          ],
        ],
      ),
    );
  }

  void _open(BuildContext context, TenancyAgreementModel agreement) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ViewAgreementModal(agreement: agreement),
      );
}

class _HistoryRow extends StatelessWidget {
  final TenancyAgreementModel agreement;
  final VoidCallback onTap;

  const _HistoryRow({required this.agreement, required this.onTap});

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _term(agreement),
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ),
          _StatusPill(agreement: agreement),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppTheme.mutedTextColor(context),
          ),
        ],
      ),
    ),
  );
}

/// Plain-language standing. The wire label (`EXECUTED`) is accurate and
/// unreadable; this is the same fact in the user's words.
class _StatusPill extends StatelessWidget {
  final TenancyAgreementModel agreement;

  const _StatusPill({required this.agreement});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (agreement.status) {
      AgreementStatus.executed ||
      AgreementStatus.activated => ('Signed', AppTheme.successColor),
      AgreementStatus.expired => ('Expired', AppTheme.mutedTextColor(context)),
      AgreementStatus.voided => ('Voided', AppTheme.disputeColor),
      _ => (agreement.status.userFriendlyTitle, AppTheme.warningColor),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppTheme.cornerSm,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: AppTheme.labelText(context, color: color)),
    );
  }
}

/// The term an agreement covers, e.g. `Sep 2026 – Aug 2027`.
///
/// Falls back to whatever the backend sent when a date will not parse: an
/// unreadable date is still more use than a blank line.
String _term(TenancyAgreementModel agreement) {
  final start = _month(agreement.startDate);
  final end = _month(agreement.endDate);
  if (start == null && end == null) return 'Term not recorded';
  return '${start ?? agreement.startDate} – ${end ?? agreement.endDate}';
}

String? _month(String raw) {
  final date = DateTime.tryParse(raw.trim());
  return date == null ? null : DateFormat('MMM yyyy').format(date);
}
