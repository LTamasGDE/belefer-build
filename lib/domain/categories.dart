import 'models.dart';

/// Kategória: név, típus, szín és ikon.
///
/// A szín ARGB-egészként, az ikon kulcsként tárolódik, így ez a réteg
/// független a Fluttertől; a felület rendeli hozzá a tényleges ikont.
class Category {
  const Category({
    required this.id,
    required this.type,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    this.custom = false,
  });

  factory Category.fromMap(String id, Map<String, Object?> map) => Category(
    id: id,
    type: EntryType.fromStorage(map['type']),
    name: map['name']! as String,
    colorValue: (map['color']! as num).toInt(),
    iconKey: map['icon'] as String? ?? 'more',
    custom: true,
  );

  final String id;
  final EntryType type;
  final String name;
  final int colorValue;
  final String iconKey;

  /// A felhasználó által felvett kategória.
  final bool custom;

  Category copyWith({
    String? name,
    EntryType? type,
    int? colorValue,
    String? iconKey,
  }) => Category(
    id: id,
    type: type ?? this.type,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    iconKey: iconKey ?? this.iconKey,
    custom: custom,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type.storageKey,
    'name': name,
    'color': colorValue,
    'icon': iconKey,
  };
}

/// Induló kiadási kategóriák.
const List<Category> expenseCategories = [
  Category(
    id: 'housing',
    type: EntryType.expense,
    name: 'Lakhatás',
    colorValue: 0xFF4C6FFF,
    iconKey: 'home',
  ),
  Category(
    id: 'utilities',
    type: EntryType.expense,
    name: 'Rezsi',
    colorValue: 0xFF9A6BFF,
    iconKey: 'bolt',
  ),
  Category(
    id: 'groceries',
    type: EntryType.expense,
    name: 'Élelmiszer',
    colorValue: 0xFF14B8A6,
    iconKey: 'basket',
  ),
  Category(
    id: 'dining',
    type: EntryType.expense,
    name: 'Étterem, kávé',
    colorValue: 0xFFF2A516,
    iconKey: 'restaurant',
  ),
  Category(
    id: 'transport',
    type: EntryType.expense,
    name: 'Közlekedés',
    colorValue: 0xFF1EA7E8,
    iconKey: 'bus',
  ),
  Category(
    id: 'health',
    type: EntryType.expense,
    name: 'Egészség',
    colorValue: 0xFFEF5A5A,
    iconKey: 'heart',
  ),
  Category(
    id: 'clothing',
    type: EntryType.expense,
    name: 'Ruházat',
    colorValue: 0xFFE85AA6,
    iconKey: 'checkroom',
  ),
  Category(
    id: 'entertainment',
    type: EntryType.expense,
    name: 'Szórakozás',
    colorValue: 0xFFFF7A2F,
    iconKey: 'celebration',
  ),
  Category(
    id: 'subscriptions',
    type: EntryType.expense,
    name: 'Előfizetések',
    colorValue: 0xFF6E73F0,
    iconKey: 'subscriptions',
  ),
  Category(
    id: 'education',
    type: EntryType.expense,
    name: 'Tanulás',
    colorValue: 0xFF7CB82F,
    iconKey: 'school',
  ),
  Category(
    id: 'gifts',
    type: EntryType.expense,
    name: 'Ajándék',
    colorValue: 0xFFC855E0,
    iconKey: 'gift',
  ),
  Category(
    id: 'other_expense',
    type: EntryType.expense,
    name: 'Egyéb',
    colorValue: 0xFF8C93AE,
    iconKey: 'more',
  ),
];

