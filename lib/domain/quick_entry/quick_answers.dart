/// Kérdések a gyorsrögzítésben: „mennyit költöttem ebben a hónapban?”,
/// „mennyi maradt?”, „mennyi volt a bevételem októberben?”.
library;

import '../calendar.dart';
import '../categories.dart';
import '../forecast.dart';
import '../formatting.dart';
import '../models.dart';
import '../text_fold.dart';
import 'interpreter.dart';
import 'lexicon.dart';
import 'tokens.dart';

/// Mit kérdez a felhasználó.
enum QuestionMeasure {
  expense,
  income,
  balance,
  help,

  /// Mikor lesz? („mikor jön a fizetés?”)
  when,

  /// Mi várható? („mi lesz a héten?”)
  upcoming,

  /// Mennyi marad a hónap végére?
  endOfMonth,

  /// Mennyi szokott lenni? („mennyit szoktam költeni kajára?”)
  usual,
}

/// Egy felismert kérdés.
class QuickQuestionQuery {
  const QuickQuestionQuery({required this.measure, required this.words});

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
    (word) =>
        RegExp(r'^\d').hasMatch(word) && !RegExp(r'^\d{1,2}$').hasMatch(word),
  );
  if (!startsLikeQuestion && !(asks && !hasNumber)) return null;
  // „mennyi volt a Lidl? 4500” típusú furcsaságokat rögzítésnek vesszük.
  if (hasNumber && !startsLikeQuestion) return null;

  bool has(String prefix) => words.any((w) => w.startsWith(prefix));
  final measure = first == 'mikor' || words.contains('mikor')
      ? QuestionMeasure.when
      : (has('szokt') || has('altalaban') || has('atlag') || has('rendszerint'))
      ? QuestionMeasure.usual
      : (has('vege') || has('vegere') || has('vegen'))
      ? QuestionMeasure.endOfMonth
      : (has('varhato') ||
            words.contains('lesz') ||
            words.contains('jon') ||
            words.contains('jonnek') ||
            has('kovetkez') ||
            has('esedekes') ||
            (words.contains('mik') && has('het')))
      ? QuestionMeasure.upcoming
      : words.any(
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

/// A kérdés megválaszolása a tételekből, a szabályokból és a tanult
/// szokásokból.
String answerQuestion(QuickQuestionQuery query, QuickEntryContext context) {
  final today = context.today;
  final history = context.history;
  switch (query.measure) {
    case QuestionMeasure.help:
      return _help(query.words);
    case QuestionMeasure.when:
      return _answerWhen(query.words, context);
    case QuestionMeasure.upcoming:
      return _answerUpcoming(query.words, context);
    case QuestionMeasure.endOfMonth:
      return _answerEndOfMonth(context);
    case QuestionMeasure.usual:
      return _answerUsual(query.words, context);
    case QuestionMeasure.expense ||
        QuestionMeasure.income ||
        QuestionMeasure.balance:
      break;
  }
  final words = query.words;

  // Időszak.
  var start = YearMonth.of(today).firstDay;
  var end = today;
  var label = '${_inMonth(today.month)} eddig';
  final previousMonth =
      words.any((w) => w == 'mult' || w == 'elozo') &&
      words.any((w) => w.startsWith('honap'));
  if (previousMonth) {
    final month = YearMonth.of(today).previous;
    start = month.firstDay;
    end = _addDays(month.next.firstDay, -1);
    label = _inMonth(month.month);
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
    label = 'idén eddig';
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
          ? '${_inMonth(month.month)} eddig'
          : month.year == today.year
          ? _inMonth(month.month)
          : '${month.year}. ${_inMonth(month.month)}';
      break;
    }
  }

  final categories = _categoriesIn(words);

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
    QuestionMeasure.expense =>
      '$capital$what ${formatForint(expense)} ment el.',
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

/// „novemberben”, „októberben”, „januárban” (hangrendi illeszkedéssel).
String _inMonth(int month) =>
    '${monthName(month)}${month >= 9 ? 'ben' : 'ban'}';

/// Kategóriák a kérdés szavaiból („kajára”, „benzinre”).
Set<String> _categoriesIn(List<String> words) {
  final categories = <String>{};
  for (final word in words) {
    if (word.length < 3 || stopWords.contains(word)) continue;
    // A kérdés mértéke nem kategória („bevételem”, „kiadásom”).
    if (const [
      'bevetel',
      'kiadas',
      'koltes',
      'koltott',
      'koltok',
      'penz',
      'egyenleg',
      'marad',
      'szokt',
      'atlag',
    ].any(word.startsWith)) {
      continue;
    }
    for (final keyword in keywords) {
      if (keyword.key.contains(' ')) continue;
      if (word == keyword.key ||
          (word.startsWith(keyword.key) && keyword.key.length >= 4)) {
        categories.add(keyword.categoryId);
      }
    }
  }
  return categories;
}

typedef _Recurring = ({
  String title,
  String rhythm,
  int amount,
  CalendarDay? next,
  bool learned,
});

/// Az ismétlődő szabályok és a felismert ismétlődések közül a kérdezett.
_Recurring? _findRecurring(List<String> words, QuickEntryContext context) {
  final today = context.today;
  final categories = _categoriesIn(words);
  bool titleMatches(String title) {
    final parts = foldForMatching(
      title,
    ).split(' ').where((part) => part.length >= 3 && !stopWords.contains(part));
    return parts.isNotEmpty &&
        parts.any(
          (part) => words.any(
            (word) =>
                word == part ||
                (word.startsWith(part) && word.length - part.length <= 4) ||
                (part.startsWith(word) && word.length >= 4),
          ),
        );
  }

  final rules = context.rules.where((rule) => !rule.isEndedOn(today));
  for (final pass in [0, 1]) {
    for (final rule in rules) {
      final ok = pass == 0
          ? titleMatches(rule.title)
          : categories.contains(rule.categoryId);
      if (!ok) continue;
      final next = rule.nextOccurrence(today);
      return (
        title: rule.title,
        rhythm: rule.describe(),
        amount: rule.amountOn(next ?? today),
        next: next,
        learned: false,
      );
    }
    for (final pattern in context.knowledge.patterns) {
      final ok = pass == 0
          ? titleMatches(pattern.title)
          : categories.contains(pattern.categoryId);
      if (!ok) continue;
      return (
        title: pattern.title,
        rhythm: pattern.rhythm,
        amount: pattern.amount,
        next: pattern.next,
        learned: true,
      );
    }
  }
  return null;
}

String _answerWhen(List<String> words, QuickEntryContext context) {
  final found = _findRecurring(words, context);
  if (found == null) {
    return 'Erről még nem tudok eleget. Ha néhányszor rögzíted, megtanulom, '
        'mikor szokott lenni.';
  }
  final next = found.next == null
      ? ''
      : ' A következő: ${formatShortDate(found.next!, context.today)}.';
  return '${found.title}: ${found.learned ? 'általában ' : ''}${found.rhythm}, '
      '${found.learned ? 'legutóbb ' : ''}${formatForint(found.amount)}.$next';
}

/// Egy várható tétel a következő napokban.
typedef UpcomingEntry = ({
  CalendarDay date,
  String title,
  int amount,
  EntryType type,
  bool learned,
});

/// A következő napok várható tételei: beállított és felismert ismétlődések.
List<UpcomingEntry> upcomingItems(
  QuickEntryContext context,
  CalendarDay until,
) {
  final today = context.today;
  final items = <UpcomingEntry>[];
  final ruleKeys = <String>{};
  for (final rule in context.rules) {
    ruleKeys.add(foldForMatching(rule.title));
    for (final date in rule.occurrencesBetween(today, until)) {
      final handled = rule.handledThrough;
      if (handled != null && date.compareTo(handled) <= 0) continue;
      items.add((
        date: date,
        title: rule.title,
        amount: rule.amountOn(date),
        type: rule.type,
        learned: false,
      ));
    }
  }
  for (final pattern in context.knowledge.patterns) {
    if (ruleKeys.contains(pattern.key)) continue;
    var date = pattern.next;
    // A várható, de még nem rögzített (pár napot késő) alkalom ma esedékes.
    if (date.compareTo(today) < 0) date = today;
    if (date.compareTo(until) > 0) continue;
    items.add((
      date: date,
      title: pattern.title,
      amount: pattern.amount,
      type: pattern.type,
      learned: true,
    ));
  }
  items.sort((a, b) => a.date.compareTo(b.date));
  return items;
}

String _answerUpcoming(List<String> words, QuickEntryContext context) {
  final today = context.today;
  CalendarDay until;
  String label;
  if (words.any((w) => w.startsWith('honap'))) {
    until = YearMonth.of(today).lastDay;
    label = 'A hónap hátralévő részében';
  } else if (words.any((w) => w == 'heten' || w == 'het' || w == 'hetre')) {
    until = CalendarDay(
      today.year,
      today.month,
      today.day + (7 - today.weekday),
    );
    label = 'Ezen a héten';
  } else {
    until = CalendarDay(today.year, today.month, today.day + 14);
    label = 'A következő két hétben';
  }
  final items = upcomingItems(context, until);
  if (items.isEmpty) return '$label nincs várható tétel.';
  final listed = items
      .take(6)
      .map(
        (item) =>
            '${formatShortDate(item.date, today)}: ${item.title} '
            '${item.learned ? '~' : ''}${formatForint(item.amount)}',
      )
      .join(' · ');
  final more = items.length > 6 ? ' (és még ${items.length - 6})' : '';
  return '$label várható: $listed$more.';
}

String _answerEndOfMonth(QuickEntryContext context) {
  final today = context.today;
  final forecast = forecastMonth(
    transactions: context.history,
    rules: [
      ...context.rules,
      for (final pattern in context.knowledge.patterns) pattern.toRule(),
    ],
    month: YearMonth.of(today),
    today: today,
  );
  if (forecast == null) return 'Erre a hónapra nem tudok előrejelzést adni.';
  return 'A hónap végére várhatóan ${formatForint(forecast.projectedBalance)} '
      'marad: eddig ${formatForint(forecast.actualIncome)} jött be és '
      '${formatForint(forecast.actualExpense)} ment el, még várható '
      '${formatForint(forecast.upcomingIncome)} bevétel, '
      '${formatForint(forecast.upcomingExpense)} ismétlődő kiadás és kb. '
      '${formatForint(forecast.projectedVariableExpense)} egyéb költés.';
}

String _answerUsual(List<String> words, QuickEntryContext context) {
  final today = context.today;
  // Egy konkrét tétel szokásos összege („mennyibe kerül általában a kávé?”).
  for (final habit in context.knowledge.habits.values) {
    if (habit.count < 2) continue;
    final parts = habit.key.split(' ').where((p) => p.length >= 3).toList();
    if (parts.isNotEmpty &&
        parts.every(
          (part) => words.any(
            (word) =>
                word == part ||
                (word.startsWith(part) && word.length - part.length <= 4),
          ),
        )) {
      final amount = habit.usualAmount ?? habit.medianAmount;
      return '${habit.title}: általában ${formatForint(amount)} '
          '(${habit.count} alkalom alapján).';
    }
  }
  // Kategória havi átlaga az előző három teljes hónapból.
  final categories = _categoriesIn(words);
  final months = [
    YearMonth.of(today).previous,
    YearMonth.of(today).previous.previous,
    YearMonth.of(today).previous.previous.previous,
  ];
  final income = words.any(
    (w) => w.startsWith('bevetel') || w.startsWith('keres') || w == 'jon',
  );
  var total = 0;
  var monthsWithData = 0;
  for (final month in months) {
    var sum = 0;
    var any = false;
    for (final transaction in context.history) {
      if (!month.contains(transaction.date)) continue;
      any = true;
      if (categories.isNotEmpty &&
          !categories.contains(transaction.categoryId)) {
        continue;
      }
      if (categories.isEmpty &&
          (transaction.type == EntryType.income) != income) {
        continue;
      }
      sum += transaction.amount;
    }
    if (any) {
      total += sum;
      monthsWithData++;
    }
  }
  if (monthsWithData == 0) {
    return 'Ehhez még kevés a korábbi adat – egy-két hónap után már tudni '
        'fogom.';
  }
  final average = (total / monthsWithData).round();
  final what = categories.isEmpty
      ? (income ? 'bevételed' : 'kiadásod')
      : '${categories.map(categoryName).toSet().join(', ')} kiadásod';
  return 'A havi $what átlagosan ${formatForint(average)} '
      '(az előző $monthsWithData hónap alapján).';
}
