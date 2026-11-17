import 'categories.dart';
import 'models.dart';

/// Közös szabályok a tétel- és a sablonűrlaphoz.
abstract final class EntryRules {
  static const int titleMaxLength = 40;
  static const int noteMaxLength = 200;
  static const int maxAmount = 999999999;
  static const int maxAmountDigits = 9;

  /// Csak a számjegyek megtartása (a csoportosító szóközök eltávolítása).
  static String digitsOf(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  /// Az összeg egész forintként, vagy `null`, ha üres vagy érvénytelen.
  static int? parseAmount(String? raw) {
    final digits = digitsOf(raw);
    if (digits.isEmpty || digits.length > maxAmountDigits) return null;
    final value = int.parse(digits);
    return value > 0 ? value : null;
  }

  /// Üres megjegyzésből `null` lesz.
  static String? normalizeNote(String? raw) {
    final trimmed = (raw ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? validateTitle(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Adj meg egy megnevezést.';
    if (value.length > titleMaxLength) {
      return 'Legfeljebb $titleMaxLength karakter lehet.';
    }
    return null;
  }

  /// Tételnél kötelező, sablonnál elhagyható összeg ellenőrzése.
  static String? validateAmount(String? raw, {required bool required}) {
    final digits = digitsOf(raw);
    if (digits.isEmpty) {
      return required ? 'Add meg az összeget.' : null;
    }
    if (digits.length > maxAmountDigits) return 'Ez túl nagy összeg.';
    if (int.parse(digits) <= 0) return 'Nullánál nagyobb összeget adj meg.';
    return null;
  }

  static String? validateCategory(String? id, EntryType type) {
    if (id == null) return 'Válassz kategóriát.';
    if (categoryById(id)?.type != type) return 'Válassz kategóriát.';
    return null;
  }

  static String? validateNote(String? raw) {
    if ((raw ?? '').trim().length > noteMaxLength) {
      return 'Legfeljebb $noteMaxLength karakter lehet.';
    }
    return null;
  }
}
