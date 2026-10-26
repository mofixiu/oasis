import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/oasis_app_bar.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_shimmer.dart';
import '../../../../core/widgets/oasis_state_views.dart';
import '../../controllers/shortlet_controller.dart';
import '../widgets/caution_fee_widgets.dart';
import 'v2_empty_state.dart';

class V2HostHomeScreen extends StatefulWidget {
  final VoidCallback onManageStays;

  const V2HostHomeScreen({super.key, required this.onManageStays});

  @override
  State<V2HostHomeScreen> createState() => _V2HostHomeScreenState();
}

class _V2HostHomeScreenState extends State<V2HostHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<ShortLetController>();
      controller.loadLandlordListings();
      controller.loadLandlordBookings();
    });
  }

  Future<void> _reload() {
    final controller = context.read<ShortLetController>();
    return Future.wait([
      controller.loadLandlordListings(),
      controller.loadLandlordBookings(),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.pageBackground(context),
    appBar: const OasisAppBar(shortLetOnlyProfile: true),
    body: Consumer<ShortLetController>(
      builder: (context, controller, _) {
        if (!controller.hasLoaded(ShortLetController.kListingsKey) &&
            controller.listings.isEmpty) {
          return const OasisSkeletonList(count: 3);
        }
        if (controller.hasError && controller.listings.isEmpty) {
          return OasisErrorState(
            message: controller.errorMessage,
            isConnectionError: controller.errorIsConnection,
            onRetry: _reload,
          );
        }
        if (controller.listings.isEmpty) {
          return V2IllustratedEmptyState(
            artwork: V2EmptyArtwork.hosting,
            title: 'Make room for your first guests.',
            message:
                'List a furnished place by the night, set your house rules, '
                'and decide who you welcome.',
            actionLabel: 'Manage shortlets',
            onAction: widget.onManageStays,
          );
        }

        final toInspect = controller.bookings
            .where((b) => b.isAwaitingCheckoutInspection)
            .toList();
        final liveBookings = controller.liveBookings.length;
        final paidBookings = controller.bookings
            .where((b) => b.status.isPaid)
            .length;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 118),
            children: [
              Text(
                'Hosting, made clearer.',
                style: AppTheme.screenTitle(context).copyWith(fontSize: 27),
              ),
              const SizedBox(height: 6),
              Text(
                'Your shortlets and guest requests, all in one place.',
                style: AppTheme.bodyText(context),
              ),
              const SizedBox(height: 22),
              if (toInspect.isNotEmpty) ...[
                _InspectionNudge(
                  count: toInspect.length,
                  soonest: toInspect
                      .map((b) => b.cautionClaimWindowLeft)
                      .whereType<Duration>()
                      .fold<Duration?>(
                        null,
                        (min, left) => min == null || left < min ? left : min,
                      ),
                  onTap: widget.onManageStays,
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'LISTED PLACES',
                      value: '${controller.listings.length}',
                      icon: Icons.holiday_village_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      label: 'NEEDS A REPLY',
                      value: '${controller.pendingBookingCount}',
                      icon: Icons.mark_chat_unread_outlined,
                      accent: AppTheme.terracottaColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _MetricCard(
                label: 'ACTIVE GUEST STAYS',
                value: '$liveBookings',
                icon: Icons.luggage_outlined,
                subtitle: '$paidBookings paid bookings',
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: AppTheme.cardShadow(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.white),
                    const SizedBox(height: 14),
                    const Text(
                      'A great booking starts with clear details.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Keep nightly prices, house rules and photos up to date. '
                      'Guests can see what to expect before they ask to book.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: widget.onManageStays,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Manage your shortlets'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Your places', style: AppTheme.sectionTitle(context)),
              const SizedBox(height: 12),
              for (final listing in controller.listings.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ListingSummary(
                    title: listing.title,
                    location: listing.location,
                    active: listing.isActive,
                    onTap: widget.onManageStays,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final String? subtitle;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: accent ?? AppTheme.profileColor),
        const SizedBox(height: 12),
        Text(label, style: AppTheme.labelText(context).copyWith(fontSize: 9)),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTheme.screenTitle(context).copyWith(fontSize: 25),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: AppTheme.bodyText(context).copyWith(fontSize: 11),
          ),
        ],
      ],
    ),
  );
}

class _ListingSummary extends StatelessWidget {
  final String title;
  final String location;
  final bool active;
  final VoidCallback onTap;
  const _ListingSummary({
    required this.title,
    required this.location,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: AppTheme.vacantSurface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.home_work_outlined,
              color: AppTheme.terracottaColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.cardTitle(context)),
                const SizedBox(height: 3),
                Text(
                  location,
                  style: AppTheme.bodyText(context).copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.successSurface(context)
                  : AppTheme.vacantSurface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              active ? 'Live' : 'Paused',
              style: AppTheme.labelText(context).copyWith(
                color: active ? AppTheme.successColor : AppTheme.primaryColor,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A prompt to inspect places guests have just left, before the caution fee
/// goes back to them on its own.
class _InspectionNudge extends StatelessWidget {
  final int count;
  final Duration? soonest;
  final VoidCallback? onTap;

  const _InspectionNudge({
    required this.count,
    required this.soonest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.isDarkMode(context)
        ? AppTheme.sandColor
        : const Color(0xFF85602F);
    return OasisPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.vacantSurface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ink.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? '1 checkout to inspect'
                        : '$count checkouts to inspect',
                    style: AppTheme.cardTitle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    soonest == null
                        ? 'Refund the caution fee or report damage within 24 '
                              'hours of checkout.'
                        : 'Refund the caution fee or report damage. '
                              '${cautionWindowLabel(soonest!)} on the next one.',
                    style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: ink),
          ],
        ),
      ),
    );
  }
}
