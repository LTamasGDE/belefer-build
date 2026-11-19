import '../calendar.dart';
import '../categories.dart';
import '../model/belefer_model.dart';
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
  'sorszam',
  'datum',
  'azonosito',
  'penztar',
  'vonalkod',
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
  // Az „Összesen” utáni sorból jött, pénznem nélküli összeg gyenge jelölt.
  var totalIsWeak = false;
  for (var index = 0; index < lines.length; index++) {
    final foldedLine = foldForMatching(lines[index]);
    final strength = _keywordStrength(foldedLine);
    if (strength == 0 || strength < bestStrength) continue;
    // Az összeg a felirat után áll („ÖSSZESEN: 12 450”); az előtte lévő
    // számok a tételsor maradékai lehetnek („Dualshock 4 … Összesen:”).
    final (before, after) = _splitAtTotalKeyword(lines[index]);
    var amount = _lineAmount(after, excludeQuantities: false);
    var weak = false;
    if (amount == null && index + 1 < lines.length) {
      amount = _lineAmount(
        lines[index + 1],
        excludeQuantities: false,
        needsCurrency: true,
      );
      if (amount == null) {
        amount = _lineAmount(lines[index + 1], excludeQuantities: false);
        weak = amount != null;
      }
    }
    // Ferde fotón a jobb oldali összeg a felirat elé kerülhet egy sorral
    // („67999 Ft.” / „Összesen:”): pénznemmel jelölt összeg az előző sorból.
    if (amount == null && index > 0) {
      amount = _lineAmount(
        lines[index - 1],
        excludeQuantities: true,
        needsCurrency: true,
      );
    }
    if (amount == null && before.isNotEmpty) {
      amount = _lineAmount(
        before,
        excludeQuantities: true,
        needsCurrency: true,
      );
    }
    if (amount == null) continue;
    if (strength > bestStrength || (total != null && amount > total)) {
      total = amount;
      bestStrength = strength;
      totalIsWeak = weak;
    }
  }
  if (total == null) {
    // Nincs kulcsszó: a legnagyobb „Ft”-os összeg.
    for (final line in lines) {
      final foldedLine = foldForMatching(line);
      if (_excludedLineWords.any(foldedLine.contains)) continue;
      final amount = _lineAmount(
        line,
        excludeQuantities: true,
        needsCurrency: true,
      );
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

  // Valószerűtlenül kicsi (pl. egy tételsor „4”-ese) vagy gyenge forrásból
  // jött végösszeg (pl. egy cikkszám a következő sorban): ha van forinttal
  // jelölt összeg, és ez nincs köztük, inkább a legnagyobb forintos.
  if (total != null && (total < 50 || totalIsWeak)) {
    final current = total;
    int? largest;
    for (final line in lines) {
      final foldedLine = foldForMatching(line);
      if (_excludedLineWords.any(foldedLine.contains)) continue;
      final amount = _lineAmount(
        line,
        excludeQuantities: true,
        needsCurrency: true,
      );
      if (amount != null && (largest == null || amount > largest)) {
        largest = amount;
      }
    }
    if (largest != null && largest >= 50 && largest != current) {
      final currencyAmounts = <int>{};
      for (final line in lines) {
        final amount = _lineAmount(
          line,
          excludeQuantities: true,
          needsCurrency: true,
        );
        if (amount != null) currencyAmounts.add(amount);
      }
      if (current < 50 || !currencyAmounts.contains(current)) {
        total = largest;
        notes.add('A végösszeget a forintos összegekből vettem – ellenőrizd.');
      }
    }
  }

  // Dátum: dátumra utaló sor előnyben (kelte, teljesítés, dátum).
  CalendarDay? date;
  for (final line in lines) {
    final foldedLine = foldForMatching(line);
    // A blokkok rövid „ÉÉ.HH.NN” dátuma elsőbbséget kap („26.11.14”).
    final found =
        _receiptShortDate([line], context.today) ?? _writtenDate(line, context);
    if (found == null) continue;
    final strong =
        foldedLine.contains('kelt') ||
        foldedLine.contains('datum') ||
        foldedLine.contains('teljesites');
    if (date == null || strong) date = found;
    if (strong) break;
  }
  if (date != null && date.compareTo(context.today) > 0) date = context.today;

  // Kereskedő és kategória.
  String? merchant;
  String? categoryId;
  final sellerLine = _sellerLine(lines);
  final searchLines = [?sellerLine, ...lines.take(8), ...lines];
  outer:
  for (final rawLine in searchLines) {
    final line = _fixOcrLetters(rawLine);
    final words = tokenize(line).map((token) => token.folded).toList();
    for (final entry in merchants) {
      for (final key in entry.keys) {
        if (key.length <= 2) continue;
        final keyParts = key.split(' ');
        final hit = keyParts.length > 1
            ? foldForMatching(line).contains(key)
            : words.any(
                (word) =>
                    word == key ||
                    (key.length >= 4 &&
                        word.length >= 4 &&
                        !stopWords.contains(word) &&
                        // Négybetűs kulcsnál csak azonos hosszú elírás
                        // („lild” ≈ „lidl”), toldalék vagy betűkihagyás nem.
                        (key.length >= 5 || word.length == key.length) &&
                        fuzzyWordMatch(word, key)),
              );
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
      : (lines.isNotEmpty
            ? _cleanCompanyName(
                _nameAboveAddress(lines) ?? _firstNameLine(lines),
              )
            : null);

  // Kategória a tételsorokból, ha a kereskedőből nem derült ki.
  if (categoryId == null) {
    final scores = <String, int>{};
    for (final line in lines) {
      final words = tokenize(line).map((token) => token.folded).toList();
      for (final keyword in keywords) {
        final category = categoryById(keyword.categoryId);
        if (category == null || category.type != EntryType.expense) continue;
        if (keyword.key.contains(' ')) continue;
        if (words.any(
          (word) =>
              word == keyword.key ||
              (keyword.key.length >= 5 && fuzzyWordMatch(word, keyword.key)),
        )) {
          scores.update(
            keyword.categoryId,
            (value) => value + keyword.weight,
            ifAbsent: () => keyword.weight,
          );
        }
      }
    }
    if (scores.isNotEmpty) {
      categoryId =
          (scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    }
  }

  // A saját modell a tételsorokból (pl. „ALGOFLEX”, „95 BENZIN”).
  final model = currentModel;
  if (categoryId == null && model != null) {
    final prediction = model.classify('category', text).restrictedTo({
      for (final category in expenseCategories) category.id,
    });
    if (prediction.confidence >= 0.4) categoryId = prediction.best;
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
        : words.any(
            (word) =>
                word == keyword ||
                (keyword.length >= 6 &&
                    editDistance(word, keyword, maxDistance: 2) <= 2) ||
                word.startsWith(keyword),
          );
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
    (a, b) => a.tokenIndexes
        .reduce((x, y) => x > y ? x : y)
        .compareTo(b.tokenIndexes.reduce((x, y) => x > y ? x : y)),
  );
  final value = filtered.last.value;
  return value > 0 && value < 100000000 ? value : null;
}

String? _sellerLine(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final folded = foldForMatching(lines[i]);
    for (final label in ['elado', 'szallito', 'kibocsato', 'szolgaltato']) {
      if (folded.startsWith(label)) {
        final rest = lines[i].replaceFirst(RegExp(r'^[^:]*:\s*'), '').trim();
        if (rest.isNotEmpty && rest != lines[i]) return rest;
        if (i + 1 < lines.length) return lines[i + 1];
      }
    }
  }
  return null;
}

const List<String> _labelPrefixes = [
  'sorszam', 'datum', 'nyugta', 'blokk', 'szamla', 'adoszam', 'tel.', //
  'tel ', 'cim ', 'penztar', 'ap ', 'nav ', 'termek', 'idopont', 'azonosito',
];

final RegExp _streetWord = RegExp(
  r'\b(ut|utca|u\.|ter|krt|korut|fasor|rakpart|sor|koz|lakotelep)\b',
);

/// Névnek látszó sor: betűk, magánhangzó, nem felirat („Sorszám: …”).
bool _looksLikeName(String line) {
  final letters = line.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]'), '');
  if (letters.length < 3 || RegExp(r'^\d').hasMatch(line.trim())) return false;
  if (letters.length < line.replaceAll(' ', '').length * 0.5) return false;
  if (!RegExp('[aeiouáéíóöőúüűAEIOUÁÉÍÓÖŐÚÜŰ]').hasMatch(letters)) {
    return false;
  }
  final folded = foldForMatching(line);
  return !_labelPrefixes.any(folded.startsWith);
}

/// A bolt neve általában közvetlenül a cím fölött áll („Konzol Game” /
/// „Budapest XIX., Üllői út 214/3.”).
String? _nameAboveAddress(List<String> lines) {
  for (var index = 1; index < lines.length && index < 14; index++) {
    final folded = foldForMatching(lines[index]);
    if (!RegExp(r'\d').hasMatch(folded) || !_streetWord.hasMatch(folded)) {
      continue;
    }
    for (var above = index - 1; above >= 0 && above >= index - 3; above--) {
      if (_looksLikeName(lines[above])) return lines[above];
    }
    return null;
  }
  return null;
}

String _firstNameLine(List<String> lines) {
  for (final line in lines.take(8)) {
    if (_looksLikeName(line)) return line;
  }
  return lines.first;
}

/// A sor szövege a végösszeg felirata előtt és után.
(String, String) _splitAtTotalKeyword(String line) {
  for (final token in tokenize(line)) {
    final word = token.folded.replaceAll('0', 'o');
    final isKeyword = _totalKeywords.any((entry) {
      final keyword = entry.$1;
      if (keyword.contains(' ')) return false;
      return word == keyword ||
          word.startsWith(keyword) ||
          (keyword.length >= 6 &&
              editDistance(word, keyword, maxDistance: 2) <= 2);
    });
    if (isKeyword && token.end <= line.length) {
      return (line.substring(0, token.start), line.substring(token.end));
    }
  }
  return ('', line);
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
        .map(
          (word) =>
              word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }
  return name;
}

/// Számokkal leírt dátum. A blokkon a „vásárlás”, „hétfő” és hasonló szavak
/// nem dátumok, ezért csak a számjegyet is tartalmazó találat számít.
CalendarDay? _writtenDate(String line, QuickEntryContext context) {
  if (!RegExp(r'\d').hasMatch(line)) return null;
  final tokens = tokenize(line);
  final match = findDate(line, tokens, context.today);
  if (match == null || match.dayOfMonthOnly) return null;
  final hasDigit = match.tokenIndexes.any(
    (index) => RegExp(r'\d').hasMatch(tokens[index].folded),
  );
  return hasDigit ? match.day : null;
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

/// Betűk közé keveredett nulla javítása („TESC0” → „TESCO”) a nevek
/// felismeréséhez (az összegeknél nem használjuk).
String _fixOcrLetters(String line) => line.replaceAllMapped(
  RegExp(r'(?<=[A-Za-zÀ-ž])0|0(?=[A-Za-zÀ-ž]{2})'),
  (_) => 'O',
);
