import '../calendar.dart';
import '../categories.dart';
import '../models.dart';
import '../text_fold.dart';
import 'amount_parser.dart';
import 'date_parser.dart';
import 'interpreter.dart';
import 'lexicon.dart';
import 'tokens.dart';

/// Végösszegre utaló kulcsszavak, erősség szerint (a nagyobb az erősebb).
const List<(String, int)> _totalKeywords = [
  ('fizetendo osszeg', 10),
  ('fizetendo vegosszeg', 10),
  ('brutto vegosszeg', 10),
  ('szamla vegosszege', 10),
  ('fizetendo', 9),
  ('vegosszeg', 9),
  ('osszesen', 8),
  ('mindosszesen', 8),
  ('total', 7),
  ('brutto osszeg', 7),
  ('brutto', 5),
  ('bankkartya', 6),
  ('kartyas fizetes', 6),
  ('kartya', 5),
  ('keszpenz', 5),
  ('fizetve', 5),
  ('osszeg', 4),
];

/// Sorok, amelyekben lévő szám biztosan nem végösszeg.
const List<String> _excludedLineWords = [
  'afa',
  'ado',
  'adoszam',
  'kedvezmeny',
  'visszajaro',
  'cimlet',
  'kerekites',
  'netto',
  'egysegar',
  'nyugtaszam',
  'szamlaszam',
  'ap ',
  'telefon',
  'tel',
  'bankszamla',
];

/// A blokk vagy számla szövegének értelmezése (a szövegfelismerés után,
/// a felhasználó ellenőrzése után).
///
/// Megkeresi a kereskedőt, a végösszeget és a dátumot; a kategóriát a
/// kereskedőből vagy a tételsorokból következteti ki.
QuickEntryResult interpretReceipt(String text, QuickEntryContext context) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final notes = <String>[];

  // Végösszeg: a legerősebb kulcsszavas sor (vagy az utána következő) összege.
  int? total;
  var bestStrength = 0;
  for (var index = 0; index < lines.length; index++) {
    final foldedLine = foldForMatching(lines[index]);
    final strength = _keywordStrength(foldedLine);
    if (strength == 0 || strength < bestStrength) continue;
    var amount = _lineAmount(lines[index], excludeQuantities: false);
    if (amount == null && index + 1 < lines.length) {
      amount = _lineAmount(lines[index + 1], excludeQuantities: false);
    }
    if (amount == null) continue;
    if (strength > bestStrength || (total != null && amount > total)) {
      total = amount;
      bestStrength = strength;
    }
  }
  if (total == null) {
    // Nincs kulcsszó: a legnagyobb „Ft”-os összeg.
    for (final line in lines) {
      final foldedLine = foldForMatching(line);
      if (_excludedLineWords.any(foldedLine.contains)) continue;
      final amount = _lineAmount(line, excludeQuantities: true, needsCurrency: true);
      if (amount != null && (total == null || amount > total)) total = amount;
    }
    if (total == null) {
      // Pénznem sincs: a legnagyobb ésszerű szám a nem kizárt sorokból.
      for (final line in lines) {
        final foldedLine = foldForMatching(line);
        if (_excludedLineWords.any(foldedLine.contains)) continue;
        final amount = _lineAmount(line, excludeQuantities: true);
        if (amount != null &&
            amount < 1000000 &&
            (total == null || amount > total)) {
          total = amount;
        }
      }
    }
    if (total != null) {
      notes.add('Nem találtam „Összesen” sort – ellenőrizd az összeget.');
    }
  }

  // Dátum: dátumra utaló sor előnyben (kelte, teljesítés, dátum).
  CalendarDay? date;
  for (final line in lines) {
    final foldedLine = foldForMatching(line);
    final match = findDate(line, tokenize(line), context.today);
    if (match == null) continue;
    final strong = foldedLine.contains('kelt') ||
        foldedLine.contains('datum') ||
        foldedLine.contains('teljesites');
    if (date == null || strong) date = match.day;
    if (strong) break;
  }
  date ??= _receiptShortDate(lines, context.today);
  if (date != null && date.compareTo(context.today) > 0) date = context.today;

  // Kereskedő és kategória.
  String? merchant;
  String? categoryId;
  final sellerLine = _sellerLine(lines);
  final searchLines = [?sellerLine, ...lines.take(8), ...lines];
  outer:
  for (final line in searchLines) {
    final words = tokenize(line).map((token) => token.folded).toList();
    for (final entry in merchants) {
      for (final key in entry.keys) {
        if (key.length <= 2) continue;
        final keyParts = key.split(' ');
        final hit = keyParts.length > 1
            ? foldForMatching(line).contains(key)
            : words.any((word) =>
                word == key || (key.length >= 4 && fuzzyWordMatch(word, key)));
        if (hit) {
          merchant = entry.name;
          categoryId = entry.categoryId;
          break outer;
        }
      }
    }
  }
  merchant ??= sellerLine != null
      ? _cleanCompanyName(sellerLine)
      : (lines.isNotEmpty ? _cleanCompanyName(_firstNameLine(lines)) : null);

  // Kategória a tételsorokból, ha a kereskedőből nem derült ki.
  if (categoryId == null) {
    final scores = <String, int>{};
    for (final line in lines) {
      final words = tokenize(line).map((token) => token.folded).toList();
      for (final keyword in keywords) {
        final category = categoryById(keyword.categoryId);
        if (category == null || category.type != EntryType.expense) continue;
        if (keyword.key.contains(' ')) continue;
        if (words.any((word) =>
            word == keyword.key ||
            (keyword.key.length >= 5 && fuzzyWordMatch(word, keyword.key)))) {
          scores.update(
            keyword.categoryId,
            (value) => value + keyword.weight,
            ifAbsent: () => keyword.weight,
          );
        }
      }
    }
    if (scores.isNotEmpty) {
      categoryId = (scores.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
    }
  }

  // Tanult kategória a korábbi, azonos nevű tételekből.
  if (merchant != null) {
    final key = foldForMatching(merchant);
    for (final transaction in context.history.reversed) {
      if (foldForMatching(transaction.title) == key &&
          categoryById(transaction.categoryId) != null) {
        categoryId = transaction.categoryId;
        break;
      }
    }
  }

  final resolvedCategory =
      categoryId ?? CategoryCatalog.fallbackIdFor(EntryType.expense);
  return QuickEntryResult(
    intent: QuickIntent.record,
    type: EntryType.expense,
    typeExplicit: true,
    amount: total,
    title: merchant == null || merchant.isEmpty
        ? null
        : (merchant.length > 40 ? merchant.substring(0, 40).trim() : merchant),
    merchant: merchant,
    categoryId: resolvedCategory,
    categoryGuessed: categoryId == null,
    date: date ?? context.today,
    dateExplicit: date != null,
    notes: notes,
  );
}

