import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/oasis_pressable.dart';

enum V2EmptyArtwork { suitcase, inbox, home, hosting }

/// A calm, illustrated empty state for the V2 short stay experience.
///
/// The suitcase is drawn in code so the state stays crisp at every screen
/// density and does not add a separate image asset to the app bundle.
class V2IllustratedEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final V2EmptyArtwork artwork;
  final bool scrollable;

  const V2IllustratedEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.artwork = V2EmptyArtwork.suitcase,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 280,
          height: 230,
          child: CustomPaint(painter: _TravelArtworkPainter(artwork)),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTheme.screenTitle(
            context,
          ).copyWith(fontSize: 27, height: 1.18, letterSpacing: -0.8),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.bodyText(context).copyWith(height: 1.55),
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: 260,
            child: OasisButton(
              label: actionLabel!,
              icon: Icons.arrow_forward_rounded,
              color: AppTheme.terracottaColor,
              onPressed: onAction,
            ),
          ),
        ],
      ],
    );

    if (!scrollable) {
      final centred = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: content,
        ),
      );
      // Centred in the space there is, but still able to scroll when that
      // space shrinks, as it does under the keyboard of a sheet opened on
      // top. Inside a list, where height is unbounded, it is just centred.
      return LayoutBuilder(
        builder: (context, constraints) => !constraints.hasBoundedHeight
            ? centred
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: centred,
                ),
              ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
      children: [content],
    );
  }
}

class _TravelArtworkPainter extends CustomPainter {
  final V2EmptyArtwork artwork;
  const _TravelArtworkPainter(this.artwork);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 280;
    canvas.save();
    canvas.scale(scale, scale);

    final paper = Paint()..color = const Color(0xFFF4E8D9);
    final paperLight = Paint()..color = const Color(0xFFFBF6EF);
    final leather = Paint()..color = const Color(0xFFB9895D);
    final leatherDark = Paint()..color = const Color(0xFF8A5C3C);
    final ink = Paint()
      ..color = const Color(0xFF72543D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final leaf = Paint()..color = const Color(0xFF829478);

    // Soft arch and ground shadow give the objects a little depth without
    // turning an empty state into a busy illustration.
    canvas.drawOval(const Rect.fromLTWH(55, 10, 170, 190), paper);
    canvas.drawOval(
      const Rect.fromLTWH(45, 191, 190, 19),
      Paint()..color = const Color(0x1F72543D),
    );

    // A long-stemmed branch sits behind the luggage.
    final stem = Path()
      ..moveTo(80, 190)
      ..cubicTo(88, 147, 74, 115, 91, 73)
      ..cubicTo(101, 50, 117, 40, 131, 34);
    canvas.drawPath(stem, ink..strokeWidth = 2.2);
    _drawLeaf(canvas, const Offset(88, 136), -0.62, leaf);
    _drawLeaf(canvas, const Offset(77, 111), 2.62, leaf);
    _drawLeaf(canvas, const Offset(97, 91), -0.55, leaf);
    _drawLeaf(canvas, const Offset(99, 66), 2.42, leaf);
    _drawLeaf(canvas, const Offset(119, 49), -0.42, leaf);

    // Main case.
    final largeCase = RRect.fromRectAndRadius(
      const Rect.fromLTWH(76, 127, 132, 66),
      const Radius.circular(14),
    );
    canvas.drawRRect(largeCase, leather);
    canvas.drawRRect(largeCase, ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(123, 120, 38, 13),
        const Radius.circular(5),
      ),
      leatherDark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(117, 111, 49, 15),
        const Radius.circular(7),
      ),
      paperLight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(117, 111, 49, 15),
        const Radius.circular(7),
      ),
      ink,
    );
    canvas.drawLine(const Offset(142, 129), const Offset(142, 189), ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(92, 149, 12, 20),
        const Radius.circular(4),
      ),
      leatherDark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(180, 149, 12, 20),
        const Radius.circular(4),
      ),
      leatherDark,
    );

    // Smaller carry-on and handle.
    final smallCase = RRect.fromRectAndRadius(
      const Rect.fromLTWH(112, 88, 74, 45),
      const Radius.circular(11),
    );
    canvas.drawRRect(smallCase, paperLight);
    canvas.drawRRect(smallCase, ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(133, 80, 31, 12),
        const Radius.circular(6),
      ),
      leatherDark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(131, 72, 35, 13),
        const Radius.circular(6),
      ),
      paperLight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(131, 72, 35, 13),
        const Radius.circular(6),
      ),
      ink,
    );
    canvas.drawLine(const Offset(149, 91), const Offset(149, 131), ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(139, 105, 20, 12),
        const Radius.circular(4),
      ),
      paper,
    );

    // Small quiet glints.
    final glint = Paint()
      ..color = const Color(0xFFC39C70)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(205, 62), const Offset(205, 76), glint);
    canvas.drawLine(const Offset(198, 69), const Offset(212, 69), glint);
    canvas.drawCircle(const Offset(65, 91), 3, glint);
    canvas.restore();
  }

  void _drawLeaf(Canvas canvas, Offset center, double rotation, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawOval(const Rect.fromLTWH(-3, -20, 19, 34), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TravelArtworkPainter oldDelegate) =>
      oldDelegate.artwork != artwork;
}
