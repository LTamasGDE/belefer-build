import '../calendar.dart';
import '../text_fold.dart';
import 'tokens.dart';

/// Felismert dátum és a hozzá felhasznált tokenek.
class DateMatch {
  const DateMatch({
    required this.day,
    required this.tokenIndexes,
    this.dayOfMonthOnly = false,
  });

  final CalendarDay day;
  final Set<int> tokenIndexes;

  /// Csak a hónap napja hangzott el („5-én”), hónap nélkül.
  final bool dayOfMonthOnly;
}

const Map<String, int> _months = {
  'januar': 1,
  'jan': 1,
  'februar': 2,
  'febr': 2,
  'feb': 2,
  'marcius': 3,
  'marc': 3,
  'aprilis': 4,
  'apr': 4,
  'majus': 5,
  'maj': 5,
  'junius': 6,
  'jun': 6,
  'julius': 7,
  'jul': 7,
  'augusztus': 8,
  'aug': 8,
  'szeptember': 9,
  'szept': 9,
  'oktober': 10,
  'okt': 10,
  'november': 11,
  'nov': 11,
  'december': 12,
  'dec': 12,
};

const Map<String, int> _weekdays = {
  'hetfo': DateTime.monday,
  'kedd': DateTime.tuesday,
  'szerda': DateTime.wednesday,
  'csutortok': DateTime.thursday,
  'pentek': DateTime.friday,
  'szombat': DateTime.saturday,
  'vasarnap': DateTime.sunday,
};

const Map<String, int> _ordinalDays = {
  'elseje': 1,
  'masodika': 2,
  'harmadika': 3,
  'negyedike': 4,
  'otodike': 5,
  'hatodika': 6,
  'hetedike': 7,
  'nyolcadika': 8,
  'kilencedike': 9,
  'tizedike': 10,
  'tizenotodike': 15,
  'huszadika': 20,
  'harmincadika': 30,
};

const Set<String> _multiplierWords = {
  'e',
  'k',
  'm',
  'ezer',
  'millio',
  'mio',
  'ft',
  'forint',
  'huf',
};

CalendarDay _addDays(CalendarDay day, int days) =>
    CalendarDay(day.year, day.month, day.day + days);

bool _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return false;
  return day <= YearMonth(year, month).daysInMonth;
}

/// A [day]-hoz legközelebbi múltbeli (vagy mai) dátum adott hónap-nappal.
CalendarDay _pastMonthDay(CalendarDay today, int month, int day) {
  var year = today.year;
  if (month > today.month || (month == today.month && day > today.day)) {
    year -= 1;
  }
  return CalendarDay(year, month, day);
}

