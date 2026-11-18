import '../text_fold.dart';

/// Egy szó a beírt szövegből, eredeti és egyszerűsített alakban.
class QuickToken {
  const QuickToken({
    required this.original,
    required this.folded,
    required this.start,
    required this.end,
  });

  /// Az eredeti alak (ékezettel, nagybetűvel).
  final String original;

  /// Kisbetűs, ékezet nélküli alak.
  final String folded;

  /// Helye az egyszerűsített szövegben.
  final int start;
  final int end;

  bool get isNumeric => RegExp(r'^\d').hasMatch(folded);
}

/// Azonos hosszúságú egyszerűsítés: kisbetű, ékezet nélkül, az írásjelek
/// megmaradnak (a dátumfelismeréshez).
String foldKeepingPunctuation(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    final folded = foldAccents(lower.isEmpty ? char : lower);
    // Egy karakter marad egy karakter (a „ß” → „s”), hogy a pozíciók egyezzenek.
    final single = folded.isEmpty ? ' ' : folded.substring(0, 1);
    if (char.length == 2) {
      buffer.write(single);
      buffer.write(' ');
    } else {
      buffer.write(single);
    }
  }
  return buffer.toString();
}

final RegExp _tokenPattern = RegExp(r'\d+(?:[.,]\d+)*[a-z]*|[a-z]+');

/// Szavakra bontás. A kötőjel elválaszt („Lidl-ben” → lidl, ben), a számok
/// tagolása egyben marad („12.450”, „4500,00”).
List<QuickToken> tokenize(String original) {
  final light = foldKeepingPunctuation(original);
  final tokens = <QuickToken>[];
  for (final match in _tokenPattern.allMatches(light)) {
    final start = match.start;
    final end = match.end;
    final surface = start < original.length && end <= original.length
        ? original.substring(start, end)
        : match.group(0)!;
    tokens.add(
      QuickToken(
        original: surface,
        folded: match.group(0)!,
        start: start,
        end: end,
      ),
    );
  }
  return tokens;
}

/// A szöveg egyszerűsített alakja, amin a tokenek pozíciói érvényesek.
String lightFold(String original) => foldKeepingPunctuation(original);

/// A [start]–[end] karaktertartománnyal átfedő tokenek indexei.
Set<int> tokensInRange(List<QuickToken> tokens, int start, int end) => {
  for (var i = 0; i < tokens.length; i++)
    if (tokens[i].start < end && tokens[i].end > start) i,
};
