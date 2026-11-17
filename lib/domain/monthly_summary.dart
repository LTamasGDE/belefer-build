import 'calendar.dart';
import 'categories.dart';
import 'models.dart';

/// Egy kategória része a havi kiadásból.
class CategorySlice {
  const CategorySlice({
    required this.categoryId,
    required this.amount,
    required this.percentTenths,
  });

  final String categoryId;

  /// A kategória havi kiadása forintban.
  final int amount;

  /// Részesedés tized százalékban (452 = 45,2%). A szeletek összege
  /// pontosan 1000, ha van kiadás.
  final int percentTenths;

  String get label => categoryName(categoryId);
}

/// Egy hónap bevétele, kiadása és egyenlege, kategóriánkénti kiadással.
class MonthlySummary {
  const MonthlySummary({
    required this.month,
    required this.income,
    required this.expense,
    required this.expenseSlices,
  });

  final YearMonth month;
  final int income;
  final int expense;

  /// Kiadási szeletek csökkenő összeg szerint.
  final List<CategorySlice> expenseSlices;

  /// Ennyi maradt: bevétel mínusz kiadás (lehet negatív).
  int get balance => income - expense;

  bool get hasExpense => expense > 0;

  /// A kiadás aránya a teljes havi kiadáshoz képest, tized százalékban.
  /// Kiadás nélkül 0.
  int get expenseTotalPercentTenths => hasExpense ? 1000 : 0;
}

/// A [month] hónap összesítése az összes tételből.
MonthlySummary summarizeMonth(Iterable<Transaction> all, YearMonth month) {
  var income = 0;
  var expense = 0;
  final byCategory = <String, int>{};
  for (final transaction in all) {
    if (!month.contains(transaction.date)) continue;
    if (transaction.type == EntryType.income) {
      income += transaction.amount;
    } else {
      expense += transaction.amount;
      byCategory.update(
        transaction.categoryId,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }
  }

  final ids = byCategory.keys.toList()
    ..sort((a, b) {
      final byAmount = byCategory[b]!.compareTo(byCategory[a]!);
      if (byAmount != 0) return byAmount;
      return categoryOrder(a).compareTo(categoryOrder(b));
    });
  final tenths = distributeTenths([for (final id in ids) byCategory[id]!]);

  return MonthlySummary(
    month: month,
    income: income,
    expense: expense,
    expenseSlices: [
      for (var i = 0; i < ids.length; i++)
        CategorySlice(
          categoryId: ids[i],
          amount: byCategory[ids[i]]!,
          percentTenths: tenths[i],
        ),
    ],
  );
}

/// Arányos felosztás tized százalékra a legnagyobb maradék módszerével,
/// hogy a kerekített részek összege pontosan 1000 (100,0%) legyen.
List<int> distributeTenths(List<int> amounts) {
  final total = amounts.fold<int>(0, (sum, value) => sum + value);
  if (total <= 0) return List<int>.filled(amounts.length, 0);

  final floors = <int>[];
  final remainders = <int>[];
  for (final amount in amounts) {
    final scaled = amount * 1000;
    floors.add(scaled ~/ total);
    remainders.add(scaled % total);
  }
  var missing = 1000 - floors.fold<int>(0, (sum, value) => sum + value);
  final order = List<int>.generate(amounts.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      if (byRemainder != 0) return byRemainder;
      final byAmount = amounts[b].compareTo(amounts[a]);
      if (byAmount != 0) return byAmount;
      return a.compareTo(b);
    });
  for (final index in order) {
    if (missing <= 0) break;
    floors[index] += 1;
    missing -= 1;
  }
  return floors;
}

/// A hónap tételei dátum szerint csökkenő sorrendben (azonos napon a később
/// rögzített elöl), opcionálisan típus szerint szűrve.
List<Transaction> transactionsInMonth(
  Iterable<Transaction> all,
  YearMonth month, {
  EntryType? type,
}) {
  final result = [
    for (final transaction in all)
      if (month.contains(transaction.date) &&
          (type == null || transaction.type == type))
        transaction,
  ];
  result.sort(compareNewestFirst);
  return result;
}

/// Rendezés: újabb dátum elöl, azon belül a nagyobb (később kapott) azonosító.
int compareNewestFirst(Transaction a, Transaction b) {
  final byDate = b.date.compareTo(a.date);
  if (byDate != 0) return byDate;
  return (b.id ?? 0).compareTo(a.id ?? 0);
}