/// Dátum keresése a szövegben. Elsőbbség: konkrét dátum, hónapnév,
/// hónap napja, relatív kifejezés, a hét napja.
DateMatch? findDate(
  String original,
  List<QuickToken> tokens,
  CalendarDay today, {
  bool preferFuture = false,
}) {
  final light = lightFold(original);

  // 1) 2026.11.17. / 2026-11-17 / 2026/11/17
  for (final match in RegExp(
    r'(\d{4})\s*[.\-/]\s*(\d{1,2})\s*[.\-/]\s*(\d{1,2})\.?',
  ).allMatches(light)) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (_validDate(year, month, day)) {
      return DateMatch(
        day: CalendarDay(year, month, day),
        tokenIndexes: tokensInRange(tokens, match.start, match.end),
      );
    }
  }

  // 2) 17.11.2026 / 17/11/2026
  for (final match in RegExp(
    r'(?<!\d)(\d{1,2})\s*[.\-/]\s*(\d{1,2})\s*[.\-/]\s*(\d{4})(?!\d)',
  ).allMatches(light)) {
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    if (_validDate(year, month, day)) {
      return DateMatch(
        day: CalendarDay(year, month, day),
        tokenIndexes: tokensInRange(tokens, match.start, match.end),
      );
    }
  }

  // 3) Hónapnévvel: „nov 3”, „november 3-án”, „2026. nov. 3.”
  for (var i = 0; i < tokens.length; i++) {
    final month = _monthOf(tokens[i].folded);
    if (month == null) continue;
    // Nap a hónapnév után.
    if (i + 1 < tokens.length) {
      final dayToken = tokens[i + 1].folded;
      final dayMatch = RegExp(r'^(\d{1,2})([a-z]*)$').firstMatch(dayToken);
      if (dayMatch != null) {
        final day = int.parse(dayMatch.group(1)!);
        var year = today.year;
        final used = <int>{i, i + 1};
        if (i > 0 && RegExp(r'^\d{4}$').hasMatch(tokens[i - 1].folded)) {
          year = int.parse(tokens[i - 1].folded);
          used.add(i - 1);
        }
        if (i + 2 < tokens.length &&
            RegExp(r'^(an|en|jen|ika|ike|ikan|iken|a|e|ig)$')
                .hasMatch(tokens[i + 2].folded)) {
          used.add(i + 2);
        }
        if (_validDate(year, month, day)) {
          final explicitYear = used.contains(i - 1);
          return DateMatch(
            day: explicitYear || preferFuture
                ? CalendarDay(year, month, day)
                : _pastMonthDay(today, month, day),
            tokenIndexes: used,
          );
        }
      }
    }
  }

  // 4) A hónap napja: „5-én”, „15-en”, „1-jén”, „elsején”
  for (final match in RegExp(
    r'(?<![\d.])(\d{1,2})\s*-?\s*(an|en|jen|ikan|iken|ika|ike)(?![a-z])',
  ).allMatches(light)) {
    final day = int.parse(match.group(1)!);
    if (day < 1 || day > 31) continue;
    return DateMatch(
      day: _dayOfMonth(today, day, preferFuture: preferFuture),
      tokenIndexes: tokensInRange(tokens, match.start, match.end),
      dayOfMonthOnly: true,
    );
  }
  for (var i = 0; i < tokens.length; i++) {
    final word = tokens[i].folded;
    for (final entry in _ordinalDays.entries) {
      if (word.startsWith(entry.key) &&
          word.length <= entry.key.length + 2) {
        return DateMatch(
          day: _dayOfMonth(today, entry.value, preferFuture: preferFuture),
          tokenIndexes: {i},
          dayOfMonthOnly: true,
        );
      }
    }
  }

  // 5) Relatív: ma, tegnap, tegnapelőtt, holnap, 3 napja, egy hete
  for (var i = 0; i < tokens.length; i++) {
    final word = tokens[i].folded;
    switch (word) {
      case 'ma' || 'mai' || 'ma reggel':
        return DateMatch(day: today, tokenIndexes: {i});
      case 'tegnap' || 'tegnapi' || 'tegnap este':
        return DateMatch(day: _addDays(today, -1), tokenIndexes: {i});
      case 'tegnapelott' || 'tegnapelotti' || 'tegnaputan':
        return DateMatch(day: _addDays(today, -2), tokenIndexes: {i});
      case 'holnap' || 'holnapi':
        return DateMatch(day: _addDays(today, 1), tokenIndexes: {i});
      case 'holnaputan' || 'holnaputani':
        return DateMatch(day: _addDays(today, 2), tokenIndexes: {i});
    }
    if (word == 'napja' || word == 'nappal' || word == 'hete' ||
        word == 'hettel') {
      if (i == 0) continue;
      final previous = tokens[i - 1].folded;
      final count = int.tryParse(previous) ?? _smallNumberWords[previous];
      if (count == null) continue;
      final used = <int>{i - 1, i};
      if (i + 1 < tokens.length &&
          (tokens[i + 1].folded == 'ezelott' ||
              tokens[i + 1].folded == 'korabban')) {
        used.add(i + 1);
      }
      final days = word.startsWith('nap') ? count : count * 7;
      return DateMatch(day: _addDays(today, -days), tokenIndexes: used);
    }
  }

  // 6) A hét napja: „pénteken”, „múlt kedden”, „jövő hétfőn”
  for (var i = 0; i < tokens.length; i++) {
    final word = tokens[i].folded;
    int? weekday;
    for (final entry in _weekdays.entries) {
      if (word == entry.key || fuzzyWordMatch(word, entry.key)) {
        weekday = entry.value;
        break;
      }
    }
    if (weekday == null) continue;
    final used = <int>{i};
    var direction = preferFuture ? 1 : -1;
    var strict = false;
    if (i > 0) {
      final previous = tokens[i - 1].folded;
      if (previous == 'mult' || previous == 'elozo') {
        direction = -1;
        strict = true;
        used.add(i - 1);
      } else if (previous == 'jovo' || previous == 'kovetkezo') {
        direction = 1;
        strict = true;
        used.add(i - 1);
      }
    }
    var day = today;
    if (direction < 0) {
      if (strict && day.weekday == weekday) day = _addDays(day, -7);
      while (day.weekday != weekday) {
        day = _addDays(day, -1);
      }
    } else {
      day = _addDays(day, 1);
      while (day.weekday != weekday) {
        day = _addDays(day, 1);
      }
    }
    return DateMatch(day: day, tokenIndexes: used);
  }

  // 7) Hónap.nap rövid alak: „11.17.” / „11/17” (Magyarországon hónap.nap)
  for (final match in RegExp(
    r'(?<![\d.,])(\d{1,2})\s*[./]\s*(\d{1,2})\.?(?![\d,a-z])',
  ).allMatches(light)) {
    final after = tokensInRange(tokens, match.end, match.end + 12);
    final nextWord = after.isEmpty ? null : tokens[after.first].folded;
    if (nextWord != null && _multiplierWords.contains(nextWord)) continue;
    var month = int.parse(match.group(1)!);
    var day = int.parse(match.group(2)!);
    if (month > 12 && day <= 12) {
      final swap = month;
      month = day;
      day = swap;
    }
    if (_validDate(today.year, month, day)) {
      return DateMatch(
        day: preferFuture
            ? CalendarDay(today.year, month, day)
            : _pastMonthDay(today, month, day),
        tokenIndexes: tokensInRange(tokens, match.start, match.end),
      );
    }
  }
  return null;
}

