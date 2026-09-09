import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
  _openingCamera();
  _fullScreenWiring();

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

/// Tapping "open full screen" continues from the inline map.
///
/// The ordering tests above pass a value straight to the resolver, so they
/// could not have caught the bug that shipped: the resolver was right, and
/// the full-screen page simply never handed it anything. This drives the
/// actual gesture — inline map, tap expand, read the camera the new map
/// opened with — which is the only level the wiring is visible at.
void _fullScreenWiring() {
  testWidgets('the full-screen map does not restart in Lagos', (tester) async {
    const lagos = LatLng(6.5244, 3.3792);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropertyLocationPicker(
              // A landlord in Oyo, no pin placed yet.
              state: 'Oyo',
              city: 'Ibadan',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Open full screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Two maps exist mid-transition; the new route's is the last one built.
    final maps = tester.widgetList<FlutterMap>(find.byType(FlutterMap));
    final opened = maps.last.options.initialCenter;

    expect(
      opened,
      isNot(lagos),
      reason: 'full screen restarted at the Lagos fallback',
    );
    expect(opened.latitude, closeTo(7.3775, 0.5));
  });
}

/// Where the map opens.
///
/// Split out as a pure function precisely because this shipped broken once:
/// the full-screen picker accepted a centre, never passed it down, and every
/// landlord who tapped "open full screen" from Ibadan landed in Lagos. The
/// widget rendered perfectly; the ordering was wrong and nothing could see it.
void _openingCamera() {
  group('the map opens on the most specific thing it knows', () {
    const lagos = LatLng(6.5244, 3.3792);
    const ibadan = LatLng(7.3775, 3.9470);

    test('an existing pin wins over everything', () {
      final camera = PropertyLocationPicker.resolveOpeningCamera(
        pin: const LatLng(6.4281, 3.4219),
        handedIn: ibadan,
        state: 'Oyo',
      );
      expect(camera.centre.latitude, closeTo(6.4281, 0.0001));
      // Close in: the landlord has already said exactly where.
      expect(camera.zoom, 17);
    });

    test('a handed-in camera continues the inline map', () {
      // The regression. Opening full screen must resume where the inline map
      // was looking, not restart at a national default.
      final camera = PropertyLocationPicker.resolveOpeningCamera(
        handedIn: ibadan,
        handedInZoom: 15,
        state: 'Oyo',
      );
      expect(camera.centre, ibadan);
      expect(camera.zoom, 15);
    });

    test('with no camera it falls back to the chosen state', () {
      final camera = PropertyLocationPicker.resolveOpeningCamera(state: 'Oyo');
      expect(camera.centre.latitude, closeTo(7.3775, 0.01));
      expect(camera.centre, isNot(lagos));
    });

    test('state spellings the picker accepts all resolve', () {
      for (final spelling in ['Oyo', 'oyo state', 'OYO']) {
        expect(
          PropertyLocationPicker.resolveOpeningCamera(
            state: spelling,
          ).centre.latitude,
          closeTo(7.3775, 0.01),
          reason: 'failed for "$spelling"',
        );
      }
    });

    test('Lagos only when nothing at all is known', () {
      final camera = PropertyLocationPicker.resolveOpeningCamera();
      expect(camera.centre, lagos);

      // …and an unrecognised state does not silently become Lagos-with-
      // confidence: it is the same last resort, at the same wide zoom.
      final unknown = PropertyLocationPicker.resolveOpeningCamera(
        state: 'Atlantis',
      );
      expect(unknown.centre, lagos);
      expect(unknown.zoom, camera.zoom);
    });
  });
}
