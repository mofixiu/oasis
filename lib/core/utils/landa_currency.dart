/// Display formatting for Naira amounts.
///
/// The backend sends money as decimal strings (`"450000.00"`) and the API
/// guide is explicit that these should be treated as string-safe decimals
/// rather than doubles. This formatter therefore works on the string itself —
/// grouping digits textually — so there is no float conversion and no way to
/// lose precision on the way to the screen.
///
/// Anything it cannot recognise is returned unchanged rather than rendered as
/// `0` or `NaN`: showing the raw backend value is always better than showing a
/// confidently wrong number for money.
class LandaCurrency {
  LandaCurrency._();

  static const String symbol = '₦';

  /// `"450000.00"` -> `"₦450,000"`, `"472500.50"` -> `"₦472,500.50"`.
  ///
  /// Trailing zero decimals are dropped because rents are whole Naira in
  /// practice; meaningful kobo are preserved.
  static String format(Object? amount, {bool showSymbol = true}) {
    final raw = amount?.toString().trim() ?? '';
    if (raw.isEmpty) return showSymbol ? '${symbol}0' : '0';

    final isNegative = raw.startsWith('-');
    final unsigned = isNegative ? raw.substring(1) : raw;

    final parts = unsigned.split('.');
    final digits = parts.first.replaceAll(RegExp(r'[^0-9]'), '');
    // Not a number we recognise — hand back exactly what the backend sent.
    if (digits.isEmpty) return raw;

    // Money shows either no decimals or exactly two — never a lone "₦100.5",
    // which reads as a truncation error. So: drop ".00" entirely, but pad any
    // real kobo back out to two places.
    final rawFraction = parts.length > 1
        ? parts[1].replaceAll(RegExp(r'[^0-9]'), '')
        : '';
    final hasKobo = rawFraction.replaceAll(RegExp(r'0+$'), '').isNotEmpty;
    final fraction = hasKobo
        ? rawFraction.padRight(2, '0').substring(0, 2)
        : '';

    final buffer = StringBuffer();
    // Sign leads the symbol: "-₦100", not "₦-100".
    if (isNegative) buffer.write('-');
    if (showSymbol) buffer.write(symbol);
    buffer.write(_group(digits));
    if (fraction.isNotEmpty) buffer.write('.$fraction');
    return buffer.toString();
  }

  /// Same as [format] but suffixed for annual rent, e.g. `"₦450,000/yr"`.
  static String perYear(Object? amount) => '${format(amount)}/yr';

  /// Inserts thousands separators from the right.
  static String _group(String digits) {
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    final firstGroup = digits.length % 3;
    if (firstGroup > 0) buffer.write(digits.substring(0, firstGroup));
    for (var i = firstGroup; i < digits.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write(',');
      buffer.write(digits.substring(i, i + 3));
    }
    return buffer.toString();
  }
}
