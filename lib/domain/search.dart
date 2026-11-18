import 'categories.dart';
import 'formatting.dart';
import 'models.dart';
import 'monthly_summary.dart';
import 'text_fold.dart';

/// Keresés az összes tétel között: megnevezés, megjegyzés, kategória,
/// összeg és dátum alapján, ékezet- és kisbetű-függetlenül.
///
/// Több szó esetén mindegyiknek illeszkednie kell. Az eredmény a legújabb
/// tétellel kezdődik.
List<Transaction> searchTransactions(Iterable<Transaction> all, String query) {
  final terms = foldForMatching(
    query,
  ).split(' ').where((term) => term.isNotEmpty).toList();
  if (terms.isEmpty) return const [];

  final result = <Transaction>[];
  for (final transaction in all) {
    final haystack = _searchableText(transaction);
    final digits = transaction.amount.toString();
    var matches = true;
    for (final term in terms) {
      final termDigits = term.replaceAll(RegExp(r'[^0-9]'), '');
      final isNumeric =
          termDigits.isNotEmpty &&
          termDigits == term.replaceAll(RegExp(r'[.,]'), '');
      if (isNumeric && digits.contains(termDigits)) continue;
      if (haystack.contains(term)) continue;
      // Elírás-tűrés a hosszabb szavaknál.
      if (term.length >= 5 &&
          haystack.split(' ').any((word) => fuzzyWordMatch(word, term))) {
        continue;
      }
      matches = false;
      break;
    }
    if (matches) result.add(transaction);
  }
  result.sort(compareNewestFirst);
  return result;
}

String _searchableText(Transaction transaction) {
  final date = transaction.date;
  return foldForMatching(
    [
      transaction.title,
      transaction.note ?? '',
      categoryName(transaction.categoryId),
      transaction.type == EntryType.expense ? 'kiadás' : 'bevétel',
      date.toIso(),
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
      monthName(date.month),
    ].join(' '),
  );
}