/// A hónap sorszáma a szóból (pontos egyezés elsőbbséggel, a teljes
/// neveknél elírás- és toldaléktűréssel), vagy `null`.
int? _monthOf(String word) {
  final exact = _months[word];
  if (exact != null) return exact;
  for (final entry in _months.entries) {
    if (entry.key.length >= 5 && fuzzyWordMatch(word, entry.key)) {
      // A „június”/„július” egy betűben tér el: csak egyértelmű egyezés.
      if ((entry.key == 'junius' || entry.key == 'julius') &&
          !word.startsWith(entry.key.substring(0, 3))) {
        continue;
      }
      return entry.value;
    }
  }
  return null;
}

const Map<String, int> _smallNumberWords = {
  'egy': 1,
  'ket': 2,
  'ketto': 2,
  'harom': 3,
  'negy': 4,
  'ot': 5,
  'hat': 6,
  'het': 7,
  'nyolc': 8,
  'kilenc': 9,
  'tiz': 10,
  'par': 2,
};

/// A hónap napja: az aktuális hónapban, vagy ha az még nem jött el, az
/// előzőben (múltbeli vásárlásnál); jövőt váró esetben a következő alkalom.
CalendarDay _dayOfMonth(
  CalendarDay today,
  int day, {
  required bool preferFuture,
}) {
  if (preferFuture) {
    var month = YearMonth.of(today);
    for (var i = 0; i < 2; i++) {
      final clamped = day > month.daysInMonth ? month.daysInMonth : day;
      final candidate = CalendarDay(month.year, month.month, clamped);
      if (candidate.compareTo(today) >= 0) return candidate;
      month = month.next;
    }
    return CalendarDay(today.year, today.month, day);
  }
  var month = YearMonth.of(today);
  if (day > today.day) month = month.previous;
  final clamped = day > month.daysInMonth ? month.daysInMonth : day;
  return CalendarDay(month.year, month.month, clamped);
}
