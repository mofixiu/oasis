import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_sheet.dart';
import '../../../../core/widgets/oasis_toast.dart';
import '../../../agreements/controllers/agreement_controller.dart';
import '../../../agreements/models/agreement_model.dart';
import '../../../agreements/models/tenancy_import.dart';
import '../../../agreements/views/widgets/rent_plan_picker.dart';
import '../../../properties/controllers/landlord_controller.dart';
import '../../../properties/models/property_model.dart';
import '../../../../core/utils/oasis_input_formatters.dart';

/// Records the tenants already living in a property.
///
/// The gap this closes: Oasis's whole tenancy flow assumes a tenancy *starts*
/// here, with the landlord inviting, the tenant applying, and an agreement
/// written from today forward. A landlord signing up with a full building has none of
/// that. Their tenants moved in years ago, paid a year up front, and are
/// halfway through a term. Asked to "invite" them, the landlord would create
/// agreements starting today, which is a different tenancy from the real one:
/// wrong renewal date, wrong rent history, and a tenant told they owe rent
/// they already paid.
///
/// So this sheet asks the two things an invitation never does, when the
/// tenancy actually began, and whether the term is already paid, and writes
/// backdated agreements from them.
///
/// Batched because the unit of work is a building, not a flat. A landlord with
/// twelve tenants should not open twelve sheets.
class MoveInTenantsModal extends StatefulWidget {
  final PropertyModel property;

  const MoveInTenantsModal({super.key, required this.property});

  /// Opens the sheet for [property] and reports what happened.
  ///
  /// Shared so every way in (finishing the add-property flow, or coming back
  /// to a property later) presents it identically.
  static Future<void> open(BuildContext context, PropertyModel property) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        // Measured against the sheet's own context, not the caller's.
        // Reading MediaQuery off the opening screen registers *that screen*
        // as a dependent, so it rebuilds every time the keyboard moves,
        // and, worse, it is an ancestor lookup on a context that may already
        // be on its way out of the tree by the time a long flow reaches this
        // step.
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints.tightFor(
            height: MediaQuery.sizeOf(sheetContext).height * 0.9,
          ),
          child: MoveInTenantsModal(property: property),
        ),
      );

  @override
  State<MoveInTenantsModal> createState() => _MoveInTenantsModalState();
}

class _MoveInTenantsModalState extends State<MoveInTenantsModal> {
  final List<_TenancyDraft> _drafts = [];

