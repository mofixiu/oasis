import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../models/portfolio_summary.dart';

class SummaryCardsSection extends StatelessWidget {
  final PortfolioSummary summary;

  const SummaryCardsSection({super.key, required this.summary});

  String formatCurrency(double amount) {
    String res = amount.toInt().toString();
    String formatted = '';
    for (int i = res.length - 1; i >= 0; i--) {
      formatted = res[i] + formatted;
      if ((res.length - i) % 3 == 0 && i != 0) {
        formatted = ',$formatted';
      }
    }
    return '₦ $formatted';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildCard(
          title: 'TOTAL RENT COLLECTED',
          icon: Icons.trending_up,
          iconColor: AppTheme.secondaryColor,
          mainValue: formatCurrency(summary.totalRentCollected),
          subText: '+${summary.rentGrowthPercentage}% from last month',
          subTextColor: AppTheme.secondaryColor,
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'ACTIVE LEASES',
          icon: Icons.description_outlined,
          iconColor: AppTheme.actionColor,
          mainValue: '${summary.activeLeases}',
          subText: '${summary.pendingRenewals} pending renewal',
          subTextColor: Colors.grey.shade600,
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'OUTSTANDING DUES',
          icon: Icons.warning_amber_rounded,
          iconColor: AppTheme.warningColor,
          mainValue: formatCurrency(summary.outstandingDues),
          subText: 'Across ${summary.outstandingUnitsCount} units',
          subTextColor: Colors.grey.shade600,
        ),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String mainValue,
    required String subText,
    required Color subTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            mainValue,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subText,
            style: TextStyle(
              fontSize: 12,
              color: subTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
