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
      ApplicationStatus.rejected ||
      ApplicationStatus.withdrawn => (
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}
