import 'package:flutter/services.dart';

/// Groups a money field's digits as they are typed: `450000` reads back as
/// `450,000`.
///
/// Every amount in this app is a Naira figure with no kobo, typed into a
/// digits-only field, and the numbers are large: a year's rent is six or
/// seven digits and a nightly price is five. Ungrouped, `4500000` and
/// `450000` are the same shape on a phone screen, and a landlord who mistypes
/// a zero has nothing to notice it by. Testers reported exactly that.
///
/// ## Why this is safe to bolt onto the existing fields
///
/// Nothing downstream reads the field's raw text as a number. Every caller
/// either strips non-digits itself (`text.replaceAll(RegExp(r'[^0-9]'), '')`)
/// or goes through [OasisCurrency.minorUnits], which strips anything that is
/// not a digit, a dot or a sign. So the separators are display-only and never
/// reach the wire.
///
/// ## Cursor handling
///
/// The naive version of this re-formats the string and leaves the caret at the
/// end, which makes editing the middle of a number impossible. Instead the
/// caret is tracked by *digit* position: count the digits before the caret in
/// the incoming value, then walk the formatted string until that many digits
/// have gone by. Deleting a separator is treated as deleting the digit in
/// front of it, so backspace over `450,000` removes a zero rather than
/// re-inserting the comma the user just deleted.
class OasisThousandsFormatter extends TextInputFormatter {
  const OasisThousandsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
        composing: TextRange.empty,
      );
    }

    // How many digits sit to the left of the caret in what the user just
    // typed. This is the anchor that survives regrouping.
    final caret = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    var digitsBeforeCaret = 0;
    for (var i = 0; i < caret; i++) {
      if (_isDigit(newValue.text.codeUnitAt(i))) digitsBeforeCaret++;
    }

    // Backspacing onto a separator: the character removed was a comma, so the
    // digit before it is what the user meant to delete. Without this, the
    // comma is simply re-inserted and backspace appears to do nothing.
    //
    // Recognised by reconstructing the edit exactly — old text with the
    // character at the caret removed — rather than by "one character shorter
    // with the same digits". That looser test also matches a wholesale
    // replacement of the field (which is what `enterText` and a paste both
    // do), and there it silently ate a digit: setting the field to "42000"
    // over a prefilled "35,000" produced 4200.
    final removedSeparator =
        newValue.text.length == oldValue.text.length - 1 &&
        caret < oldValue.text.length &&
        oldValue.text[caret] == ',' &&
        newValue.text ==
            oldValue.text.substring(0, caret) +
                oldValue.text.substring(caret + 1);
    if (removedSeparator && digitsBeforeCaret > 0) {
      final trimmed = digits.replaceRange(
        digitsBeforeCaret - 1,
        digitsBeforeCaret,
        '',
      );
      return _valueFor(trimmed, digitsBeforeCaret - 1);
    }

    return _valueFor(digits, digitsBeforeCaret);
  }

  /// Builds the grouped string and places the caret after [digitsBeforeCaret]
  /// digits of it.
  TextEditingValue _valueFor(String digits, int digitsBeforeCaret) {
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final grouped = group(digits);

    var seen = 0;
    var offset = grouped.length;
    for (var i = 0; i < grouped.length; i++) {
      if (seen == digitsBeforeCaret) {
        offset = i;
        break;
      }
      if (_isDigit(grouped.codeUnitAt(i))) seen++;
    }
    if (seen < digitsBeforeCaret) offset = grouped.length;

    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  /// Inserts thousands separators into a run of digits.
  ///
  /// Public so a screen that *sets* a field programmatically (prefilling the
  /// shortfall on a top-up, or a listing's current price when editing it) can
  /// write the same shape the formatter would have produced. Without it the
  /// prefilled value is the one number in the app that is not grouped.
  static String group(String digits) {
    final clean = digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length <= 3) return clean;
    final buffer = StringBuffer();
    final head = clean.length % 3;
    if (head > 0) buffer.write(clean.substring(0, head));
    for (var i = head; i < clean.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write(',');
      buffer.write(clean.substring(i, i + 3));
    }
    return buffer.toString();
  }

  /// The digits a grouped field is actually holding: `"450,000"` -> `"450000"`.
  ///
  /// Every call site that sends a typed amount to the API goes through this.
  /// The separators are a display device and must never reach the wire: a
  /// `rent_amount` of `"450,000"` is rejected by the serializer, and, worse,
  /// a `min_rent` query parameter of `"450,000"` is not — it is silently
  /// matched against nothing.
  static String digitsOf(Object? text) =>
      (text?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  /// The whole-Naira part of a decimal money string, grouped for display in
  /// an input: `"450000.00"` -> `"450,000"`.
  ///
  /// Used wherever a field is seeded from a backend amount. The kobo are
  /// dropped rather than shown, because these fields are whole-Naira and the
  /// value is read back with a digits-only strip.
  static String groupAmount(Object? amount) =>
      group((amount?.toString() ?? '').split('.').first);

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
}
