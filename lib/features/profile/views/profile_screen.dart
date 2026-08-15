import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/sign_in_screen.dart';
import '../../properties/controllers/landlord_controller.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log Out',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.logoutColor,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out of your Landa OS account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.logoutColor,
            ),
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final authController = context.read<AuthController>();
      await authController.logout();

      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          FadePageRoute(page: const SignInScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final landlordController = context.watch<LandlordController>();
    final themeController = context.watch<ThemeController>();
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    final user = authController.currentUser;
    final isLandlord = authController.currentRole == UserRole.owner;

    final email = user?.email.isNotEmpty == true ? user!.email : 'Not provided';
    final phone = user?.phone.isNotEmpty == true ? user!.phone : 'Not provided';
    final verificationLabel = user?.verificationStatus.label ?? 'UNVERIFIED';
    final isVerified = user?.verificationStatus == VerificationStatus.verified;

    // Calculate real portfolio stats
    final totalProperties = landlordController.properties.length;
    int totalUnits = 0;
    for (final units in landlordController.propertyUnits.values) {
      totalUnits += units.length;
    }

    final pageBackgroundColor = isDarkTheme
        ? AppTheme.darkBackgroundColor
        : AppTheme.slateSurfaceColor;
    final surfaceColor = isDarkTheme ? AppTheme.darkCardColor : Colors.white;
    final borderColor = isDarkTheme
        ? AppTheme.profileColor.withOpacity(0.35)
        : Colors.grey.shade200;
    final primaryTextColor = isDarkTheme
        ? AppTheme.whiteColor
        : AppTheme.profileColor;
    final sectionLabelColor = isDarkTheme
        ? AppTheme.whiteColor.withOpacity(0.75)
        : Colors.grey;
    final secondaryTextColor = isDarkTheme
        ? AppTheme.whiteColor.withOpacity(0.72)
        : Colors.grey.shade700;

    return Scaffold(
      backgroundColor: pageBackgroundColor,
      appBar: AppBar(
        backgroundColor: pageBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile Settings',
          style: TextStyle(
            color: primaryTextColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Identity Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        isDarkTheme ? 0.18 : 0.04,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppTheme.profileColor,
                      child: Text(
                        email.isNotEmpty ? email[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isLandlord
                                      ? AppTheme.primaryColor.withOpacity(0.1)
                                      : AppTheme.secondaryColor.withOpacity(
                                          0.1,
                                        ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isLandlord ? 'LANDLORD / OWNER' : 'TENANT',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isLandlord
                                        ? AppTheme.primaryColor
                                        : AppTheme.secondaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isVerified
                                      ? AppTheme.successSurfaceColor
                                      : AppTheme.vacantSurfaceColor,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isVerified
                                        ? AppTheme.successColor.withOpacity(
                                            0.45,
                                          )
                                        : AppTheme.vacantColor.withOpacity(0.8),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isVerified
                                          ? Icons.check_circle
                                          : Icons.pending_outlined,
                                      size: 12,
                                      color: isVerified
                                          ? AppTheme.successColor
                                          : AppTheme.primaryColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      verificationLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isVerified
                                            ? AppTheme.successColor
                                            : AppTheme.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Portfolio Summary Stats (Landlord)
              if (isLandlord) ...[
                Text(
                  'PORTFOLIO SUMMARY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: sectionLabelColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROPERTIES',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: sectionLabelColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$totalProperties',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL UNITS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: sectionLabelColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$totalUnits',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // Account Details Card
              Text(
                'ACCOUNT DETAILS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: sectionLabelColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    _buildDetailTile(
                      context: context,
                      icon: Icons.email_outlined,
                      title: 'Email',
                      value: email,
                    ),
                    Divider(height: 1, color: borderColor),
                    _buildDetailTile(
                      context: context,
                      icon: Icons.phone_outlined,
                      title: 'Phone Number',
                      value: phone,
                    ),
                    Divider(height: 1, color: borderColor),
                    _buildDetailTile(
                      context: context,
                      icon: Icons.badge_outlined,
                      title: 'Role',
                      value: isLandlord ? 'Landlord / Owner' : 'Tenant',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'APPEARANCE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: sectionLabelColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.dark_mode_outlined,
                      color: primaryTextColor,
                      size: 20,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dark Mode',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Use the black theme across the app',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: themeController.isDarkMode,
                      activeColor: AppTheme.actionColor,
                      onChanged: themeController.setDarkMode,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Logout Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _handleLogout(context),
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.logoutColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
  }) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDarkTheme
        ? AppTheme.whiteColor
        : AppTheme.profileColor;
    final secondaryTextColor = isDarkTheme
        ? AppTheme.whiteColor.withOpacity(0.72)
        : Colors.grey.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: primaryTextColor, size: 20),
          const SizedBox(width: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: secondaryTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}
