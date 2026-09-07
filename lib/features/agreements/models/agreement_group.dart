import 'agreement_model.dart';

/// One unit's tenancy history: the same unit, re-let or renewed over time.
///
/// The unit, not the agreement, is what people remember. "My tenancy at
/// Unit 4B" is one thing with a history, not three unrelated documents, so
/// the archive groups the renewals under the unit rather than listing them
/// flat.
class TenancyGroup {
  /// Stable identity for the unit. Unit *numbers* repeat across properties:
  /// nearly every building has an "A1", so the id is what groups them, and
  /// falls back only when the payload carried none.
  final String unitKey;

  final String unitNumber;

  /// Newest first, so [latest] is the current state of this tenancy.
  final List<TenancyAgreementModel> agreements;

  const TenancyGroup({
    required this.unitKey,
    required this.unitNumber,
    required this.agreements,
  });

  TenancyAgreementModel get latest => agreements.first;

  /// Prior agreements on this unit: everything but the current one.
  List<TenancyAgreementModel> get history => agreements.skip(1).toList();

  bool get hasHistory => agreements.length > 1;

  String get label => unitNumber.isEmpty ? 'Agreement' : 'Unit $unitNumber';
}

/// One property's agreements, grouped by unit.
class PropertyAgreementGroup {
  /// Null for the unassigned bucket: see [isUnassigned].
  final String? propertyId;

  final String propertyName;

  /// Where it is, when the payload carried an address. Empty otherwise.
  final String propertyLocation;

  final List<TenancyGroup> tenancies;

  const PropertyAgreementGroup({
    required this.propertyId,
    required this.propertyName,
    required this.tenancies,
    this.propertyLocation = '',
  });

  /// Agreements whose payload carried no property.
  ///
  /// They get a bucket rather than being dropped: a property-keyed map with no
  /// null bucket loses them silently, which is the worst outcome for a record
  /// somebody signed.
  bool get isUnassigned => propertyId == null;

  int get agreementCount =>
      tenancies.fold(0, (total, tenancy) => total + tenancy.agreements.length);
}

/// Groups signed agreements into properties, then units.
///
/// Pure and side-effect free so the ordering rules can be tested directly
/// rather than through a screen.
abstract final class AgreementGrouping {
  /// Property A→Z with the unassigned bucket last, units in natural order
  /// within a property, and agreements newest first within a unit.
  static List<PropertyAgreementGroup> byProperty(
    List<TenancyAgreementModel> agreements,
  ) {
    // Keyed by property id, with a null key reserved for the unassigned
    // bucket. LinkedHashMap iteration order is insertion order, which is not
    // the order we want: everything is sorted explicitly below.
    final byPropertyId = <String?, List<TenancyAgreementModel>>{};
    for (final agreement in agreements) {
      byPropertyId
          .putIfAbsent(_propertyKey(agreement), () => [])
          .add(agreement);
    }

    final groups = byPropertyId.entries.map((entry) {
      final first = entry.value.first;
      return PropertyAgreementGroup(
        propertyId: entry.key,
        propertyName: entry.key == null
            ? 'Unassigned'
            : (first.property?.name.trim().isNotEmpty ?? false)
            ? first.property!.name.trim()
            : 'Property',
        propertyLocation: entry.key == null ? '' : _location(first),
        tenancies: _tenancies(entry.value),
      );
    }).toList();

    groups.sort((a, b) {
      // The unassigned bucket is a loose end, not a property. It sorts last
      // however it is named.
      if (a.isUnassigned != b.isUnassigned) return a.isUnassigned ? 1 : -1;
      return a.propertyName.toLowerCase().compareTo(
        b.propertyName.toLowerCase(),
      );
    });
    return groups;
  }

  /// Groups agreements by the unit they are for, newest first within each.
  ///
  /// A renewal chain on one unit is one tenancy with a history, not three
  /// unrelated documents, which is also why a tenant with two homes has two
  /// of these however many agreements they have signed.
  static List<TenancyGroup> byUnit(List<TenancyAgreementModel> agreements) =>
      _tenancies(agreements);

  static List<TenancyGroup> _tenancies(List<TenancyAgreementModel> agreements) {
    final byUnit = <String, List<TenancyAgreementModel>>{};
    for (final agreement in agreements) {
      byUnit.putIfAbsent(_unitKey(agreement), () => []).add(agreement);
    }

    final tenancies = byUnit.entries.map((entry) {
      final sorted = [...entry.value]..sort(_newestFirst);
      return TenancyGroup(
        unitKey: entry.key,
        unitNumber: sorted.first.unitNumber.trim(),
        agreements: sorted,
      );
    }).toList();

    tenancies.sort((a, b) => _naturalCompare(a.unitNumber, b.unitNumber));
    return tenancies;
  }

  /// Null when the agreement carried no usable property, which is what puts
  /// it in the unassigned bucket.
  static String? _propertyKey(TenancyAgreementModel agreement) {
    final id = agreement.property?.id.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  /// The unit id where there is one. An agreement with no unit id still has
  /// to land somewhere, so it falls back to its unit number and finally to
  /// its own id: a group of one is better than a lost record.
  static String _unitKey(TenancyAgreementModel agreement) {
    final unit = agreement.unit.trim();
    if (unit.isNotEmpty) return unit;
    final number = agreement.unitNumber.trim();
    return number.isNotEmpty ? 'number:$number' : 'agreement:${agreement.id}';
  }

  static String _location(TenancyAgreementModel agreement) {
    final property = agreement.property;
    if (property == null) return '';
    return [
      property.address.trim(),
      property.city.trim(),
    ].where((part) => part.isNotEmpty).join(', ');
  }

  /// Most recent tenancy first, by the term it covers.
  ///
  /// `start_date` is the honest key: it is the term the agreement is *for*,
  /// which is what someone scanning a renewal chain is looking for. Creation
  /// time only breaks ties, because a backdated agreement can be created
  /// after a later one.
  static int _newestFirst(TenancyAgreementModel a, TenancyAgreementModel b) {
    final byStart = _laterFirst(a.startDate, b.startDate);
    if (byStart != 0) return byStart;
    return _laterFirst(a.createdAt, b.createdAt);
  }

  /// Later date first, with unreadable or missing dates last.
  ///
  /// Descending order is built in rather than obtained by swapping the
  /// arguments at the call site: reversing the arguments also reverses the
  /// nulls-last rule, which floats a record with no date to the top of a
  /// renewal chain and hides the current tenancy behind it.
  static int _laterFirst(String left, String right) {
    final a = DateTime.tryParse(left.trim());
    final b = DateTime.tryParse(right.trim());
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  /// Compares unit labels the way a person reads them, so "A2" precedes
  /// "A10" instead of sorting between "A1" and "A3".
  static int _naturalCompare(String left, String right) {
    final a = _chunk(left);
    final b = _chunk(right);
    for (var i = 0; i < a.length && i < b.length; i++) {
      final x = a[i];
      final y = b[i];
      final xNumber = int.tryParse(x);
      final yNumber = int.tryParse(y);
      final result = xNumber != null && yNumber != null
          ? xNumber.compareTo(yNumber)
          : x.toLowerCase().compareTo(y.toLowerCase());
      if (result != 0) return result;
    }
    return a.length.compareTo(b.length);
  }

  /// Splits a label into digit and non-digit runs: `"A10"` -> `["A", "10"]`.
  static List<String> _chunk(String value) =>
      RegExp(r'\d+|\D+').allMatches(value).map((m) => m.group(0)!).toList();
}
