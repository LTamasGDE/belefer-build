import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../../domain/formatting.dart';
import '../../domain/validation.dart';

/// Gépelés közben hármas csoportokra bontja az összeget (124 500),
/// csak számjegyet enged, és a kurzort a megfelelő helyen tartja.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  static bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  static int _digitsBefore(String text, int offset) {
    var count = 0;
    for (var i = 0; i < offset && i < text.length; i++) {
      if (_isDigit(text.codeUnitAt(i))) count++;
    }
    return count;
  }

  /// Az összeg megjelenítése a mezőben: `124 500`; üresből üres.
  static String format(String digits) {
    if (digits.isEmpty) return '';
    return groupDigits(int.parse(digits));
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = EntryRules.digitsOf(newValue.text);
    final rawCursor = newValue.selection.isValid
        ? newValue.selection.extentOffset
        : newValue.text.length;
    final cursor = math.min(math.max(rawCursor, 0), newValue.text.length);
    var digitsBeforeCursor = _digitsBefore(newValue.text, cursor);

    // Csak egy elválasztó szóköz törlődött: a mögötte álló számjegyet töröljük.
    final oldDigits = EntryRules.digitsOf(oldValue.text);
    if (digits == oldDigits &&
        newValue.text.length < oldValue.text.length &&
        digitsBeforeCursor > 0) {
      digits =
          digits.substring(0, digitsBeforeCursor - 1) +
          digits.substring(digitsBeforeCursor);
      digitsBeforeCursor -= 1;
    }

    // Vezető nullák elhagyása.
    var stripped = 0;
    while (digits.length > 1 && digits.startsWith('0')) {
      digits = digits.substring(1);
      stripped++;
    }
    digitsBeforeCursor = math.min(
      math.max(digitsBeforeCursor - stripped, 0),
      digits.length,
    );

    if (digits.length > EntryRules.maxAmountDigits) return oldValue;

    final text = format(digits);
    var offset = 0;
    var seen = 0;
    while (offset < text.length && seen < digitsBeforeCursor) {
      if (_isDigit(text.codeUnitAt(offset))) seen++;
      offset++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
