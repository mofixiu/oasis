import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:landa_app/features/properties/views/widgets/property_location_picker.dart';

/// The pin map renders in both of its shapes without throwing.
///
/// Structural, not cosmetic. The inline map lives in a `SingleChildScrollView`
/// (unbounded height) and the full-screen one lives in a `Column` on a page
/// (bounded), and the two want opposite things: inline needs a fixed height,
/// full-screen needs `Expanded`. Getting it backwards does not look wrong, it
/// throws — a `Container(height: double.infinity)` in a Column is a RenderFlex
/// overflow, and an `Expanded` inside a scroll view is an unbounded-constraints
/// assertion. Both are hard failures that only appear at runtime, which is
/// exactly the kind of bug `context.md` §14 says to pin with a widget test.
void main() {
  // Tiles are network images; the test binding returns a 400 for them, which
  // the map handles. Nothing here asserts on tiles.
  Widget host({required Widget child}) => MaterialApp(
    home: Scaffold(body: child),
  );

  testWidgets('inline, inside a scroll view, it lays out', (tester) async {
    await tester.pumpWidget(
      host(
        child: SingleChildScrollView(
          child: Column(
            children: [
              PropertyLocationPicker(onChanged: (_) {}),
              // Something below the map, because the whole point of the fix
              // is that a landlord can reach the fields under it.
              const SizedBox(height: 400, child: Text('photos section')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(PropertyLocationPicker), findsOneWidget);
  });

  testWidgets('full screen, inside a bounded column, it lays out', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        child: Column(
          children: [
            Expanded(
              child: PropertyLocationPicker(
                isFullScreen: true,
                initialPin: const LatLng(6.5244, 3.3792),
                onChanged: (_) {},
              ),
            ),
            const SizedBox(height: 60, child: Text('use this pin')),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('use this pin'), findsOneWidget);
  });

  testWidgets('the two-finger hint is inline-only', (tester) async {
    // Full screen the map drags with one finger like any map, so the hint
    // would be a lie. Inline it is the difference between a map that looks
    // broken and one whose gesture is explained.
    await tester.pumpWidget(
      host(
        child: SingleChildScrollView(
          child: PropertyLocationPicker(onChanged: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('two fingers'), findsOneWidget);

    await tester.pumpWidget(
      host(
        child: Column(
          children: [
            Expanded(
              child: PropertyLocationPicker(
                isFullScreen: true,
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('two fingers'), findsNothing);
  });
}
