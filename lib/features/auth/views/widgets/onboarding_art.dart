import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/app_variant.dart';

/// Hand-built illustrations for the onboarding flow.
///
/// Each one is a miniature of the screen it is selling rather than a generic
/// icon in a circle: a listing card, a signed agreement, an escrow ledger, a
/// verified ID. Showing the product is what makes onboarding read as a real
/// app instead of a stock template, and it costs nothing at runtime because
/// everything here is Flutter primitives: no image pipeline, no animation
/// package.
///
/// Every piece is drawn on a fixed [kArtSize] canvas and scaled by the caller
/// with a [FittedBox]. Laying out at one known size is what lets the pieces be
/// composed by absolute position; the FittedBox handles every phone from an SE
/// to a Max without a single breakpoint.
const Size kArtSize = Size(300, 240);

/// Text colour for the copy inside a mini card.
///
/// Deliberately not [AppTheme.primaryTextColor], which resolves to terracotta
/// in light mode: on these vignettes that would put the listing title, the
/// price and the screen heading all in the same brand colour and flatten the
/// hierarchy. Ink here keeps terracotta meaning "this is the number that
/// matters".
Color _ink(BuildContext context) =>
    AppTheme.isDarkMode(context) ? AppTheme.whiteColor : AppTheme.blackColor;

/// Scales an illustration to whatever box the page gives it.
class OnboardingArtFrame extends StatelessWidget {
  final Widget child;

