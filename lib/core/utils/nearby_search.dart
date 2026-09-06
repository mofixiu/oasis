import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/landa_toast.dart';
import 'device_location.dart';

/// The "where am I, and what do I do when the answer is no" half of a Near me
/// control.
///
/// Two screens ask for the device's position to reorder a list: Stays and
/// Discover, and the interesting part is not the fix, it is the four ways it
/// can fail and the fact that only two of them can be fixed inside the app.
/// That reasoning was written once for Stays; keeping a second copy of it in
/// Discover would guarantee the two drift, and the one that drifts is the one
/// that sends a tenant to Settings for a permission they merely declined.
///
/// Mixed into the [State] rather than written as a free function because the
/// spinner has to live somewhere: [isLocating] is what stops the button
/// looking dead for the second or two a fix takes.
mixin NearbySearchMixin<T extends StatefulWidget> on State<T> {
  bool _isLocating = false;

  /// True while the device is being asked where it is.
  bool get isLocating => _isLocating;

  /// Reads the device position and hands it to [onLocated].
  ///
  /// [explain] is false for the automatic offer a screen makes on first open,
  /// and true for an explicit tap. Nearby is a convenience on these screens,
  /// not the way they work, typing an area name finds the same listings, so
  /// a refusal the tenant did not ask about leaves the full list on screen
  /// with nothing to dismiss. Only a deliberate tap gets an answer back.
  ///
  /// Re-entrant calls are dropped: two fixes in flight would race to reorder
  /// the same list.
  Future<void> useNearby({
    required Future<void> Function(double latitude, double longitude) onLocated,
    bool explain = true,
  }) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final location = await DeviceLocationService.current();
      if (!mounted) return;

      if (location.hasCoordinates) {
        await onLocated(location.latitude!, location.longitude!);
        return;
      }

      final message = location.message;
      if (!explain || message == null || !mounted) return;
      // Settings is the only thing that can undo a block or switched-off
      // Location Services, so those two get a route there rather than a dead
      // end. Everything else is a toast: there is nothing to decide.
      if (location.isRetryable) {
        LandaToast.info(context, message);
      } else {
        await _offerSettings(message, location.outcome);
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _offerSettings(String message, LocationOutcome outcome) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Turn on location?',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Text(message, style: AppTheme.bodyText(dialogContext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Open Settings',
              style: AppTheme.cardTitle(
                dialogContext,
                color: AppTheme.actionColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (open == true) await DeviceLocationService.openSettingsFor(outcome);
  }
}
