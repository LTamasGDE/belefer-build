/// Szövegegyszerűsítés kereséshez és a gyorsrögzítés értelmezőjéhez.
library;

const Map<String, String> _accentMap = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'ő': 'o',
  'õ': 'o',
  'ỗ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ű': 'u',
  'ũ': 'u',
  'ç': 'c',
  'ñ': 'n',
  'ß': 'ss',
};

/// Kisbetűs, ékezet nélküli alak: „Tescóban” → „tescoban”.
String foldAccents(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accentMap[char] ?? char);
  }
  return buffer.toString();
}

/// Egyszerűsített alak: ékezet nélkül, a betűkön, számjegyeken és a
/// számokhoz tartozó írásjeleken kívül minden szóköz.
String foldForMatching(String input) {
  final folded = foldAccents(input);
  final buffer = StringBuffer();
  for (final unit in folded.codeUnits) {
    final isLetter = unit >= 97 && unit <= 122;
    final isDigit = unit >= 48 && unit <= 57;
    if (isLetter || isDigit || unit == 46 || unit == 44) {
      buffer.writeCharCode(unit);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Damerau–Levenshtein-távolság (szomszédos betűcserével), korláttal.
///
/// Ha a távolság biztosan nagyobb [maxDistance]-nél, `maxDistance + 1`-et ad.
int editDistance(String a, String b, {int maxDistance = 3}) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
  final n = a.length;
  final m = b.length;
  if (n == 0) return m;
  if (m == 0) return n;
  var previousPrevious = List<int>.filled(m + 1, 0);
  var previous = List<int>.generate(m + 1, (j) => j);
  var current = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    current[0] = i;
    var rowMin = current[0];
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var value = previous[j] + 1;
      final insert = current[j - 1] + 1;
      if (insert < value) value = insert;
      final substitute = previous[j - 1] + cost;
      if (substitute < value) value = substitute;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        final transpose = previousPrevious[j - 2] + 1;
        if (transpose < value) value = transpose;
      }
      current[j] = value;
      if (value < rowMin) rowMin = value;
    }
    if (rowMin > maxDistance) return maxDistance + 1;
    final recycled = previousPrevious;
    previousPrevious = previous;
    previous = current;
    current = recycled;
  }
  return previous[m];
}

/// Megengedett elírás a szó hossza alapján.
int allowedTypos(int length) {
  if (length <= 3) return 0;
  if (length <= 5) return 1;
  return 2;
}

/// Gyakori magyar toldalékok, a hosszabbak elöl.
const List<String> hungarianSuffixes = [
  'javal',
  'jevel',
  'eval',
  'aval',
  'ekkel',
  'akkal',
  'okkal',
  'jaert',
  'jeert',
  'eert',
  'aert',
  'jaba',
  'jebe',
  'jara',
  'jere',
  'jat',
  'jet',
  'ban',
  'ben',
  'bol',
  'rol',
  'tol',
  'nal',
  'nel',
  'hoz',
  'hez',
  'nak',
  'nek',
  'val',
  'vel',
  'ert',
  'kent',
  'ig',
  'ba',
  'be',
  'ra',
  're',
  'ot',
  'et',
  'at',
  'on',
  'en',
  'an',
  'ok',
  'ek',
  'ak',
  'os',
  'es',
  'as',
  'ja',
  'je',
  'om',
  'em',
  'am',
  'im',
  'i',
  't',
  'n',
];

/// A szó lehetséges tövei a toldalékok levágásával (a szó maga is benne van).
List<String> candidateStems(String word) {
  final stems = <String>[word];
  for (final suffix in hungarianSuffixes) {
    if (word.length - suffix.length >= 3 && word.endsWith(suffix)) {
      final stem = word.substring(0, word.length - suffix.length);
      if (!stems.contains(stem)) stems.add(stem);
    }
  }
  return stems;
}

final Set<String> _suffixSet = hungarianSuffixes.toSet();

bool _isSuffix(String rest) => rest.isEmpty || _suffixSet.contains(rest);

/// Illeszkedik-e a [word] (toldalékkal, elírással) a [key] kulcsszóra.
bool fuzzyWordMatch(String word, String key) {
  if (word.isEmpty || key.isEmpty) return false;
  if (word == key) return true;
  if (key.length >= 3 && word.startsWith(key)) {
    final rest = word.substring(key.length);
    if (_isSuffix(rest) || key.length >= 6) return true;
  }
  final allowed = allowedTypos(key.length);
  for (final stem in candidateStems(word)) {
    if (stem == key) return true;
    // Hárombetűs szó nem elírása egy hosszabb kulcsnak („ára” ≠ „Zara”).
    if (allowed > 0 &&
        stem.length >= 4 &&
        editDistance(stem, key, maxDistance: allowed) <= allowed) {
      return true;
    }
  }
  // Elírt szó toldalékkal: a kulcs hosszával egyező eleje, utána toldalék.
  if (allowed > 0 && word.length > key.length) {
    for (final cut in [key.length, key.length - 1, key.length + 1]) {
      if (cut < 3 || cut >= word.length) continue;
      final prefix = word.substring(0, cut);
      final rest = word.substring(cut);
      if (_isSuffix(rest) &&
          editDistance(prefix, key, maxDistance: allowed) <= allowed) {
        return true;
      }
    }
  }
  return false;
}
