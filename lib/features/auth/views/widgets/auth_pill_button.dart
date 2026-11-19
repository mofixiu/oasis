import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/oasis_busy.dart';

/// The black pill that commits an auth form, as in the brand mockups: black
/// on the cream page for signing in or up, so the orange stays reserved for
/// the first call to action a visitor sees.
class AuthPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const AuthPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDarkMode(context);
    final fill = dark ? AppTheme.whiteColor : AppTheme.oasisBlack;
    final text = dark ? AppTheme.oasisBlack : AppTheme.whiteColor;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: text,
          disabledBackgroundColor: fill.withValues(alpha: 0.85),
          elevation: 0,
          shape: const StadiumBorder(),
        ),
        child: isLoading
            ? OasisBusyDots(color: text, size: 7)
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// "Already have an account? Sign in", with the link in the logo orange.
class AuthSwitchLink extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onTap;

  const AuthSwitchLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        '$prompt ',
        style: TextStyle(
          fontSize: 14,
          color: AppTheme.secondaryTextColor(context),
        ),
      ),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Text(
            action,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.linkColor(context),
            ),
          ),
        ),
      ),
    ],
  );
}
