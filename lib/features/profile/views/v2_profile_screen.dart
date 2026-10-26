import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/utils/oasis_haptics.dart';
import '../../../core/widgets/oasis_network_image.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/v2_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/identity_verification_screen.dart';
import '../../auth/views/sign_in_screen.dart';
import '../../notifications/controllers/notification_controller.dart';
import '../../notifications/views/notifications_screen.dart';
import '../../payouts/controllers/payout_controller.dart';
import '../../payouts/views/payout_account_screen.dart';
import '../../shortlets/controllers/saved_shortlets_controller.dart';
import '../../shortlets/controllers/shortlet_controller.dart';
import '../../shortlets/views/my_shortlet_bookings_screen.dart';
import '../../shortlets/views/v2/v2_payments_screen.dart';
import '../../shortlets/views/v2/v2_saved_screen.dart';
import '../../shortlets/views/v2/v2_stay_widgets.dart';
import '../../vault/controllers/vault_controller.dart';
import '../../support/views/v2_help_screen.dart';
import '../../support/views/v2_terms_screen.dart';
import '../../vault/views/vault_pin_sheet.dart';
import 'v2_edit_profile_screen.dart';

/// The v2 account screen: who you are, shortcuts to your trips, money and
/// updates, your settings, and the way out.
class V2ProfileScreen extends StatefulWidget {
  const V2ProfileScreen({super.key});

  @override
  State<V2ProfileScreen> createState() => _V2ProfileScreenState();
}

