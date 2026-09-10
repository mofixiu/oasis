import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_network_image.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../../dashboard/views/widgets/move_in_tenants_modal.dart';
import '../../fix/views/unit_recommendations_sheet.dart';
import '../../messaging/views/widgets/message_action_button.dart';
import '../controllers/landlord_controller.dart';
import '../models/property_model.dart';
import 'widgets/edit_unit_rent_sheet.dart';
import 'widgets/property_media_manager.dart';
import 'widgets/remove_property_sheet.dart';
import 'widgets/unit_media_sheet.dart';

class ManagedPropertyDetailScreen extends StatefulWidget {
  final PropertyModel property;
  final List<UnitModel> units;
  final VoidCallback onAddUnits;

  const ManagedPropertyDetailScreen({
    super.key,
    required this.property,
    required this.units,
    required this.onAddUnits,
  });

  @override
  State<ManagedPropertyDetailScreen> createState() =>
      _ManagedPropertyDetailScreenState();
}

class _ManagedPropertyDetailScreenState
    extends State<ManagedPropertyDetailScreen>
    with AutoRefreshMixin<ManagedPropertyDetailScreen> {
  /// Re-read on return as well as on mount: units are added, tenants moved
  /// in and media uploaded from sheets pushed over this screen, and every one
  /// of them leaves the page behind describing the property as it was.
  ///
  /// The agreements list used to be refetched here as well, because the unit
  /// sheet's "Message tenant" button was keyed on scanning it. API guide 19
  /// §3 puts `active_agreement` on the unit itself, so one request now
  /// answers what two used to.
  @override
  Future<void> onAutoRefresh() =>
      context.read<LandlordController>().refreshPropertyDetail(
        widget.property.id,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.pageBackground(context),
    appBar: AppBar(
      backgroundColor: AppTheme.pageBackground(context),
      title: Text(
        'Property details',
        style: TextStyle(
          color: AppTheme.primaryTextColor(context),
          fontWeight: FontWeight.bold,
        ),
      ),
      iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
    ),
    body: Consumer<LandlordController>(
      builder: (context, controller, _) {
        final currentProperty = controller.properties.firstWhere(
          (p) => p.id == widget.property.id,
          orElse: () => widget.property,
        );
        final currentUnits =
            controller.propertyUnits[widget.property.id] ?? widget.units;
        return RefreshIndicator(
          onRefresh: () => controller.refreshPropertyDetail(widget.property.id),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // The property itself was passed in, so a failed detail refresh
              // never blanks the page: it reports itself over the stale copy.
              if (controller.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OasisErrorBanner(
                    message: controller.errorMessage!,
                    isConnectionError: controller.errorIsConnection,
                    onRetry: () =>
                        controller.refreshPropertyDetail(widget.property.id),
                  ),
                ),
              // Ahead of the property itself: a landlord who has asked to
              // remove this building needs the countdown and the way back
              // before anything else on the page, not under three sections
              // of detail about a listing that is on its way out.
              if (currentProperty.pendingRemoval case final removal?
                  when currentProperty.isBeingRemoved) ...[
                _RemovalPendingBanner(
                  property: currentProperty,
                  removal: removal,
                ),
                const SizedBox(height: 16),
              ],
              _PropertyHero(property: currentProperty),
              const SizedBox(height: 24),
              PropertyMediaManager(property: currentProperty),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('UNITS', style: AppTheme.labelText(context)),
                        const SizedBox(height: 2),
                        Text(
                          '${currentUnits.length} total',
                          style: AppTheme.screenTitle(
                            context,
                            color: AppTheme.primaryColor,
                          ).copyWith(fontSize: AppTheme.textXl),
                        ),
                      ],
                    ),
                  ),
                  OasisButton(
                    label: 'Add units',
                    icon: Icons.add_rounded,
                    expand: false,
                    onPressed: widget.onAddUnits,
                  ),
                ],
              ),
              // Offered for as long as there is somewhere to put somebody. A
              // landlord rarely finishes moving their building across in one
              // sitting: they add the property, get through four flats, and
              // come back, so the step cannot only exist inside the
              // add-property flow they have already left.
              if (currentUnits.any((unit) => !unit.isOccupied)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        MoveInTenantsModal.open(context, currentProperty),
                    icon: const Icon(Icons.groups_2_outlined, size: 18),
                    label: const Text('Move in existing tenants'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.actionColor,
                      side: const BorderSide(color: AppTheme.actionColor),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.cornerMd,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (currentUnits.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.meeting_room_outlined,
                        size: 36,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 8),
                      Text('No units added yet'),
                    ],
                  ),
                ),
              ...currentUnits.map(
                (unit) => _UnitCard(unit: unit, propertyId: widget.property.id),
              ),

              // Last on the page, and the only destructive control on it.
              // Hidden while a removal is already running: the banner at the
              // top owns that state, and offering "remove" again underneath
              // a countdown reads as a second, different action.
              if (!currentProperty.isBeingRemoved) ...[
                const SizedBox(height: 28),
                _RemovePropertyAction(property: currentProperty),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _PropertyHero extends StatelessWidget {
  final PropertyModel property;
  const _PropertyHero({required this.property});

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 190,
          width: double.infinity,
          child: OasisNetworkImage(
            url: property.displayImageUrl,
            placeholderIcon: Icons.home_work_outlined,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      property.name,
                      style: AppTheme.sectionTitle(
                        context,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  _StatusPill(status: property.verificationStatus),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${property.address}, ${property.city}, ${property.state}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              if (property.latitude != null && property.longitude != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppTheme.actionColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pinned at ${property.latitude!.toStringAsFixed(5)}, ${property.longitude!.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    final verified = status.toUpperCase() == 'VERIFIED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: verified
            ? AppTheme.successSurface(context)
            : AppTheme.vacantSurface(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        verified ? 'VERIFIED' : 'UNDER REVIEW',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: verified ? AppTheme.successColor : AppTheme.primaryColor,
        ),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  final UnitModel unit;
  final String propertyId;

  const _UnitCard({required this.unit, required this.propertyId});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => _UnitInfoSheet(unit: unit, propertyId: propertyId),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.door_front_door_outlined,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unit ${unit.unitNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${unit.bedrooms} bed · ${unit.bathrooms} bath · ${OasisCurrency.perYear(unit.rentAmount)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    unit.isOccupied || unit.isReserved
                        ? 'Tenant: ${unit.tenant ?? 'Assigned'}'
                        : 'Vacant',
                    style: TextStyle(
                      fontSize: 12,
                      // Sand while the flat is only reserved: sage is for a
                      // tenancy that is actually running.
                      color: unit.isOccupied && !unit.isReserved
                          ? AppTheme.successColor
                          : AppTheme.vacantColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Only when something is missing. A unit with its media in
                  // order says nothing here: the landlord does not need a
                  // green tick on every row to know the block is fine.
                  if (unit.needsTourVideo) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.videocam_off_outlined,
                          size: 13,
                          color: AppTheme.actionColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'No tour video',
                          style: AppTheme.labelText(
                            context,
                            color: AppTheme.actionColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // A direct route to the media, so fixing a missing walkthrough is
            // one tap from the warning that named it rather than three.
            IconButton(
              onPressed: () => openUnitMediaSheet(
                context,
                unit: unit,
                propertyId: propertyId,
              ),
              icon: const Icon(Icons.perm_media_outlined, size: 20),
              color: unit.needsTourVideo
                  ? AppTheme.actionColor
                  : AppTheme.mutedTextColor(context),
              tooltip: 'Photos and tour video',
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.mutedTextColor(context),
            ),
          ],
        ),
      ),
    ),
  );
}

class _UnitInfoSheet extends StatelessWidget {
  final UnitModel unit;
  final String propertyId;

  const _UnitInfoSheet({required this.unit, required this.propertyId});

  /// Both buttons here close this sheet and then open another one, and that
  /// is the whole difficulty: by the time the second sheet is asked for, the
  /// context that asked for it belongs to a widget being torn down. An
  /// ancestor lookup on one of those does not fail politely: it trips
  /// *"Looking up a deactivated widget's ancestor is unsafe"* and takes the
  /// screen with it.
  ///
  /// This used to be worked around by passing the property page's own
  /// `BuildContext` down through two widgets and using that instead, which
  /// moved the problem rather than removing it: that context is only valid
  /// while the page behind the sheet is still on the stack, and nothing
  /// checked that it was.
  ///
  /// What is captured instead is a [NavigatorState] and the controller:
  /// plain objects, both of which outlive every sheet in this file. The
  /// navigator's own context is the one used to present, and it is alive for
  /// as long as the app is.
  Future<void> _openCreateAgreement(
    NavigatorState navigator,
    LandlordController controller,
  ) async {
    final created = await showModalBottomSheet<bool>(
      context: navigator.context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CreateAgreementModal(
        unitId: unit.id,
        unitNumber: unit.unitNumber,
        assignedTenantId: unit.tenantEmail ?? unit.tenantPhone,
      ),
    );

    if (created == true) await controller.loadLandlordProperties();
  }

  /// Opens the rent editor over this sheet.
  ///
  /// Layered rather than swapped: a landlord changing a price wants to see
  /// the unit they are pricing, and popping back to the property page first
  /// would lose the row they were reading. The navigator is captured before
  /// anything is awaited, for the reason set out in [openAddPropertyFlow].
  Future<void> _openRentEditor(BuildContext context) async {
    final navigator = Navigator.of(context);
    final changed = await openEditUnitRentSheet(
      context,
      unit: unit,
      propertyId: propertyId,
    );
    // The sheet behind this one is rendering the old rent from the copy it
    // was handed, and it has no way to hear about the change. Closing it
    // sends the landlord back to the property page, which reads the unit
    // from the controller and is already correct.
    if (changed && navigator.mounted) navigator.pop();
  }

  /// Names the artisans this landlord trusts on this unit.
  ///
  /// Lives on the unit rather than the property because that is what the
  /// backend keys recommendations on, and because a tenant's repair happens in
  /// one flat, not across a block.
  Future<void> _openRecommendations(NavigatorState navigator) =>
      openUnitRecommendationsSheet(
        navigator.context,
        unitId: unit.id,
        unitLabel: 'Unit ${unit.unitNumber}',
      );

  /// The live tenancy on this unit, from the unit's own payload.
  ///
  /// A landlord cannot open a conversation from a unit id: `POST
  /// /conversations/` refuses it, because a unit can have several applicants
  /// and the backend will not guess which of them is meant. It *will* take an
  /// agreement, which names exactly one tenant, so that is what the button
  /// hangs off.
  ///
  /// This used to be found by scanning every agreement the landlord has for
  /// one whose `unit` matched — forty agreements held in memory to decide one
  /// button on a screen showing one flat, and wrong whenever the agreements
  /// list had not been fetched. API guide 19 §3 puts `active_agreement` on
  /// the unit itself, so the screen no longer depends on another feature's
  /// controller having loaded.
  UnitActiveAgreement? get _liveTenancy => unit.activeAgreement;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unit ${unit.unitNumber}',
          style: AppTheme.sectionTitle(context, color: AppTheme.primaryColor),
        ),
        const SizedBox(height: 16),
        _InfoRow(
          'Layout',
          '${unit.bedrooms} bedroom · ${unit.bathrooms} bathroom',
        ),
        // The one row here that is a decision rather than a fact. A flat
        // sitting empty is usually a flat priced for a market that has
        // moved, and the landlord looking at this sheet is the person who
        // can fix that, so the way to do it is on the number itself rather
        // than somewhere they would have to know to look.
        _InfoRow(
          'Annual rent',
          OasisCurrency.format(unit.rentAmount),
          onEdit: () => _openRentEditor(context),
          editTooltip: 'Change the rent',
        ),
        // Three states, not two. "Occupied" used to start the moment an
        // application was approved — before the agreement was signed and
        // before any rent had moved — so a landlord read it as money on the
        // way when it was not. Since API guide 19 the backend distinguishes
        // reserved from occupied itself, and [UnitModel.occupancyLabel] is
        // the one place that turns it into words.
        _InfoRow('Occupancy', unit.occupancyLabel),
        if (unit.isOccupied || unit.isReserved) ...[
          _InfoRow('Tenant', unit.tenant ?? 'Tenant assigned'),
          if (unit.tenantEmail != null) _InfoRow('Email', unit.tenantEmail!),
          if (unit.tenantPhone != null) _InfoRow('Phone', unit.tenantPhone!),
          const SizedBox(height: 14),
          // Messaging used to be reachable only from an application, which
          // meant a landlord could talk to somebody applying for a flat and
          // then lose the thread the moment they became the tenant of it.
          // Testers hit exactly that. The tenancy is the relationship the
          // backend will open a conversation against, so the button lives on
          // the unit the tenancy is for.
          if (_liveTenancy case final tenancy?)
            MessageActionButton(
              agreementId: tenancy.id,
              label: 'Message ${unit.tenant ?? 'tenant'}',
              expanded: true,
            )
          else
            Text(
              'You can message this tenant once their tenancy agreement '
              'exists. Create it below.',
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              // Resolved before the pop, while this context is still active.
              final navigator = Navigator.of(context);
              final controller = context.read<LandlordController>();
              navigator.pop();
              _openCreateAgreement(navigator, controller);
            },
            icon: const Icon(Icons.description_outlined, color: Colors.white),
            label: const Text(
              'Create tenancy agreement',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.actionColor,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              _openRecommendations(navigator);
            },
            icon: const Icon(
              Icons.handshake_outlined,
              color: AppTheme.primaryColor,
            ),
            label: const Text(
              'Recommended artisans',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.primaryColor),
            ),
          ),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  /// Optional trailing action. Only the rows that describe a *choice* get
  /// one (a rent is set, a bedroom count is measured) so the presence of
  /// the pencil is itself the signal for which is which.
  final VoidCallback? onEdit;
  final String? editTooltip;

  const _InfoRow(this.label, this.value, {this.onEdit, this.editTooltip});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: onEdit == null ? 12 : 4),
    child: Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            tooltip: editTooltip,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(
              Icons.edit_outlined,
              size: 17,
              color: AppTheme.actionColor,
            ),
          ),
      ],
    ),
  );
}

