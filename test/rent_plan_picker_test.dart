import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';
import 'package:oasis_app/features/agreements/views/widgets/rent_plan_picker.dart';

/// The plan a landlord picks here decides how a tenant is billed for a year,
/// so these cover what would mislead either party: an option the backend does
/// not support, and an instalment figure presented as the final bill.
void main() {
  testWidgets('every supported plan is offered', (tester) async {
    await _pump(tester, selected: RentPlan.annual);

    for (final plan in RentPlan.selectable) {
      expect(find.text(plan.label), findsOneWidget);
    }
    // The catch-all is not a tenancy anyone can choose.
    expect(find.text(RentPlan.unknown.label), findsNothing);
  });

  testWidgets('picking a plan reports it once', (tester) async {
    final picked = <RentPlan>[];
    await _pump(tester, selected: RentPlan.annual, onChanged: picked.add);

    await tester.tap(find.text('Monthly'));
    await tester.pump();

    expect(picked, [RentPlan.monthly]);
  });

  testWidgets('the instalment preview is flagged as before fees', (
    tester,
  ) async {
    await _pump(tester, selected: RentPlan.monthly, annualRent: '1200000.00');

    // A twelfth of the year's rent, and said to be an estimate, because the
    // tenant's real bill carries the platform fee on top.
    expect(find.textContaining('₦100,000 each'), findsOneWidget);
    expect(find.textContaining('before fees'), findsOneWidget);
  });

  testWidgets('a yearly plan quotes no instalment', (tester) async {
    await _pump(tester, selected: RentPlan.annual, annualRent: '1200000.00');

    // There is nothing to divide, so there is no figure to preview.
    expect(find.text('One payment for the year'), findsOneWidget);
    expect(find.textContaining('each'), findsNothing);
  });

  testWidgets('an unreadable rent leaves the description alone', (
    tester,
  ) async {
    // Half-typed amounts are the normal state of this field. Showing "₦0 each"
    // while someone types would be worse than showing nothing.
    await _pump(tester, selected: RentPlan.quarterly, annualRent: '');

    expect(find.text("The year's rent in 4 payments"), findsOneWidget);
    expect(find.textContaining('each'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required RentPlan selected,
  String? annualRent,
  ValueChanged<RentPlan>? onChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: RentPlanPicker(
        selected: selected,
        annualRent: annualRent,
        onChanged: onChanged ?? (_) {},
      ),
    ),
  ),
);
