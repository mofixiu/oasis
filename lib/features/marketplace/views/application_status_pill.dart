import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/marketplace_models.dart';

/// Shared status chip so tenant and landlord views label applications the
/// same way.
class ApplicationStatusPill extends StatelessWidget {
  final ApplicationStatus status;

  const ApplicationStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, surface) = switch (status) {
      ApplicationStatus.approved => (
        AppTheme.successColor,
        AppTheme.successSurfaceColor,
      ),
      ApplicationStatus.rejected || ApplicationStatus.withdrawn => (
        AppTheme.disputeColor,
        AppTheme.disputeSurfaceColor,
      ),
      ApplicationStatus.pending => (
        AppTheme.primaryColor,
        AppTheme.vacantSurfaceColor,
      ),
      ApplicationStatus.unknown => (
        AppTheme.profileColor,
        AppTheme.slateSurfaceColor,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: surface,
        // Stadium plus a hairline in the status colour: a flat tint alone
        // reads as a coloured rectangle, the border makes it a badge.
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.label,
        style: AppTheme.labelText(
          context,
          color: color,
        ).copyWith(fontSize: 10, letterSpacing: 0.4),
      ),
    );
  }
}
