/// Amit a Belefér kérdezés nélkül, a tételeidből tanul meg rólad.
///
/// - **Szokások:** megnevezésenként a szokásos kategória, összeg és számla
///   („kávé” → 950 Ft, „Lidl” → a Közös számla).
/// - **Ismétlődések:** a nem beállított, de rendszeresen visszatérő tételek
///   (fizetés minden hónap 10-én, Spotify havonta), és hogy mikor várható a
///   következő.
/// - **Leckék:** amit a gyorsrögzítésbe írtál, és ahogy végül elmentetted
///   („pötyi” → Pöttyös kisbolt, Élelmiszer); a javításaidból tanul.
///
/// Minden a telefonon marad, és a tételekből bármikor újraszámolható.
library;

import 'dart:math' as math;

import '../calendar.dart';
import '../categories.dart';
import '../formatting.dart';
import '../models.dart';
import '../recurring.dart';
import '../text_fold.dart';

/// Egy megnevezés szokásai.
class Habit {
  const Habit({
    required this.key,
    required this.title,
    required this.categoryId,
    required this.type,
    required this.count,
    required this.medianAmount,
    required this.usualAmount,
    required this.usualAccountId,
    required this.last,
  });

  /// Egyszerűsített megnevezés (kisbetű, ékezet nélkül).
  final String key;
  final String title;
  final String categoryId;
  final EntryType type;
  final int count;
  final int medianAmount;

  /// A szokásos összeg, ha elég állandó (különben `null`: pl. a Lidlben
  /// mindig mást költesz).
  final int? usualAmount;

  /// A szokásos számla, ha szinte mindig ugyanaz.
  final int? usualAccountId;
  final CalendarDay last;
}

/// Rendszeresen visszatérő tétel, amelyet nem állítottál be ismétlődőnek.
class DetectedPattern {
  const DetectedPattern({
    required this.key,
    required this.title,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.frequency,
    required this.interval,
    required this.dayOfMonth,
    required this.last,
    required this.next,
    required this.occurrences,
    this.accountId,
  });

  final String key;
  final String title;
  final String categoryId;
  final EntryType type;

  /// A legutóbbi összeg (a várható összeg).
  final int amount;
  final Frequency frequency;
  final int interval;

  /// Havi ismétlődésnél a szokásos nap.
  final int? dayOfMonth;
  final CalendarDay last;

  /// A következő várható alkalom.
  final CalendarDay next;
  final int occurrences;
  final int? accountId;

  /// Szöveges leírás: „minden hónap 10-én”, „hetente”, „kéthetente”.
  String get rhythm => switch (frequency) {
    Frequency.weekly => interval == 2 ? 'kéthetente' : 'hetente',
    Frequency.monthly =>
      dayOfMonth == null ? 'havonta' : 'minden hónap ${dayWithSuffix(dayOfMonth!)}',
    Frequency.yearly => 'évente',
  };

  /// Ismétlődő szabály ebből (az előrejelzéshez).
  RecurringRule toRule() => RecurringRule(
    type: type,
    title: title,
    categoryId: categoryId,
    amount: amount,
    frequency: frequency,
    interval: interval,
    startDate: next,
    accountId: accountId,
  );
}

/// Egy gyorsrögzítésből tanult kapcsolat: a beírt szavak és a végül
/// elmentett tétel.
class Lesson {
  const Lesson({
    required this.words,
    required this.title,
    required this.categoryId,
    required this.type,
    this.accountId,
    required this.day,
  });

  factory Lesson.fromMap(Map<String, Object?> map) => Lesson(
    words: [
      for (final word in (map['words'] as List? ?? const []))
        if (word is String) word,
    ],
    title: map['title']! as String,
    categoryId: map['category']! as String,
    type: EntryType.fromStorage(map['type']),
    accountId: map['account'] is num ? (map['account']! as num).toInt() : null,
    day: CalendarDay.parse(map['day']! as String),
  );

