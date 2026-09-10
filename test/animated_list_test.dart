import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/widgets/oasis_animated_list.dart';

/// A list animation that gets its diff wrong is worse than none: rows
/// duplicate, or vanish early, or an approved application is still on screen
/// after the list says it is gone. These pin the three cases that matter.
void main() {
  Widget listOf(List<String> items) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OasisAnimatedList<String>(
          items: items,
          keyOf: (item) => item,
          itemBuilder: (_, item, _) => SizedBox(height: 40, child: Text(item)),
        ),
      ),
    ),
  );

  testWidgets('renders what it is given, once each', (tester) async {
    await tester.pumpWidget(listOf(['a', 'b', 'c']));
    await tester.pumpAndSettle();

    for (final item in ['a', 'b', 'c']) {
      expect(find.text(item), findsOneWidget);
    }
  });

  testWidgets('a removed row is gone once its collapse finishes', (
    tester,
  ) async {
    await tester.pumpWidget(listOf(['a', 'b', 'c']));
    await tester.pumpAndSettle();

    await tester.pumpWidget(listOf(['a', 'c']));
    // Still on screen mid-collapse, that is the whole point, the row leaves
    // rather than being deleted between two frames.
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('b'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('b'), findsNothing);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('an added row appears exactly once', (tester) async {
    await tester.pumpWidget(listOf(['a']));
    await tester.pumpAndSettle();

    await tester.pumpWidget(listOf(['a', 'b']));
    await tester.pumpAndSettle();

    // The bug a hand-rolled diff produces: the row is inserted by the
    // animation *and* by the rebuild, and shows up twice.
    expect(find.text('b'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('a row that only changed content is not re-animated', (
    tester,
  ) async {
    // Same keys, different objects: an application whose status flipped.
    // It must redraw in place, not leave and come back.
    await tester.pumpWidget(listOf(['a', 'b']));
    await tester.pumpAndSettle();

    await tester.pumpWidget(listOf(['a', 'b']));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });
}
