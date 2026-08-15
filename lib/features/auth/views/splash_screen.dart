import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/auth_token_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/main_scaffold.dart';
import '../controllers/auth_controller.dart';
import '../models/user_model.dart';
import 'identity_verification_screen.dart';
import 'sign_in_screen.dart';
import 'welcome_screen.dart';

/// A modern, minimalist Splash Screen for Landa OS.
/// Renders a white/soft-grey background and applies a premium scale and fade-in
/// animation to the Landa logo. Once finished and auth check completes, it dynamically
/// routes to the WelcomeScreen (first time only), SignInScreen, or MainScaffold based on auth state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _animationCompleted = false;

  @override
  void initState() {
    super.initState();

    // 1. Setup high-fidelity 2-second ease-out animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();

    // 2. Schedule navigation immediately after the animation completes and auth status resolves
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationCompleted = true;
        _navigateToNextScreen();
      }
    });
  }

  void _navigateToNextScreen() async {
    if (!mounted || !_animationCompleted) return;

    final authController = context.read<AuthController>();

    // Wait until background auth check completes
    while (authController.isLoading && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    Widget targetScreen;
    if (authController.isAuthenticated) {
      final user = authController.currentUser;
      targetScreen = (user?.verificationStatus != VerificationStatus.verified)
          ? const IdentityVerificationScreen()
          : const MainScaffold();
    } else {
      final onboardingDone = await AuthTokenStorage.isOnboardingCompleted();
      targetScreen = onboardingDone
          ? const SignInScreen()
          : const WelcomeScreen();
    }

    if (!mounted) return;

    // 3. Modern smooth fade page transition
    Navigator.of(context).pushReplacement(FadePageRoute(page: targetScreen));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = AppTheme.isDarkMode(context);
    final backgroundColor = AppTheme.pageBackground(context);
    final accentTextColor = isDarkMode
        ? AppTheme.whiteColor.withOpacity(0.55)
        : AppTheme.primaryColor.withOpacity(0.35);
    final footerTextColor = isDarkMode
        ? AppTheme.whiteColor.withOpacity(0.4)
        : AppTheme.primaryColor.withOpacity(0.25);
    final logoShellColor = isDarkMode
        ? AppTheme.whiteColor.withOpacity(0.08)
        : Colors.transparent;
    final logoShellBorder = isDarkMode
        ? AppTheme.whiteColor.withOpacity(0.08)
        : Colors.transparent;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background layout
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDarkMode ? 24 : 0,
                        vertical: isDarkMode ? 20 : 0,
                      ),
                      decoration: BoxDecoration(
                        color: logoShellColor,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: logoShellBorder),
                      ),
                      child: Image.asset(
                        'assets/images/newlogonobackground.png',
                        height: 52,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'RADICAL CLARITY',
                      style: TextStyle(
                        color: accentTextColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Secure end-to-end indicator at bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: footerTextColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SECURED BY LANDA OS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: footerTextColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
