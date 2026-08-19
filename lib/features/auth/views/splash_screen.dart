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
    // The tagline is the only line of copy on the screen, so it is set in
    // full-strength brand colour. At 0.35 alpha it read as a rendering
    // artefact rather than a deliberate mark.
    final accentTextColor = isDarkMode
        ? AppTheme.sandColor
        : AppTheme.terracottaColor;
    final footerTextColor = isDarkMode
        ? AppTheme.whiteColor.withValues(alpha: 0.42)
        : AppTheme.profileColor.withValues(alpha: 0.55);

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
                    // The navy wordmark disappears on the dark background, so
                    // dark mode gets the white-on-transparent variant.
                    Image.asset(
                      isDarkMode
                          ? 'assets/images/logo_wordmark_light.png'
                          : 'assets/images/newlogonobackground.png',
                      height: 104,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'RADICAL CLARITY',
                      style: TextStyle(
                        color: accentTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4.5,
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
