import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/network/auth_token_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/utils/landa_haptics.dart';
import '../../../core/widgets/landa_pressable.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';
import 'widgets/onboarding_art.dart';

/// One slide of the onboarding flow.
class _Slide {
  final String eyebrow;
  final String title;
  final String body;

  /// Tints the ambient glow, the eyebrow pill and the active page dot. The
  /// call to action stays terracotta on every slide: the accent is there to
  /// give each screen its own air, not to redefine the brand button.
  final Color accent;

  final Widget art;

  const _Slide({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.accent,
    required this.art,
  });
}

const List<_Slide> _slides = [
  _Slide(
    eyebrow: 'MARKETPLACE',
    title: 'Homes you can trust',
    body:
        'Browse listings with real photos, real prices and a landlord who has '
        'been checked. Apply in a few taps.',
    accent: AppTheme.terracottaColor,
    art: OnboardingListingArt(),
  ),
  _Slide(
    eyebrow: 'AGREEMENTS',
    title: 'Sign the lease right here',
    body:
        'Tenancy agreements are drafted, reviewed and signed inside Landa. No '
        'printing, no courier, no lost copies.',
    accent: AppTheme.sandColor,
    art: OnboardingAgreementArt(),
  ),
  _Slide(
    eyebrow: 'ESCROW',
    title: 'Rent that stays protected',
    body:
        'Your payment sits in escrow and is only released when the keys change '
        'hands. Payouts reach the landlord automatically.',
    accent: AppTheme.sageGreenColor,
    art: OnboardingEscrowArt(),
  ),
  _Slide(
    eyebrow: 'VERIFIED',
    title: 'Everyone here is verified',
    body:
        'Landlords and tenants both pass identity checks, and every document '
        'you sign is filed away in your vault.',
    accent: AppTheme.terracottaColor,
    art: OnboardingVerifiedArt(),
  ),
];

