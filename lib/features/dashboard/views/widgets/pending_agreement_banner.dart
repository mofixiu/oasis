import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class PendingAgreementBanner extends StatelessWidget {
  const PendingAgreementBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // Very light yellow/amber
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFDE68A),
        ), // Light amber border
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFD97706),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Action Required:\nSign Tenancy\nAgreement in Settings',
                  style: AppTheme.sectionTitle(
                    context,
                    // Dark amber, for the warning surface this sits on.
                    color: const Color(0xFF92400E),
                  ).copyWith(height: 1.2),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your lease renewal is pending signature.\nPlease review and sign to avoid late\nfees.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309), // Amber text
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B), // Action color
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Review',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
