import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'oasis_pressable.dart';
import 'oasis_busy.dart';

/// The toggle between "everywhere" and "near me".
///
/// One button doing both directions rather than a button and a separate
/// clear: once results are distance-sorted, the only thing left to ask of it
/// is to stop, and a second control for that would be a control that does
/// nothing most of the time.
///
/// Shared by Stays and Discover. The two screens ask different backends the
/// same question, and a tenant who learns the control on one must not find a
/// different-looking one on the other.
class NearMeButton extends StatelessWidget {
  final bool isActive;
  final bool isLoading;
  final VoidCallback onPressed;

  /// What the button will do next, for the tooltip. Phrased as the action, so
  /// it reads "Show every stay" / "Show every home" when active.
  final String inactiveHint;
  final String activeHint;

  const NearMeButton({
    super.key,
    required this.isActive,
    required this.isLoading,
    required this.onPressed,
    this.inactiveHint = 'Sort by distance from you',
    this.activeHint = 'Show everywhere',
  });

  @override
  Widget build(BuildContext context) {
    final foreground = isActive
        ? Colors.white
        : AppTheme.secondaryTextColor(context);

    return Tooltip(
      message: isActive ? activeHint : inactiveHint,
      child: OasisPressable(
        onTap: isLoading ? null : onPressed,
        pressedScale: 0.97,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.actionColor
                : AppTheme.inputFillColor(context),
            borderRadius: AppTheme.cornerMd,
            border: Border.all(
              color: isActive
                  ? AppTheme.actionColor
                  : AppTheme.borderColor(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OasisBusyDots(color: foreground),
                )
              else
                Icon(
                  isActive ? Icons.my_location_rounded : Icons.near_me_outlined,
                  size: 18,
                  color: foreground,
                ),
              const SizedBox(width: 6),
              Text(
                'Near me',
                style: AppTheme.labelText(context, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Says plainly that the list is no longer everything: distance sorting
/// silently reorders and can hide what falls outside the radius, and someone
/// who cannot find a place they saw yesterday deserves to know why.
class NearbyNotice extends StatelessWidget {
  final String message;
  final String clearLabel;
  final VoidCallback onClear;

  const NearbyNotice({
    super.key,
    required this.message,
    required this.onClear,
    this.clearLabel = 'See all',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.my_location_rounded,
            size: 16,
            color: AppTheme.actionColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              clearLabel,
              style: AppTheme.labelText(context, color: AppTheme.actionColor),
            ),
          ),
        ],
      ),
    );
  }
}
