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
    // Kobo always render as two places — "₦100.1" would read as truncated.
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
}
