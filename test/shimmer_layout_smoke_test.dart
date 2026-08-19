import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/core/widgets/landa_shimmer.dart';

void main() {
  testWidgets('LandaSkeletonList renders inside an unbounded Column', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                Text('MY PROPERTIES'),
                LandaSkeletonList(
                  count: 2,
                  hasThumbnail: true,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(LandaCardSkeleton), findsNWidgets(2));
    expect(find.byType(LandaShimmer), findsNWidgets(2));
  });
}
