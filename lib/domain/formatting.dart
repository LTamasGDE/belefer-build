import 'calendar.dart';

/// Nem törhető szóköz: az összeg és a „Ft” nem válik el sortörésnél.
const String nbsp = ' ';

/// Matematikai mínuszjel a negatív összegekhez.
const String minusSign = '−';

const List<String> _monthNames = [
  'január',
  'február',
  'március',
  'április',
  'május',
  'június',
  'július',
  'augusztus',
  'szeptember',
  'október',
  'november',
  'december',
];

const List<String> _weekdayNames = [
  'hétfő',
  'kedd',
  'szerda',
  'csütörtök',
  'péntek',
  'szombat',
  'vasárnap',
];

/// Számjegyek hármas csoportosítása nem törhető szóközzel: 124 500.
String groupDigits(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(nbsp);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Forintösszeg magyar formátumban, például `124 500 Ft`.
///
/// Negatív érték mínuszjellel jelenik meg. A [signed] esetén a pozitív
/// összeg `+` jelet kap.
String formatForint(int amount, {bool signed = false}) {
  final sign = amount < 0 ? minusSign : (signed && amount > 0 ? '+' : '');
  return '$sign${groupDigits(amount)}${nbsp}Ft';
}

/// Tized százalék magyar formátumban: 452 → `45,2%`, 1000 → `100%`.
String formatPercentTenths(int tenths) {
  final whole = tenths ~/ 10;
  final fraction = tenths % 10;
  return fraction == 0 ? '$whole%' : '$whole,$fraction%';
}

String monthName(int month) => _monthNames[month - 1];

String weekdayName(int weekday) => _weekdayNames[weekday - 1];

/// Hónap címkéje: `2026. november`.
String formatYearMonth(YearMonth month) =>
    '${month.year}. ${monthName(month.month)}';

/// Teljes dátum: `2026. november 17., kedd`.
String formatFullDate(CalendarDay day) =>
    '${day.year}. ${monthName(day.month)} ${day.day}., ${weekdayName(day.weekday)}';

/// Rövid dátum listafejlécnek: `november 17., kedd`.
String formatDayHeading(CalendarDay day) =>
    '${monthName(day.month)} ${day.day}., ${weekdayName(day.weekday)}';

const List<String> _weekdayOnNames = [
  'hétfőn',
  'kedden',
  'szerdán',
  'csütörtökön',
  'pénteken',
  'szombaton',
  'vasárnap',
];

/// „kedden”, „vasárnap” – a hét napja határozóként.
String weekdayOn(int weekday) => _weekdayOnNames[weekday - 1];

/// A hónap napja ragozva: 1-jén, 2-án, 5-én, 20-án, 21-jén.
String dayWithSuffix(int day) {
  final String suffix;
  if (day % 10 == 0) {
    suffix = day == 10 ? 'én' : 'án';
  } else {
    suffix = const {
      1: 'jén',
      2: 'án',
      3: 'án',
      4: 'én',
      5: 'én',
      6: 'án',
      7: 'én',
      8: 'án',
      9: 'én',
    }[day % 10]!;
  }
  return '$day-$suffix';
}