  /// Terms that apply to the whole building. A landlord runs one lease
  /// structure across a block far more often than one per flat, and asking for
  /// the plan and the house rules on every row would triple the height of a
  /// sheet that already has to hold twelve of them. Anything genuinely
  /// per-tenant (the unit, who they are, what they pay, when they started)
  /// stays on the row.
  RentPlan _rentPlan = RentPlan.fallback;
  final _rulesController = TextEditingController(
    text: 'No noise after 10 PM. Rent due annually.',
  );

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _drafts.add(_TenancyDraft());
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    _rulesController.dispose();
    super.dispose();
  }

  /// Units in this property that no row has claimed yet.
  ///
  /// Occupied units are excluded: the backend refuses an agreement on a unit
  /// already assigned to somebody else, and offering one here would only
  /// produce a row that always fails.
  List<UnitModel> _availableUnits(UnitModel? keep) {
    final claimed = _drafts
        .map((draft) => draft.unit?.id)
        .whereType<String>()
        .toSet();
    final units =
        context.read<LandlordController>().propertyUnits[widget.property.id] ??
        const <UnitModel>[];
    return units
        .where(
          (unit) =>
              unit.id == keep?.id ||
              (!unit.isOccupied && !claimed.contains(unit.id)),
        )
        .toList();
  }

  void _addRow() => setState(() => _drafts.add(_TenancyDraft()));

  /// The rows still waiting to be sent.
  ///
  /// A row that already landed is excluded for good. After a partial failure
  /// the sheet stays open with every row still on screen, that is how the
  /// landlord fixes the one typo without retyping the other six, and sending
  /// the whole list again would write a second agreement for every tenancy
  /// that worked the first time.
  List<_TenancyDraft> get _pendingDrafts =>
      _drafts.where((draft) => !draft.isDone).toList();

  /// The pending rows that are complete enough to send.
  List<TenancyImportRow> _readyRows() => _pendingDrafts
      .where((draft) => draft.isComplete)
      .map(
        (draft) => TenancyImportRow(
          unitId: draft.unit!.id,
          unitLabel: 'Unit ${draft.unit!.unitNumber}',
          tenantContact: draft.contact.text,
          rentAmount: OasisThousandsFormatter.digitsOf(draft.rent.text),
          startDate: draft.startDate!,
          endDate: draft.endDate,
          rentPlan: _rentPlan,
          rules: _rulesController.text,
          rentAlreadyPaid: draft.rentAlreadyPaid,
        ),
      )
      .toList();

  Future<void> _submit() async {
    final rows = _readyRows();
    if (rows.isEmpty || rows.length != _pendingDrafts.length) {
      OasisToast.error(
        context,
        'Give every tenant a unit, a contact, a rent amount and a start date.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final controller = context.read<AgreementController>();
    final report = await controller.importTenancies(rows);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (report == null) {
      OasisToast.error(
        context,
        controller.errorMessage ?? 'Could not record these tenancies.',
      );
      return;
    }

    // A refresh rather than a local patch: importing marks units occupied
    // server-side, and the property lists behind this sheet are now stale.
    if (report.succeeded.isNotEmpty) {
      await context.read<LandlordController>().refreshPropertyDetail(
        widget.property.id,
      );
    }
    if (!mounted) return;

    // Everything outstanding landed: including the case where earlier rows
    // had already succeeded on a previous attempt, which is why this counts
    // the whole sheet rather than this report.
    if (report.isCompleteSuccess) {
      Navigator.pop(context);
      final count =
          _drafts.where((draft) => draft.isDone).length +
          report.succeeded.length;
      OasisToast.success(
        context,
        '$count tenanc${count == 1 ? 'y' : 'ies'} recorded. Each tenant gets '
        'their agreement to sign.',
      );
      return;
    }

    // Partial or total failure keeps the sheet open with the failed rows still
    // filled in, so the landlord fixes a typo rather than retyping the batch.
    setState(() {
      final failedUnitIds = report.failed
          .map((outcome) => outcome.row.unitId)
          .toSet();
      for (final draft in _pendingDrafts) {
        final unitId = draft.unit?.id;
        draft.error = report.failed
            .where((outcome) => outcome.row.unitId == unitId)
            .map((outcome) => outcome.error)
            .firstOrNull;
        draft.isDone = unitId != null && !failedUnitIds.contains(unitId);
      }
    });
    await _showReport(report);
  }

  /// Says what landed and what did not, per flat.
  Future<void> _showReport(TenancyImportReport report) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ImportReportSheet(report: report),
  );

  @override
  Widget build(BuildContext context) {
    final pending = _pendingDrafts;
    final ready = pending.isNotEmpty && _readyRows().length == pending.length;

    return OasisSheet(
      icon: Icons.groups_2_outlined,
      title: 'Move in existing tenants',
      subtitle:
          'Record the people already living in ${widget.property.name}. Their '
          'agreements start on the day they really moved in.',
      footer: OasisSheetButton(
        label: pending.length == 1
            ? 'Record this tenancy'
            : 'Record ${pending.length} tenancies',
        icon: Icons.history_edu_outlined,
        isLoading: _isSubmitting,
        onPressed: ready && !_isSubmitting ? _submit : null,
      ),
      children: [
        const _BackdatingNotice(),
        const SizedBox(height: 20),

        for (var index = 0; index < _drafts.length; index++) ...[
          _TenancyDraftCard(
            draft: _drafts[index],
            index: index,
            units: _availableUnits(_drafts[index].unit),
            canRemove: _drafts.length > 1 && !_drafts[index].isDone,
            enabled: !_isSubmitting && !_drafts[index].isDone,
            onChanged: () => setState(() {}),
            onRemove: () => setState(() {
              _drafts.removeAt(index).dispose();
            }),
          ),
          const SizedBox(height: 14),
        ],

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isSubmitting ? null : _addRow,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add another tenant'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.actionColor,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 24),

        Text('Applies to everyone here', style: AppTheme.sectionTitle(context)),
        const SizedBox(height: 14),
        const OasisFieldLabel('How often rent is due'),
        RentPlanPicker(
          selected: _rentPlan,
          onChanged: (plan) => setState(() => _rentPlan = plan),
        ),
        const SizedBox(height: 18),
        const OasisFieldLabel('House rules'),
        TextField(
          controller: _rulesController,
          maxLines: 3,
          style: AppTheme.bodyText(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'The terms every tenancy here carries.',
          ),
        ),
      ],
    );
  }
}

