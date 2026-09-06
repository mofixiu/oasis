import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/features/marketplace/models/marketplace_models.dart';
import 'package:landa_app/features/marketplace/views/marketplace_filter_sheet.dart';

/// The one rule the backend itself enforces (a max price below the min
/// returns `400 Bad Request`) has to be impossible to submit from here, not
/// merely caught afterward, and the fields have to refuse letters and minus
/// signs outright, not just fail validation on them.
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

    await tester.enterText(find.byType(TextField).at(2), '500000');
    await tester.enterText(find.byType(TextField).at(3), '100000');
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

    await tester.enterText(find.byType(TextField).at(2), '100000');
    await tester.enterText(find.byType(TextField).at(3), '500000');
    await tester.pump();

    expect(find.text('Max rent cannot be lower than min rent.'), findsNothing);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('letters and a minus sign never reach the rent fields', (
    tester,
  ) async {
    await pump(tester);

    final minField = find.byType(TextField).at(2);
    await tester.enterText(minField, 'cheap-1');
    await tester.pump();

    // Digit-only input formatters strip everything that is not a digit as
    // it is typed, so the field never holds anything the backend would
    // reject as `?min_price=cheap`.
    expect(tester.widget<TextField>(minField).controller!.text, '1');
  });
}
