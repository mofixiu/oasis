import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/features/agreements/models/agreement_group.dart';
import 'package:landa_app/features/agreements/models/agreement_model.dart';

/// The archive is a record of things people signed, so the failure that
/// matters most is losing one. These pin that first, then the ordering rules
/// that make a long list readable.
void main() {
  test('nothing is dropped, whatever the payload is missing', () {
    final agreements = [
      _agreement(id: 'a', unit: 'unit-1', unitNumber: 'A1', property: _house),
      _agreement(id: 'b', unit: 'unit-2', unitNumber: 'A2'),
      _agreement(id: 'c', unitNumber: 'B1'),
      _agreement(id: 'd'),
    ];

    final groups = AgreementGrouping.byProperty(agreements);
    final total = groups.fold(0, (n, g) => n + g.agreementCount);

    // Four in, four out. A property-keyed map with no null bucket loses the
    // last three silently, which is the whole reason the bucket exists.
    expect(total, 4);
  });

  test('agreements with no property land in a bucket that sorts last', () {
    final groups = AgreementGrouping.byProperty([
      _agreement(id: 'a', unit: 'unit-1', unitNumber: 'A1'),
      _agreement(id: 'b', unit: 'unit-2', unitNumber: '1', property: _zebra),
      _agreement(id: 'c', unit: 'unit-3', unitNumber: '1', property: _house),
    ]);

    expect(groups.map((g) => g.propertyName), [
      'Sunset House',
      'Zebra Court',
      'Unassigned',
    ]);
    expect(groups.last.isUnassigned, isTrue);
    expect(groups.first.isUnassigned, isFalse);
  });

  test('renewals on one unit collapse into a single tenancy', () {
    final groups = AgreementGrouping.byProperty([
      _agreement(
        id: 'old',
        unit: 'unit-1',
        unitNumber: 'A1',
        property: _house,
        startDate: '2025-09-01',
      ),
      _agreement(
        id: 'current',
        unit: 'unit-1',
        unitNumber: 'A1',
        property: _house,
        startDate: '2026-09-01',
      ),
      _agreement(
        id: 'oldest',
        unit: 'unit-1',
        unitNumber: 'A1',
        property: _house,
        startDate: '2024-09-01',
      ),
    ]);

    final tenancy = groups.single.tenancies.single;
    expect(tenancy.agreements, hasLength(3));
    expect(tenancy.latest.id, 'current');
    expect(tenancy.history.map((a) => a.id), ['old', 'oldest']);
    expect(tenancy.hasHistory, isTrue);
    expect(tenancy.label, 'Unit A1');
  });

  test('the same unit number in two properties never merges', () {
    // Nearly every building has an "A1". Grouping on the display string
    // would file one landlord's tenancies under another's building.
    final groups = AgreementGrouping.byProperty([
      _agreement(id: 'a', unit: 'unit-1', unitNumber: 'A1', property: _house),
      _agreement(id: 'b', unit: 'unit-9', unitNumber: 'A1', property: _zebra),
    ]);

    expect(groups, hasLength(2));
    expect(
      groups.every((g) => g.tenancies.single.agreements.length == 1),
      isTrue,
    );
  });

  test('units are ordered the way a person reads them', () {
    final groups = AgreementGrouping.byProperty([
      for (final number in ['A10', 'A2', 'A1', 'B1'])
        _agreement(
          id: number,
          unit: 'unit-$number',
          unitNumber: number,
          property: _house,
        ),
    ]);

    // Lexical ordering would put A10 between A1 and A2.
    expect(groups.single.tenancies.map((t) => t.unitNumber), [
      'A1',
      'A2',
      'A10',
      'B1',
    ]);
  });

  test('an agreement with no unit id still gets a place', () {
    final groups = AgreementGrouping.byProperty([
      _agreement(id: 'a', unitNumber: 'A1', property: _house),
      _agreement(id: 'b', property: _house),
    ]);

    expect(groups.single.tenancies, hasLength(2));
    expect(groups.single.agreementCount, 2);
    // No unit number either, so it says what it is rather than "Unit ".
    expect(
      groups.single.tenancies.map((t) => t.label),
      containsAll(['Unit A1', 'Agreement']),
    );
  });

  test('an unreadable date sinks rather than surfacing as newest', () {
    // Sorting a blank date as the epoch would be harmless; sorting it as
    // "now" would put a broken record above the current tenancy.
    final groups = AgreementGrouping.byProperty([
      _agreement(
        id: 'undated',
        unit: 'unit-1',
        unitNumber: 'A1',
        property: _house,
        startDate: '',
      ),
      _agreement(
        id: 'current',
        unit: 'unit-1',
        unitNumber: 'A1',
        property: _house,
        startDate: '2026-09-01',
      ),
    ]);

    expect(groups.single.tenancies.single.latest.id, 'current');
  });

  test('a single tenant tenancy collapses to one section, one card', () {
    // The same screen serves both roles. A tenant must not be shown grouping
    // scaffolding around a list of one.
    final groups = AgreementGrouping.byProperty([
      _agreement(id: 'a', unit: 'unit-1', unitNumber: '4B', property: _house),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.tenancies, hasLength(1));
    expect(groups.single.tenancies.single.hasHistory, isFalse);
    expect(groups.single.propertyLocation, '123 Main Street, Lagos');
  });

  test('an empty archive groups to nothing', () {
    expect(AgreementGrouping.byProperty([]), isEmpty);
  });
}

const _house = {
  'id': 'property-1',
  'name': 'Sunset House',
  'address': '123 Main Street',
  'city': 'Lagos',
};

const _zebra = {
  'id': 'property-2',
  'name': 'Zebra Court',
  'address': '9 Marina',
  'city': 'Lagos',
};

TenancyAgreementModel _agreement({
  required String id,
  String unit = '',
  String unitNumber = '',
  Map<String, dynamic>? property,
  String startDate = '2026-09-01',
}) => TenancyAgreementModel.fromJson({
  'id': id,
  'unit': unit,
  'unit_number': unitNumber,
  'rent_amount': '450000.00',
  'start_date': startDate,
  'end_date': '2027-08-31',
  'status': 'EXECUTED',
  'pay_rent_unlocked': true,
  if (property != null) 'property': property,
});
