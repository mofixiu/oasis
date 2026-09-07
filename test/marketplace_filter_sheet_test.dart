import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/features/marketplace/models/marketplace_models.dart';
import 'package:landa_app/features/marketplace/views/marketplace_filter_sheet.dart';

/// The one rule the backend itself enforces (a max price below the min
/// returns `400 Bad Request`) has to be impossible to submit from here, not
/// merely caught afterward, and the fields have to refuse letters and minus
/// signs outright, not just fail validation on them.
///
/// City and state are pickers rather than text fields, so the only remaining
/// `TextField`s on this sheet are the two rent boxes: min at 0, max at 1.
/// They were at 2 and 3 while the location filters were typed.
void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MarketplaceFilterSheet(initial: const MarketplaceFilters()),
      ),
    ),
  );

  testWidgets('a max rent below the min is refused, not sent', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).at(0), '500000');
    await tester.enterText(find.byType(TextField).at(1), '100000');
    await tester.pump();

    expect(
      find.text('Max rent cannot be lower than min rent.'),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('a valid range has no warning and an enabled button', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).at(0), '100000');
    await tester.enterText(find.byType(TextField).at(1), '500000');
    await tester.pump();

    expect(find.text('Max rent cannot be lower than min rent.'), findsNothing);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('letters and a minus sign never reach the rent fields', (
    tester,
  ) async {
    await pump(tester);

    final minField = find.byType(TextField).at(0);
    await tester.enterText(minField, 'cheap-1');
    await tester.pump();

    // The grouping formatter strips everything that is not a digit as it is
    // typed, so the field never holds anything the backend would reject as
    // `?min_price=cheap`.
    expect(tester.widget<TextField>(minField).controller!.text, '1');
  });

  testWidgets('a rent is grouped as it is typed', (tester) async {
    await pump(tester);

    final minField = find.byType(TextField).at(0);
    await tester.enterText(minField, '450000');
    await tester.pump();

    expect(tester.widget<TextField>(minField).controller!.text, '450,000');
    // …and the separators are display only: the range check still reads the
    // number, so an inverted range is still caught.
    await tester.enterText(find.byType(TextField).at(1), '100000');
    await tester.pump();
    expect(
      find.text('Max rent cannot be lower than min rent.'),
      findsOneWidget,
    );
  });

  testWidgets('state and city are picked from a list, not typed', (
    tester,
  ) async {
    await pump(tester);

    // Two labels, no text fields under them: the whole point of the change
    // is that a landlord's "Lagos" and a tenant's "lagos state" can no
    // longer be different places.
    expect(find.text('STATE'), findsOneWidget);
    expect(find.text('CITY'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.text('Any state'));
    await tester.pumpAndSettle();

    expect(find.text('Which state?'), findsOneWidget);
    await tester.tap(find.text('Abuja (FCT)'));
    await tester.pumpAndSettle();

    expect(find.text('Abuja (FCT)'), findsOneWidget);
  });
}
