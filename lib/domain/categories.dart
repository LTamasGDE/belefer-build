import 'models.dart';

/// Kategória. A megjelenését (szín, ikon) a felület rendeli hozzá az
/// [id] alapján, így ez a réteg független a Fluttertől.
class Category {
  const Category({required this.id, required this.type, required this.name});

  final String id;
  final EntryType type;
  final String name;
}

/// Induló kiadási kategóriák.
const List<Category> expenseCategories = [
  Category(id: 'housing', type: EntryType.expense, name: 'Lakhatás'),
  Category(id: 'utilities', type: EntryType.expense, name: 'Rezsi'),
  Category(id: 'groceries', type: EntryType.expense, name: 'Élelmiszer'),
  Category(id: 'dining', type: EntryType.expense, name: 'Étterem, kávé'),
  Category(id: 'transport', type: EntryType.expense, name: 'Közlekedés'),
  Category(id: 'health', type: EntryType.expense, name: 'Egészség'),
  Category(id: 'clothing', type: EntryType.expense, name: 'Ruházat'),
  Category(id: 'entertainment', type: EntryType.expense, name: 'Szórakozás'),
  Category(id: 'subscriptions', type: EntryType.expense, name: 'Előfizetések'),
  Category(id: 'education', type: EntryType.expense, name: 'Tanulás'),
  Category(id: 'gifts', type: EntryType.expense, name: 'Ajándék'),
  Category(id: 'other_expense', type: EntryType.expense, name: 'Egyéb'),
];

/// Induló bevételi kategóriák.
const List<Category> incomeCategories = [
  Category(id: 'salary', type: EntryType.income, name: 'Fizetés'),
  Category(id: 'side_income', type: EntryType.income, name: 'Mellékes'),
  Category(id: 'scholarship', type: EntryType.income, name: 'Ösztöndíj'),
  Category(id: 'gift_income', type: EntryType.income, name: 'Ajándék'),
  Category(id: 'refund', type: EntryType.income, name: 'Visszatérítés'),
  Category(id: 'other_income', type: EntryType.income, name: 'Egyéb'),
];

List<Category> categoriesFor(EntryType type) =>
    type == EntryType.expense ? expenseCategories : incomeCategories;

final Map<String, Category> _byId = {
  for (final category in [...expenseCategories, ...incomeCategories])
    category.id: category,
};

/// A kategória az azonosítója alapján, vagy `null`, ha ismeretlen.
Category? categoryById(String id) => _byId[id];

/// A kategória neve; ismeretlen azonosítónál „Egyéb”.
String categoryName(String id) => _byId[id]?.name ?? 'Egyéb';

/// A kategória sorszáma a saját típusán belül (rendezéshez).
int categoryOrder(String id) {
  final category = _byId[id];
  if (category == null) return 1 << 20;
  return categoriesFor(category.type).indexOf(category);
}
