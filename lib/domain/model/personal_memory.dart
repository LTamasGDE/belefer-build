import 'dart:math' as math;

import '../categories.dart';
import '../models.dart';
import 'features.dart';

/// A modell személyes része: a korábbi tételeidből tanul.
///
/// A megnevezéseket betűcsoportokra bontja, és egy új szöveghez a
/// leghasonlóbb korábbi megnevezések kategóriáját ajánlja. Így a saját
/// szóhasználatodat is megérti („Kisbolt a sarkon” → amit korábban adtál
/// neki), elírva és toldalékkal is.
class PersonalMemory {
  PersonalMemory._(this._entries);

  /// Felépítés a tételekből (a legutóbbi 400 különböző megnevezés).
  factory PersonalMemory.from(List<Transaction> history) {
    final recent = [...history]..sort((a, b) => b.date.compareTo(a.date));
    final seen = <String, _Entry>{};
    for (final transaction in recent) {
      if (seen.length >= 400) break;
      if (categoryById(transaction.categoryId) == null) continue;
      final words = modelWords(transaction.title);
      final key = words.join(' ');
      if (key.isEmpty || seen.containsKey(key)) continue;
      final buckets = _buckets(words);
      if (buckets.isEmpty) continue;
      seen[key] = _Entry(transaction.categoryId, transaction.title, buckets);
    }
    return PersonalMemory._(seen.values.toList());
  }

  final List<_Entry> _entries;

  static List<Transaction>? _cachedFor;
  static PersonalMemory? _cached;

  /// Gyorsítótárazva: amíg a tétellista ugyanaz, nem épül újra.
  static PersonalMemory of(List<Transaction> history) {
    if (!identical(history, _cachedFor) || _cached == null) {
      _cached = PersonalMemory.from(history);
      _cachedFor = history;
    }
    return _cached!;
  }

  bool get isEmpty => _entries.isEmpty;
  int get size => _entries.length;

  /// A leghasonlóbb korábbi tétel (hasonlóság 0–1), ha van elég hasonló.
  ({String categoryId, String title, double similarity})? recall(
    List<String> words, {
    double threshold = 0.5,
    Set<String>? allowedCategories,
  }) {
    final query = _buckets(words);
    if (query.isEmpty) return null;
    _Entry? best;
    var bestScore = threshold;
    for (final entry in _entries) {
      if (allowedCategories != null &&
          !allowedCategories.contains(entry.categoryId)) {
        continue;
      }
      // A korábbi megnevezés mennyire van benne az új szövegben.
      final shared = _intersection(query, entry.buckets);
      final score = shared / math.sqrt(entry.buckets.length * query.length);
      final containment = shared / entry.buckets.length;
      final combined = math.max(score, containment * 0.85);
      if (combined > bestScore) {
        bestScore = combined;
        best = entry;
      }
    }
    if (best == null) return null;
    return (
      categoryId: best.categoryId,
      title: best.title,
      similarity: bestScore,
    );
  }

  static List<int> _buckets(List<String> words) {
    final meaningful = [
      for (final word in words)
        if (word != '#' && word.length >= 2) word,
    ];
    final features = [
      for (final feature in sequenceFeatures(meaningful))
        if (feature.startsWith('c:')) feature,
    ];
    return vectorize(features, 20).buckets;
  }

  static int _intersection(List<int> a, List<int> b) {
    var i = 0;
    var j = 0;
    var count = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        count++;
        i++;
        j++;
      } else if (a[i] < b[j]) {
        i++;
      } else {
        j++;
      }
    }
    return count;
  }
}

class _Entry {
  _Entry(this.categoryId, this.title, this.buckets);

  final String categoryId;
  final String title;
  final List<int> buckets;
}
