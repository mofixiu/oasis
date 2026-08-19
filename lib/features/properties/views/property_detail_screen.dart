import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../../core/utils/landa_currency.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../controllers/landlord_controller.dart';
import '../models/property_model.dart';
import 'widgets/property_media_manager.dart';

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
    extends State<ManagedPropertyDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<LandlordController>().refreshPropertyDetail(
        widget.property.id,
      ),
    );
  }

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
              // never blanks the page — it reports itself over the stale copy.
              if (controller.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LandaErrorBanner(
                    message: controller.errorMessage!,
                    isConnectionError: controller.errorIsConnection,
                    onRetry: () =>
                        controller.refreshPropertyDetail(widget.property.id),
                  ),
                ),
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
                  LandaButton(
                    label: 'Add units',
                    icon: Icons.add_rounded,
                    expand: false,
                    onPressed: widget.onAddUnits,
                  ),
                ],
              ),
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
                (unit) => _UnitCard(unit: unit, pageContext: context),
              ),
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
          child: property.displayImageUrl != null
              ? Image.network(
                  property.displayImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(),
                )
              : _fallback(),
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
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
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

  Widget _fallback() => Container(
    color: AppTheme.primaryColor.withValues(alpha: .08),
    child: const Center(
      child: Icon(
        Icons.home_work_outlined,
        size: 64,
        color: AppTheme.primaryColor,
      ),
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
            ? AppTheme.successSurfaceColor
            : AppTheme.vacantSurfaceColor,
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
  final BuildContext pageContext;

  const _UnitCard({required this.unit, required this.pageContext});

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
        builder: (_) => _UnitInfoSheet(unit: unit, pageContext: pageContext),
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
                    '${unit.bedrooms} bed · ${unit.bathrooms} bath · ${LandaCurrency.perYear(unit.rentAmount)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    unit.isOccupied
                        ? 'Tenant: ${unit.tenant ?? 'Assigned'}'
                        : 'Vacant',
                    style: TextStyle(
                      fontSize: 12,
                      color: unit.isOccupied
                          ? AppTheme.successColor
                          : AppTheme.vacantColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    ),
  );
}

class _UnitInfoSheet extends StatelessWidget {
  final UnitModel unit;
  final BuildContext pageContext;

  const _UnitInfoSheet({required this.unit, required this.pageContext});

  Future<void> _openCreateAgreement() async {
    final created = await showModalBottomSheet<bool>(
      context: pageContext,
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

    if (created == true && pageContext.mounted) {
      await pageContext.read<LandlordController>().loadLandlordProperties();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unit ${unit.unitNumber}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 16),
        _InfoRow(
          'Layout',
          '${unit.bedrooms} bedroom · ${unit.bathrooms} bathroom',
        ),
        _InfoRow('Annual rent', LandaCurrency.format(unit.rentAmount)),
        _InfoRow('Occupancy', unit.isOccupied ? 'Occupied' : 'Vacant'),
        if (unit.isOccupied) ...[
          _InfoRow('Tenant', unit.tenant ?? 'Tenant assigned'),
          if (unit.tenantEmail != null) _InfoRow('Email', unit.tenantEmail!),
          if (unit.tenantPhone != null) _InfoRow('Phone', unit.tenantPhone!),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Future<void>.delayed(Duration.zero, _openCreateAgreement);
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
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
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
      ],
    ),
  );
}
