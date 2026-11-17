import 'package:sembast/sembast.dart' hide Transaction;

import '../domain/models.dart';

/// A készüléken tárolt adatok (Sembast-adatbázis).
///
/// Tárolók: `transactions`, `templates` és `settings`. Minden adat csak ezen
/// a készüléken van; szinkronizálás nincs.
class LocalStore {
  LocalStore._(this._db);

  static const int schemaVersion = 1;
  static const String _themeKey = 'darkMode';

  static Future<LocalStore> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(path, version: schemaVersion);
    return LocalStore._(db);
  }

  final Database _db;
  final StoreRef<int, Map<String, Object?>> _transactions = intMapStoreFactory
      .store('transactions');
  final StoreRef<int, Map<String, Object?>> _templates = intMapStoreFactory
      .store('templates');
  final StoreRef<String, Object?> _settings = StoreRef<String, Object?>(
    'settings',
  );

  Future<List<Transaction>> loadTransactions() async {
    final records = await _transactions.find(_db);
    return [
      for (final record in records) Transaction.fromMap(record.key, record.value),
    ];
  }

  Future<Transaction> saveTransaction(Transaction transaction) async {
    final id = transaction.id;
    if (id == null) {
      final key = await _transactions.add(_db, transaction.toMap());
      return transaction.copyWith(id: key);
    }
    await _transactions.record(id).put(_db, transaction.toMap());
    return transaction;
  }

  Future<void> deleteTransaction(int id) async {
    await _transactions.record(id).delete(_db);
  }

  Future<List<EntryTemplate>> loadTemplates() async {
    final records = await _templates.find(_db);
    return [
      for (final record in records)
        EntryTemplate.fromMap(record.key, record.value),
    ];
  }

  Future<EntryTemplate> saveTemplate(EntryTemplate template) async {
    final id = template.id;
    if (id == null) {
      final key = await _templates.add(_db, template.toMap());
      return template.copyWith(id: key);
    }
    await _templates.record(id).put(_db, template.toMap());
    return template;
  }

  Future<void> deleteTemplate(int id) async {
    await _templates.record(id).delete(_db);
  }

  Future<bool> readDarkMode() async {
    final value = await _settings.record(_themeKey).get(_db);
    return value == true;
  }

  Future<void> writeDarkMode(bool value) async {
    await _settings.record(_themeKey).put(_db, value);
  }

  /// Minden tétel, sablon és beállítás törlése egy tranzakcióban.
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await _transactions.delete(txn);
      await _templates.delete(txn);
      await _settings.delete(txn);
    });
  }

  Future<void> close() => _db.close();
}