/// Induló bevételi kategóriák.
const List<Category> incomeCategories = [
  Category(
    id: 'salary',
    type: EntryType.income,
    name: 'Fizetés',
    colorValue: 0xFF12A37F,
    iconKey: 'payments',
  ),
  Category(
    id: 'side_income',
    type: EntryType.income,
    name: 'Mellékes',
    colorValue: 0xFF14B8A6,
    iconKey: 'handyman',
  ),
  Category(
    id: 'scholarship',
    type: EntryType.income,
    name: 'Ösztöndíj',
    colorValue: 0xFF6E73F0,
    iconKey: 'school',
  ),
  Category(
    id: 'gift_income',
    type: EntryType.income,
    name: 'Ajándék',
    colorValue: 0xFFC855E0,
    iconKey: 'redeem',
  ),
  Category(
    id: 'refund',
    type: EntryType.income,
    name: 'Visszatérítés',
    colorValue: 0xFF1EA7E8,
    iconKey: 'replay',
  ),
  Category(
    id: 'other_income',
    type: EntryType.income,
    name: 'Egyéb',
    colorValue: 0xFF8C93AE,
    iconKey: 'more',
  ),
];

/// Választható színek az egyéni kategóriákhoz.
const List<int> customCategoryColors = [
  0xFF4C6FFF,
  0xFF9A6BFF,
  0xFF14B8A6,
  0xFFF2A516,
  0xFF1EA7E8,
  0xFFEF5A5A,
  0xFFE85AA6,
  0xFFFF7A2F,
  0xFF6E73F0,
  0xFF7CB82F,
  0xFFC855E0,
  0xFF8C93AE,
];

/// Választható ikonkulcsok az egyéni kategóriákhoz.
const List<String> customCategoryIcons = [
  'star',
  'pets',
  'fitness',
  'games',
  'travel',
  'car',
  'phone',
  'wifi',
  'book',
  'music',
  'coffee',
  'beauty',
  'baby',
  'sports',
  'savings',
  'work',
  'home',
  'basket',
  'restaurant',
  'heart',
  'gift',
  'school',
  'payments',
  'more',
];

/// Beépített és egyéni kategóriák együtt.
class CategoryCatalog {
  CategoryCatalog([List<Category> custom = const []])
    : custom = List.unmodifiable(custom) {
    for (final category in [
      ...expenseCategories,
      ...incomeCategories,
      ...custom,
    ]) {
      _byId[category.id] = category;
    }
  }

  static final CategoryCatalog builtIn = CategoryCatalog();

  final List<Category> custom;
  final Map<String, Category> _byId = {};

  /// A típus kategóriái: beépítettek, egyéniek, végül az „Egyéb”.
  List<Category> forType(EntryType type) {
    final builtIns = type == EntryType.expense
        ? expenseCategories
        : incomeCategories;
    final fallback = fallbackIdFor(type);
    return [
      for (final category in builtIns)
        if (category.id != fallback) category,
      for (final category in custom)
        if (category.type == type) category,
      _byId[fallback]!,
    ];
  }

  List<Category> get all => [
    ...forType(EntryType.expense),
    ...forType(EntryType.income),
  ];

  Category? byId(String id) => _byId[id];

  String nameOf(String id) => _byId[id]?.name ?? 'Egyéb';

  /// Sorrend a típuson belül (rendezéshez).
  int orderOf(String id) {
    final category = _byId[id];
    if (category == null) return 1 << 20;
    return forType(category.type).indexWhere((c) => c.id == id);
  }

  /// Az „Egyéb” kategória azonosítója a típushoz.
  static String fallbackIdFor(EntryType type) =>
      type == EntryType.expense ? 'other_expense' : 'other_income';
}

/// Az éppen érvényes katalógus. Az [AppState] frissíti betöltéskor és az
/// egyéni kategóriák változásakor.
CategoryCatalog currentCatalog = CategoryCatalog.builtIn;

List<Category> categoriesFor(EntryType type) => currentCatalog.forType(type);

/// A kategória az azonosítója alapján, vagy `null`, ha ismeretlen.
Category? categoryById(String id) => currentCatalog.byId(id);

/// A kategória neve; ismeretlen azonosítónál „Egyéb”.
String categoryName(String id) => currentCatalog.nameOf(id);

/// A kategória sorszáma a saját típusán belül (rendezéshez).
int categoryOrder(String id) => currentCatalog.orderOf(id);
