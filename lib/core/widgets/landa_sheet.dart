import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/landa_haptics.dart';
import 'landa_busy.dart';
import 'landa_pressable.dart';

/// Shared chrome for the app's bottom sheets.
///
/// Every sheet gets the same grab handle, header block and pinned footer so
/// they read as one family instead of a set of forms that happen to slide up
/// from the bottom. The body scrolls under the header; the footer action stays
/// on screen and rides above the keyboard.
class LandaSheet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  /// Pinned action area. Usually a [LandaSheetButton].
  final Widget? footer;

  /// Tint for the header icon badge. Defaults to the action terracotta.
  final Color? accent;

  const LandaSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppTheme.actionColor;
    final surface = AppTheme.surfaceColor(context);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _GrabHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: AppTheme.cornerMd,
                  ),
                  child: Icon(icon, color: tint, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.sectionTitle(
                          context,
                        ).copyWith(fontSize: 19, letterSpacing: -0.45),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: AppTheme.bodyText(context)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _CloseButton(onTap: () => Navigator.pop(context)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
          if (footer != null)
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    16,
              ),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  top: BorderSide(color: AppTheme.borderColor(context)),
                ),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 14),
    child: Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(
        color: AppTheme.mutedTextColor(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    pressedScale: 0.9,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.close_rounded,
        size: 17,
        color: AppTheme.secondaryTextColor(context),
      ),
    ),
  );
}

/// Small uppercase label that sits above a field or a group of fields.
class LandaFieldLabel extends StatelessWidget {
  final String label;

  /// Optional right-aligned affordance, e.g. a "use live location" action.
  final Widget? trailing;

  const LandaFieldLabel(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// The one input look for sheets: soft filled field, hairline border, and a
/// terracotta ring on focus. Material's default outlined field is what made
/// these forms read as a prototype.
InputDecoration landaInputDecoration(
  BuildContext context, {
  String? hint,
  IconData? prefixIcon,
  Widget? suffix,
}) {
  final border = OutlineInputBorder(
    borderRadius: AppTheme.cornerMd,
    borderSide: BorderSide(color: AppTheme.borderColor(context)),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTheme.bodyText(
      context,
      color: AppTheme.mutedTextColor(context),
    ),
    filled: true,
    fillColor: AppTheme.subtleSurfaceColor(context),
    isDense: true,
    contentPadding: EdgeInsets.fromLTRB(
      prefixIcon == null ? 16 : 4,
      16,
      16,
      16,
    ),
    prefixIcon: prefixIcon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              prefixIcon,
              size: 19,
              color: AppTheme.mutedTextColor(context),
            ),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppTheme.actionColor, width: 1.5),
    ),
    errorBorder: border.copyWith(
      borderSide: const BorderSide(color: AppTheme.brickRedColor),
    ),
  );
}

/// Full-width action button used at the foot of a sheet.
class LandaSheetButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? color;

  const LandaSheetButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final background = enabled
        ? (color ?? AppTheme.actionColor)
        : AppTheme.subtleSurfaceColor(context);
    final foreground = enabled
        ? Colors.white
        : AppTheme.mutedTextColor(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 54,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.cornerMd,
        border: enabled
            ? null
            : Border.all(color: AppTheme.borderColor(context)),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: (color ?? AppTheme.actionColor).withValues(
                    alpha: 0.28,
                  ),
                  blurRadius: 18,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: LandaPressable(
        onTap: enabled ? onPressed : null,
        pressedScale: 0.985,
        // A sheet's primary button is the commit: pay, apply, submit, sign.
        // The generic tap would understate every one of them.
        hapticOnTap: false,
        onTapHaptic: LandaHaptics.commit,
        child: Stack(
          children: [
            // The label stays put while the request runs. Swapping it for a
            // wheel loses the one thing on screen that says what is
            // happening, and makes the button visibly change size.
            Positioned.fill(
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 18,
                        color: foreground.withValues(
                          alpha: isLoading ? 0.65 : 1,
                        ),
                      ),
                      const SizedBox(width: 9),
                    ],
                    Text(
                      label,
                      style: AppTheme.cardTitle(
                        context,
                        color: foreground.withValues(
                          alpha: isLoading ? 0.65 : 1,
                        ),
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            if (isLoading)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LandaBusyBar(color: foreground),
              ),
          ],
        ),
      ),
    );
  }
}

/// Soft secondary action used inside a sheet body (photo pickers, etc).
class LandaSheetChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const LandaSheetChipButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.actionColor.withValues(alpha: 0.07),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: AppTheme.actionColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppTheme.actionColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.cardTitle(
              context,
              color: AppTheme.actionColor,
            ).copyWith(fontSize: AppTheme.textSm, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
