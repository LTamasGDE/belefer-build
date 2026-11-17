/// Naptári nap időpont és időzóna nélkül.
///
/// A tételek dátuma így mindig ugyanabban a hónapban marad, akárhol és
/// akármikor nyitja meg a felhasználó az alkalmazást.
class CalendarDay implements Comparable<CalendarDay> {
  /// Létrehoz egy naptári napot. A túlcsorduló értékeket (pl. 13. hónap)
  /// a [DateTime] szabályai szerint normalizálja.
  factory CalendarDay(int year, int month, int day) {
    final normalized = DateTime.utc(year, month, day);
    return CalendarDay._(normalized.year, normalized.month, normalized.day);
  }

  const CalendarDay._(this.year, this.month, this.day);

  /// A megadott időpont naptári napja, a [dateTime] saját mezői alapján.
  factory CalendarDay.fromDateTime(DateTime dateTime) =>
      CalendarDay._(dateTime.year, dateTime.month, dateTime.day);

  /// A készülék helyi ideje szerinti mai nap.
  factory CalendarDay.today() => CalendarDay.fromDateTime(DateTime.now());

  /// `ÉÉÉÉ-HH-NN` formátumú szöveg beolvasása.
  static CalendarDay parse(String value) {
    final match = _isoPattern.firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Érvénytelen dátum', value);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final result = CalendarDay(year, month, day);
    if (result.year != year || result.month != month || result.day != day) {
      throw FormatException('Nem létező nap', value);
    }
    return result;
  }

  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  /// A hét napja: 1 = hétfő … 7 = vasárnap.
  int get weekday => DateTime.utc(year, month, day).weekday;

  YearMonth get yearMonth => YearMonth(year, month);

  /// Helyi éjfél ezen a napon, például dátumválasztóhoz.
  DateTime toLocalDateTime() => DateTime(year, month, day);

  /// Tárolási formátum: `ÉÉÉÉ-HH-NN`.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(CalendarDay other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

/// Egy naptári hónap.
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month)
    : assert(month >= 1 && month <= 12, 'A hónap 1 és 12 közé esik.');

  factory YearMonth.of(CalendarDay day) => YearMonth(day.year, day.month);

  final int year;
  final int month;

  YearMonth get next =>
      month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);

  YearMonth get previous =>
      month == 1 ? YearMonth(year - 1, 12) : YearMonth(year, month - 1);

  CalendarDay get firstDay => CalendarDay(year, month, 1);

  CalendarDay get lastDay => CalendarDay(year, month, daysInMonth);

  int get daysInMonth => DateTime.utc(year, month + 1, 0).day;

  bool contains(CalendarDay day) => day.year == year && day.month == month;

  @override
  int compareTo(YearMonth other) {
    if (year != other.year) return year.compareTo(other.year);
    return month.compareTo(other.month);
  }

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}
