import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/core/utils/landa_currency.dart';

void main() {
  test('groups thousands and drops meaningless decimals', () {
    expect(LandaCurrency.format('450000.00'), '₦450,000');
    expect(LandaCurrency.format('600000.00'), '₦600,000');
    expect(LandaCurrency.format('300000'), '₦300,000');
    expect(LandaCurrency.format('1000'), '₦1,000');
    expect(LandaCurrency.format('999'), '₦999');
    expect(LandaCurrency.format('0'), '₦0');
    expect(LandaCurrency.format('12345678.00'), '₦12,345,678');
  });

  test('preserves meaningful kobo', () {
    expect(LandaCurrency.format('472500.50'), '₦472,500.50');
    expect(LandaCurrency.format('22500.05'), '₦22,500.05');
    // Kobo always render as two places: "₦100.1" would read as truncated.
    expect(LandaCurrency.format('100.10'), '₦100.10');
    expect(LandaCurrency.format('100.5'), '₦100.50');
  });

  test('never loses precision on very large values', () {
    // Formatting textually rather than via double means values beyond
    // double's exact-integer range still render digit-for-digit.
    expect(LandaCurrency.format('9007199254740993'), '₦9,007,199,254,740,993');
  });

  test('handles signs and symbol suppression', () {
    expect(LandaCurrency.format('-450000.00'), '-₦450,000');
    expect(LandaCurrency.format('450000.00', showSymbol: false), '450,000');
  });

  test('returns unrecognised input unchanged rather than a wrong number', () {
    // Better to surface whatever the backend sent than to invent a 0.
    expect(LandaCurrency.format('N/A'), 'N/A');
    expect(LandaCurrency.format('pending'), 'pending');
    expect(LandaCurrency.format(''), '₦0');
    expect(LandaCurrency.format(null), '₦0');
  });

  test('perYear suffixes the formatted amount', () {
    expect(LandaCurrency.perYear('600000.00'), '₦600,000/yr');
  });

  group('money arithmetic', () {
    test('parses decimal strings to whole kobo', () {
      expect(LandaCurrency.minorUnits('450000.00'), 45000000);
      expect(LandaCurrency.minorUnits('1000'), 100000);
      expect(LandaCurrency.minorUnits('1000.5'), 100050);
      expect(LandaCurrency.minorUnits('₦1,000.25'), 100025);
      expect(LandaCurrency.minorUnits('-500.00'), -50000);
    });

    test('refuses to invent a number it cannot read', () {
      // A null here becomes "we do not know", which callers turn into "do not
      // offer to pay from the vault". A 0 would silently mean "free".
      expect(LandaCurrency.minorUnits('pending'), isNull);
      expect(LandaCurrency.minorUnits(''), isNull);
      expect(LandaCurrency.minorUnits(null), isNull);
    });

    test('round-trips kobo back to the API string shape', () {
      expect(LandaCurrency.fromMinorUnits(45000000), '450000.00');
      expect(LandaCurrency.fromMinorUnits(100050), '1000.50');
      expect(LandaCurrency.fromMinorUnits(5), '0.05');
    });

    test('scale converts a quoted period into a year', () {
      // What the add-units sheet does with a rent typed per month. The API
      // stores one figure per unit and every screen reads it as annual, so
      // this multiplication is the whole of the interval feature.
      expect(LandaCurrency.scale('250000.00', 12), '3000000.00');
      expect(LandaCurrency.scale('450000.00', 1), '450000.00');
      // Kobo survive the multiplication rather than being rounded away.
      expect(LandaCurrency.scale('1000.50', 12), '12006.00');
      // Not a number: no rent, rather than a confident zero that would be
      // saved as a free flat.
      expect(LandaCurrency.scale('', 12), isNull);
      expect(LandaCurrency.scale('soon', 12), isNull);
    });

    test('subtract floors at zero and reports the shortfall', () {
      expect(LandaCurrency.subtract('450000.00', '120000.00'), '330000.00');
      // Saved more than the bill: the answer is "nothing left to save", not a
      // negative amount to display.
      expect(LandaCurrency.subtract('100000.00', '450000.00'), '0.00');
      expect(LandaCurrency.subtract('450000.00', 'unknown'), isNull);
    });

    test('covers compares exactly, including kobo', () {
      expect(LandaCurrency.covers('450000.00', '450000.00'), isTrue);
      // One kobo short is short. This gates the "pay from vault" button, and a
      // rounded comparison here becomes a payment that is offered then fails.
      expect(LandaCurrency.covers('449999.99', '450000.00'), isFalse);
      expect(LandaCurrency.covers('450000.01', '450000.00'), isTrue);
      expect(LandaCurrency.covers('unknown', '450000.00'), isFalse);
    });
  });
}
