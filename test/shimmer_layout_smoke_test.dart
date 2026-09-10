import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/widgets/oasis_shimmer.dart';

void main() {
  testWidgets('OasisSkeletonList renders inside an unbounded Column', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                Text('MY PROPERTIES'),
                OasisSkeletonList(
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
    expect(find.byType(OasisCardSkeleton), findsNWidgets(2));
    expect(find.byType(OasisShimmer), findsNWidgets(2));
  });
}