  /// A beírt szöveg jelentős szavai (szám, dátum, töltelékszó nélkül).
  final List<String> words;
  final String title;
  final String categoryId;
  final EntryType type;
  final int? accountId;
  final CalendarDay day;

  Map<String, Object?> toMap() => {
    'words': words,
    'title': title,
    'category': categoryId,
    'type': type.storageKey,
    'account': ?accountId,
    'day': day.toString(),
  };
}

/// Ennyi leckét őrzünk meg (a legutóbbiakat).
const int maxLessons = 300;

/// A gyorsrögzítésbe írt szöveg jelentős szavai a leckékhez.
List<String> lessonWords(String text) {
  final words = <String>[];
  for (final word in foldForMatching(text).split(' ')) {
    if (word.length < 2) continue;
    if (RegExp(r'\d').hasMatch(word)) continue;
    if (_fillerWords.contains(word)) continue;
    if (!words.contains(word)) words.add(word);
  }
  return words.take(6).toList();
}

/// Új lecke a meglévők elé; az azonos szavúakat felülírja.
List<Lesson> addLesson(List<Lesson> lessons, Lesson lesson) {
  if (lesson.words.isEmpty) return lessons;
  final key = lesson.words.join(' ');
  return [
    lesson,
    for (final old in lessons)
      if (old.words.join(' ') != key) old,
  ].take(maxLessons).toList();
}

const Set<String> _fillerWords = {
  'a', 'az', 'egy', 'es', 'meg', 'is', 'de', 'hogy', 'ft', 'huf', 'forint', //
  'forintot', 'forintert', 'ezer', 'ezret', 'ezerert', 'e', 'k', 'ma', 'mai', //
  'tegnap', 'tegnapi', 'tegnapelott', 'reggel', 'delben', 'delutan', 'este', //
  'ejjel', 'most', 'mar', 'vettem', 'fizettem', 'kifizettem', 'koltottem', //
  'elkoltottem', 'vasaroltam', 'rendeltem', 'kaptam', 'megkaptam', 'jott', //
  'megjott', 'ment', 'elment', 'volt', 'lett', 'nekem', 'hetfon', 'kedden', //
  'szerdan', 'csutortokon', 'penteken', 'szombaton', 'vasarnap', 'mult', //
  'heten', 'het', 'napja', 'hete', 'kb', 'korulbelul', 'kozel', 'osszesen',
};

/// A tanult tudás: szokások, ismétlődések, leckék.
class PersonalKnowledge {
  PersonalKnowledge._({
    required this.habits,
    required this.patterns,
    required this.lessons,
  });

  factory PersonalKnowledge.from(
    List<Transaction> history, {
    List<RecurringRule> rules = const [],
    List<Lesson> lessons = const [],
    required CalendarDay today,
  }) {
    final groups = <String, List<Transaction>>{};
    for (final transaction in history) {
      final key = foldForMatching(transaction.title);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(transaction);
    }
    final habits = <String, Habit>{};
    final patterns = <DetectedPattern>[];
    final ruleKeys = {for (final rule in rules) foldForMatching(rule.title)};
    for (final MapEntry(key: key, value: items) in groups.entries) {
      items.sort((a, b) => a.date.compareTo(b.date));
      final habit = _habit(key, items);
      if (habit != null) habits[key] = habit;
      if (!ruleKeys.contains(key)) {
        final pattern = _pattern(key, items, today);
        if (pattern != null) patterns.add(pattern);
      }
    }
    patterns.sort((a, b) => a.next.compareTo(b.next));
    return PersonalKnowledge._(
      habits: habits,
      patterns: patterns,
      lessons: lessons,
    );
  }

  /// Megnevezésenként (egyszerűsített kulccsal).
  final Map<String, Habit> habits;

  /// A felismert, nem beállított ismétlődések, a következő alkalom szerint.
  final List<DetectedPattern> patterns;
  final List<Lesson> lessons;