/// States the one thing about this sheet a landlord could get wrong without
/// noticing: these agreements are still signed, and the tenant still sees
/// them.
class _BackdatingNotice extends StatelessWidget {
  const _BackdatingNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.subtleSurfaceColor(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.history_toggle_off_rounded,
          size: 18,
          color: AppTheme.actionColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Each tenant is sent the agreement to sign, dated from when they '
            'moved in. Say the term is already paid and Oasis will not ask '
            'them for rent until it runs out.',
            style: AppTheme.bodyText(context),
          ),
        ),
      ],
    ),
  );
}

/// One tenancy being recorded.
class _TenancyDraftCard extends StatelessWidget {
  final _TenancyDraft draft;
  final int index;
  final List<UnitModel> units;
  final bool canRemove;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _TenancyDraftCard({
    required this.draft,
    required this.index,
    required this.units,
    required this.canRemove,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  Future<void> _pickStartDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.startDate ?? now,
      // Ten years back covers a long-running tenancy without offering a date
      // nobody has a record of. Today is the latest: a tenancy starting in the
      // future is an invitation, and that is the other sheet.
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'When did this tenant move in?',
    );
    if (picked == null) return;
    draft.startDate = picked;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final startDate = draft.startDate;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(
          color: draft.error != null
              ? AppTheme.brickRedColor.withValues(alpha: 0.5)
              : AppTheme.borderColor(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tenant ${index + 1}',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
              if (draft.isDone) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle,
                  size: 15,
                  color: AppTheme.successColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'Recorded',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.successColor,
                  ),
                ),
              ],
              const Spacer(),
              if (canRemove)
                OasisPressable(
                  onTap: enabled ? onRemove : null,
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.mutedTextColor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          DropdownButtonFormField<UnitModel>(
            initialValue: draft.unit,
            isExpanded: true,
            borderRadius: AppTheme.cornerMd,
            icon: Icon(
              Icons.expand_more_rounded,
              color: AppTheme.mutedTextColor(context),
            ),
            hint: Text(
              units.isEmpty ? 'No free units left' : 'Which unit?',
              style: AppTheme.bodyText(
                context,
                color: AppTheme.mutedTextColor(context),
              ),
            ),
            style: AppTheme.cardTitle(context),
            decoration: oasisInputDecoration(
              context,
              prefixIcon: Icons.meeting_room_outlined,
            ),
            items: units
                .map(
                  (unit) => DropdownMenuItem(
                    value: unit,
                    child: Text(
                      'Unit ${unit.unitNumber} · '
                      '${OasisCurrency.format(unit.rentAmount)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: enabled && units.isNotEmpty
                ? (unit) {
                    draft.unit = unit;
                    // The unit's own rent is the best first guess at what this
                    // tenant pays, and it is right often enough to save typing,
                    // but only where the landlord has not already typed
                    // something, which would be the real figure.
                    if (unit != null && draft.rent.text.trim().isEmpty) {
                      draft.rent.text = OasisThousandsFormatter.groupAmount(
                        unit.rentAmount,
                      );
                    }
                    onChanged();
                  }
                : null,
          ),
          const SizedBox(height: 10),

          TextField(
            controller: draft.contact,
            enabled: enabled,
            keyboardType: TextInputType.emailAddress,
            style: AppTheme.cardTitle(context),
            onChanged: (_) => onChanged(),
            decoration: oasisInputDecoration(
              context,
              hint: 'Their email or phone number',
              prefixIcon: Icons.alternate_email_rounded,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.rent,
                  enabled: enabled,
                  // Grouped as it is typed. A year's rent is six or seven
                  // digits and this row is filled in once per flat: an
                  // unnoticed extra zero here writes the wrong rent into a
                  // signed tenancy.
                  keyboardType: TextInputType.number,
                  inputFormatters: const [OasisThousandsFormatter()],
                  style: AppTheme.cardTitle(context),
                  onChanged: (_) => onChanged(),
                  decoration: oasisInputDecoration(
                    context,
                    hint: 'Rent per year',
                    prefixIcon: Icons.payments_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  label: startDate == null
                      ? 'Moved in'
                      : _TenancyDraft.readableDate(startDate),
                  isSet: startDate != null,
                  onTap: enabled ? () => _pickStartDate(context) : null,
                ),
              ),
            ],
          ),

          if (startDate != null) ...[
            const SizedBox(height: 10),
            _PaidUpToggle(
              endDate: draft.endDate,
              value: draft.rentAlreadyPaid,
              onChanged: enabled
                  ? (value) {
                      draft.rentAlreadyPaid = value;
                      onChanged();
                    }
                  : null,
            ),
          ],

          if (draft.error != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 15,
                  color: AppTheme.brickRedColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    draft.error!,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.brickRedColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable date, styled to sit beside a text field without looking like
/// one: it opens a picker rather than a keyboard.
class _DateField extends StatelessWidget {
  final String label;
  final bool isSet;
  final VoidCallback? onTap;

  const _DateField({required this.label, required this.isSet, this.onTap});

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    pressedScale: 0.98,
    child: Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.inputFillColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_outlined,
            size: 18,
            color: AppTheme.mutedTextColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: isSet
                  ? AppTheme.cardTitle(context)
                  : AppTheme.bodyText(
                      context,
                      color: AppTheme.mutedTextColor(context),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Whether the current term has already been paid off-platform.
///
/// The single most consequential switch on the row, which is why it is a
/// visible toggle with the date spelled out rather than a checkbox with a
/// label. Left off, the tenant's first act in Oasis is being billed for rent
/// they handed over in cash last year.
class _PaidUpToggle extends StatelessWidget {
  final DateTime endDate;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _PaidUpToggle({
    required this.endDate,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
    decoration: BoxDecoration(
      color: value
          ? AppTheme.successSurface(context)
          : AppTheme.surfaceColor(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(
        color: value
            ? AppTheme.successColor.withValues(alpha: 0.4)
            : AppTheme.borderColor(context),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Rent already paid to ${_TenancyDraft.readableDate(endDate)}',
            style: AppTheme.labelText(
              context,
              color: value
                  ? AppTheme.successColor
                  : AppTheme.secondaryTextColor(context),
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.successColor,
        ),
      ],
    ),
  );
}

/// What the import did, flat by flat.
class _ImportReportSheet extends StatelessWidget {
  final TenancyImportReport report;

  const _ImportReportSheet({required this.report});

  @override
  Widget build(BuildContext context) {
    final failed = report.failed;
    final succeeded = report.succeeded;

    return OasisSheet(
      icon: report.isCompleteFailure
          ? Icons.error_outline_rounded
          : Icons.fact_check_outlined,
      accent: report.isCompleteFailure
          ? AppTheme.brickRedColor
          : AppTheme.actionColor,
      title: report.isCompleteFailure
          ? 'Nothing was recorded'
          : '${succeeded.length} of ${report.outcomes.length} recorded',
      subtitle: failed.isEmpty
          ? 'Every tenant has been sent their agreement.'
          : 'Fix the ones below and send them again. The rest are done.',
      footer: OasisSheetButton(
        label: 'Back to the list',
        onPressed: () => Navigator.pop(context),
      ),
      children: [
        for (final outcome in succeeded)
          _ReportRow(
            icon: Icons.check_circle_outline_rounded,
            color: AppTheme.successColor,
            title: outcome.row.unitLabel,
            detail: outcome.tenantWasInvited
                ? '${outcome.row.tenantContact} has no Oasis account yet, '
                      'they have been invited to claim this tenancy.'
                : 'Agreement sent to ${outcome.row.tenantContact}.',
          ),
        for (final outcome in failed)
          _ReportRow(
            icon: Icons.error_outline_rounded,
            color: AppTheme.brickRedColor,
            title: outcome.row.unitLabel,
            detail: outcome.error ?? 'Could not record this tenancy.',
          ),
      ],
    );
  }
}

class _ReportRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  const _ReportRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.cardTitle(context)),
              const SizedBox(height: 2),
              Text(detail, style: AppTheme.bodyText(context)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Mutable state for one row.
class _TenancyDraft {
  UnitModel? unit;
  final TextEditingController contact = TextEditingController();
  final TextEditingController rent = TextEditingController();
  DateTime? startDate;
  bool rentAlreadyPaid = true;

  /// Set after a submit that partly failed, so the row can say why.
  String? error;

  /// Set for rows that landed, so a retry does not re-send them.
  bool isDone = false;

  /// A year from the start, which is the Nigerian default and the term the
  /// rest of the app already assumes. Derived rather than asked for: a second
  /// date picker on every row buys one editable field for a number that is
  /// almost never anything else.
  DateTime get endDate => DateTime(
    startDate!.year + 1,
    startDate!.month,
    startDate!.day,
  ).subtract(const Duration(days: 1));

  bool get isComplete =>
      unit != null &&
      contact.text.trim().isNotEmpty &&
      double.tryParse(OasisThousandsFormatter.digitsOf(rent.text)) != null &&
      startDate != null;

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String readableDate(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  void dispose() {
    contact.dispose();
    rent.dispose();
  }
}
