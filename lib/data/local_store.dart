import 'package:sembast/sembast.dart' hide Transaction;

import '../domain/categories.dart';
import '../domain/models.dart';
import '../domain/recurring.dart';

/// A készüléken tárolt adatok (Sembast-adatbázis).
///
/// Tárolók: `transactions`, `templates`, `recurring` (ismétlődő tételek),
/// `categories` (saját kategóriák) és `settings`. Minden adat csak ezen a
/// készüléken van; szinkronizálás nincs.
class LocalStore {
  LocalStore._(this._db);

  static const int schemaVersion = 1;
  static const String _themeKey = 'darkMode';
  static const String _tourKey = 'tourSeen';
  static const String _reminderKey = 'reminderDefaults';

  static Future<LocalStore> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(path, version: schemaVersion);
    return LocalStore._(db);
  }

  final Database _db;
  final StoreRef<int, Map<String, Object?>> _transactions = intMapStoreFactory
      .store('transactions');
  final StoreRef<int, Map<String, Object?>> _templates = intMapStoreFactory
      .store('templates');
  final StoreRef<int, Map<String, Object?>> _recurring = intMapStoreFactory
      .store('recurring');
  final StoreRef<int, Map<String, Object?>> _categories = intMapStoreFactory
      .store('categories');
  final StoreRef<String, Object?> _settings = StoreRef<String, Object?>(
    'settings',
  );

  /// A saját kategóriák azonosítója: `custom_<kulcs>`.
  static const String customPrefix = 'custom_';

  Future<List<Transaction>> loadTransactions() async {
    final records = await _transactions.find(_db);
    return [
      for (final record in records)
        Transaction.fromMap(record.key, record.value),
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

  Future<List<RecurringRule>> loadRecurring() async {
    final records = await _recurring.find(_db);
    return [
      for (final record in records)
        RecurringRule.fromMap(record.key, record.value),
    ];
  }

  Future<RecurringRule> saveRecurring(RecurringRule rule) async {
    final id = rule.id;
    if (id == null) {
      final key = await _recurring.add(_db, rule.toMap());
      return rule.copyWith(id: key);
    }
    await _recurring.record(id).put(_db, rule.toMap());
    return rule;
  }

  Future<void> deleteRecurring(int id) async {
    await _recurring.record(id).delete(_db);
  }

  Future<List<Category>> loadCategories() async {
    final records = await _categories.find(_db);
    return [
      for (final record in records)
        Category.fromMap('$customPrefix${record.key}', record.value),
    ];
  }

  /// Saját kategória mentése. Új kategóriánál (üres azonosító) a tároló adja
  /// a kulcsot.
  Future<Category> saveCategory(Category category) async {
    if (!category.id.startsWith(customPrefix)) {
      final key = await _categories.add(_db, category.toMap());
      return Category.fromMap('$customPrefix$key', category.toMap());
    }
    final key = int.parse(category.id.substring(customPrefix.length));
    await _categories.record(key).put(_db, category.toMap());
    return category;
  }

  /// Saját kategória törlése; a tételei, sablonjai és ismétlődő tételei a
  /// típus „Egyéb” kategóriájába kerülnek (egy tranzakcióban).
  Future<void> deleteCategory(Category category) async {
    final key = int.tryParse(category.id.substring(customPrefix.length));
    if (key == null) return;
    final fallback = CategoryCatalog.fallbackIdFor(category.type);
    final filter = Filter.equals('category', category.id);
    await _db.transaction((txn) async {
      for (final store in [_transactions, _templates, _recurring]) {
        await store.update(
          txn,
          <String, Object?>{'category': fallback},
          finder: Finder(filter: filter),
        );
      }
      await _categories.record(key).delete(txn);
    });
  }

  Future<bool> readTourSeen() async =>
      await _settings.record(_tourKey).get(_db) == true;

  Future<void> writeTourSeen(bool value) async {
    await _settings.record(_tourKey).put(_db, value);
  }

  Future<ReminderDefaults> readReminderDefaults() async {
    final value = await _settings.record(_reminderKey).get(_db);
    return value is Map
        ? ReminderDefaults.fromMap(value.cast<String, Object?>())
        : const ReminderDefaults();
  }

  Future<void> writeReminderDefaults(ReminderDefaults value) async {
    await _settings.record(_reminderKey).put(_db, value.toMap());
  }

  Future<bool> readDarkMode() async {
    final value = await _settings.record(_themeKey).get(_db);
    return value == true;
  }

  Future<void> writeDarkMode(bool value) async {
    await _settings.record(_themeKey).put(_db, value);
  }

  /// Minden tétel, sablon, ismétlődő tétel, saját kategória és beállítás
  /// törlése egy tranzakcióban. Csak az marad meg, hogy a bemutatót már
  /// látta-e a felhasználó.
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      final tourSeen = await _settings.record(_tourKey).get(txn);
      await _transactions.delete(txn);
      await _templates.delete(txn);
      await _recurring.delete(txn);
      await _categories.delete(txn);
      await _settings.delete(txn);
      if (tourSeen != null) await _settings.record(_tourKey).put(txn, tourSeen);
    });
  }

  Future<void> close() => _db.close();
}
