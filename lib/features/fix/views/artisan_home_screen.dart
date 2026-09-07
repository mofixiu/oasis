import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../controllers/fix_controller.dart';
import '../models/fix_models.dart';
import 'artisan_profile_sheet.dart';
import 'widgets/artisan_card.dart';

/// The whole of an artisan's app.
///
/// It used to be a job queue: requests arrived, the artisan accepted or
/// declined them, sent a price, marked the work done, and Landa moved the
/// money. API guide 18 removed all of it (§7B): Landa does not broker
/// repairs or artisan payments any more.
///
/// What is left is one job, and it is worth stating plainly rather than
/// dressing up: **be findable, and be accurate**. A landlord or tenant
/// searches a trade, reads this profile, and rings the number on it. Every
/// field here is the difference between being called and being scrolled past,
/// which is why the screen leads with the card exactly as they will see it
/// rather than with a form.
class ArtisanHomeScreen extends StatefulWidget {
  const ArtisanHomeScreen({super.key});

  @override
  State<ArtisanHomeScreen> createState() => _ArtisanHomeScreenState();
}

class _ArtisanHomeScreenState extends State<ArtisanHomeScreen>
    with AutoRefreshMixin<ArtisanHomeScreen> {
  @override
  Future<void> onAutoRefresh() => _reload();

  Future<void> _reload() async {
    final controller = context.read<FixController>();
    // Categories as well as the profile: the edit sheet needs the live trade
    // list, and an artisan who opens it to change trade should not be shown
    // the four defaults when the backend serves more.
    await Future.wait([
      controller.loadMyArtisanProfile(),
      controller.loadCategories(),
    ]);
  }

  Future<void> _edit() async {
    final saved = await openArtisanProfileSheet(context);
    if (saved && mounted) await refreshNow();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FixController>();
    final profile = controller.myProfile;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      // No Messages button: threads are landlord-to-tenant, and an artisan
      // has none. The bell stays: verification lands there.
      appBar: const LandaAppBar(showMessages: false),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _body(context, controller, profile),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    FixController controller,
    ArtisanProfile? profile,
  ) {
    if (!controller.hasLoaded(FixController.kMyProfileKey) && profile == null) {
      return const LandaSkeletonList(count: 2);
    }

    if (profile == null) {
      // The only screen this role has, so a failure here is the whole app
      // being blank. It gets the full state with a retry rather than a
      // banner over nothing.
      return LandaErrorState(
        message:
            controller.errorMessage ??
            'Could not load your profile. Pull down to try again.',
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Text(
          'Your listing',
          style: AppTheme.screenTitle(context, color: AppTheme.primaryColor),
        ),
        const SizedBox(height: 4),
        Text(
          'This is what a landlord or tenant sees when they search your '
          'trade. They call you directly. Landa does not take a cut and '
          'does not handle the payment.',
          style: AppTheme.bodyText(context),
        ),
        const SizedBox(height: 20),

        // The real card, not a mock-up of one. An artisan deciding whether a
        // bio is worth writing should be looking at the thing the bio goes
        // in, and a preview that drifts from the list is worse than none.
        ArtisanCard(artisan: profile, onTap: _edit),
        const SizedBox(height: 20),

        // What is missing, named. Everything here is optional to the backend
        // and decisive to whoever is choosing between four plumbers.
        _Completeness(profile: profile, onFix: _edit),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: LandaButton(
            label: 'Edit your details',
            icon: Icons.edit_outlined,
            onPressed: _edit,
          ),
        ),
        const SizedBox(height: 24),

        _Detail(
          icon: Icons.call_outlined,
          title: 'Your number is shown',
          body:
              'Landlords and tenants browsing your trade can see '
              '${profile.phone ?? 'your phone number'} and ring you. Change '
              'it from your account settings.',
        ),
        const SizedBox(height: 12),
        _Detail(
          icon: Icons.verified_user_outlined,
          title: 'Only verified artisans are listed',
          body:
              'Your verified badge is why somebody calls you instead of a '
              'number off a wall. It stays as long as your account does.',
        ),
        const SizedBox(height: 12),
        _Detail(
          icon: Icons.handshake_outlined,
          title: 'You agree the work directly',
          body:
              'Landa introduces you and stops there. The price, the timing '
              'and the payment are between you and whoever called.',
        ),
      ],
    );
  }
}

/// The fields that are empty, and why they matter.
///
/// A checklist rather than a percentage: "60% complete" tells an artisan
/// nothing they can act on, and the three things missing are each one line of
/// typing.
class _Completeness extends StatelessWidget {
  final ArtisanProfile profile;
  final VoidCallback onFix;

  const _Completeness({required this.profile, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final missing = <String>[
      if (profile.location.trim().isEmpty)
        'Where you work. Nobody searches without an area.',
      if (profile.bio.trim().isEmpty)
        'A line about yourself. It is the only thing that separates you '
            'from the next name on the list.',
      if (profile.yearsOfExperience <= 0) 'How long you have been doing this.',
    ];

    if (missing.isEmpty) {
      return _Detail(
        icon: Icons.check_circle_outline_rounded,
        accent: AppTheme.successColor,
        title: 'Your listing is complete',
        body:
            'Nothing is missing. Keep your area up to date if you move where '
            'you work.',
      );
    }

    return LandaPressable(
      onTap: onFix,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.actionColor.withValues(alpha: 0.07),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(
            color: AppTheme.actionColor.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  size: 18,
                  color: AppTheme.actionColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    missing.length == 1
                        ? 'One thing is missing'
                        : '${missing.length} things are missing',
                    style: AppTheme.cardTitle(
                      context,
                      color: AppTheme.actionColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in missing)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('· ', style: AppTheme.bodyText(context)),
                    Expanded(
                      child: Text(
                        item,
                        style: AppTheme.bodyText(
                          context,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One explanatory row. Quiet by design: these are the rules of the place,
/// not things to act on.
class _Detail extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color? accent;

  const _Detail({
    required this.icon,
    required this.title,
    required this.body,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppTheme.mutedTextColor(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.cardTitle(context)),
              const SizedBox(height: 2),
              Text(
                body,
                style: AppTheme.bodyText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