  static List<Transaction>? _cachedHistory;
  static String? _cachedRules;
  static List<Lesson>? _cachedLessons;
  static CalendarDay? _cachedToday;
  static PersonalKnowledge? _cached;

  /// Gyorsítótárazva, amíg a tételek, szabályok és leckék ugyanazok.
  static PersonalKnowledge of(
    List<Transaction> history, {
    List<RecurringRule> rules = const [],
    List<Lesson> lessons = const [],
    required CalendarDay today,
  }) {
    final rulesKey = rules.map((rule) => rule.title).join('|');
    if (_cached == null ||
        !identical(history, _cachedHistory) ||
        rulesKey != _cachedRules ||
        !identical(lessons, _cachedLessons) ||
        _cachedToday != today) {
      _cached = PersonalKnowledge.from(
        history,
        rules: rules,
        lessons: lessons,
        today: today,
      );
      _cachedHistory = history;
      _cachedRules = rulesKey;
      _cachedLessons = lessons;
      _cachedToday = today;
    }
    return _cached!;
  }

  /// Egy megnevezés szokásai.
  Habit? habitFor(String title) => habits[foldForMatching(title)];

  /// A beírt szavakhoz illő legutóbbi lecke: minden szava szerepel a
  /// szövegben (toldalékkal is). Visszaadja a felhasznált szavak indexeit.
  (Lesson, Set<int>)? lessonFor(List<String> words) {
    (Lesson, Set<int>)? best;
    for (final lesson in lessons) {
      if (lesson.words.isEmpty) continue;
      final used = <int>{};
      var ok = true;
      for (final word in lesson.words) {
        final index = _indexOfWord(words, word, used);
        if (index == null) {
          ok = false;
          break;
        }
        used.add(index);
      }
      if (!ok) continue;
      // A több szóból álló (konkrétabb) lecke nyer; egyenlőségnél a
      // legutóbbi (a lista eleje).
      if (best == null || lesson.words.length > best.$1.words.length) {
        best = (lesson, used);
      }
    }
    return best;
  }

  /// A felismert ismétlődés a megnevezés szavai alapján („fizetés”,
  /// „netflix”).
  DetectedPattern? patternMatching(List<String> words) {
    for (final pattern in patterns) {
      final parts = pattern.key.split(' ').where((p) => p.length >= 3);
      if (parts.isNotEmpty &&
          parts.every((part) => _indexOfWord(words, part, const {}) != null)) {
        return pattern;
      }
    }
    return null;
  }
}

int? _indexOfWord(List<String> words, String key, Set<int> skip) {
  for (var i = 0; i < words.length; i++) {
    if (skip.contains(i)) continue;
    final word = words[i];
    if (word == key) return i;
    if (key.length >= 3 && word.startsWith(key) && word.length - key.length <= 4) {
      return i;
    }
  }
  return null;
}

Habit? _habit(String key, List<Transaction> items) {
  if (items.isEmpty) return null;
  final recent = items.length > 12 ? items.sublist(items.length - 12) : items;
  final last = recent.last;
  // A leggyakoribb kategória (egyenlőségnél a legutóbbi).
  final categoryCounts = <String, int>{};
  for (final item in recent) {
    if (categoryById(item.categoryId) == null) continue;
    categoryCounts.update(item.categoryId, (v) => v + 1, ifAbsent: () => 1);
  }
  if (categoryCounts.isEmpty) return null;
  var categoryId = last.categoryId;
  if (!categoryCounts.containsKey(categoryId)) {
    categoryId = categoryCounts.keys.first;
  }
  for (final entry in categoryCounts.entries) {
    if (entry.value > categoryCounts[categoryId]!) categoryId = entry.key;
  }

  final amounts = [for (final item in recent) item.amount]..sort();
  final median = amounts[amounts.length ~/ 2];
  int? usual;
  if (recent.length >= 2) {
    final counts = <int, int>{};
    for (final item in recent) {
      counts.update(item.amount, (v) => v + 1, ifAbsent: () => 1);
    }
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final spread = (amounts.last - amounts.first) / math.max(1, median);
    if (top.value >= 2 && top.value * 2 >= recent.length) {
      usual = top.key;
    } else if (recent.length >= 3 && spread <= 0.12) {
      usual = (median / 10).round() * 10;
    }
  }

  int? account;
  final withAccount = [
    for (final item in recent)
      if (item.accountId != null) item.accountId!,
  ];
  if (withAccount.length >= 3) {
    final counts = <int, int>{};
    for (final id in withAccount) {
      counts.update(id, (v) => v + 1, ifAbsent: () => 1);
    }
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value >= withAccount.length * 0.75) account = top.key;
  }

  return Habit(
    key: key,
    title: last.title,
    categoryId: categoryId,
    type: last.type,
    count: items.length,
    medianAmount: median,
    usualAmount: usual,
    usualAccountId: account,
    last: last.date,
  );
}

