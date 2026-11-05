import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../models/shortlet_details.dart';
import '../../models/shortlet_models.dart';

// ------------------------------------------------------------- slideshow

/// The small auto-playing slideshow at the top of "Where is your place?".
///
/// It is the first screen of listing, so it sets the tone: what happens to
/// the place once it is on Oasis, in four short frames. Photos and drawn
/// vignettes alternate so it never reads as a stock carousel.
class ListPlaceSlideshow extends StatefulWidget {
  const ListPlaceSlideshow({super.key});

  @override
  State<ListPlaceSlideshow> createState() => _ListPlaceSlideshowState();
}

class _ListPlaceSlideshowState extends State<ListPlaceSlideshow> {
  static const _interval = Duration(milliseconds: 3800);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  static const _slides = <_Slide>[
    _Slide(
      title: 'Your place, ready for guests',
      body: 'A few short steps and you are live.',
      photo: 'assets/images/room_interior.png',
    ),
    _Slide(
      title: 'Pin it once',
      body: 'Guests see the area. The exact address unlocks after they pay.',
      art: _SlideArt.map,
    ),
    _Slide(
      title: 'You stay in control',
      body: 'Approve every booking before anyone pays.',
      photo: 'assets/images/quality_hero.png',
    ),
    _Slide(
      title: 'Paid through Oasis',
      body: 'Guests pay in the app. Your payout goes to your bank.',
      art: _SlideArt.payout,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restartTimer());
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!mounted) return;
    // Someone who has asked the phone for less motion gets a still image
    // they can still swipe through.
    if (MediaQuery.of(context).disableAnimations) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % _slides.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  /// A tap moves on a slide, for anyone who wants to read faster than the
  /// clock turns the pages.
  void _next() {
    if (!_controller.hasClients) return;
    _controller.animateToPage(
      (_page + 1) % _slides.length,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 176,
            child: NotificationListener<ScrollStartNotification>(
              // A swipe resets the clock, so the slide the host just chose
              // is not snatched away a second later.
              onNotification: (notification) {
                if (notification.dragDetails != null) _restartTimer();
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: _next,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      // A gentle parallax on the artwork as the page moves.
                      final offset =
                          _controller.hasClients &&
                              _controller.position.haveDimensions
                          ? (_controller.page ?? 0) - index
                          : 0.0;
                      return _SlideView(slide: _slides[index], offset: offset);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page
                      ? AppTheme.terracottaColor
                      : AppTheme.borderColor(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

enum _SlideArt { map, payout }

class _Slide {
  final String title;
  final String body;
  final String? photo;
  final _SlideArt? art;

  const _Slide({required this.title, required this.body, this.photo, this.art});
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  final double offset;

  const _SlideView({required this.slide, required this.offset});

  @override
  Widget build(BuildContext context) {
    final photo = slide.photo;
    final isPhoto = photo != null;
    final textColor = isPhoto ? Colors.white : AppTheme.blackColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isPhoto)
          Transform.translate(
            offset: Offset(offset * 40, 0),
            child: Transform.scale(
              scale: 1.15,
              child: Image.asset(photo, fit: BoxFit.cover),
            ),
          )
        else
          Container(
            color: slide.art == _SlideArt.map
                ? AppTheme.creamRecessedColor
                : AppTheme.vacantSurfaceColor,
            child: Transform.translate(
              offset: Offset(offset * 30, 0),
              child: slide.art == _SlideArt.map
                  ? const _MapArt()
                  : const _PayoutArt(),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: isPhoto
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                    stops: [0.3, 1],
                  )
                // The drawn slides are light, so the caption gets a light
                // wash from the left instead, to lift it off the artwork.
                : LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      AppTheme.creamColor.withValues(alpha: 0.95),
                      AppTheme.creamColor.withValues(alpha: 0),
                    ],
                    stops: const [0.3, 0.75],
                  ),
          ),
        ),
        Positioned(
          left: 16,
          right: isPhoto ? 16 : 120,
          bottom: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                slide.title,
                style: TextStyle(
                  color: textColor,
                  fontSize: AppTheme.textLg,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                slide.body,
                style: TextStyle(
                  color: textColor.withValues(alpha: isPhoto ? 0.88 : 0.7),
                  fontSize: AppTheme.textSm,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A little street map with a bobbing pin, for "Pin it once".
class _MapArt extends StatelessWidget {
  const _MapArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _StreetsPainter())),
        Positioned(
          right: 44,
          top: 22,
          child: _Bob(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Lekki',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.blackColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(
                  Icons.location_on_rounded,
                  size: 44,
                  color: AppTheme.terracottaColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StreetsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final block = Paint()..color = Colors.white.withValues(alpha: 0.75);
    final park = Paint()
      ..color = AppTheme.sageGreenColor.withValues(alpha: 0.35);
    final water = Paint()
      ..color = const Color(0xFF9DBFD1).withValues(alpha: 0.55);

    // A lagoon along the bottom edge, the way Lagos maps always have one.
    final lagoon = Path()
      ..moveTo(0, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.68,
        size.width * 0.6,
        size.height * 0.82,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.93,
        size.width,
        size.height * 0.8,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(lagoon, water);

    const cell = 46.0;
    const gap = 10.0;
    var i = 0;
    for (var y = -12.0; y < size.height * 0.7; y += cell + gap) {
      for (var x = -8.0; x < size.width; x += cell * 1.4 + gap) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cell * 1.4, cell),
          const Radius.circular(8),
        );
        canvas.drawRRect(rect, i % 7 == 3 ? park : block);
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A payout card with a coin dropping into it, for "Paid through Oasis".
class _PayoutArt extends StatelessWidget {
  const _PayoutArt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          right: 22,
          top: 26,
          child: Transform.rotate(
            angle: -0.08,
            child: Container(
              width: 112,
              height: 70,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.terracottaColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.terracottaColor.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payout',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '₦140,000',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 108,
          top: 14,
          child: _Bob(
            distance: 8,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.sandColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Text(
                '₦',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 30,
          top: 104,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 13,
                  color: AppTheme.sageGreenColor,
                ),
                SizedBox(width: 4),
                Text(
                  'Secure',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.blackColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Floats its child up and down, gently and forever.
class _Bob extends StatefulWidget {
  final Widget child;
  final double distance;

  const _Bob({required this.child, this.distance = 5});

  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Transform.translate(
      offset: Offset(
        0,
        -widget.distance * Curves.easeInOut.transform(_controller.value),
      ),
      child: child,
    ),
    child: widget.child,
  );
}

// --------------------------------------------------------- occasion cards

/// The tints the occasion cards rotate through, so a grid of thirteen reads
/// as a set of moods rather than thirteen identical boxes.
const _occasionTints = [
  AppTheme.terracottaColor,
  AppTheme.sageGreenColor,
  AppTheme.sandColor,
  AppTheme.slateGreyColor,
];

/// A two-column grid of occasion cards for the "best for" step.
class OccasionGrid extends StatelessWidget {
  final Set<ShortLetOccasion> selected;
  final ValueChanged<ShortLetOccasion> onToggle;

  const OccasionGrid({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const values = ShortLetOccasion.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < values.length; i++)
              SizedBox(
                width: width,
                child: _OccasionCard(
                  occasion: values[i],
                  tint: _occasionTints[i % _occasionTints.length],
                  selected: selected.contains(values[i]),
                  onTap: () => onToggle(values[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OccasionCard extends StatelessWidget {
  final ShortLetOccasion occasion;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  const _OccasionCard({
    required this.occasion,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${occasion.label}. ${occasion.tagline}',
      child: OasisPressable(
        onTap: onTap,
        pressedScale: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 128,
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.terracottaColor.withValues(alpha: 0.08)
                : AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppTheme.terracottaColor
                  : AppTheme.borderColor(context),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.terracottaColor
                          : tint.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      occasion.icon,
                      size: 20,
                      color: selected ? Colors.white : tint,
                    ),
                  ),
                  const Spacer(),
                  AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    scale: selected ? 1 : 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppTheme.terracottaColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                occasion.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.cardTitle(context).copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                occasion.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ).copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Above the grid: how many are picked, and where guests will find the
/// place because of them.
class OccasionSummary extends StatelessWidget {
  final Set<ShortLetOccasion> selected;

  const OccasionSummary({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final picked = [
      for (final occasion in ShortLetOccasion.values)
        if (selected.contains(occasion)) occasion,
    ];
    final String line;
    if (picked.isEmpty) {
      line = 'Tap every card that fits. Pick as many as you like.';
    } else {
      final names = picked.take(2).map((o) => o.label).toList();
      final more = picked.length - names.length;
      final list = switch ((names.length, more)) {
        (1, _) => names.first,
        (_, 0) => '${names[0]} and ${names[1]}',
        _ => '${names[0]}, ${names[1]} and $more more',
      };
      line = 'Guests browsing $list will see your place.';
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: picked.isEmpty
            ? AppTheme.subtleSurfaceColor(context)
            : AppTheme.successSurface(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(
            width: picked.length > 1
                ? 34 + 18.0 * (math.min(picked.length, 3) - 1)
                : 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (picked.isEmpty)
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 30,
                    color: AppTheme.mutedTextColor(context),
                  )
                else
                  for (var i = 0; i < math.min(picked.length, 3); i++)
                    Positioned(
                      left: i * 18.0,
                      top: 2,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.terracottaColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.surfaceColor(context),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          picked[i].icon,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  picked.isEmpty
                      ? 'Nothing picked yet'
                      : '${picked.length} picked',
                  style: AppTheme.cardTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------- cancellation policy

/// The host's cancellation choice: one card per policy, and the chosen one
/// opens to show exactly what guests would get back.
class CancellationPolicyPicker extends StatelessWidget {
  final ShortLetCancellationPolicy value;
  final ValueChanged<ShortLetCancellationPolicy> onChanged;

  const CancellationPolicyPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final policy in ShortLetCancellationPolicy.values) ...[
        _PolicyOption(
          policy: policy,
          selected: policy == value,
          onTap: () => onChanged(policy),
        ),
        if (policy != ShortLetCancellationPolicy.values.last)
          const SizedBox(height: 8),
      ],
    ],
  );
}

class _PolicyOption extends StatelessWidget {
  final ShortLetCancellationPolicy policy;
  final bool selected;
  final VoidCallback onTap;

  const _PolicyOption({
    required this.policy,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: OasisPressable(
        onTap: onTap,
        pressedScale: 0.98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.terracottaColor.withValues(alpha: 0.06)
                : AppTheme.surfaceColor(context),
            borderRadius: AppTheme.cornerMd,
            border: Border.all(
              color: selected
                  ? AppTheme.terracottaColor
                  : AppTheme.borderColor(context),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RadioDot(selected: selected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(policy.label, style: AppTheme.cardTitle(context)),
                        Text(
                          policy.pitch,
                          style: AppTheme.labelText(
                            context,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: CancellationTimeline(
                          policy: policy,
                          heading: 'What guests get back',
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;

  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: selected
            ? AppTheme.terracottaColor
            : AppTheme.borderColor(context),
        width: selected ? 7 : 2,
      ),
    ),
  );
}

Color _refundColor(CancellationRefund refund) => switch (refund) {
  CancellationRefund.full => AppTheme.sageGreenColor,
  CancellationRefund.half => AppTheme.sandColor,
  CancellationRefund.none => AppTheme.brickRedColor,
};

/// What a cancellation policy means in practice: a coloured bar running
/// from booking to check-in, and one row per window saying what comes back.
///
/// Shared by the host's picker and the guest's listing page, so both read
/// the same terms in the same shape.
class CancellationTimeline extends StatelessWidget {
  final ShortLetCancellationPolicy policy;
  final String heading;

  const CancellationTimeline({
    super.key,
    required this.policy,
    required this.heading,
  });

  @override
  Widget build(BuildContext context) {
    final tiers = policy.refundTiers;
    // Non-refundable is not a sequence in time: one row is the rule, the
    // other the exception. A bar would suggest a refund window that is not
    // there.
    final showBar = policy != ShortLetCancellationPolicy.nonRefundable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading.toUpperCase(),
          style: AppTheme.labelText(
            context,
            color: AppTheme.mutedTextColor(context),
          ).copyWith(fontSize: 10, letterSpacing: 0.7),
        ),
        if (showBar) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                for (var i = 0; i < tiers.length; i++) ...[
                  Expanded(
                    flex: tiers[i].refund == CancellationRefund.full ? 3 : 2,
                    child: Container(
                      height: 8,
                      color: _refundColor(tiers[i].refund),
                    ),
                  ),
                  if (i < tiers.length - 1) const SizedBox(width: 2),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                'Booked',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.mutedTextColor(context),
                ).copyWith(fontSize: 10),
              ),
              const Spacer(),
              Icon(
                Icons.vpn_key_outlined,
                size: 11,
                color: AppTheme.mutedTextColor(context),
              ),
              const SizedBox(width: 3),
              Text(
                'Check-in',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.mutedTextColor(context),
                ).copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        for (final tier in tiers)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _refundColor(tier.refund),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tier.when,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  tier.refund.label,
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.primaryTextColor(context),
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
