import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/utils/oasis_currency.dart';

void main() {
  test('groups thousands and drops meaningless decimals', () {
    expect(OasisCurrency.format('450000.00'), '₦450,000');
    expect(OasisCurrency.format('600000.00'), '₦600,000');
    expect(OasisCurrency.format('300000'), '₦300,000');
    expect(OasisCurrency.format('1000'), '₦1,000');
    expect(OasisCurrency.format('999'), '₦999');
    expect(OasisCurrency.format('0'), '₦0');
    expect(OasisCurrency.format('12345678.00'), '₦12,345,678');
  });

  test('preserves meaningful kobo', () {
    expect(OasisCurrency.format('472500.50'), '₦472,500.50');
    expect(OasisCurrency.format('22500.05'), '₦22,500.05');
    // Kobo always render as two places: "₦100.1" would read as truncated.
    expect(OasisCurrency.format('100.10'), '₦100.10');
    expect(OasisCurrency.format('100.5'), '₦100.50');
  });

  test('never loses precision on very large values', () {
    // Formatting textually rather than via double means values beyond
    // double's exact-integer range still render digit-for-digit.
    expect(OasisCurrency.format('9007199254740993'), '₦9,007,199,254,740,993');
  });

  test('handles signs and symbol suppression', () {
    expect(OasisCurrency.format('-450000.00'), '-₦450,000');
    expect(OasisCurrency.format('450000.00', showSymbol: false), '450,000');
  });

  test('returns unrecognised input unchanged rather than a wrong number', () {
    // Better to surface whatever the backend sent than to invent a 0.
    expect(OasisCurrency.format('N/A'), 'N/A');
    expect(OasisCurrency.format('pending'), 'pending');
    expect(OasisCurrency.format(''), '₦0');
    expect(OasisCurrency.format(null), '₦0');
  });

  test('perYear suffixes the formatted amount', () {
    expect(OasisCurrency.perYear('600000.00'), '₦600,000/yr');
  });

  group('money arithmetic', () {
    test('parses decimal strings to whole kobo', () {
      expect(OasisCurrency.minorUnits('450000.00'), 45000000);
      expect(OasisCurrency.minorUnits('1000'), 100000);
      expect(OasisCurrency.minorUnits('1000.5'), 100050);
      expect(OasisCurrency.minorUnits('₦1,000.25'), 100025);
      expect(OasisCurrency.minorUnits('-500.00'), -50000);
    });

    test('refuses to invent a number it cannot read', () {
      // A null here becomes "we do not know", which callers turn into "do not
      // offer to pay from the vault". A 0 would silently mean "free".
      expect(OasisCurrency.minorUnits('pending'), isNull);
      expect(OasisCurrency.minorUnits(''), isNull);
      expect(OasisCurrency.minorUnits(null), isNull);
    });

    test('round-trips kobo back to the API string shape', () {
      expect(OasisCurrency.fromMinorUnits(45000000), '450000.00');
      expect(OasisCurrency.fromMinorUnits(100050), '1000.50');
      expect(OasisCurrency.fromMinorUnits(5), '0.05');
    });

    test('scale converts a quoted period into a year', () {
      // What the add-units sheet does with a rent typed per month. The API
      // stores one figure per unit and every screen reads it as annual, so
      // this multiplication is the whole of the interval feature.
      expect(OasisCurrency.scale('250000.00', 12), '3000000.00');
      expect(OasisCurrency.scale('450000.00', 1), '450000.00');
      // Kobo survive the multiplication rather than being rounded away.
      expect(OasisCurrency.scale('1000.50', 12), '12006.00');
      // Not a number: no rent, rather than a confident zero that would be
      // saved as a free flat.
      expect(OasisCurrency.scale('', 12), isNull);
      expect(OasisCurrency.scale('soon', 12), isNull);
    });

    test('subtract floors at zero and reports the shortfall', () {
      expect(OasisCurrency.subtract('450000.00', '120000.00'), '330000.00');
      // Saved more than the bill: the answer is "nothing left to save", not a
      // negative amount to display.
      expect(OasisCurrency.subtract('100000.00', '450000.00'), '0.00');
      expect(OasisCurrency.subtract('450000.00', 'unknown'), isNull);
    });

    test('covers compares exactly, including kobo', () {
      expect(OasisCurrency.covers('450000.00', '450000.00'), isTrue);
      // One kobo short is short. This gates the "pay from vault" button, and a
      // rounded comparison here becomes a payment that is offered then fails.
      expect(OasisCurrency.covers('449999.99', '450000.00'), isFalse);
      expect(OasisCurrency.covers('450000.01', '450000.00'), isTrue);
      expect(OasisCurrency.covers('unknown', '450000.00'), isFalse);
    });
  });
}