DetectedPattern? _pattern(
  String key,
  List<Transaction> items,
  CalendarDay today,
) {
  // Naponként egy alkalom; a legutóbbi 8.
  final byDay = <CalendarDay, Transaction>{};
  for (final item in items) {
    byDay[item.date] = item;
  }
  final days = byDay.keys.toList()..sort();
  if (days.length < 3) return null;
  final recentDays = days.length > 8 ? days.sublist(days.length - 8) : days;
  final gaps = [
    for (var i = 1; i < recentDays.length; i++)
      _daysBetween(recentDays[i - 1], recentDays[i]),
  ];
  Frequency? frequency;
  var interval = 1;
  bool all(int low, int high) => gaps.every((g) => g >= low && g <= high);
  if (all(25, 36)) {
    frequency = Frequency.monthly;
  } else if (all(6, 8)) {
    frequency = Frequency.weekly;
  } else if (all(13, 16)) {
    frequency = Frequency.weekly;
    interval = 2;
  } else if (all(55, 66)) {
    frequency = Frequency.monthly;
    interval = 2;
  } else if (all(85, 97)) {
    frequency = Frequency.monthly;
    interval = 3;
  }
  if (frequency == null) return null;

  final transactions = [for (final day in recentDays) byDay[day]!];
  final amounts = [for (final t in transactions) t.amount]..sort();
  final median = amounts[amounts.length ~/ 2];
  // Állandó összeg (±25%) – a változó bevásárlás nem ismétlődés.
  if (amounts.any((a) => (a - median).abs() > median * 0.25)) return null;

  final last = recentDays.last;
  int? dayOfMonth;
  CalendarDay next;
  if (frequency == Frequency.monthly) {
    final daysOfMonth = [for (final day in recentDays) day.day]..sort();
    dayOfMonth = daysOfMonth[daysOfMonth.length ~/ 2];
    var month = YearMonth.of(last);
    for (var k = 0; k < interval; k++) {
      month = month.next;
    }
    next = CalendarDay(
      month.year,
      month.month,
      math.min(dayOfMonth, month.daysInMonth),
    );
  } else {
    next = CalendarDay(last.year, last.month, last.day + 7 * interval);
  }
  // Régen abbamaradt: a várható alkalom óta eltelt egy teljes kör.
  final period = frequency == Frequency.monthly ? 30 * interval : 7 * interval;
  if (_daysBetween(next, today) > period ~/ 2) return null;

  final latest = transactions.last;
  return DetectedPattern(
    key: key,
    title: latest.title,
    categoryId: latest.categoryId,
    type: latest.type,
    amount: latest.amount,
    frequency: frequency,
    interval: interval,
    dayOfMonth: dayOfMonth,
    last: last,
    next: next,
    occurrences: days.length,
    accountId: latest.accountId,
  );
}

int _daysBetween(CalendarDay a, CalendarDay b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
