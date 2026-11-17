import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import '../domain/calendar.dart';
import '../domain/models.dart';
import '../domain/monthly_summary.dart';

/// Az alkalmazás egyetlen állapotforrása.
///
/// Minden képernyő ugyanebből olvas, ezért mentés, szerkesztés és törlés
/// után a lista és az áttekintés ugyanazt a friss adatot mutatja.
class AppState extends ChangeNotifier {
  AppState({
    required LocalStore store,
    required this.versionLabel,
    CalendarDay Function()? today,
  }) : _store = store,
       _today = today ?? CalendarDay.today {
    _selectedMonth = YearMonth.of(_today());
  }

  final LocalStore _store;
  final CalendarDay Function() _today;

  /// Az alkalmazás verziója a build metaadataiból, pl. `0.1.0 (1)`.
  final String versionLabel;

  List<Transaction> _transactions = const [];
  List<EntryTemplate> _templates = const [];
  bool _darkMode = false;
  late YearMonth _selectedMonth;

  CalendarDay today() => _today();

  List<Transaction> get transactions => _transactions;
  List<EntryTemplate> get templates => _templates;
  bool get darkMode => _darkMode;

  /// Az Áttekintés és a Tételek képernyő közös hónapja.
  YearMonth get selectedMonth => _selectedMonth;

  bool get isCurrentMonth => _selectedMonth == YearMonth.of(_today());

  MonthlySummary get summary => summarizeMonth(_transactions, _selectedMonth);

  List<Transaction> transactionsOfSelectedMonth({EntryType? type}) =>
      transactionsInMonth(_transactions, _selectedMonth, type: type);

  /// Sablonok név szerint, opcionálisan típus szerint szűrve.
  List<EntryTemplate> templatesOf(EntryType? type) {
    final result = [
      for (final template in _templates)
        if (type == null || template.type == type) template,
    ];
    result.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return result;
  }

  Future<void> load() async {
    _transactions = await _store.loadTransactions();
    _templates = await _store.loadTemplates();
    _darkMode = await _store.readDarkMode();
    notifyListeners();
  }

  void showMonth(YearMonth month) {
    if (month == _selectedMonth) return;
    _selectedMonth = month;
    notifyListeners();
  }

  void showPreviousMonth() => showMonth(_selectedMonth.previous);

  void showNextMonth() => showMonth(_selectedMonth.next);

  void showCurrentMonth() => showMonth(YearMonth.of(_today()));

  /// Új tétel felvétele vagy meglévő módosítása.
  Future<Transaction> saveTransaction(Transaction transaction) async {
    final saved = await _store.saveTransaction(transaction);
    _transactions = [
      for (final existing in _transactions)
        if (existing.id != saved.id) existing,
      saved,
    ];
    notifyListeners();
    return saved;
  }

  Future<void> deleteTransaction(int id) async {
    await _store.deleteTransaction(id);
    _transactions = [
      for (final existing in _transactions)
        if (existing.id != id) existing,
    ];
    notifyListeners();
  }

  Future<EntryTemplate> saveTemplate(EntryTemplate template) async {
    final saved = await _store.saveTemplate(template);
    _templates = [
      for (final existing in _templates)
        if (existing.id != saved.id) existing,
      saved,
    ];
    notifyListeners();
    return saved;
  }

  Future<void> deleteTemplate(int id) async {
    await _store.deleteTemplate(id);
    _templates = [
      for (final existing in _templates)
        if (existing.id != id) existing,
    ];
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (value == _darkMode) return;
    _darkMode = value;
    notifyListeners();
    await _store.writeDarkMode(value);
  }

  /// Minden helyi tétel és sablon törlése, a beállítások visszaállítása.
  Future<void> clearAllData() async {
    await _store.clearAll();
    _transactions = const [];
    _templates = const [];
    _darkMode = false;
    _selectedMonth = YearMonth.of(_today());
    notifyListeners();
  }

  /// Az adatbázis lezárása (tesztekhez és újranyitás szimulálásához).
  Future<void> close() => _store.close();
}
