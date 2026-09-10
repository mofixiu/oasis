import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'oasis_pressable.dart';

/// Full-page failure state with a retry action.
///
/// Every screen that fetches shows the same thing when the fetch fails, so a
/// connection drop reads identically everywhere instead of each screen
/// improvising (some used to render the raw error inside the empty state,
/// which told the user "no applications yet" when the truth was "we could not
/// reach the server").
class OasisErrorState extends StatelessWidget {
  /// Message to show. Falls back to a connection-appropriate default.
  final String? message;

  /// True when the request never reached the backend. Changes the icon,
  /// heading and hint from "something broke" to "you're offline".
  final bool isConnectionError;

  final Future<void> Function()? onRetry;

  /// Wraps the state in a scrollable so an enclosing [RefreshIndicator] still
  /// works: a non-scrollable child silently disables pull-to-refresh.
  final bool scrollable;

  final EdgeInsets padding;

  const OasisErrorState({
    super.key,
    this.message,
    this.isConnectionError = false,
    this.onRetry,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(32, 56, 32, 100),
  });

  @override
  Widget build(BuildContext context) {
    final accent = isConnectionError
        ? AppTheme.profileColor
        : AppTheme.disputeColor;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isConnectionError
                ? Icons.wifi_off_rounded
                : Icons.error_outline_rounded,
            size: 34,
            color: accent,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          isConnectionError ? "You're offline" : 'Something went wrong',
          textAlign: TextAlign.center,
          style: AppTheme.sectionTitle(context),
        ),
        const SizedBox(height: 8),
        Text(
          message ??
              (isConnectionError
                  ? 'Check your internet connection and try again.'
                  : 'We could not load this right now. Please try again.'),
          textAlign: TextAlign.center,
          style: AppTheme.bodyText(context),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 24),
          _RetryButton(onRetry: onRetry!),
        ],
      ],
    );

    if (!scrollable) {
      return Padding(
        padding: padding,
        child: Center(child: content),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: [content],
    );
  }
}

/// Retry button that owns its own in-flight state, so the user gets immediate
/// feedback on a slow retry instead of tapping a dead control repeatedly.
class _RetryButton extends StatefulWidget {
  final Future<void> Function() onRetry;

  const _RetryButton({required this.onRetry});

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _retrying = false;

  Future<void> _run() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OasisButton(
        label: 'Try again',
        icon: Icons.refresh_rounded,
        expand: false,
        isBusy: _retrying,
        onPressed: _run,
      ),
    );
  }
}

/// Slim inline banner for when a refresh fails but cached content is still on
/// screen. Wiping usable content off the page over a failed background
/// refresh is worse than saying so quietly at the top.
class OasisErrorBanner extends StatelessWidget {
  final String message;
  final bool isConnectionError;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const OasisErrorBanner({
    super.key,
    required this.message,
    this.isConnectionError = false,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isConnectionError
        ? AppTheme.profileColor
        : AppTheme.disputeColor;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: AppTheme.isDarkMode(context) ? 0.18 : 0.08,
        ),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isConnectionError
                ? Icons.wifi_off_rounded
                : Icons.error_outline_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.bodyText(
                context,
                color: AppTheme.primaryTextColor(context),
              ).copyWith(fontSize: AppTheme.textSm - 1),
            ),
          ),
          if (onRetry != null)
            OasisPressable(
              onTap: onRetry,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ),
          if (onDismiss != null)
            OasisPressable(
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Empty state with an optional primary action.
///
/// An empty state without a next step is a dead end; every one of these that
/// can suggest an action now does.
class OasisEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool scrollable;
  final EdgeInsets padding;

  const OasisEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(32, 64, 32, 100),
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 32, color: AppTheme.primaryColor),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTheme.sectionTitle(context),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTheme.bodyText(context),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          Center(
            child: OasisButton(
              label: actionLabel!,
              icon: actionIcon,
              expand: false,
              onPressed: onAction,
            ),
          ),
        ],
      ],
    );

    if (!scrollable) {
      return Padding(
        padding: padding,
        child: Center(child: content),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: [content],
    );
  }
}
