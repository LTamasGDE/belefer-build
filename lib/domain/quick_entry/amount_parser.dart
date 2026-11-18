/// Összegek felismerése magyar szövegben.
library;

/// Egy felismert összegjelölt.
class AmountCandidate {
  const AmountCandidate({
    required this.value,
    required this.score,
    required this.tokenIndexes,
  });

  final int value;

  /// Minél nagyobb, annál valószínűbb, hogy ez az összeg.
  final int score;

  /// A felhasznált (folded) tokenek indexei.
  final Set<int> tokenIndexes;
}

const Set<String> _currencyWords = {
  'ft',
  'huf',
  'forint',
  'forintot',
  'forintert',
  'forintba',
  'forintos',
  'forintnyi',
  'ftot',
  'ftert',
  'fttal',
  'ftos',
  'ftba',
  'ftbol',
  'forintbol',
  'forinttal',
};

const Set<String> _thousandWords = {
  'e',
  'k',
  'ezer',
  'ezres',
  'ezret',
  'ezerert',
  'ezerbe',
  'ezerba',
  'ezerbol',
  'ezerrel',
  'rugo',
  'rongy',
};

const Set<String> _millionWords = {
  'm',
  'mio',
  'millio',
  'milliot',
  'millioert',
  'millios',
  'milla',
  'mill',
};

const Set<String> _quantityUnits = {
  'db',
  'darab',
  'darabot',
  'kg',
  'kilo',
  'kilot',
  'g',
  'gramm',
  'dkg',
  'deka',
  'l',
  'liter',
  'litert',
  'dl',
  'ml',
  'cl',
  'csomag',
  'doboz',
  'uveg',
  'szelet',
  'adag',
  'x',
  'szem',
  'par',
  'ora',
  'orat',
  'orara',
  'perc',
  'percet',
  'nap',
  'napra',
  'napot',
  'het',
  'hetre',
  'honap',
  'honapra',
  'ev',
  'evre',
  'km',
  'fo',
  'fore',
  'szemely',
  'szemelyre',
  'alkalom',
  'alkalomra',
  'resz',
  'reszlet',
  'szazalek',
  'szazalekos',
};

/// Számhoz közvetlenül tapadó, „ért/ba/ot” jellegű toldalékok.
const Set<String> _amountSuffixes = {
  'ert',
  'ot',
  'et',
  'at',
  'ba',
  'be',
  'bol',
  'ra',
  're',
  'tal',
  'tel',
  'os',
  'es',
  'as',
  't',
};

const List<(String, double)> _numberMorphemes = [
  ('millio', -1000000),
  ('ezer', -1000),
  ('szaz', -100),
  ('kilencven', 90),
  ('nyolcvan', 80),
  ('hetven', 70),
  ('hatvan', 60),
  ('otven', 50),
  ('negyven', 40),
  ('harminc', 30),
  ('huszon', 20),
  ('husz', 20),
  ('tizen', 10),
  ('tiz', 10),
  ('masfel', 1.5),
  ('kilenc', 9),
  ('nyolc', 8),
  ('ketto', 2),
  ('harom', 3),
  ('negy', 4),
  ('egy', 1),
  ('ket', 2),
  ('het', 7),
  ('hat', 6),
  ('ot', 5),
];

/// Magyar számnév értéke („kétezer-ötszáz” → 2500), vagy `null`.
///
/// A kötőjeleket a hívó már szóközzé alakította; a szóközzel tagolt
/// alakokat összevonva kell átadni („ket ezer” → „ketezer”).
double? parseHungarianNumberWord(String word) {
  if (word.isEmpty) return null;
  final parts = <double>[];
  var rest = word;
  while (rest.isNotEmpty) {
    var matched = false;
    for (final (morpheme, value) in _numberMorphemes) {
      if (rest.startsWith(morpheme)) {
        parts.add(value);
        rest = rest.substring(morpheme.length);
        matched = true;
        break;
      }
    }
    if (!matched) return null;
  }
  double total = 0;
  double current = 0;
  for (final part in parts) {
    if (part == -100) {
      current = (current == 0 ? 1 : current) * 100;
    } else if (part == -1000) {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
    } else if (part == -1000000) {
      total = (total + (current == 0 ? 1 : current)) * 1000000;
      current = 0;
    } else {
      current += part;
    }
  }
  return total + current;
}

