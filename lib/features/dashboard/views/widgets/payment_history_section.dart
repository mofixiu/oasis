import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Section showing the recent payment history transactions.
class PaymentHistorySection extends StatelessWidget {
  const PaymentHistorySection({super.key});

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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Payment History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View All',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // List Items
          _buildPaymentItem(
            title: 'September Rent',
            date: 'Paid on Aug 28, 2023',
            amount: '₦450,000',
            status: 'PAID',
            icon: Icons.receipt_long,
          ),
          const Divider(height: 32, thickness: 1, color: Color(0xFFF1F5F9)),
          _buildPaymentItem(
            title: 'August Rent',
            date: 'Paid on Jul 30, 2023',
            amount: '₦450,000',
            status: 'PAID',
            icon: Icons.receipt_long,
          ),
          const Divider(height: 32, thickness: 1, color: Color(0xFFF1F5F9)),
          _buildPaymentItem(
            title: 'Facility Maintenance Fee',
            date: 'Due Jun 15, 2023',
            amount: '₦25,000',
            status: 'DEBT',
            isWarning: true,
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentItem({
    required String title,
    required String date,
    required String amount,
    required String status,
    required IconData icon,
    Color iconColor = Colors.grey,
    bool isWarning = false,
  }) {
    final statusColor = status == 'PAID' ? AppTheme.secondaryColor : Colors.red;
    
    return Row(
      children: [
        // Leading Icon Container
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isWarning ? Colors.red.withOpacity(0.1) : Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        
        // Title & Date
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        
        // Amount & Status Pill
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              amount,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
