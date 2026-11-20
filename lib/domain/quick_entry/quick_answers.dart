/// Kérdések a gyorsrögzítésben: „mennyit költöttem ebben a hónapban?”,
/// „mennyi maradt?”, „mennyi volt a bevételem októberben?”.
library;

import '../calendar.dart';
import '../categories.dart';
import '../formatting.dart';
import '../models.dart';
import '../text_fold.dart';
import 'lexicon.dart';
import 'tokens.dart';

/// Mit kérdez a felhasználó.
enum QuestionMeasure { expense, income, balance, help }

/// Egy felismert kérdés.
class QuickQuestionQuery {
  const QuickQuestionQuery({
    required this.measure,
    required this.words,
  });

  final QuestionMeasure measure;

  /// A kérdés (egyszerűsített) szavai: időszak és kategória.
  final List<String> words;
}

const Set<String> _questionStarts = {
  'mennyi',
  'mennyit',
  'mennyibe',
  'mennyiert',
  'hany',
  'hanyszor',
  'hogyan',
  'hogy',
  'mikor',
  'miert',
  'mit',
  'hol',
  'melyik',
  'milyen',
  'tudsz',
  'tudod',
  'tudnal',
  'mutasd',
  'segits',
  'segitseg',
  'help',
  'listazd',
};

const Set<String> _weakQuestionStarts = {'mi', 'van', 'lehet', 'kell'};

/// Kérdés-e a mondat. Rögzítendő tételnél (szám és ige) `null`.
QuickQuestionQuery? detectQuestion(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final words = [for (final token in tokenize(trimmed)) token.folded];
  if (words.isEmpty) return null;
  final asks = trimmed.endsWith('?');
  final first = words.first;
  final startsLikeQuestion =
      _questionStarts.contains(first) ||
      (asks && _weakQuestionStarts.contains(first));
  final hasNumber = words.any(
    (word) => RegExp(r'^\d').hasMatch(word) && !RegExp(r'^\d{1,2}$').hasMatch(word),
  );
  if (!startsLikeQuestion && !(asks && !hasNumber)) return null;
  // „mennyi volt a Lidl? 4500” típusú furcsaságokat rögzítésnek vesszük.
  if (hasNumber && !startsLikeQuestion) return null;

  final measure =
      words.any(
        (w) =>
            w.startsWith('maradt') ||
            w.startsWith('marad') ||
            w.startsWith('egyenleg') ||
            w == 'mennyim',
      )
      ? QuestionMeasure.balance
      : words.any(
          (w) =>
              w.startsWith('bevetel') ||
              w.startsWith('kerestem') ||
              w == 'jott' ||
              w.startsWith('bejott') ||
              w.startsWith('kaptam') ||
              w.startsWith('fizetes'),
        )
      ? QuestionMeasure.income
      : words.any(
          (w) =>
              w.startsWith('koltott') ||
              w.startsWith('elkoltott') ||
              w == 'ment' ||
              w.startsWith('elment') ||
              w.startsWith('kiadas') ||
              w.startsWith('fizettem') ||
              w.startsWith('vasaroltam') ||
              w.startsWith('kolt'),
        )
      ? QuestionMeasure.expense
      : QuestionMeasure.help;
  return QuickQuestionQuery(measure: measure, words: words);
}

const List<String> _monthStems = [
  'januar',
  'februar',
  'marcius',
  'aprilis',
  'majus',
  'junius',
  'julius',
  'augusztus',
  'szeptember',
  'oktober',
  'november',
  'december',
];

