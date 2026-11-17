import 'calendar.dart';

/// A tétel iránya: kiadás vagy bevétel.
enum EntryType {
  expense('expense'),
  income('income');

  const EntryType(this.storageKey);

  /// Az adatbázisban tárolt azonosító.
  final String storageKey;

  static EntryType fromStorage(Object? value) {
    for (final type in EntryType.values) {
      if (type.storageKey == value) return type;
    }
    throw FormatException('Ismeretlen tételtípus', value);
  }
}

/// Egy rögzített kiadás vagy bevétel.
///
/// Az [amount] mindig pozitív, egész forint. A [type] dönti el, hogy az
/// összeg hozzáadódik vagy levonódik.
class Transaction {
  const Transaction({
    this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note,
  }) : assert(amount > 0, 'Az összeg pozitív egész forint.');

  factory Transaction.fromMap(int id, Map<String, Object?> map) {
    return Transaction(
      id: id,
      type: EntryType.fromStorage(map['type']),
      title: map['title']! as String,
      amount: (map['amount']! as num).toInt(),
      categoryId: map['category']! as String,
      date: CalendarDay.parse(map['date']! as String),
      note: _readOptionalText(map['note']),
    );
  }

  /// Az adatbázis kulcsa; mentés előtt `null`.
  final int? id;
  final EntryType type;
  final String title;
  final int amount;
  final String categoryId;
  final CalendarDay date;
  final String? note;

  /// Előjeles összeg: a kiadás negatív, a bevétel pozitív.
  int get signedAmount => type == EntryType.expense ? -amount : amount;

  Transaction copyWith({int? id}) => Transaction(
    id: id ?? this.id,
    type: type,
    title: title,
    amount: amount,
    categoryId: categoryId,
    date: date,
    note: note,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type.storageKey,
    'title': title,
    'amount': amount,
    'category': categoryId,
    'date': date.toIso(),
    'note': note,
  };
}

/// Újrahasználható minta egy tétel gyors rögzítéséhez.
///
/// A sablonból mentett tétel a saját adataival tárolódik, így a sablon
/// későbbi módosítása a korábbi tételeket nem érinti.
class EntryTemplate {
  const EntryTemplate({
    this.id,
    required this.type,
    required this.title,
    required this.categoryId,
    this.amount,
    this.note,
  }) : assert(amount == null || amount > 0, 'Az összeg pozitív egész forint.');

  factory EntryTemplate.fromMap(int id, Map<String, Object?> map) {
    final amount = map['amount'];
    return EntryTemplate(
      id: id,
      type: EntryType.fromStorage(map['type']),
      title: map['title']! as String,
      categoryId: map['category']! as String,
      amount: amount is num ? amount.toInt() : null,
      note: _readOptionalText(map['note']),
    );
  }

  final int? id;
  final EntryType type;

  /// A sablon neve, egyben a kitöltött tétel megnevezése.
  final String title;
  final String categoryId;
  final int? amount;
  final String? note;

  EntryTemplate copyWith({int? id}) => EntryTemplate(
    id: id ?? this.id,
    type: type,
    title: title,
    categoryId: categoryId,
    amount: amount,
    note: note,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type.storageKey,
    'title': title,
    'category': categoryId,
    'amount': amount,
    'note': note,
  };
}

String? _readOptionalText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
