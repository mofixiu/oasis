import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_network_image.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../dashboard/controllers/landlord_dashboard_controller.dart';
import '../../dashboard/models/property_unit.dart';
import '../../profile/views/profile_screen.dart';
import '../../../core/utils/fade_page_route.dart';

class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen>
    with AutoRefreshMixin<UnitsScreen> {
  @override
  Future<void> onAutoRefresh() =>
      context.read<LandlordDashboardController>().loadDashboardData();

  @override
  Widget build(BuildContext context) {
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        title: Text('Oasis', style: AppTheme.sectionTitle(context)),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              FadePageRoute(page: const ProfileScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: const AssetImage(
                  'assets/images/profile_avatar.png',
                ),
                backgroundColor: Colors.grey.shade300,
              ),
            ),
          ),
        ],
      ),
      body: Consumer<LandlordDashboardController>(
        builder: (context, controller, child) {
          if (controller.isLoading && controller.activeUnits == null) {
            return const OasisSkeletonList(count: 4, hasThumbnail: true);
          }

          if (controller.hasError && controller.activeUnits == null) {
            return RefreshIndicator(
              onRefresh: controller.loadDashboardData,
              child: OasisErrorState(
                message: controller.errorMessage,
                isConnectionError: controller.errorIsConnection,
                onRetry: controller.loadDashboardData,
              ),
            );
          }

          final units = controller.activeUnits ?? [];

          return RefreshIndicator(
            onRefresh: () => controller.loadDashboardData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Units',
                    style: AppTheme.screenTitle(
                      context,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Manage your property portfolio',
                    style: AppTheme.bodyText(
                      context,
                      color: secondaryTextColor,
                    ),
                  ),
                  if (controller.hasError) ...[
                    const SizedBox(height: 16),
                    OasisErrorBanner(
                      message: controller.errorMessage!,
                      isConnectionError: controller.errorIsConnection,
                      onRetry: controller.loadDashboardData,
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Portfolio Health Section
                  _PortfolioHealthSection(units: units),
                  const SizedBox(height: 32),

                  // Search and Filter Header
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.subtleSurfaceColor(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.borderColor(context),
                            ),
                          ),
                          child: TextField(
                            style: TextStyle(
                              color: AppTheme.profileTextColor(context),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search units, tenants...',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: AppTheme.mutedTextColor(context),
                              ),
                              border: InputBorder.none,
                              icon: Icon(
                                Icons.search,
                                color: AppTheme.mutedTextColor(context),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurfaceColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.borderColor(context),
                          ),
                        ),
                        child: const Icon(
                          Icons.tune,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Units List
                  if (units.isEmpty)
                    const OasisEmptyState(
                      icon: Icons.meeting_room_outlined,
                      title: 'No units yet',
                      message:
                          'Units you add to your properties will be listed here.',
                      scrollable: false,
                      padding: EdgeInsets.fromLTRB(8, 24, 8, 24),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: units.length,
                      itemBuilder: (context, index) {
                        final unit = units[index];
                        return OasisEntrance(
                          index: index,
                          child: _UnitCard(
                            unit: unit,
                            isLast: index == units.length - 1,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PortfolioHealthSection extends StatelessWidget {
  final List<PropertyUnit> units;

  const _PortfolioHealthSection({required this.units});

  @override
  Widget build(BuildContext context) {
    final int totalUnits = units.length;
    final int paidUnits = units
        .where((u) => u.status == UnitStatus.paid)
        .length;
    final double collectionRate = totalUnits > 0
        ? (paidUnits / totalUnits) * 100
        : 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.slateSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.profileColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PORTFOLIO HEALTH',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successSurface(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified,
                      color: AppTheme.successColor,
                      size: 12,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'VERIFIED AUDIT',
                      style: TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHealthStat(context, 'TOTAL UNITS', '$totalUnits'),
              _buildHealthStat(context, 'OCCUPANCY', '100%'),
              _buildHealthStat(
                context,
                'COLLECTION',
                '${collectionRate.toStringAsFixed(0)}%',
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: AppTheme.profileColor,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                'Your portfolio health is excellent this month.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade400,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTheme.sectionTitle(context, color: AppTheme.primaryColor),
        ),
      ],
    );
  }
}

class _UnitCard extends StatelessWidget {
  final PropertyUnit unit;
  final bool isLast;

  const _UnitCard({required this.unit, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // Unit Image
          OasisNetworkImage(
            url: unit.imagePath,
            width: 70,
            height: 70,
            borderRadius: AppTheme.cornerMd,
            placeholderIcon: Icons.home_outlined,
          ),
          const SizedBox(width: 16),

          // Unit Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unit.tenantName,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: unit.status == UnitStatus.paid
                            ? const Color(0xFFEFFFFA)
                            : const Color(0xFFFFFAEF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        unit.status == UnitStatus.paid ? 'PAID' : 'PENDING',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: unit.status == UnitStatus.paid
                              ? AppTheme.secondaryColor
                              : AppTheme.warningColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '₦${_formatAmount(unit.rentAmount)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right, color: Colors.grey.shade300),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    String res = amount.toInt().toString();
    String formatted = '';
    for (int i = res.length - 1; i >= 0; i--) {
      formatted = res[i] + formatted;
      if ((res.length - i) % 3 == 0 && i != 0) {
        formatted = ',$formatted';
      }
    }
    return formatted;
  }
}
