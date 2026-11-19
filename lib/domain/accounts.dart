import 'text_fold.dart';

/// A számla fajtája.
enum AccountKind {
  personal('personal', 'Saját'),
  savings('savings', 'Megtakarítás'),
  shared('shared', 'Közös');

  const AccountKind(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static AccountKind fromStorage(Object? value) {
    for (final kind in AccountKind.values) {
      if (kind.storageKey == value) return kind;
    }
    return AccountKind.personal;
  }
}

/// Egy számla vagy kártya, amelyhez a tételek tartoznak (pl. Saját Revolut,
/// Megtakarítás, Közös a pároddal).
class Account {
  const Account({
    this.id,
    required this.name,
    this.kind = AccountKind.personal,
    this.matchers = const [],
    this.isDefault = false,
  });

  factory Account.fromMap(int id, Map<String, Object?> map) {
    final matchers = map['matchers'];
    return Account(
      id: id,
      name: map['name']! as String,
      kind: AccountKind.fromStorage(map['kind']),
      matchers: [
        if (matchers is List)
          for (final matcher in matchers)
            if (matcher is String && matcher.trim().isNotEmpty) matcher.trim(),
      ],
      isDefault: map['default'] == true,
    );
  }

  final int? id;
  final String name;
  final AccountKind kind;

  /// Felismerő szavak: kártyanév az Apple Pay-ből (pl. „Revolut Közös”),
  /// kártyaszám vége (pl. „1234”) vagy szó az értesítésben (pl. „Joint”).
  final List<String> matchers;

  /// Ide kerül minden automatikus tétel, amelyre egyik felismerő sem illik.
  final bool isDefault;

  Account copyWith({
    int? id,
    String? name,
    AccountKind? kind,
    List<String>? matchers,
    bool? isDefault,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    matchers: matchers ?? this.matchers,
    isDefault: isDefault ?? this.isDefault,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'kind': kind.storageKey,
    'matchers': matchers,
    'default': isDefault,
  };
}

/// Melyik számlához tartozik egy automatikusan érkezett tétel: a leghosszabb
/// illeszkedő felismerő szó dönt; ha egyik sem illik, az alapértelmezett
/// számla (vagy `null`, ha nincs).
Account? matchAccount(List<Account> accounts, String text) {
  final haystack = ' ${foldForMatching(text)} ';
  // Különálló számcsoportok (pl. „•4821”); a teljes kártyaszám végére is
  // illeszkedik, de egy összeg darabjaira („14 821 Ft”) nem.
  final groups = [
    for (final match in RegExp(r'\d+').allMatches(text)) match.group(0)!,
  ];
  Account? best;
  var bestLength = 0;
  for (final account in accounts) {
    for (final matcher in account.matchers) {
      final key = foldForMatching(matcher);
      if (key.isEmpty) continue;
      final isNumber = RegExp(r'^\d+$').hasMatch(key);
      final hit = isNumber
          ? groups.any(
              (group) =>
                  group == key || (group.length >= 12 && group.endsWith(key)),
            )
          : haystack.contains(' $key ') ||
                (key.contains(' ') && haystack.contains(key)) ||
                (key.length >= 5 && haystack.contains(key));
      if (hit && key.length > bestLength) {
        best = account;
        bestLength = key.length;
      }
    }
  }
  if (best != null) return best;
  for (final account in accounts) {
    if (account.isDefault) return account;
  }
  return null;
}
