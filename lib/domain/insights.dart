/// „Mi van, mi lesz”: rövid megállapítások a hónapról a tételekből és a
/// tanult szokásokból – kérdezés nélkül.
library;

import 'calendar.dart';
import 'categories.dart';
import 'formatting.dart';
import 'model/personal_knowledge.dart';
import 'models.dart';
import 'recurring.dart';
import 'text_fold.dart';

enum InsightKind {
  /// Az eddigi költés üteme a szokásoshoz képest.
  pace,

  /// Egy kategória a szokásosnál többet visz.
  unusual,

  /// Ami a következő napokban várható.
  upcoming,
}

class Insight {
  const Insight(this.kind, this.text);

  final InsightKind kind;
  final String text;
}

/// A hónap megállapításai (az aktuális hónapra).
List<Insight> buildInsights({
  required List<Transaction> transactions,
  required List<RecurringRule> rules,
  required PersonalKnowledge knowledge,
  required CalendarDay today,
}) {
  final insights = <Insight>[];
  final month = YearMonth.of(today);
  final previous = [
    month.previous,
    month.previous.previous,
    month.previous.previous.previous,
  ];

  // Az eddigi költés a hónap ugyanazon napjáig, az előző hónapok átlagához.
  var spentSoFar = 0;
  final byCategoryNow = <String, int>{};
  for (final t in transactions) {
    if (t.type != EntryType.expense || !month.contains(t.date)) continue;
    if (t.date.compareTo(today) > 0) continue;
    spentSoFar += t.amount;
    byCategoryNow.update(t.categoryId, (v) => v + t.amount, ifAbsent: () => t.amount);
  }
  var usualSoFar = 0;
  var monthsWithData = 0;
  final byCategoryUsual = <String, int>{};
  for (final m in previous) {
    final hasData = transactions.any((t) => m.contains(t.date));
    if (!hasData) continue;
    monthsWithData++;
    final cutoff = today.day.clamp(1, m.daysInMonth);
    for (final t in transactions) {
      if (t.type != EntryType.expense || !m.contains(t.date)) continue;
      if (t.date.day <= cutoff) usualSoFar += t.amount;
      byCategoryUsual.update(
        t.categoryId,
        (v) => v + t.amount,
        ifAbsent: () => t.amount,
      );
    }
  }
  if (monthsWithData >= 2 && usualSoFar > 0) {
    final usual = (usualSoFar / monthsWithData).round();
    final ratio = (spentSoFar - usual) / usual;
    final percent = (ratio.abs() * 100).round();
    if (percent >= 10) {
      insights.add(
        Insight(
          InsightKind.pace,
          'Ilyenkorra általában kb. ${formatForint(_round(usual))} szokott '
          'elmenni – most ${formatForint(spentSoFar)}, $percent%-kal '
          '${ratio > 0 ? 'több' : 'kevesebb'}.',
        ),
      );
    } else {
      insights.add(
        Insight(
          InsightKind.pace,
          'A költésed a szokásos ütemben halad: eddig '
          '${formatForint(spentSoFar)} (ilyenkorra általában kb. '
          '${formatForint(_round(usual))}).',
        ),
      );
    }

    // A szokásosnál jóval többet vivő kategória (a legnagyobb eltérés).
    String? topCategory;
    var topExcess = 0;
    for (final MapEntry(key: id, value: now) in byCategoryNow.entries) {
      final average = (byCategoryUsual[id] ?? 0) / monthsWithData;
      if (average < 3000) continue;
      final excess = now - average;
      if (now >= average * 1.4 && excess >= 5000 && excess > topExcess) {
        topExcess = excess.round();
        topCategory = id;
      }
    }
    if (topCategory != null) {
      final average = (byCategoryUsual[topCategory]! / monthsWithData).round();
      insights.add(
        Insight(
          InsightKind.unusual,
          '${categoryName(topCategory)}: eddig '
          '${formatForint(byCategoryNow[topCategory]!)}, ez több, mint a '
          'szokásos havi kb. ${formatForint(_round(average))}.',
        ),
      );
    }
  }

  // A következő hét várható tételei: beállított és felismert ismétlődések.
  final until = CalendarDay(today.year, today.month, today.day + 7);
  final upcoming = <(CalendarDay, String, int, bool)>[];
  final ruleKeys = <String>{};
  for (final rule in rules) {
    if (rule.isEndedOn(today)) continue;
    ruleKeys.add(foldForMatching(rule.title));
    final tomorrow = CalendarDay(today.year, today.month, today.day + 1);
    for (final date in rule.occurrencesBetween(tomorrow, until)) {
      upcoming.add((date, rule.title, rule.amountOn(date), false));
    }
  }
  for (final pattern in knowledge.patterns) {
    if (ruleKeys.contains(pattern.key)) continue;
    var date = pattern.next;
    if (date.compareTo(today) < 0) date = today;
    if (date.compareTo(until) > 0) continue;
    upcoming.add((date, pattern.title, pattern.amount, true));
  }
  upcoming.sort((a, b) => a.$1.compareTo(b.$1));
  if (upcoming.isNotEmpty) {
    final listed = upcoming
        .take(3)
        .map(
          (item) =>
              '${formatShortDate(item.$1, today)} ${item.$2} '
              '${item.$4 ? '~' : ''}${formatForint(item.$3)}',
        )
        .join(', ');
    final more = upcoming.length > 3 ? ' és még ${upcoming.length - 3}' : '';
    insights.add(
      Insight(InsightKind.upcoming, 'A következő 7 napban: $listed$more.'),
    );
  }
  return insights;
}

/// Kerekítés a becsült összegekhez (100 Ft-ra, nagyobbnál 1000-re).
int _round(int value) =>
    value >= 20000 ? (value / 1000).round() * 1000 : (value / 100).round() * 100;