  const OnboardingArtFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: kArtSize.width,
        height: kArtSize.height,
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------- 1. listing

/// Marketplace: a real listing card sitting on top of the stack behind it.
class OnboardingListingArt extends StatelessWidget {
  const OnboardingListingArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The card behind carries no detail on purpose: it says "there are
        // more of these" without competing with the one being read.
        Positioned(
          left: 6,
          top: 30,
          child: Transform.rotate(
            angle: -0.085,
            child: Opacity(
              opacity: 0.9,
              child: _Panel(
                width: 152,
                height: 168,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 84,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.sandColor.withValues(alpha: 0.85),
                            AppTheme.terracottaColor.withValues(alpha: 0.55),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(17),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 14, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Skeleton(width: 96, height: 8),
                          SizedBox(height: 9),
                          _Skeleton(width: 64, height: 7),
                          SizedBox(height: 16),
                          _Skeleton(width: 78, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          left: 94,
          top: 6,
          child: Transform.rotate(
            angle: 0.028,
            child: _Panel(
              width: 194,
              height: 202,
              padding: EdgeInsets.zero,
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 96,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(17),
                          ),
                          child: Image.asset(
                            'assets/images/room_interior.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Scrim: the photo is bright at the top and the pill
                        // sitting on it would otherwise disappear.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(17),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.34),
                                Colors.black.withValues(alpha: 0.0),
                              ],
                              stops: const [0.0, 0.55],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          top: 10,
                          child: _MicroPill(
                            label: 'VERIFIED',
                            icon: Icons.verified_rounded,
                            color: AppTheme.whiteColor,
                            background: Colors.black.withValues(alpha: 0.42),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isOasisV2 ? '2 Bedroom Shortlet' : '2 Bedroom Flat',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: _ink(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Lekki Phase 1, Lagos',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.mutedTextColor(context),
                            ),
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text(
                                isOasisV2 ? '₦180,000' : '₦1,200,000',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: AppTheme.terracottaColor,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isOasisV2 ? '/night' : '/yr',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.mutedTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: const [
                              _MicroMeta(icon: Icons.bed_outlined, label: '2'),
                              SizedBox(width: 12),
                              _MicroMeta(
                                icon: Icons.shower_outlined,
                                label: '2',
                              ),
                              SizedBox(width: 12),
                              _MicroMeta(
                                icon: Icons.square_foot_rounded,
                                label: '96m²',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          bottom: 0,
          child: _Bob(
            child: _FloatingChip(
              icon: Icons.task_alt_rounded,
              label: isOasisV2 ? 'Request sent' : 'Application sent',
              accent: AppTheme.sageGreenColor,
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- 2. agreement

/// Agreements: a tenancy agreement that signs itself.
class OnboardingAgreementArt extends StatelessWidget {
  const OnboardingAgreementArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 40,
          top: 0,
          child: Transform.rotate(
            angle: -0.06,
            child: Opacity(
              opacity: 0.85,
              child: _Panel(
                width: 182,
                height: 180,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Skeleton(width: 74, height: 7),
                    SizedBox(height: 16),
                    _Skeleton(width: 148, height: 6),
                    SizedBox(height: 9),
                    _Skeleton(width: 132, height: 6),
                    SizedBox(height: 9),
                    _Skeleton(width: 150, height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          left: 70,
          top: 12,
          child: Transform.rotate(
            angle: 0.022,
            child: _Panel(
              width: 202,
              height: 196,
              elevated: true,
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppTheme.terracottaColor.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          Icons.description_rounded,
                          size: 13,
                          color: AppTheme.terracottaColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'TENANCY AGREEMENT',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.9,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Container(height: 1, color: AppTheme.borderColor(context)),
                  const SizedBox(height: 14),
                  const _Skeleton(width: 166, height: 6),
                  const SizedBox(height: 8),
                  const _Skeleton(width: 148, height: 6),
                  const SizedBox(height: 8),
                  const _Skeleton(width: 108, height: 6),
                  const Spacer(),
                  Text(
                    'SIGNED BY TENANT',
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppTheme.mutedTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  _Signature(color: _ink(context)),
                  Container(
                    width: 128,
                    height: 1,
                    color: AppTheme.borderColor(context),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Adaeze O.  ·  12 Aug 2026',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mutedTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // One callout, sitting below the sheet rather than on top of it. The
        // second chip this used to carry landed square on the signatory line,
        // which is the one detail the illustration exists to show.
        Positioned(
          left: 0,
          bottom: 0,
          child: _Bob(
            phase: 0.3,
            child: _FloatingChip(
              icon: Icons.verified_rounded,
              label: 'Legally binding',
              accent: AppTheme.sageGreenColor,
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- 3. escrow

/// Payments: money entering escrow on one side and leaving on the other.
class OnboardingEscrowArt extends StatefulWidget {
  const OnboardingEscrowArt({super.key});

  @override
  State<OnboardingEscrowArt> createState() => _OnboardingEscrowArtState();
}

class _OnboardingEscrowArtState extends State<OnboardingEscrowArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The track is painted first so the vault panel sits on top of it and
        // the travelling coin disappears into the vault rather than sliding
        // over it, which is the whole point of escrow.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _flow,
            builder: (context, _) => CustomPaint(
              painter: _EscrowFlowPainter(
                progress: _flow.value,
                trackColor: AppTheme.mutedTextColor(
                  context,
                ).withValues(alpha: 0.38),
                dotColor: AppTheme.terracottaColor,
              ),
            ),
          ),
        ),

        Positioned(
          left: 4,
          top: 12,
          child: _FlowNode(
            icon: Icons.person_rounded,
            label: isOasisV2 ? 'Guest pays' : 'Tenant pays',
            accent: AppTheme.slateGreyColor,
          ),
        ),

        Positioned(
          left: 62,
          top: 72,
          child: _Panel(
            width: 176,
            height: 110,
            elevated: true,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.terracottaColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 14,
                        color: AppTheme.terracottaColor,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'ESCROW',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: AppTheme.secondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  isOasisV2 ? '₦540,000' : '₦1,200,000',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: _ink(context),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const _PulseDot(color: AppTheme.sageGreenColor),
                    const SizedBox(width: 6),
                    // Expanded, not a bare Text: the label is the widest thing
                    // in the panel and any wording change would otherwise
                    // overflow the card rather than wrap.
                    Expanded(
                      child: Text(
                        isOasisV2
                            ? 'Held safely by Oasis'
                            : 'Held until move-in day',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mutedTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        Positioned(
          right: 2,
          bottom: 8,
          child: _FlowNode(
            icon: Icons.account_balance_rounded,
            label: isOasisV2 ? 'Host paid' : 'Landlord paid',
            accent: AppTheme.sageGreenColor,
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- 4. verified

/// Identity: both sides of the deal are a checked, real person.
class OnboardingVerifiedArt extends StatelessWidget {
  const OnboardingVerifiedArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 34,
          top: 8,
          child: Transform.rotate(
            angle: -0.07,
            child: Opacity(
              opacity: 0.85,
              child: _Panel(
                width: 184,
                height: 116,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.sandColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Skeleton(width: 88, height: 7),
                          SizedBox(height: 8),
                          _Skeleton(width: 62, height: 6),
                          SizedBox(height: 8),
                          _Skeleton(width: 74, height: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          left: 42,
          top: 62,
          child: Transform.rotate(
            angle: 0.02,
            child: _Panel(
              width: 212,
              height: 134,
              elevated: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.terracottaColor.withValues(alpha: 0.22),
                              AppTheme.sandColor.withValues(alpha: 0.32),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          size: 24,
                          color: AppTheme.terracottaColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Adaeze Okafor',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: _ink(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _MicroPill(
                              label: 'NIN VERIFIED',
                              icon: Icons.check_circle_rounded,
                              color: AppTheme.sageGreenColor,
                              background: AppTheme.sageGreenColor.withValues(
                                alpha: 0.14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(height: 1, color: AppTheme.borderColor(context)),
                  const SizedBox(height: 11),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _IdField(label: 'ID', value: '•••• 4821'),
                      _IdField(label: 'CHECKED', value: '12 Aug'),
                      _IdField(label: 'STATUS', value: 'Active'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // The seal overlaps the card edge: a badge fully inside the card
        // reads as content, one breaking the edge reads as a stamp.
        Positioned(
          right: 18,
          top: 44,
          child: _Bob(
            amplitude: 3.5,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.sageGreenColor,
                border: Border.all(
                  color: AppTheme.surfaceColor(context),
                  width: 3.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.sageGreenColor.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          bottom: 6,
          child: _Bob(
            phase: 0.4,
            child: _FloatingChip(
              icon: Icons.folder_shared_rounded,
              label: isOasisV2
                  ? 'Guests & hosts checked'
                  : 'Docs in your vault',
              accent: AppTheme.slateGreyColor,
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ pieces

/// A card surface matching the app's own cards, at illustration scale.
class _Panel extends StatelessWidget {
  final double width;
  final double height;
  final Widget child;
  final EdgeInsets padding;
  final bool elevated;

  const _Panel({
    required this.width,
    required this.height,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: elevated
            ? AppTheme.elevatedSurfaceColor(context)
            : AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: elevated
            ? AppTheme.raisedShadow(context)
            : AppTheme.cardShadow(context),
      ),
      child: child,
    );
  }
}

/// Placeholder copy inside a mini card. Real sentences at 6px are unreadable
/// noise; bars read as "text" instantly.
class _Skeleton extends StatelessWidget {
  final double width;
  final double height;

  const _Skeleton({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.mutedTextColor(context).withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

class _MicroPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  const _MicroPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroMeta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MicroMeta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.mutedTextColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _IdField extends StatelessWidget {
  final String label;
  final String value;

  const _IdField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppTheme.mutedTextColor(context),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _ink(context),
          ),
        ),
      ],
    );
  }
}

/// A labelled endpoint on the escrow flow.
class _FlowNode extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _FlowNode({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: _ink(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small status dot that breathes, so the escrow card doesn't look frozen.
class _PulseDot extends StatefulWidget {
  final Color color;

  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.20 + 0.35 * t),
                blurRadius: 2 + 5 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A callout that sits off the edge of the main card.
class _FloatingChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _FloatingChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.elevatedSurfaceColor(context),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.raisedShadow(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: _ink(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gentle vertical drift. Floating callouts that are perfectly still look
/// pasted on; a couple of pixels of movement is what sells them as floating.
class _Bob extends StatefulWidget {
  final Widget child;
  final double amplitude;

  /// 0–1 offset into the cycle, so several chips on one screen never bob in
  /// lockstep.
  final double phase;

  const _Bob({required this.child, this.amplitude = 4.5, this.phase = 0});

  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value + widget.phase) % 1.0;
        return Transform.translate(
          offset: Offset(0, math.sin(t * 2 * math.pi) * widget.amplitude),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A signature that draws itself, holds, and redraws.
class _Signature extends StatefulWidget {
  final Color color;

  const _Signature({required this.color});

  @override
  State<_Signature> createState() => _SignatureState();
}

class _SignatureState extends State<_Signature>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Draw over the first third of the cycle, then hold the finished
        // signature for the rest: a nib that never stops moving is a fidget,
        // not a flourish.
        final raw = (_controller.value / 0.34).clamp(0.0, 1.0);
        return CustomPaint(
          size: const Size(134, 34),
          painter: _SignaturePainter(
            color: widget.color,
            progress: Curves.easeInOut.transform(raw),
          ),
        );
      },
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final Color color;
  final double progress;

  const _SignaturePainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;

    // Every segment gets its own amplitude and a different overshoot. Evenly
    // sized humps read as a sine wave, which is exactly how the first version
    // of this looked; handwriting is irregular by definition.
    final path = Path()
      ..moveTo(w * 0.03, h * 0.88)
      ..cubicTo(w * 0.04, h * 0.10, w * 0.12, h * -0.28, w * 0.15, h * 0.14)
      ..cubicTo(w * 0.19, h * 0.50, w * 0.12, h * 0.78, w * 0.16, h * 0.92)
      ..cubicTo(w * 0.19, h * 1.02, w * 0.25, h * 0.64, w * 0.27, h * 0.36)
      ..cubicTo(w * 0.29, h * 0.14, w * 0.34, h * 0.26, w * 0.33, h * 0.64)
      ..cubicTo(w * 0.32, h * 0.98, w * 0.39, h * 1.00, w * 0.42, h * 0.50)
      ..cubicTo(w * 0.45, h * 0.10, w * 0.51, h * 0.32, w * 0.50, h * 0.74)
      ..cubicTo(w * 0.49, h * 1.04, w * 0.57, h * 0.88, w * 0.61, h * 0.42)
      ..cubicTo(w * 0.65, h * 0.04, w * 0.73, h * 0.36, w * 0.79, h * 0.62)
      // One long trailing flourish: the stroke that makes it read as a
      // signature rather than a scribble.
      ..cubicTo(w * 0.87, h * 0.96, w * 0.93, h * 0.70, w * 0.99, h * 0.30);

    final drawn = Path();
    for (final metric in path.computeMetrics()) {
      drawn.addPath(
        metric.extractPath(0, metric.length * progress),
        Offset.zero,
      );
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SignaturePainter old) =>
      old.progress != progress || old.color != color;
}

/// The dashed track between tenant, escrow and landlord, plus the payment
/// travelling along it.
class _EscrowFlowPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color dotColor;

  const _EscrowFlowPainter({
    required this.progress,
    required this.trackColor,
    required this.dotColor,
  });

  Path _buildPath() {
    return Path()
      ..moveTo(56, 54)
      ..cubicTo(56, 92, 84, 104, 118, 118)
      ..cubicTo(168, 138, 214, 148, 236, 166)
      ..cubicTo(256, 182, 254, 194, 254, 206);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath();

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Dashes, drawn by walking the path: a solid line would read as a
    // connector, dashes read as movement waiting to happen.
    const dash = 6.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = math.min(start + dash, metric.length);
        canvas.drawPath(metric.extractPath(start, end), trackPaint);
        start = end + gap;
      }
    }

    for (final metric in path.computeMetrics()) {
      final tangent = metric.getTangentForOffset(metric.length * progress);
      if (tangent == null) continue;
      final p = tangent.position;

      canvas.drawCircle(
        p,
        11,
        Paint()..color = dotColor.withValues(alpha: 0.16),
      );
      canvas.drawCircle(p, 5.5, Paint()..color = dotColor);
      canvas.drawCircle(
        p,
        5.5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(_EscrowFlowPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.dotColor != dotColor;
}