class _V2ProfileScreenState extends State<V2ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthController>().refreshProfile();
      context.read<PayoutController>().loadPayoutAccount();
      context.read<VaultController>()
        ..loadVault()
        ..loadPinStatus();
    });
  }

  void _push(Widget page) => Navigator.push(context, FadePageRoute(page: page));

  Future<void> _logOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Log out?',
          textAlign: TextAlign.center,
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Text(
          'You will need to sign in again to see your trips.',
          textAlign: TextAlign.center,
          style: AppTheme.bodyText(dialogContext),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            children: [
              Expanded(
                child: OasisButton(
                  label: 'Cancel',
                  outlined: true,
                  color: AppTheme.profileColor,
                  onPressed: () => Navigator.pop(dialogContext, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OasisButton(
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
    if (confirmed != true || !mounted) return;

    await context.read<AuthController>().logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      FadePageRoute(page: const SignInScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.currentUser;
    final role = auth.currentRole;
    final isHost = role == UserRole.owner;
    final status = user?.verificationStatus ?? VerificationStatus.unverified;
    final email = user?.email ?? '';
    final displayName = user?.preferredName ?? 'Your account';
    final savedCount = context.select<SavedShortLetsController, int>(
      (controller) => controller.count,
    );

    final shortlets = context.watch<ShortLetController>();
    final upcoming = shortlets.bookings
        .where((booking) => !v2IsPastTrip(booking))
        .length;
    final vault = context.watch<VaultController>();
    final unread = context.select<NotificationController, int>(
      (controller) => controller.unreadCount,
    );
    final payout = context.watch<PayoutController>();
    final themeController = context.watch<ThemeController>();

    return V2StatusBar(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.paddingOf(context).bottom + 28,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: V2CircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  size: 40,
                  onTap: () => Navigator.maybePop(context),
                ),
              ),
              const SizedBox(height: 14),
              const V2PageHeader(
                title: 'Profile',
                subtitle: 'Manage your account, trips and preferences.',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              OasisPressable(
                onTap: () => _push(const V2EditProfileScreen()),
                pressedScale: 0.99,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      if (user?.avatarUrl.isNotEmpty ?? false)
                        ClipOval(
                          child: OasisNetworkImage(
                            url: user!.avatarUrl,
                            width: 64,
                            height: 64,
                            placeholderIcon: Icons.person,
                          ),
                        )
                      else
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppTheme.terracottaColor,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            displayName.characters.first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: AppTheme.cardTitle(context).copyWith(
                                fontSize: AppTheme.textLg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyText(context),
                            ),
                            if (user?.phone.isNotEmpty ?? false)
                              Text(
                                user!.phone,
                                style: AppTheme.bodyText(context),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.mutedTextColor(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (!isHost) ...[
                    Expanded(
                      child: _StatTile(
                        icon: Icons.favorite_border_rounded,
                        label: 'Saved',
                        value: v2Plural(savedCount, 'place', 'places'),
                        onTap: () => _push(const V2SavedScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _StatTile(
                      icon: isHost
                          ? Icons.holiday_village_outlined
                          : Icons.luggage_outlined,
                      label: isHost ? 'Bookings' : 'Trips',
                      value: v2Plural(upcoming, 'upcoming', 'upcoming'),
                      onTap: isHost
                          ? null
                          : () => _push(
                              const MyShortLetBookingsScreen(isV2: true),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.savings_outlined,
                      label: 'Vault',
                      value: vault.vault == null
                          ? '—'
                          : OasisCurrency.format(vault.availableBalance),
                      onTap: () =>
                          _push(const V2PaymentsScreen(isPushed: true)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.notifications_none_rounded,
                      label: 'Updates',
                      value: unread == 0 ? 'All read' : '$unread new',
                      onTap: () => _push(const NotificationsScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsRow(
                icon: Icons.person_outline_rounded,
                label: 'Personal information',
                onTap: () => _push(const V2EditProfileScreen()),
              ),
              _SettingsRow(
                icon: Icons.account_balance_outlined,
                label: 'Bank account',
                trailing: payout.isVerified
                    ? const V2StatusPill(label: 'Added', tone: V2Tone.positive)
                    : null,
                onTap: () => _push(const PayoutAccountScreen()),
              ),
              _SettingsRow(
                icon: Icons.lock_outline_rounded,
                label: 'Vault PIN',
                trailing: vault.hasLoadedPinStatus
                    ? V2StatusPill(
                        label: vault.hasVaultPin ? 'Set' : 'Not set',
                        tone: vault.hasVaultPin
                            ? V2Tone.positive
                            : V2Tone.pending,
                      )
                    : null,
                onTap: () => openVaultPinManager(context),
              ),
              _SettingsRow(
                icon: Icons.verified_user_outlined,
                label: 'Identity verification',
                trailing: V2StatusPill(
                  label: switch (status) {
                    VerificationStatus.verified => 'Verified',
                    VerificationStatus.pending => 'In review',
                    _ => 'Verify',
                  },
                  tone: switch (status) {
                    VerificationStatus.verified => V2Tone.positive,
                    VerificationStatus.pending => V2Tone.pending,
                    _ => V2Tone.negative,
                  },
                ),
                onTap:
                    status == VerificationStatus.verified ||
                        status == VerificationStatus.pending
                    ? null
                    : () => _push(const IdentityVerificationScreen()),
              ),
              // Three-way rather than a switch: an on/off control has no
              // way back to following the phone once it has been touched.
              const _SettingsRow(
                icon: Icons.dark_mode_outlined,
                label: 'Appearance',
                showDivider: false,
              ),
              Container(
                padding: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.borderColor(context)),
                  ),
                ),
                child: V2SegmentChips(
                  labels: const ['Match phone', 'Light', 'Dark'],
                  selected: switch (themeController.themeMode) {
                    ThemeMode.system => 0,
                    ThemeMode.light => 1,
                    ThemeMode.dark => 2,
                  },
                  onSelected: (index) {
                    OasisHaptics.select();
                    themeController.setThemeMode(
                      const [
                        ThemeMode.system,
                        ThemeMode.light,
                        ThemeMode.dark,
                      ][index],
                    );
                  },
                ),
              ),
              _SettingsRow(
                icon: Icons.help_outline_rounded,
                label: 'Help & support',
                onTap: () => _push(const V2HelpScreen()),
              ),
              _SettingsRow(
                icon: Icons.description_outlined,
                label: 'Terms & policies',
                showDivider: false,
                onTap: () => _push(const V2TermsScreen()),
              ),
              const SizedBox(height: 22),
              V2DestructiveButton(label: 'Log out', onTap: _logOut),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    child: Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: AppTheme.terracottaColor),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTheme.cardTitle(context).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyText(context).copyWith(fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const _SettingsRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.borderColor(context)),
              ),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.primaryTextColor(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: AppTheme.cardTitle(
                context,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          ?trailing,
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.mutedTextColor(context),
            ),
          ],
        ],
      ),
    ),
  );
}