/// The first-run tour. Four slides, each a miniature of the part of Landa it
/// describes, ending on the sign-up call to action.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _controller = PageController();

  /// Fractional scroll position. Every moving part on this screen (parallax,
  /// glow colour, indicator) is driven off this single value so they stay in
  /// step with the finger instead of snapping on page-changed callbacks.
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final page = _controller.page ?? 0;
    if ((page - _page).abs() < 0.001) return;
    setState(() => _page = page);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  bool get _isLastSlide => _page > _slides.length - 1.5;

  Color get _accent {
    final lower = _page.floor().clamp(0, _slides.length - 1);
    final upper = (lower + 1).clamp(0, _slides.length - 1);
    return Color.lerp(
      _slides[lower].accent,
      _slides[upper].accent,
      _page - lower,
    )!;
  }

  Future<void> _leaveOnboarding(Widget destination) async {
    await AuthTokenStorage.setOnboardingCompleted();
    if (!mounted) return;
    Navigator.pushReplacement(context, FadePageRoute(page: destination));
  }

  void _advance() {
    if (_isLastSlide) {
      _leaveOnboarding(const SignUpScreen());
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDarkMode(context);
    final accent = _accent;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      body: Stack(
        children: [
          // Ambient wash behind everything. A flat background made the old
          // screen read as a form; a large, very soft field of the slide's
          // accent gives the illustration something to sit in.
          Positioned(
            top: -160,
            left: -110,
            child: _Glow(
              size: 460,
              color: accent.withValues(alpha: isDark ? 0.20 : 0.24),
            ),
          ),
          Positioned(
            bottom: -190,
            right: -140,
            child: _Glow(
              size: 420,
              color: accent.withValues(alpha: isDark ? 0.14 : 0.16),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _Header(
                  isDark: isDark,
                  showSkip: !_isLastSlide,
                  onSkip: () {
                    LandaHaptics.tap();
                    _leaveOnboarding(const SignUpScreen());
                  },
                ),

                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (_) => LandaHaptics.select(),
                    itemBuilder: (context, index) =>
                        _SlideView(slide: _slides[index], delta: _page - index),
                  ),
                ),

                _Footer(
                  page: _page,
                  count: _slides.length,
                  accent: accent,
                  isLastSlide: _isLastSlide,
                  onPrimary: _advance,
                  onSignIn: () => _leaveOnboarding(const SignInScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- header

class _Header extends StatelessWidget {
  final bool isDark;
  final bool showSkip;
  final VoidCallback onSkip;

  const _Header({
    required this.isDark,
    required this.showSkip,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(
            isDark
                ? 'assets/images/logo_wordmark_light.png'
                : 'assets/images/newlogonobackground.png',
            height: 30,
            fit: BoxFit.contain,
          ),
          // Kept in the tree at zero opacity rather than swapped out: removing
          // it on the last slide would shift the logo's row height.
          AnimatedOpacity(
            opacity: showSkip ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !showSkip,
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- slide

class _SlideView extends StatelessWidget {
  final _Slide slide;

  /// How far this slide is from resting position, in pages. 0 while it fills
  /// the screen, ±1 when it is exactly one page away.
  final double delta;

  const _SlideView({required this.slide, required this.delta});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final distance = delta.abs().clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        // The art box is the same height on every slide, so the illustration
        // never resizes as you swipe. Copy takes whatever is left; on short
        // screens the art gives way first.
        final artHeight = math.max(
          150.0,
          math.min(constraints.maxHeight * 0.54, constraints.maxHeight - 196),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: artHeight,
                // The PageView already carries this slide at 100% of the swipe;
                // adding a third of it back makes the art trail the copy, which
                // is what reads as depth.
                child: Transform.translate(
                  offset: Offset(delta * width * 0.32, 0),
                  child: Transform.scale(
                    scale: 1 - distance * 0.10,
                    child: Opacity(
                      opacity: 1 - distance * 0.6,
                      child: OnboardingArtFrame(child: slide.art),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Expanded(
                child: Transform.translate(
                  offset: Offset(delta * width * 0.08, distance * 18),
                  child: Opacity(
                    opacity: (1 - distance * 1.7).clamp(0.0, 1.0),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Eyebrow(label: slide.eyebrow, accent: slide.accent),
                          const SizedBox(height: 14),
                          Text(
                            slide.title,
                            style: AppTheme.screenTitle(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            slide.body,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              height: 1.55,
                              color: AppTheme.secondaryTextColor(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String label;
  final Color accent;

  const _Eyebrow({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    // Sand is a pale tint; at full strength on a light background its label
    // fails to read, so it borrows the deeper terracotta for text.
    final textColor = accent == AppTheme.sandColor
        ? (AppTheme.isDarkMode(context)
              ? AppTheme.sandColor
              : AppTheme.terracottaColor)
        : accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: textColor,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- footer

class _Footer extends StatelessWidget {
  final double page;
  final int count;
  final Color accent;
  final bool isLastSlide;
  final VoidCallback onPrimary;
  final VoidCallback onSignIn;

  const _Footer({
    required this.page,
    required this.count,
    required this.accent,
    required this.isLastSlide,
    required this.onPrimary,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Column(
        children: [
          _PageIndicator(page: page, count: count, accent: accent),
          const SizedBox(height: 22),
          // Cross-fading the whole button rather than just its label: the two
          // states are identical apart from the wording, so the dissolve reads
          // as the label changing rather than the button being replaced.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: LandaButton(
              key: ValueKey(isLastSlide),
              label: isLastSlide ? 'Create your account' : 'Continue',
              onPressed: onPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account?',
                style: TextStyle(
                  fontSize: AppTheme.textSm,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
              TextButton(
                onPressed: onSignIn,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Sign in',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.terracottaColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dots that stretch into a bar as their slide arrives. Driven by the
/// fractional page so the bar grows under the finger rather than after it.
class _PageIndicator extends StatelessWidget {
  final double page;
  final int count;
  final Color accent;

  const _PageIndicator({
    required this.page,
    required this.count,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final idle = AppTheme.mutedTextColor(context).withValues(alpha: 0.4);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final nearness = (1 - (page - index).abs()).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 7 + 21 * nearness,
          height: 7,
          decoration: BoxDecoration(
            color: Color.lerp(idle, accent, nearness),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

/// A soft field of colour. Cheap stand-in for a blur: a radial gradient with
/// a transparent outer stop has no edge to give it away.
class _Glow extends StatelessWidget {
  final double size;
  final Color color;

  const _Glow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
