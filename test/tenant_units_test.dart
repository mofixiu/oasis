import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/features/agreements/models/agreement_group.dart';
import 'package:oasis_app/features/agreements/models/agreement_model.dart';

/// A tenant with two homes was shown one, because the app asked
/// `GET /tenant/assigned-unit/`, which the backend documents as returning
/// *the first* unit assigned. Their agreements have no such limit, so the
/// list of places someone lives is derived from those. These hold that.
void main() {
  test('two units show as two homes, not one', () {
    final tenancies = AgreementGrouping.byUnit([
      _agreement(id: 'a1', unit: 'unit-1', unitNumber: 'B1'),
      _agreement(id: 'a2', unit: 'unit-2', unitNumber: 'C4'),
    ]);

    expect(tenancies.length, 2);
    expect(tenancies.map((t) => t.unitNumber), containsAll(['B1', 'C4']));
  });

  test('a renewal is one home with a history, not two homes', () {
    // Same unit, two terms. Counting these as two would tell a tenant they
    // live somewhere twice.
    final tenancies = AgreementGrouping.byUnit([
      _agreement(
        id: 'old',
        unit: 'unit-1',
        unitNumber: 'B1',
        startDate: '2025-09-01',
        endDate: '2026-08-31',
      ),
      _agreement(
        id: 'current',
        unit: 'unit-1',
        unitNumber: 'B1',
        startDate: '2026-09-01',
        endDate: '2027-08-31',
      ),
    ]);

    expect(tenancies.length, 1);
    final tenancy = tenancies.single;
    expect(tenancy.latest.id, 'current', reason: 'newest term leads');
    expect(tenancy.hasHistory, isTrue);
    expect(tenancy.history.single.id, 'old');
  });

  test('a unit still waiting on a signature is still a home', () {
    // Hiding it until signed would leave the dashboard disagreeing with the
    // agreement sitting right below it.
    final tenancies = AgreementGrouping.byUnit([
      _agreement(id: 'a1', unit: 'unit-1', unitNumber: 'B1'),
      _agreement(id: 'a2', unit: 'unit-2', unitNumber: 'C4', status: 'PENDING'),
    ]);

    expect(tenancies.length, 2);
  });

  test('units with the same number at different addresses stay separate', () {
    // Nearly every building has an "A1". Grouping on the number rather than
    // the id would merge two unrelated homes into one card.
    final tenancies = AgreementGrouping.byUnit([
      _agreement(id: 'a1', unit: 'unit-1', unitNumber: 'A1'),
      _agreement(id: 'a2', unit: 'unit-2', unitNumber: 'A1'),
    ]);

    expect(tenancies.length, 2);
  });

  test('no agreements means no homes, not a blank one', () {
    expect(AgreementGrouping.byUnit(const []), isEmpty);
  });
}

TenancyAgreementModel _agreement({
  required String id,
  required String unit,
  required String unitNumber,
  String status = 'EXECUTED',
  String startDate = '2026-09-01',
  String endDate = '2027-08-31',
}) => TenancyAgreementModel.fromJson({
  'id': id,
  'unit': unit,
  'unit_number': unitNumber,
  'rent_amount': '300000.00',
  'status': status,
  'start_date': startDate,
  'end_date': endDate,
  'pay_rent_unlocked': status == 'EXECUTED',
  'property': {
    'id': 'property-$unit',
    'name': 'Sunset House',
    'address': '12 Ikeja Road',
    'city': 'Ikeja',
    'state': 'Lagos',
  },
});