/// A kérdés megválaszolása a tételekből.
String answerQuestion(
  QuickQuestionQuery query,
  CalendarDay today,
  List<Transaction> history,
) {
  if (query.measure == QuestionMeasure.help) return _help(query.words);
  final words = query.words;

  // Időszak.
  var start = YearMonth.of(today).firstDay;
  var end = today;
  var label = '${monthName(today.month)}ban eddig';
  final previousMonth =
      words.any((w) => w == 'mult' || w == 'elozo') &&
      words.any((w) => w.startsWith('honap'));
  if (previousMonth) {
    final month = YearMonth.of(today).previous;
    start = month.firstDay;
    end = _addDays(month.next.firstDay, -1);
    label = '${monthName(month.month)}ban';
  } else if (words.any((w) => w == 'ma' || w == 'mai')) {
    start = today;
    label = 'ma';
  } else if (words.any((w) => w == 'tegnap')) {
    start = _addDays(today, -1);
    end = start;
    label = 'tegnap';
  } else if (words.any((w) => w == 'heten' || w == 'het')) {
    final lastWeek = words.any((w) => w == 'mult' || w == 'elozo');
    final monday = _addDays(today, -(today.weekday - 1));
    start = lastWeek ? _addDays(monday, -7) : monday;
    end = lastWeek ? _addDays(monday, -1) : today;
    label = lastWeek ? 'a múlt héten' : 'ezen a héten';
  } else if (words.any((w) => w == 'iden' || w == 'evben')) {
    start = CalendarDay(today.year, 1, 1);
    label = '${today.year}-ben eddig';
  } else {
    for (var m = 0; m < 12; m++) {
      if (!words.any((w) => w.startsWith(_monthStems[m]))) continue;
      var month = YearMonth(today.year, m + 1);
      if (month.compareTo(YearMonth.of(today)) > 0) {
        month = YearMonth(today.year - 1, m + 1);
      }
      start = month.firstDay;
      final last = _addDays(month.next.firstDay, -1);
      end = last.compareTo(today) > 0 ? today : last;
      label = month == YearMonth.of(today)
          ? '${monthName(month.month)}ban eddig'
          : '${month.year}. ${monthName(month.month)}ban';
      break;
    }
  }

  // Kategória a kulcsszavakból („kajára”, „benzinre”).
  final categories = <String>{};
  for (final word in words) {
    if (word.length < 3 || stopWords.contains(word)) continue;
    for (final keyword in keywords) {
      if (keyword.key.contains(' ')) continue;
      if (word == keyword.key ||
          (word.startsWith(keyword.key) && keyword.key.length >= 4)) {
        categories.add(keyword.categoryId);
      }
    }
  }

  var income = 0;
  var expense = 0;
  var count = 0;
  for (final transaction in history) {
    if (transaction.date.compareTo(start) < 0 ||
        transaction.date.compareTo(end) > 0) {
      continue;
    }
    if (categories.isNotEmpty && !categories.contains(transaction.categoryId)) {
      continue;
    }
    count++;
    if (transaction.type == EntryType.income) {
      income += transaction.amount;
    } else {
      expense += transaction.amount;
    }
  }
  final what = categories.isEmpty
      ? ''
      : ' (${categories.map(categoryName).toSet().join(', ')})';
  final capital = label[0].toUpperCase() + label.substring(1);
  if (count == 0) return '$capital$what nincs rögzített tétel.';
  return switch (query.measure) {
    QuestionMeasure.expense => '$capital$what ${formatForint(expense)} ment el.',
    QuestionMeasure.income => '$capital$what ${formatForint(income)} jött be.',
    _ =>
      '$capital ${formatForint(income)} jött be, ${formatForint(expense)} '
          'ment el, ${formatForint(income - expense)} maradt.',
  };
}

String _help(List<String> words) {
  bool mentions(String stem) => words.any((w) => w.startsWith(stem));
  if (mentions('sablon')) {
    return 'Sablont a Sablonok fülön hozhatsz létre (pl. Lakbér, Fizetés). '
        'Kiválasztáskor előre kitölti a megnevezést, a kategóriát és az '
        'összeget.';
  }
  if (mentions('ismetlod') || mentions('rendszeres')) {
    return 'Ismétlődő tételt itt is felvehetsz, pl. „Netflix havi 4990” '
        'vagy „minden hónapban 180 ezer lakbér”; az Ismétlődő fülön kezelheted.';
  }
  if (mentions('szamla') || mentions('revolut')) {
    return 'A számláidat a Beállítások › Számlák alatt kezelheted. Itt így '
        'jelölheted: „a közösről fizettem a Tescoban 8000”.';
  }
  if (mentions('blokk') || mentions('fot') || mentions('kep')) {
    return 'Blokkot a gyorsrögzítés kamera gombjával olvashatsz be.';
  }
  return 'Írd le, mire mennyit költöttél vagy mennyi jött be, pl. '
      '„Lidl 4500”, „tegnap ebéd 2800”, „megjött a fizetés 450 ezer”. '
      'Kérdezni is lehet: „mennyit költöttem ebben a hónapban?”.';
}

CalendarDay _addDays(CalendarDay day, int days) =>
    CalendarDay(day.year, day.month, day.day + days);