final RegExp _numberToken = RegExp(r'^(\d+(?:[.,]\d+)*)([a-z]*)$');
final RegExp _groupToken = RegExp(r'^(\d{3})([.,]\d{1,2})?([a-z]*)$');

/// A szám szöveges alakjának értéke (ezres tagolás és tizedes kezelése).
double? _numericValue(String text, {required bool hasMultiplier}) {
  // 12.450 vagy 1.234.567: ezres pont.
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(text)) {
    return hasMultiplier
        ? double.tryParse(text.replaceFirst('.', '').replaceAll('.', ''))
        : double.tryParse(text.replaceAll('.', ''));
  }
  // 12,450: forintnál ezres vessző, szorzóval tizedes (1,500 millió ritka).
  if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(text) && !hasMultiplier) {
    return double.tryParse(text.replaceAll(',', ''));
  }
  // 4500,00 / 2,5 / 1.5: tizedes.
  final decimal = RegExp(r'^(\d+)[.,](\d+)$').firstMatch(text);
  if (decimal != null) {
    return double.tryParse('${decimal.group(1)}.${decimal.group(2)}');
  }
  if (RegExp(r'^\d+$').hasMatch(text)) return double.tryParse(text);
  // Vegyes (1.234,50): pontok ezres, vessző tizedes.
  final mixed = RegExp(r'^(\d{1,3}(?:\.\d{3})+),(\d+)$').firstMatch(text);
  if (mixed != null) {
    return double.tryParse(
      '${mixed.group(1)!.replaceAll('.', '')}.${mixed.group(2)}',
    );
  }
  return null;
}

