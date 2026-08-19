import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/utils/landa_haptics.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/identity_verification_screen.dart';
import '../../auth/views/sign_in_screen.dart';
import '../../payments/controllers/payment_controller.dart';
import '../../properties/controllers/landlord_controller.dart';

/// Account screen: identity, verification standing, portfolio/tenancy figures,
/// account details and preferences.
///
/// Built around one idea — the user's verified identity is the product's whole
/// premise, so it gets the hero treatment at the top rather than being a chip
/// tucked beside an email address.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        icon: Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            color: AppTheme.logoutColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: AppTheme.logoutColor,
            size: 24,
          ),
        ),
        title: Text(
          'Log out?',
          textAlign: TextAlign.center,
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Text(
          'You will need to sign in again to reach your dashboard.',
          textAlign: TextAlign.center,
          style: AppTheme.bodyText(dialogContext),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            children: [
              Expanded(
                child: LandaButton(
                  label: 'Cancel',
                  outlined: true,
                  color: AppTheme.profileColor,
                  onPressed: () => Navigator.pop(dialogContext, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LandaButton(
                  label: 'Log out',
                  color: AppTheme.logoutColor,
                  onPressed: () => Navigator.pop(dialogContext, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final authController = context.read<AuthController>();
    await authController.logout();
    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      FadePageRoute(page: const SignInScreen()),
      (route) => false,
    );
  }

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    LandaToast.success(context, '$label copied');
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final landlordController = context.watch<LandlordController>();
    final agreementController = context.watch<AgreementController>();
    final paymentController = context.watch<PaymentController>();
    final themeController = context.watch<ThemeController>();

    final user = authController.currentUser;
    final isLandlord = authController.currentRole == UserRole.owner;
    final status = user?.verificationStatus ?? VerificationStatus.unverified;

    final email = user?.email ?? '';
    final phone = user?.phone.isNotEmpty == true ? user!.phone : 'Not provided';
    // The local part of the email is the closest thing to a display name the
    // backend gives us; capitalised so the header reads as a person, not a
    // login string.
    final handle = email.contains('@') ? email.split('@').first : email;
    final displayName = handle.isEmpty
        ? 'Your account'
        : handle[0].toUpperCase() + handle.substring(1);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: AppTheme.pageBackground(context),
            iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Account',
              style: TextStyle(color: AppTheme.primaryTextColor(context)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            sliver: SliverList.list(
              children: [
                LandaEntrance(
                  index: 0,
                  child: _IdentityHero(
                    displayName: displayName,
                    email: email,
                    isLandlord: isLandlord,
                    status: status,
                  ),
                ),
                if (status != VerificationStatus.verified) ...[
                  const SizedBox(height: 14),
                  LandaEntrance(
                    index: 1,
                    child: _VerificationCallout(status: status),
                  ),
                ],
                const SizedBox(height: 24),
                LandaEntrance(
                  index: 2,
                  child: _StatsStrip(
                    tiles: isLandlord
                        ? _landlordStats(landlordController)
                        : _tenantStats(
                            landlordController,
                            agreementController,
                            paymentController,
                          ),
                  ),
                ),
                const SizedBox(height: 28),
                LandaEntrance(
                  index: 3,
                  child: _Section(
                    label: 'ACCOUNT',
                    children: [
                      _DetailRow(
                        label: 'Email',
                        value: email.isEmpty ? 'Not provided' : email,
                        onTap: email.isEmpty
                            ? null
                            : () => _copy(context, 'Email', email),
                      ),
                      _DetailRow(
                        label: 'Phone',
                        value: phone,
                        onTap: user?.phone.isNotEmpty == true
                            ? () => _copy(context, 'Phone number', user!.phone)
                            : null,
                      ),
                      _DetailRow(
                        label: 'Role',
                        value: isLandlord ? 'Landlord / Owner' : 'Tenant',
                      ),
                      _DetailRow(
                        label: 'Identity',
                        value: _statusCopy(status),
                        valueColor: _statusColor(status),
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                LandaEntrance(
                  index: 4,
                  child: _Section(
                    label: 'PREFERENCES',
                    children: [
                      _SwitchRow(
                        title: 'Dark mode',
                        subtitle: 'Use the black theme across the app',
                        // Resolved brightness, not the stored choice: on
                        // ThemeMode.system the switch must show what the user
                        // is actually looking at.
                        value: AppTheme.isDarkMode(context),
                        onChanged: (value) {
                          LandaHaptics.select();
                          themeController.setDarkMode(value);
                        },
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                LandaEntrance(
                  index: 5,
                  child: LandaButton(
                    label: 'Log out',
                    icon: Icons.logout_rounded,
                    outlined: true,
                    color: AppTheme.logoutColor,
                    onPressed: () => _handleLogout(context),
                  ),
                ),
                const SizedBox(height: 28),
                const _BrandFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_StatTile> _landlordStats(LandlordController controller) {
    final units = controller.propertyUnits.values.expand((u) => u).toList();
    final occupied = units.where((u) => u.isOccupied).length;

    return [
      _StatTile(label: 'Properties', value: '${controller.properties.length}'),
      _StatTile(label: 'Units', value: '${units.length}'),
      _StatTile(
        label: 'Occupied',
        value: units.isEmpty ? '—' : '$occupied/${units.length}',
      ),
    ];
  }

  List<_StatTile> _tenantStats(
    LandlordController landlordController,
    AgreementController agreementController,
    PaymentController paymentController,
  ) {
    final unit = landlordController.tenantAssignedUnit;
    final executed = agreementController.agreements
        .where((a) => a.isExecuted)
        .length;

    return [
      _StatTile(label: 'My unit', value: unit == null ? '—' : unit.unitNumber),
      _StatTile(label: 'Agreements', value: '$executed'),
      _StatTile(
        label: 'Payments',
        value: '${paymentController.payments.length}',
      ),
    ];
  }
}

// --------------------------------------------------------------- identity

/// Gradient identity card. The avatar, name and standing sit on brand colour
/// so the top of the screen belongs to the user rather than to a form.
/// Identity header.
///
/// Deliberately not a coloured hero card: a saturated gradient block with a
/// circular avatar and pill badges is the default look every template ships
/// with, and it fights the restrained palette used everywhere else in the app.
/// This is the editorial alternative — a monogram tile, the name set large and
/// tight, and standing expressed as one line of small caps under a hairline.
class _IdentityHero extends StatelessWidget {
  final String displayName;
  final String email;
  final bool isLandlord;
  final VerificationStatus status;

  const _IdentityHero({
    required this.displayName,
    required this.email,
    required this.isLandlord,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isEmpty ? 'U' : displayName[0].toUpperCase();
    final verified = status == VerificationStatus.verified;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Squircle monogram rather than a circle avatar: it reads as a
            // considered mark instead of a placeholder photo slot.
            Container(
              height: 62,
              width: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.isDarkMode(context)
                    ? Colors.white.withValues(alpha: 0.06)
                    : AppTheme.profileColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: AppTheme.profileTextColor(context),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.screenTitle(
                            context,
                            color: AppTheme.profileTextColor(context),
                          ),
                        ),
                      ),
                      // Verified reads as a mark against the name, the way a
                      // verified account does everywhere else — not as a chip.
                      if (verified) ...[
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.verified_rounded,
                          size: 19,
                          color: AppTheme.successColor,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email.isEmpty ? 'No email on file' : email,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Divider(height: 1, color: AppTheme.borderColor(context)),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              (isLandlord ? 'Landlord' : 'Tenant').toUpperCase(),
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
            _Dot(),
            Text(
              _statusCopy(status).toUpperCase(),
              style: AppTheme.labelText(context, color: _statusColor(status)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Hairline separator between metadata items.
class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        height: 3,
        width: 3,
        decoration: BoxDecoration(
          color: AppTheme.mutedTextColor(context),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _VerificationCallout extends StatelessWidget {
  final VerificationStatus status;

  const _VerificationCallout({required this.status});

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(status);
    final pending = status == VerificationStatus.pending;

    return LandaPressable(
      onTap: pending
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const IdentityVerificationScreen(),
              ),
            ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accent.withValues(
            alpha: AppTheme.isDarkMode(context) ? 0.18 : 0.09,
          ),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(_statusIcon(status), size: 20, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pending ? 'Verification in review' : 'Verify your identity',
                    style: AppTheme.cardTitle(
                      context,
                      color: AppTheme.profileTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    pending
                        ? 'We are checking your NIN and selfie. This usually takes a few minutes.'
                        : 'Complete your NIN and liveness check to unlock payments and agreements.',
                    style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!pending) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: accent, size: 22),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ stats

class _StatTile {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});
}

/// Figures rail.
///
/// One card holding three columns split by hairlines, rather than three
/// separate cards each with its own tinted icon tile — fewer boxes, and the
/// numbers carry the section instead of the chrome around them.
class _StatsStrip extends StatelessWidget {
  final List<_StatTile> tiles;

  const _StatsStrip({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, tile) in tiles.indexed) ...[
              if (index > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppTheme.borderColor(context),
                ),
              Expanded(child: _StatColumn(tile: tile)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final _StatTile tile;

  const _StatColumn({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              tile.value,
              style: AppTheme.screenTitle(
                context,
                color: AppTheme.profileTextColor(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tile.label.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTheme.labelText(context).copyWith(fontSize: 9.5),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- sections

/// Labelled group of rows rendered as one card, so the screen reads as a few
/// deliberate blocks rather than a stack of loose containers.
class _Section extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _Section({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(label, style: AppTheme.labelText(context)),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: AppTheme.cornerLg,
            border: Border.all(color: AppTheme.borderColor(context)),
            boxShadow: AppTheme.cardShadow(context),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Label/value row.
///
/// No leading icon tile: a decorative glyph beside "Email" adds nothing a
/// reader did not already know, and a column of tinted squares is exactly the
/// texture that made the old screen look assembled from a kit.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final bool isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Text(label, style: AppTheme.bodyText(context)),
          // Expanded rather than Spacer + Flexible: the value gets every pixel
          // the label does not need, so a long email stays readable instead of
          // ellipsising with empty space beside it.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.cardTitle(
                  context,
                  color: valueColor ?? AppTheme.profileTextColor(context),
                ),
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.copy_rounded,
              size: 15,
              color: AppTheme.mutedTextColor(context),
            ),
          ],
        ],
      ),
    );

    return Column(
      children: [
        if (onTap == null)
          row
        else
          LandaPressable(
            onTap: onTap,
            // Rows sit flush against each other, so a scale dip on the whole
            // row would visibly overlap its neighbours.
            pressedScale: 0.995,
            child: row,
          ),
        if (!isLast)
          Divider(height: 1, indent: 18, color: AppTheme.borderColor(context)),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.cardTitle(
                        context,
                        color: AppTheme.profileTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeThumbColor: AppTheme.actionColor,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, indent: 18, color: AppTheme.borderColor(context)),
      ],
    );
  }
}

class _BrandFooter extends StatelessWidget {
  const _BrandFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 13,
              color: AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              'SECURED BY LANDA OS',
              style: AppTheme.labelText(context).copyWith(letterSpacing: 1.2),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'NIN-verified · Escrow-protected',
          style: AppTheme.bodyText(
            context,
            color: AppTheme.mutedTextColor(context),
          ).copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- helpers

String _statusCopy(VerificationStatus status) => switch (status) {
  VerificationStatus.verified => 'Verified',
  VerificationStatus.pending => 'Pending',
  VerificationStatus.failed => 'Failed',
  VerificationStatus.unverified => 'Unverified',
};

Color _statusColor(VerificationStatus status) => switch (status) {
  VerificationStatus.verified => AppTheme.successColor,
  VerificationStatus.pending => AppTheme.primaryColor,
  VerificationStatus.failed => AppTheme.disputeColor,
  VerificationStatus.unverified => AppTheme.primaryColor,
};

IconData _statusIcon(VerificationStatus status) => switch (status) {
  VerificationStatus.verified => Icons.verified_rounded,
  VerificationStatus.pending => Icons.hourglass_top_rounded,
  VerificationStatus.failed => Icons.error_outline_rounded,
  VerificationStatus.unverified => Icons.gpp_maybe_outlined,
};