int _keywordStrength(String foldedLine) {
  if (_excludedLineWords.any(foldedLine.contains) &&
      !foldedLine.contains('osszesen') &&
      !foldedLine.contains('fizetendo')) {
    return 0;
  }
  var best = 0;
  final words = foldedLine.split(' ');
  for (final (keyword, strength) in _totalKeywords) {
    final parts = keyword.split(' ');
    final matches = parts.length > 1
        ? foldedLine.contains(keyword)
        : words.any((word) =>
            word == keyword ||
            (keyword.length >= 6 &&
                editDistance(word, keyword, maxDistance: 2) <= 2) ||
            word.startsWith(keyword));
    if (matches && strength > best) best = strength;
  }
  // Gyakori szövegfelismerési hibák: „0SSZESEN”, „OSSZESEN:”.
  if (best == 0 && foldedLine.replaceAll('0', 'o').contains('osszesen')) {
    best = 8;
  }
  return best;
}

/// A sor (utolsó) összege, a mennyiségeket és egységárakat kihagyva.
int? _lineAmount(
  String line, {
  required bool excludeQuantities,
  bool needsCurrency = false,
}) {
  final tokens = tokenize(line);
  final words = [for (final token in tokens) token.folded];
  final dateMatch = findDate(line, tokens, CalendarDay(2100, 1, 1));
  final candidates = findAmountCandidates(
    words,
    blocked: {...?dateMatch?.tokenIndexes},
  );
  if (candidates.isEmpty) return null;
  final filtered = needsCurrency
      ? candidates.where((candidate) => candidate.score >= 6).toList()
      : candidates;
  if (filtered.isEmpty) return null;
  // A sor végén álló összeg a végösszeg („ÖSSZESEN 2 db 12 450”).
  filtered.sort(
    (a, b) => a.tokenIndexes.reduce((x, y) => x > y ? x : y).compareTo(
      b.tokenIndexes.reduce((x, y) => x > y ? x : y),
    ),
  );
  final value = filtered.last.value;
  return value > 0 && value < 100000000 ? value : null;
}

String? _sellerLine(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final folded = foldForMatching(lines[i]);
    for (final label in ['elado', 'szallito', 'kibocsato', 'szolgaltato']) {
      if (folded.startsWith(label)) {
        final rest = lines[i]
            .replaceFirst(RegExp(r'^[^:]*:\s*'), '')
            .trim();
        if (rest.isNotEmpty && rest != lines[i]) return rest;
        if (i + 1 < lines.length) return lines[i + 1];
      }
    }
  }
  return null;
}

String _firstNameLine(List<String> lines) {
  for (final line in lines.take(6)) {
    final letters = line.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]'), '');
    if (letters.length >= 3 && !RegExp(r'^\d').hasMatch(line)) return line;
  }
  return lines.first;
}

/// Cégforma és címrészek nélküli név („LIDL Magyarország Bt.” → „Lidl
/// Magyarország”).
String _cleanCompanyName(String raw) {
  var name = raw
      .replaceAll(
        RegExp(
          r'\b(kft|zrt|nyrt|bt|kkt|rt|ev|e\.v|kft\.|zrt\.|bt\.)\b\.?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\d{4}\s+\S.*$'), '')
      .replaceAll(RegExp(r'[,;:]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (name.isEmpty) name = raw.trim();
  // CSUPA NAGYBETŰ → Első betű nagy.
  if (name == name.toUpperCase() && name.length > 3) {
    name = name
        .toLowerCase()
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
  return name;
}

/// Blokkokon gyakori rövid dátum: „26.11.17” (év.hó.nap két jeggyel).
CalendarDay? _receiptShortDate(List<String> lines, CalendarDay today) {
  for (final line in lines) {
    final match = RegExp(
      r'(?<!\d)(\d{2})\.(\d{2})\.(\d{2})(?!\d)',
    ).firstMatch(line);
    if (match == null) continue;
    final year = 2000 + int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= YearMonth(year, month).daysInMonth &&
        (year - today.year).abs() <= 1) {
      return CalendarDay(year, month, day);
    }
  }
  return null;
}
