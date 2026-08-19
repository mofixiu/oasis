import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class LandlordVaultView extends StatelessWidget {
  const LandlordVaultView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        24,
        20,
        100,
      ), // Bottom padding for navbar
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Available Balance Card (Dark Gradient)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A), // Deep Slate Navy
                  Color(0xFF1E293B), // Navy Slate
                  Color(0xFF0F172A), // Deep Navy
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AVAILABLE BALANCE',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),

                // Rich balance display with decimals
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    children: [
                      TextSpan(
                        text: '₦ 1,200,000',
                        style: TextStyle(fontSize: 32, letterSpacing: -1),
                      ),
                      TextSpan(
                        text: '.00',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Secured Label
                Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      color: Colors.greenAccent.shade400,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Secured by Landa Institutional Vault',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Withdraw Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.account_balance_outlined,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Withdraw to Bank',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.actionColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Pending In Escrow Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PENDING IN ESCROW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            '₦450,000.00',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Hold Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              border: Border.all(
                                color: const Color(0xFFFDE68A),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.access_time_filled,
                                  color: AppTheme.warningColor,
                                  size: 10,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'HOLD',
                                  style: TextStyle(
                                    color: AppTheme.warningColor,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Padlock and Clock Container
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lock_clock,
                        color: AppTheme.warningColor,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  'Expected release: Oct 24, 2023',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Annual Yield Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ANNUAL YIELD (YTD)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '+14.2%',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦8.4M Total generated',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                // Yield Icon Green Circle
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: AppTheme.secondaryColor,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Recent Payouts Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Payouts',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Text(
                  'View Statement',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.actionColor,
                  ),
                ),
                label: const Icon(
                  Icons.file_download_outlined,
                  size: 14,
                  color: AppTheme.actionColor,
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Recent Payouts Table-Like List
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              children: [
                // Table Headers
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'DATE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Text(
                          'DESTINATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'AMOUNT',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Rows
                _buildPayoutRow(
                  date: 'Oct 18, 2023',
                  bankName: 'GTBank Business',
                  mask: '**** 8821',
                  amount: '₦280,000',
                ),
                const Divider(height: 1),
                _buildPayoutRow(
                  date: 'Oct 12, 2023',
                  bankName: 'Zenith Savings',
                  mask: '**** 4432',
                  amount: '₦1,050,000',
                ),
                const Divider(height: 1),
                _buildPayoutRow(
                  date: 'Sep 28, 2023',
                  bankName: 'GTBank Business',
                  mask: '**** 8821',
                  amount: '₦1,200,000',
                  showBorder: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutRow({
    required String date,
    required String bankName,
    required String mask,
    required String amount,
    bool showBorder = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Date
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date.split(',')[0],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date.split(',')[1].trim(),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                ),
              ],
            ),
          ),

          // Destination
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.account_balance,
                    color: Colors.grey,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bankName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mask,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Expanded(
            flex: 3,
            child: Text(
              amount,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
