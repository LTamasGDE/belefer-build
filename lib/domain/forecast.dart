import 'calendar.dart';
import 'models.dart';
import 'recurring.dart';
import 'text_fold.dart';

/// A jellemzően havonta egyszer fizetett kategóriák: ezeket nem vetítjük
/// ki napi átlaggal (a lakbér nem ismétlődik minden nap).
const Set<String> fixedExpenseCategories = {
  'housing',
  'utilities',
  'subscriptions',
};

/// Változó (napról napra előforduló) kiadás-e a tétel: nem ismétlődő
/// szabályból jött, nem fix kategóriájú, és a neve sem egyezik egy
/// ismétlődő tételével (pl. kézzel rögzített lakbér).
bool isVariableExpense(Transaction transaction, Set<String> ruleTitles) =>
    transaction.type == EntryType.expense &&
    transaction.recurringId == null &&
    !fixedExpenseCategories.contains(transaction.categoryId) &&
    !ruleTitles.contains(foldForMatching(transaction.title));

/// Egy várható (még nem rögzített) ismétlődő tétel.
class UpcomingItem {
  const UpcomingItem({
    required this.rule,
    required this.date,
    required this.amount,
    this.learned = false,
  });

  final RecurringRule rule;
  final CalendarDay date;
  final int amount;

  /// Nem beállított, hanem a tételeidből felismert ismétlődés (szokás).
  final bool learned;

  EntryType get type => rule.type;
}

/// Előrejelzés egy hónap végére.
class Forecast {
  const Forecast({
    required this.month,
    required this.actualIncome,
    required this.actualExpense,
    required this.upcoming,
    required this.projectedVariableExpense,
    required this.remainingDays,
    required this.basedOnHistory,
  });

  final YearMonth month;

  /// Eddig rögzített bevétel és kiadás a hónapban.
  final int actualIncome;
  final int actualExpense;

  /// A hónap hátralévő részében várható ismétlődő tételek.
  final List<UpcomingItem> upcoming;

  /// A nem ismétlődő kiadások becsült összege a hónap hátralévő részére.
  final int projectedVariableExpense;
  final int remainingDays;

  /// A becslés az előző hónapok átlagán alapul (kevés idei adat esetén).
  final bool basedOnHistory;

  int get upcomingIncome => upcoming
      .where((item) => item.type == EntryType.income)
      .fold(0, (sum, item) => sum + item.amount);

  int get upcomingExpense => upcoming
      .where((item) => item.type == EntryType.expense)
      .fold(0, (sum, item) => sum + item.amount);

  /// Várhatóan ennyi marad a hónap végén.
  int get projectedBalance =>
      actualIncome +
      upcomingIncome -
      actualExpense -
      upcomingExpense -
      projectedVariableExpense;

  int get projectedIncome => actualIncome + upcomingIncome;

  int get projectedExpense =>
      actualExpense + upcomingExpense + projectedVariableExpense;
}

