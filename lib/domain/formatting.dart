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

/// A hónap napja ragozva: 1-jén, 2-án, 5-én, 11-én, 20-án, 21-én.
String dayWithSuffix(int day) {
  final String suffix;
  if (day == 1) {
    suffix = 'jén';
  } else if (day % 10 == 1) {
    // tizenegyedikén, huszonegyedikén
    suffix = 'én';
  } else if (day % 10 == 0) {
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

/// Rövid, viszonyított dátum: „ma”, „holnap”, „tegnap”, „nov. 25.”
/// (más évben az évvel együtt).
String formatShortDate(CalendarDay day, CalendarDay today) {
  final difference = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  switch (difference) {
    case 0:
      return 'ma';
    case 1:
      return 'holnap';
    case -1:
      return 'tegnap';
  }
  final month = _shortMonthNames[day.month - 1];
  return day.year == today.year
      ? '$month ${day.day}.'
      : '${day.year}. $month ${day.day}.';
}

const List<String> _shortMonthNames = [
  'jan.',
  'febr.',
  'márc.',
  'ápr.',
  'máj.',
  'jún.',
  'júl.',
  'aug.',
  'szept.',
  'okt.',
  'nov.',
  'dec.',
];

/// „mától”, „holnaptól”, „december 5-étől”.
String formatFromDate(CalendarDay day, CalendarDay today) {
  final difference = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (difference == 0) return 'mától';
  if (difference == 1) return 'holnaptól';
  final onDay = dayWithSuffix(day.day);
  final from = onDay.endsWith('jén')
      ? '${onDay.substring(0, onDay.length - 3)}jétől'
      : onDay.endsWith('án')
      ? '${onDay.substring(0, onDay.length - 2)}ától'
      : '${onDay.substring(0, onDay.length - 2)}étől';
  final year = day.year == today.year ? '' : '${day.year}. ';
  return '$year${monthName(day.month)} $from';
}
