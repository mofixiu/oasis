import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/features/agreements/models/agreement_model.dart';

/// The rent schedule decides what a tenant is told about money they owe, so
/// these cover the two failures that actually cost them: being told rent is
/// months away when it is due, and being shown a due date the backend never
/// sent.
void main() {
  test('reads the backend schedule as sent', () {
    final agreement = _agreement(
      status: 'EXECUTED',
      rentSchedule: {
        'plan': 'SIX_MONTHLY',
        'next_due_date': '2026-11-01',
        'next_amount_due': '225000.00',
        'days_until_due': 66,
        'is_overdue': false,
        'instalments_paid': 1,
        'instalments_total': 2,
      },
    );

    final schedule = agreement.upcomingRent!;
    expect(schedule.plan, RentPlan.sixMonthly);
    expect(schedule.plan.label, 'Every 6 months');
    expect(schedule.nextAmountDue, '225000.00');
    expect(schedule.daysUntilDue, 66);
    expect(schedule.isDueNow, isFalse);
    expect(schedule.isDueSoon, isFalse);
    expect(schedule.instalmentsTotal, 2);
  });

  test('a three-month plan is recognised under either wire name', () {
    expect(RentPlan.fromString('QUARTERLY'), RentPlan.quarterly);
    expect(RentPlan.fromString('THREE_MONTHLY'), RentPlan.quarterly);
    expect(RentPlan.quarterly.label, 'Every 3 months');
    // Whichever name it arrived under, it goes back canonical.
    expect(RentPlan.quarterly.apiValue, 'QUARTERLY');
  });

  test('an unrecognised plan does not hide the bill', () {
    // The date is the part that matters. A plan name the app has not seen
    // must not stop the card rendering the money and the deadline.
    final agreement = _agreement(
      status: 'EXECUTED',
      rentSchedule: {
        'plan': 'FORTNIGHTLY',
        'next_due_date': '2026-09-01',
        'next_amount_due': '50000.00',
        'days_until_due': 5,
      },
    );

    final schedule = agreement.upcomingRent!;
    expect(schedule.plan, RentPlan.unknown);
    expect(schedule.nextAmountDue, '50000.00');
    expect(schedule.isDueSoon, isTrue);
  });

  test('the backend verdict on lateness wins over the day count', () {
    // A tenancy can be overdue while its stored date still reads as future:
    // a grace period, a re-scheduled instalment. The server knows; we do not.
    final agreement = _agreement(
      status: 'EXECUTED',
      rentSchedule: {
        'next_due_date': '2099-01-01',
        'next_amount_due': '450000.00',
        'is_overdue': true,
      },
    );

    final schedule = agreement.upcomingRent!;
    expect(schedule.isOverdue, isTrue);
    expect(schedule.isDueNow, isTrue);
  });

  test('rent owed now outranks the end of the term', () {
    // No schedule from the backend, but rent_payment says money is owed. The
    // tenant can pay today, so the card must not show them a date next year.
    final agreement = _agreement(
      status: 'EXECUTED',
      endDate: '2027-06-30',
      rentPayment: {'status': 'DUE', 'total_amount': '472500.00'},
    );

    final schedule = agreement.upcomingRent!;
    expect(schedule.isDueNow, isTrue);
    expect(schedule.nextAmountDue, '472500.00');
    expect(schedule.nextDueDate, isNull);
  });

  test('without a schedule, the end of the term is the next rent date', () {
    final agreement = _agreement(
      status: 'EXECUTED',
      endDate: '2027-06-30',
      rentPayment: {'status': 'PAID', 'total_amount': '472500.00'},
    );

    final schedule = agreement.upcomingRent!;
    expect(schedule.nextDueDate, '2027-06-30');
    // The real next_amount_due carries the platform fee, so the stand-in has
    // to as well. Quoting the bare rent would understate the bill by 5%, and
    // the payments screen checks the vault balance against this figure, so it
    // would offer a payment that is then declined.
    expect(schedule.nextAmountDue, '472500.00');
    // Nothing was guessed about the instalment count.
    expect(schedule.instalmentsTotal, 0);
  });

  test('the plan is known before there is any schedule', () {
    // rent_schedule is null until the agreement is payable, so a tenant
    // reading an unsigned agreement can only learn the cycle from rent_plan.
    final agreement = _agreement(status: 'PENDING', rentPlan: 'MONTHLY');

    expect(agreement.rentPlan, RentPlan.monthly);
    expect(agreement.plan, RentPlan.monthly);
    expect(agreement.upcomingRent, isNull);
  });

  test('the schedule outranks the agreement on the cycle', () {
    // Both fields can be present once executed. The schedule is the one the
    // backend computed the instalments from.
    final agreement = _agreement(
      status: 'EXECUTED',
      rentPlan: 'ANNUAL',
      rentSchedule: {
        'plan': 'MONTHLY',
        'next_due_date': '2026-09-01',
        'next_amount_due': '39375.00',
        'instalments_total': 12,
      },
    );

    expect(agreement.plan, RentPlan.monthly);
  });

  test('a fallback schedule carries the plan the agreement was written on', () {
    final agreement = _agreement(
      status: 'EXECUTED',
      rentPlan: 'QUARTERLY',
      endDate: '2027-06-30',
      rentPayment: {'status': 'DUE', 'total_amount': '472500.00'},
    );

    expect(agreement.upcomingRent!.plan, RentPlan.quarterly);
  });

  test('weekly is a plan the backend supports', () {
    expect(RentPlan.fromString('WEEKLY'), RentPlan.weekly);
    expect(RentPlan.weekly.label, 'Weekly');
    expect(RentPlan.weekly.apiValue, 'WEEKLY');
    expect(RentPlan.selectable, contains(RentPlan.weekly));
  });

  test('every alias maps to the canonical value it stands for', () {
    expect(RentPlan.fromString('YEARLY').apiValue, 'ANNUAL');
    expect(RentPlan.fromString('BIANNUAL').apiValue, 'SIX_MONTHLY');
    expect(RentPlan.fromString('THREE_MONTHLY').apiValue, 'QUARTERLY');
    // An unrecognised plan sends nothing, leaving the backend its own default
    // rather than asserting one from here.
    expect(RentPlan.unknown.apiValue, isNull);
    expect(RentPlan.selectable, isNot(contains(RentPlan.unknown)));
  });

  test('an unsigned agreement has no rent to show', () {
    // Rent on an agreement nobody has executed is not a bill. Showing one
    // would ask a tenant to pay for a tenancy that does not exist yet.
    expect(_agreement(status: 'PENDING').upcomingRent, isNull);
  });

  test('a settled schedule with no next date shows nothing', () {
    final agreement = _agreement(
      status: 'EXECUTED',
      rentSchedule: {'next_due_date': null, 'is_overdue': false},
    );
    expect(agreement.upcomingRent, isNull);
  });

  test('days until due falls back to the date when the server omits it', () {
    final due = DateTime.now().add(const Duration(days: 10));
    final agreement = _agreement(
      status: 'EXECUTED',
      rentSchedule: {
        'next_due_date':
            '${due.year}-${due.month.toString().padLeft(2, '0')}-'
            '${due.day.toString().padLeft(2, '0')}',
        'next_amount_due': '450000.00',
      },
    );

    final schedule = agreement.upcomingRent!;
    expect(schedule.daysUntilDue, 10);
    expect(schedule.isDueSoon, isTrue);
    expect(schedule.isDueNow, isFalse);
  });
}

TenancyAgreementModel _agreement({
  required String status,
  String endDate = '',
  String? rentPlan,
  Map<String, dynamic>? rentSchedule,
  Map<String, dynamic>? rentPayment,
}) => TenancyAgreementModel.fromJson({
  'id': 'agreement-1',
  'unit': 'unit-1',
  'unit_number': '4B',
  'rent_amount': '450000.00',
  'start_date': '2026-07-01',
  'end_date': endDate,
  'status': status,
  'pay_rent_unlocked': status == 'EXECUTED',
  if (rentPlan != null) 'rent_plan': rentPlan,
  if (rentSchedule != null) 'rent_schedule': rentSchedule,
  if (rentPayment != null) 'rent_payment': rentPayment,
});
