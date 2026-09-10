import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/core/utils/oasis_input_formatters.dart';

/// The grouping formatter sits on every amount the app accepts: a year's
/// rent, a nightly price, a caution fee, a vault top-up, a withdrawal. It is
/// display-only by design, so the two things worth pinning are that it never
/// changes the digits and that the caret stays where the user put it.
void main() {
  const formatter = OasisThousandsFormatter();

  TextEditingValue value(String text, [int? caret]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length),
  );

  TextEditingValue apply(String before, String after, [int? caret]) =>
      formatter.formatEditUpdate(value(before), value(after, caret));

  group('grouping', () {
    test('inserts separators from the right', () {
      expect(apply('45000', '450000').text, '450,000');
      expect(apply('450000', '4500000').text, '4,500,000');
      expect(apply('', '999').text, '999');
      expect(apply('', '1000').text, '1,000');
    });

    test('strips anything that is not a digit', () {
      expect(apply('', 'cheap-1').text, '1');
      expect(apply('', '12a3').text, '123');
      expect(apply('1', '').text, '');
    });

    test('the caret follows the digit it was next to', () {
      // Typing the final "0" of 450000 leaves the caret at the end.
      final result = apply('45,000', '45,0000');
      expect(result.text, '450,000');
      expect(result.selection.baseOffset, result.text.length);
    });
  });

  group('editing', () {
    test('backspacing a separator deletes the digit before it', () {
      // "450,000" with the caret just after the comma: the comma is what got
      // removed, and re-inserting it would make backspace look broken.
      final result = formatter.formatEditUpdate(
        value('450,000', 4),
        value('450000', 3),
      );
      expect(result.text, '45,000');
    });

    test('replacing the whole field keeps every digit', () {
      // The regression this exists for: `enterText`, a paste and a
      // select-all-then-type all replace the field wholesale, and a looser
      // "one character shorter" rule read that as a separator deletion and
      // silently ate a digit — 42000 over a prefilled 35,000 became 4,200.
      expect(apply('35,000', '42000').text, '42,000');
      expect(apply('450,000', '90000').text, '90,000');
    });
  });

  group('round-tripping', () {
    test('digitsOf undoes the grouping', () {
      expect(OasisThousandsFormatter.digitsOf('450,000'), '450000');
      expect(OasisThousandsFormatter.digitsOf('₦1,250,000'), '1250000');
      expect(OasisThousandsFormatter.digitsOf(''), '');
      expect(OasisThousandsFormatter.digitsOf(null), '');
    });

    test('groupAmount seeds a field from a backend decimal', () {
      expect(OasisThousandsFormatter.groupAmount('450000.00'), '450,000');
      expect(OasisThousandsFormatter.groupAmount('4200.50'), '4,200');
      expect(OasisThousandsFormatter.groupAmount(null), '');
    });

    test('what the field shows is what the wire gets, digit for digit', () {
      const typed = '1234567';
      final shown = apply('', typed).text;
      expect(shown, '1,234,567');
      expect(OasisThousandsFormatter.digitsOf(shown), typed);
    });
  });
}