/// Előrejelzés a [month] hónapra. Múltbeli hónapra `null`.
///
/// - Az ismétlődő tételek közül a még nem rögzített esedékességek számítanak.
/// - Az egyéb (nem ismétlődő) kiadásokat napi átlaggal becsüli: az aktuális
///   hónapban legalább 7 eltelt nap után az idei, előtte az előző három hónap
///   átlagából.
///
/// A [learnedRules] a tételekből felismert (nem beállított) ismétlődések:
/// ezek is várható tételek, és a napi átlagba sem számítanak bele.
Forecast? forecastMonth({
  required Iterable<Transaction> transactions,
  required Iterable<RecurringRule> rules,
  required YearMonth month,
  required CalendarDay today,
  Iterable<RecurringRule> learnedRules = const [],
}) {
  final current = YearMonth.of(today);
  if (month.compareTo(current) < 0) return null;
  final isCurrent = month == current;

  final ruleTitles = {
    for (final rule in rules) foldForMatching(rule.title),
    for (final rule in learnedRules) foldForMatching(rule.title),
  };
  var actualIncome = 0;
  var actualExpense = 0;
  var variableSoFar = 0;
  for (final transaction in transactions) {
    if (!month.contains(transaction.date)) continue;
    if (transaction.type == EntryType.income) {
      actualIncome += transaction.amount;
    } else {
      actualExpense += transaction.amount;
      if (isVariableExpense(transaction, ruleTitles) &&
          transaction.date.compareTo(today) <= 0) {
        variableSoFar += transaction.amount;
      }
    }
  }

  // Várható ismétlődő tételek: holnaptól (aktuális hónap) vagy a hónap
  // elejétől (jövőbeli hónap), a már kezelteket kihagyva.
  final from = isCurrent
      ? CalendarDay(today.year, today.month, today.day + 1)
      : month.firstDay;
  final upcoming = <UpcomingItem>[];
  for (final rule in rules) {
    for (final date in rule.occurrencesBetween(from, month.lastDay)) {
      final handled = rule.handledThrough;
      if (handled != null && date.compareTo(handled) <= 0) continue;
      upcoming.add(
        UpcomingItem(rule: rule, date: date, amount: rule.amountOn(date)),
      );
    }
    // A mai napig esedékes, de jóváhagyásra váró tételek is várhatóak.
    if (isCurrent && !rule.autoBook) {
      for (final date in rule.dueOccurrences(today)) {
        if (!month.contains(date)) continue;
        upcoming.add(
          UpcomingItem(rule: rule, date: date, amount: rule.amountOn(date)),
        );
      }
    }
  }
  // Felismert ismétlődések: a várható alkalom, ha ebben a hónapban még nem
  // rögzítetted (a pár napot késő alkalom is várható még).
  for (final rule in learnedRules) {
    final key = foldForMatching(rule.title);
    final recordedThisMonth = transactions.any(
      (t) =>
          month.contains(t.date) &&
          foldForMatching(t.title) == key &&
          t.date.compareTo(
                CalendarDay(rule.startDate.year, rule.startDate.month, 1),
              ) >=
              0,
    );
    if (recordedThisMonth) continue;
    var date = rule.startDate;
    if (isCurrent && date.compareTo(from) < 0) date = from;
    if (!month.contains(date)) continue;
    upcoming.add(
      UpcomingItem(rule: rule, date: date, amount: rule.amount, learned: true),
    );
  }
  upcoming.sort((a, b) => a.date.compareTo(b.date));

  final remainingDays = isCurrent
      ? month.daysInMonth - today.day
      : month.daysInMonth;
  final elapsedDays = isCurrent ? today.day : 0;

  final historyDaily = _historicalDailyVariableExpense(
    transactions,
    current,
    ruleTitles,
  );
  final useHistory = elapsedDays < 7 && historyDaily != null;
  final double daily;
  if (useHistory) {
    daily = historyDaily;
  } else if (elapsedDays > 0) {
    daily = variableSoFar / elapsedDays;
  } else {
    daily = historyDaily ?? 0;
  }

  return Forecast(
    month: month,
    actualIncome: actualIncome,
    actualExpense: actualExpense,
    upcoming: upcoming,
    projectedVariableExpense: (daily * remainingDays).round(),
    remainingDays: remainingDays,
    basedOnHistory: useHistory || (!isCurrent && historyDaily != null),
  );
}

/// Az előző (legfeljebb) három teljes hónap nem ismétlődő kiadásának napi
/// átlaga, vagy `null`, ha nincs adat.
double? _historicalDailyVariableExpense(
  Iterable<Transaction> transactions,
  YearMonth current,
  Set<String> ruleTitles,
) {
  final months = [
    current.previous,
    current.previous.previous,
    current.previous.previous.previous,
  ];
  var total = 0;
  var days = 0;
  for (final month in months) {
    var sum = 0;
    var any = false;
    for (final transaction in transactions) {
      if (!month.contains(transaction.date)) continue;
      any = true;
      if (isVariableExpense(transaction, ruleTitles)) {
        sum += transaction.amount;
      }
    }
    if (any) {
      total += sum;
      days += month.daysInMonth;
    }
  }
  if (days == 0) return null;
  return total / days;
}
