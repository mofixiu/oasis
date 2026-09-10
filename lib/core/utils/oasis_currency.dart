/// Display formatting for Naira amounts.
///
/// The backend sends money as decimal strings (`"450000.00"`) and the API
/// guide is explicit that these should be treated as string-safe decimals
/// rather than doubles. This formatter therefore works on the string itself,
/// grouping digits textually, so there is no float conversion and no way to
/// lose precision on the way to the screen.
///
/// Anything it cannot recognise is returned unchanged rather than rendered as
/// `0` or `NaN`: showing the raw backend value is always better than showing a
/// confidently wrong number for money.
class OasisCurrency {
  OasisCurrency._();

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
    // Not a number we recognise: hand back exactly what the backend sent.
    if (digits.isEmpty) return raw;

    // Money shows either no decimals or exactly two: never a lone "₦100.5",
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

  /// A decimal money string as whole kobo, or null when there is no number in
  /// it at all.
  ///
  /// Integer kobo, not doubles, for the same reason [format] works on the
  /// string: these values decide whether a payment is offered and whether a
  /// balance covers a bill, and a rounding artefact there becomes a payment
  /// that was promised and then declined. Tolerates a missing or short
  /// fractional part (`"1000"`, `"1000.5"`) and any grouping or symbol left
  /// in by a formatter.
  static int? minorUnits(Object? amount) {
    final cleaned = (amount?.toString() ?? '').replaceAll(
      RegExp(r'[^0-9.\-]'),
      '',
    );
    final isNegative = cleaned.startsWith('-');
    final unsigned = isNegative ? cleaned.substring(1) : cleaned;
    if (unsigned.replaceAll('.', '').isEmpty) return null;

    final parts = unsigned.split('.');
    final whole = int.tryParse(parts.first.isEmpty ? '0' : parts.first);
    if (whole == null) return null;
    var fraction = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      final parsed = int.tryParse(parts[1].padRight(2, '0').substring(0, 2));
      if (parsed == null) return null;
      fraction = parsed;
    }
    final total = whole * 100 + fraction;
    return isNegative ? -total : total;
  }

  /// Whole kobo back to the decimal string shape the API speaks.
  static String fromMinorUnits(int minor) {
    final isNegative = minor < 0;
    final absolute = minor.abs();
    final kobo = (absolute % 100).toString().padLeft(2, '0');
    return '${isNegative ? '-' : ''}${absolute ~/ 100}.$kobo';
  }

  /// `amount × factor` as a decimal string, or null when [amount] is not a
  /// number.
  ///
  /// Whole kobo throughout, for the same reason [minorUnits] exists: this is
  /// what turns a rent a landlord types per month into the annual figure the
  /// API stores, and a float artefact there would be a rent that is a kobo
  /// out on every listing it appears on.
  static String? scale(Object? amount, int factor) {
    final minor = minorUnits(amount);
    if (minor == null) return null;
    return fromMinorUnits(minor * factor);
  }

  /// `a - b` as a decimal string, floored at zero, or null when either side
  /// is not a number.
  ///
  /// Floored because every caller is asking "how much more is needed?": a
  /// negative shortfall is not a debt owed back, it is zero.
  static String? subtract(Object? a, Object? b) {
    final left = minorUnits(a);
    final right = minorUnits(b);
    if (left == null || right == null) return null;
    final difference = left - right;
    return fromMinorUnits(difference < 0 ? 0 : difference);
  }

  /// Whether [balance] settles a bill of [amount] in full. False when either
  /// is unreadable: offering to pay from a balance we cannot parse would put
  /// the user through a checkout that fails.
  static bool covers(Object? balance, Object? amount) {
    final have = minorUnits(balance);
    final owed = minorUnits(amount);
    if (have == null || owed == null) return false;
    return have >= owed;
  }

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
