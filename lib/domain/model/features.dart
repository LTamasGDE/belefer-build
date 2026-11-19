/// A Belefér-modell jellemzői.
///
/// A `tool/model/textproc.py` pontos mása: ugyanaz a szavakra bontás,
/// ugyanazok a jellemzők és ugyanaz a hash. Ha az egyik változik, a másiknak
/// is változnia kell (a `test/fixtures/model_golden.json` ezt ellenőrzi).
library;

import 'dart:math' as math;

import '../quick_entry/tokens.dart';

final RegExp _number = RegExp(r'^\d+(?:[.,]\d+)*([a-z]*)$');
final RegExp _digitStart = RegExp(r'^\d');

/// Szavak: a számok helyén `#`, a számhoz tapadt betűk külön szóként.
List<String> modelWords(String text) {
  final result = <String>[];
  for (final token in tokenize(text)) {
    final match = _number.firstMatch(token.folded);
    if (match != null) {
      result.add('#');
      final rest = match.group(1)!;
      if (rest.isNotEmpty) result.add(rest);
    } else {
      result.add(token.folded);
    }
  }
  return result;
}

/// A szöveg egészét leíró jellemzők: szavak, szópárok, betűcsoportok.
List<String> sequenceFeatures(List<String> words) {
  final features = <String>[];
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    features.add('w:$word');
    if (i + 1 < words.length) features.add('b:${word}_${words[i + 1]}');
    if (word != '#' && word.length >= 3) {
      final padded = '<$word>';
      for (final n in const [3, 4, 5]) {
        for (var j = 0; j + n <= padded.length; j++) {
          features.add('c:${padded.substring(j, j + n)}');
        }
      }
    }
  }
  return features;
}

/// Egy szó jellemzői a megnevezés-jelölőhöz (a környezetével együtt).
List<String> tokenFeatures(
  List<String> tokens,
  int i,
  Map<String, Set<String>> flags,
) {
  String norm(String token) => _digitStart.hasMatch(token) ? '#' : token;
  final word = norm(tokens[i]);
  final prev1 = i > 0 ? norm(tokens[i - 1]) : '^';
  final prev2 = i > 1 ? norm(tokens[i - 2]) : '^';
  final next1 = i + 1 < tokens.length ? norm(tokens[i + 1]) : r'$';
  final next2 = i + 2 < tokens.length ? norm(tokens[i + 2]) : r'$';
  final features = <String>[
    't:$word',
    'p1:$prev1',
    'p2:$prev2',
    'n1:$next1',
    'n2:$next2',
    'pw:${prev1}_$word',
    'wn:${word}_$next1',
    'len:${math.min(word.length, 9)}',
  ];
  if (word != '#') {
    features
      ..add('s2:${_tail(word, 2)}')
      ..add('s3:${_tail(word, 3)}')
      ..add('s4:${_tail(word, 4)}')
      ..add('f3:${word.substring(0, math.min(3, word.length))}');
  }
  if (i == 0) features.add('first');
  if (i == tokens.length - 1) features.add('last');
  for (final entry in flags.entries) {
    final members = entry.value;
    if (members.contains(word)) features.add('in:${entry.key}');
    if (members.contains(prev1)) features.add('pin:${entry.key}');
    if (members.contains(next1)) features.add('nin:${entry.key}');
  }
  return features;
}

String _tail(String word, int n) =>
    word.length <= n ? word : word.substring(word.length - n);

/// FNV-1a (32 bites) hash.
int fnv1a(String text) {
  var hash = 0x811C9DC5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// A jellemzők egyedi, rendezett hash-indexei és az egyenletes súly (1/√n).
({List<int> buckets, double weight}) vectorize(
  Iterable<String> features,
  int dimBits,
) {
  final mask = (1 << dimBits) - 1;
  final buckets = {
    for (final feature in features) fnv1a(feature) & mask,
  }.toList()..sort();
  return (
    buckets: buckets,
    weight: buckets.isEmpty ? 0.0 : 1 / math.sqrt(buckets.length),
  );
}
