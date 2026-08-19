import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Rent due summary card showing amount due, vault progress, and actions.
class RentDueCard extends StatelessWidget {
  const RentDueCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with label and status pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NEXT RENT DUE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.secondaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'ON TRACK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Amount
          const Text(
            '₦450,000',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryColor,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Due by October 1st, 2023',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          // Vault Progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Rent Vault Progress',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              Text(
                '₦200,000 Saved',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Custom Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: 45, // 45% saved
                  child: Container(
                    height: 8,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.actionColor, AppTheme.secondaryColor],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 55,
                  child: Container(height: 8, color: Colors.grey.shade200),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Percentage text
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '45% of total due',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Pay Now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Add to Vault'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