/// The banner on a property that is on its way out.
///
/// States the two things the landlord needs: how long is left, and that it is
/// reversible. Brick red, like every other destructive surface in the app.
class _RemovalPendingBanner extends StatelessWidget {
  final PropertyModel property;
  final PropertyRemovalRequest removal;

  const _RemovalPendingBanner({
    required this.property,
    required this.removal,
  });

  Future<void> _cancel(BuildContext context) async {
    final controller = context.read<LandlordController>();
    final cancelled = await controller.cancelPropertyRemoval(
      propertyId: property.id,
      requestId: removal.id,
    );
    if (!context.mounted) return;
    if (cancelled) {
      OasisToast.success(
        context,
        '${property.name} is back on Oasis.',
      );
    } else {
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not undo the removal. Try again in a moment.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final countdown = removal.countdown;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.disputeSurface(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(
          color: AppTheme.logoutColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.domain_disabled_outlined,
                size: 19,
                color: AppTheme.logoutColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  countdown == null
                      ? 'Being removed from Oasis'
                      : 'Being removed · $countdown',
                  style: AppTheme.cardTitle(
                    context,
                    color: AppTheme.logoutColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tenants can no longer see this property. Nothing has been '
            'deleted, and you can put it back until it archives.',
            style: AppTheme.bodyText(context),
          ),
          const SizedBox(height: 14),
          Consumer<LandlordController>(
            builder: (context, controller, _) => OasisButton(
              label: 'Keep this property',
              icon: Icons.undo_rounded,
              isBusy: controller.isRemoving,
              onPressed: controller.isRemoving ? null : () => _cancel(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// The way out, at the bottom of the page where destructive actions belong.
class _RemovePropertyAction extends StatelessWidget {
  final PropertyModel property;

  const _RemovePropertyAction({required this.property});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('REMOVING THIS PROPERTY', style: AppTheme.labelText(context)),
      const SizedBox(height: 6),
      Text(
        'Takes it off Oasis. It cannot be removed while a tenancy is '
        'running, money is in escrow, a stay is booked or an application is '
        'waiting.',
        style: AppTheme.bodyText(context),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () =>
              openRemovePropertySheet(context, property: property),
          icon: const Icon(Icons.domain_disabled_outlined, size: 18),
          label: const Text('Remove property'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.logoutColor,
            side: const BorderSide(color: AppTheme.logoutColor),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerMd),
          ),
        ),
      ),
    ],
  );
}
