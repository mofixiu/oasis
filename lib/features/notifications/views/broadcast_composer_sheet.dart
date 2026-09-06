import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_sheet.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../controllers/notification_controller.dart';
import '../models/broadcast_model.dart';

/// Composes an announcement to a landlord's tenants.
///
/// It lands in each tenant's notification list, not in a chat thread: a
/// broadcast is one-way by design. A tenant with something to say opens a
/// conversation instead, which keeps every two-way exchange in one place.
class BroadcastComposerSheet extends StatefulWidget {
  const BroadcastComposerSheet({super.key});

  @override
  State<BroadcastComposerSheet> createState() => _BroadcastComposerSheetState();
}

class _BroadcastComposerSheetState extends State<BroadcastComposerSheet> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  BroadcastAudience _audience = BroadcastAudience.allTenants;
  String? _propertyId;

  @override
  void initState() {
    super.initState();
    // Properties may not be loaded if the landlord came straight here from the
    // notification bell, and the audience picker needs them.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<LandlordController>().loadLandlordProperties(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty) {
      LandaToast.error(context, 'Give your announcement a subject.');
      return;
    }
    if (body.isEmpty) {
      LandaToast.error(context, 'Write what you want your tenants to know.');
      return;
    }
    if (_audience == BroadcastAudience.property && _propertyId == null) {
      LandaToast.error(context, 'Choose which property this is for.');
      return;
    }

    final controller = context.read<NotificationController>();
    final broadcast = await controller.sendBroadcast(
      audience: _audience,
      title: title,
      body: body,
      propertyId: _propertyId,
    );
    if (!mounted) return;

    if (broadcast == null) {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not send that announcement. Try again in a moment.',
      );
      return;
    }

    Navigator.pop(context);
    LandaToast.success(
      context,
      'Sent to ${broadcast.recipientCount} '
      '${broadcast.recipientCount == 1 ? 'tenant' : 'tenants'}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();
    final properties = context.watch<LandlordController>().properties;

    return LandaSheet(
      icon: Icons.campaign_outlined,
      title: 'Announce to tenants',
      subtitle:
          'This lands in their notifications. Keep it to things about the '
          'property: a water schedule, a gate code, a service visit.',
      footer: LandaSheetButton(
        label: 'Send announcement',
        icon: Icons.campaign_outlined,
        isLoading: controller.isSendingBroadcast,
        onPressed: _send,
      ),
      children: [
        const LandaFieldLabel('Who gets this'),
        Row(
          children: [
            for (final audience in BroadcastAudience.values) ...[
              Expanded(
                child: _AudienceChip(
                  label: audience.label,
                  selected: _audience == audience,
                  onTap: () => setState(() {
                    _audience = audience;
                    if (audience == BroadcastAudience.allTenants) {
                      _propertyId = null;
                    }
                  }),
                ),
              ),
              if (audience != BroadcastAudience.values.last)
                const SizedBox(width: 10),
            ],
          ],
        ),

        if (_audience == BroadcastAudience.property) ...[
          const SizedBox(height: 18),
          const LandaFieldLabel('Property'),
          DropdownButtonFormField<String>(
            initialValue: _propertyId,
            isExpanded: true,
            decoration: landaInputDecoration(context, hint: 'Choose property'),
            items: [
              for (final property in properties)
                DropdownMenuItem(
                  value: property.id,
                  child: Text(
                    property.name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(context),
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _propertyId = value),
          ),
        ],

        const SizedBox(height: 18),
        const LandaFieldLabel('Subject'),
        TextField(
          controller: _titleController,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          style: AppTheme.bodyText(context),
          decoration: landaInputDecoration(
            context,
            hint: 'Water supply maintenance',
          ).copyWith(counterText: ''),
        ),

        const SizedBox(height: 18),
        const LandaFieldLabel('Message'),
        TextField(
          controller: _bodyController,
          maxLines: 5,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          style: AppTheme.bodyText(context),
          decoration: landaInputDecoration(
            context,
            hint:
                'The borehole pump will be serviced on Saturday between 9am '
                'and 2pm. Please store water ahead of time.',
          ),
        ),

        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tenants cannot reply to an announcement. They can message you '
                'directly if they need to.',
                style: AppTheme.labelText(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AudienceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AudienceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    child: Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.actionColor.withValues(alpha: 0.1)
            : AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(
          color: selected
              ? AppTheme.actionColor
              : AppTheme.borderColor(context),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTheme.cardTitle(
          context,
          color: selected
              ? AppTheme.actionColor
              : AppTheme.secondaryTextColor(context),
        ),
      ),
    ),
  );
}
