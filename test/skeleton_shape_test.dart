import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/core/theme/app_theme.dart';
import 'package:landa_app/core/widgets/landa_shimmer.dart';

/// A skeleton exists to show the shape of what is coming. This one did the
/// opposite for a long time: `LandaShimmer` wrapped the whole card, and
/// `BlendMode.srcATop` paints every opaque pixel it is given, so the card's
/// own surface and border were painted the same grey as the bars inside it,
/// and the carefully-built silhouette collapsed into one featureless slab.
///
/// It was reported as "the dashboard's loading state looks like an error",
/// and it survived a round of "make the skeletons content-shaped" because the
/// shapes were already there. They were just being painted over.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('the card surface is outside the shimmer, not under it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LandaCardSkeleton(hasThumbnail: true)));

    // The ordering is the whole fix: the shader must be *inside* the card, so
    // it reaches the bars and leaves the surface alone. Inverted, which is
    // the arrangement this replaced, every pixel of the card gets the sweep.
    final shaderUnderCard = find.descendant(
      of: find.byType(Container).first,
      matching: find.byType(LandaShimmer),
    );
    expect(shaderUnderCard, findsOneWidget);

    final cardUnderShader = find.descendant(
      of: find.byType(LandaShimmer),
      matching: find.byType(Container),
    );
    // Bars are Containers too, so this is not "nothing": it is that the
    // outermost Container, the card, is not one of them.
    expect(
      tester.widgetList(cardUnderShader).length,
      lessThan(tester.widgetList(find.byType(Container)).length),
    );
  });

  testWidgets('it still draws the silhouette it promises', (tester) async {
    await tester.pumpWidget(
      wrap(const LandaCardSkeleton(hasThumbnail: true, hasAction: true)),
    );

    // Thumbnail, two text bars, a pill, a third bar and an action bar. Six
    // shapes, not one rectangle, that is what makes the swap read as content
    // resolving rather than replacing.
    expect(find.byType(ShimmerBox), findsNWidgets(6));
  });

  testWidgets('the listing skeleton keeps its image block on top', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LandaListingSkeleton()));

    expect(
      find.descendant(
        of: find.byType(Container).first,
        matching: find.byType(LandaShimmer),
      ),
      findsOneWidget,
    );
    expect(find.byType(ShimmerBox), findsNWidgets(5));
  });
}