/// Összegjelöltek a [tokens] (folded) listában; a [blocked] indexek
/// (pl. dátum) kimaradnak.
List<AmountCandidate> findAmountCandidates(
  List<String> tokens, {
  Set<int> blocked = const {},
}) {
  final candidates = <AmountCandidate>[];
  var i = 0;
  while (i < tokens.length) {
    if (blocked.contains(i)) {
      i++;
      continue;
    }
    final token = tokens[i];
    final match = _numberToken.firstMatch(token);
    if (match != null) {
      var numberText = match.group(1)!;
      var letters = match.group(2)!;
      final used = <int>{i};
      var j = i + 1;
      // Szóközzel tagolt ezres csoportok: „12 450”, „1 234 567”.
      if (letters.isEmpty && RegExp(r'^\d{1,3}$').hasMatch(numberText)) {
        while (j < tokens.length && !blocked.contains(j)) {
          final group = _groupToken.firstMatch(tokens[j]);
          if (group == null) break;
          numberText += group.group(1)!;
          if (group.group(2) != null) numberText += group.group(2)!;
          letters = group.group(3)!;
          used.add(j);
          j++;
          if (letters.isNotEmpty || group.group(2) != null) break;
        }
      }
      var multiplier = 1.0;
      var hasCurrency = false;
      var isQuantity = false;
      String? suffix = letters.isEmpty ? null : letters;
      // A számhoz tapadó betűk: 12e, 2k, 4500ft, 4500ert, 3db.
      if (suffix != null) {
        if (_thousandWords.contains(suffix)) {
          multiplier = 1000;
        } else if (_millionWords.contains(suffix)) {
          multiplier = 1000000;
        } else if (_currencyWords.contains(suffix) ||
            _amountSuffixes.contains(suffix)) {
          hasCurrency = _currencyWords.contains(suffix) ||
              suffix == 'ert' ||
              suffix == 'ba' ||
              suffix == 'ot' ||
              suffix == 'et' ||
              suffix == 'at';
        } else if (_quantityUnits.contains(suffix)) {
          isQuantity = true;
        } else if (suffix.startsWith('ft') || suffix.startsWith('forint')) {
          hasCurrency = true;
        } else if (suffix.startsWith('ezer')) {
          multiplier = 1000;
        } else {
          // Ismeretlen tapadó szó (pl. „2026ban”, „3as”): nem összeg.
          isQuantity = true;
        }
      }
      // Következő szavak: szorzó, pénznem, mértékegység.
      if (j < tokens.length && !blocked.contains(j)) {
        final next = tokens[j];
        if (multiplier == 1 && _thousandWords.contains(next)) {
          multiplier = 1000;
          used.add(j);
          j++;
        } else if (multiplier == 1 && _millionWords.contains(next)) {
          multiplier = 1000000;
          used.add(j);
          j++;
        } else if (_quantityUnits.contains(next)) {
          isQuantity = true;
        }
      }
      if (j < tokens.length && !blocked.contains(j)) {
        final next = tokens[j];
        if (_currencyWords.contains(next) ||
            next.startsWith('forint') ||
            (next.startsWith('ft') && next.length <= 5)) {
          hasCurrency = true;
          used.add(j);
          j++;
          // „Ft-ért”, „Ft-ot”: a kötőjel után külön toldalék.
          if (j < tokens.length && _amountSuffixes.contains(tokens[j])) {
            used.add(j);
            j++;
          }
        } else if (next == 'ert' || next == 'ba' || next == 'ot') {
          hasCurrency = true;
          used.add(j);
          j++;
        }
      }
      // Pénznem a szám előtt: „HUF 4500”, „Ft 4500”.
      if (!hasCurrency && i > 0 && _currencyWords.contains(tokens[i - 1])) {
        hasCurrency = true;
        used.add(i - 1);
      }
      final base = _numericValue(numberText, hasMultiplier: multiplier != 1);
      if (base != null && !isQuantity) {
        final value = (base * multiplier).round();
        if (value > 0) {
          var score = 0;
          if (hasCurrency) score += 6;
          if (multiplier != 1) score += 4;
          if (value >= 100) score += 2;
          if (value >= 10) score += 1;
          candidates.add(
            AmountCandidate(value: value, score: score, tokenIndexes: used),
          );
        }
      }
      i = j > i ? j : i + 1;
      continue;
    }

    // Számnevek: „kétezer”, „ötszáz forint”, „másfél millió”, „öt ezer”.
    final wordValue = _readNumberWords(tokens, i, blocked);
    if (wordValue != null) {
      final (value, used, end) = wordValue;
      var hasCurrency = false;
      var j = end;
      if (j < tokens.length &&
          (_currencyWords.contains(tokens[j]) ||
              tokens[j].startsWith('forint'))) {
        hasCurrency = true;
        used.add(j);
        j++;
      }
      // Kis számnév (pl. „egy”, „hat”) csak pénznemmel együtt összeg.
      if (value >= 100 || hasCurrency) {
        final rounded = value.round();
        if (rounded > 0) {
          candidates.add(
            AmountCandidate(
              value: rounded,
              score: (hasCurrency ? 6 : 0) + (rounded >= 100 ? 3 : 0),
              tokenIndexes: used,
            ),
          );
        }
        i = j;
        continue;
      }
    }
    i++;
  }
  return candidates;
}

/// Egymás utáni számnév-tokenek összeolvasása. Visszaad: (érték,
/// felhasznált indexek, következő index).
(double, Set<int>, int)? _readNumberWords(
  List<String> tokens,
  int start,
  Set<int> blocked,
) {
  var end = start;
  while (end < tokens.length && end < start + 5 && !blocked.contains(end)) {
    final token = tokens[end];
    if (token.isEmpty || RegExp(r'\d').hasMatch(token)) break;
    if (parseHungarianNumberWord(_stripNumberSuffix(token)) == null) break;
    end++;
  }
  if (end == start) return null;
  final combined = _stripNumberSuffix(tokens.sublist(start, end).join());
  final value = parseHungarianNumberWord(combined);
  if (value == null) return null;
  return (value, {for (var k = start; k < end; k++) k}, end);
}

String _stripNumberSuffix(String word) {
  if (parseHungarianNumberWord(word) != null) return word;
  for (final suffix in ['ert', 'at', 'et', 'ot', 'ba', 'be', 'bol', 'rol']) {
    if (word.length > suffix.length + 2 && word.endsWith(suffix)) {
      final stem = word.substring(0, word.length - suffix.length);
      if (parseHungarianNumberWord(stem) != null) return stem;
    }
  }
  return word;
}

/// A legvalószínűbb összeg a jelöltek közül (vagy `null`).
AmountCandidate? pickAmount(List<AmountCandidate> candidates) {
  if (candidates.isEmpty) return null;
  final sorted = [...candidates]
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.value.compareTo(a.value);
    });
  return sorted.first;
}
