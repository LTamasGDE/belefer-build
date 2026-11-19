import 'calendar.dart';
import 'formatting.dart';
import 'models.dart';

/// Az ismétlődés gyakorisága.
enum Frequency {
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const Frequency(this.storageKey);

  final String storageKey;

  static Frequency fromStorage(Object? value) {
    for (final frequency in Frequency.values) {
      if (frequency.storageKey == value) return frequency;
    }
    return Frequency.monthly;
  }
}

/// Összegváltozás egy adott naptól (pl. költözés után új lakbér).
class AmountChange {
  const AmountChange({required this.from, required this.amount});

  factory AmountChange.fromMap(Map<String, Object?> map) => AmountChange(
    from: CalendarDay.parse(map['from']! as String),
    amount: (map['amount']! as num).toInt(),
  );

  final CalendarDay from;
  final int amount;

  Map<String, Object?> toMap() => {'from': from.toIso(), 'amount': amount};
}

/// Emlékeztető beállítása egy ismétlődő tételhez.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.daysBefore = 1,
    this.hour = 9,
    this.minute = 0,
    this.customText,
  });

  factory ReminderSettings.fromMap(Map<String, Object?>? map) {
    if (map == null) return const ReminderSettings();
    final text = map['text'];
    return ReminderSettings(
      enabled: map['enabled'] == true,
      daysBefore: (map['daysBefore'] as num?)?.toInt() ?? 1,
      hour: (map['hour'] as num?)?.toInt() ?? 9,
      minute: (map['minute'] as num?)?.toInt() ?? 0,
      customText: text is String && text.trim().isNotEmpty ? text : null,
    );
  }

  final bool enabled;

  /// Ennyi nappal az esedékesség előtt (0 = aznap).
  final int daysBefore;
  final int hour;
  final int minute;

  /// Egyéni szöveg; helyőrzők: {név}, {összeg}, {dátum}, {mikor}.
  final String? customText;

  ReminderSettings copyWith({
    bool? enabled,
    int? daysBefore,
    int? hour,
    int? minute,
    String? customText,
    bool clearCustomText = false,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    daysBefore: daysBefore ?? this.daysBefore,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    customText: clearCustomText ? null : (customText ?? this.customText),
  );

  Map<String, Object?> toMap() => {
    'enabled': enabled,
    'daysBefore': daysBefore,
    'hour': hour,
    'minute': minute,
    'text': customText,
  };
}

/// Rendszeresen ismétlődő kiadás vagy bevétel (lakbér, fizetés, előfizetés).
class RecurringRule {
  const RecurringRule({
    this.id,
    required this.type,
    required this.title,
    required this.categoryId,
    required this.amount,
    this.note,
    this.frequency = Frequency.monthly,
    this.interval = 1,
    required this.startDate,
    this.endDate,
    this.autoBook = true,
    this.reminder = const ReminderSettings(),
    this.amountChanges = const [],
    this.handledThrough,
    this.accountId,
  }) : assert(amount > 0, 'Az összeg pozitív egész forint.'),
       assert(interval >= 1, 'Az ismétlődési köz legalább 1.');

  factory RecurringRule.fromMap(int id, Map<String, Object?> map) {
    final end = map['end'];
    final handled = map['handled'];
    final changes = map['changes'];
    final note = map['note'];
    final account = map['account'];
    return RecurringRule(
      id: id,
      type: EntryType.fromStorage(map['type']),
      title: map['title']! as String,
      categoryId: map['category']! as String,
      amount: (map['amount']! as num).toInt(),
      note: note is String && note.trim().isNotEmpty ? note : null,
      frequency: Frequency.fromStorage(map['frequency']),
      interval: (map['interval'] as num?)?.toInt() ?? 1,
      startDate: CalendarDay.parse(map['start']! as String),
      endDate: end is String ? CalendarDay.parse(end) : null,
      autoBook: map['autoBook'] != false,
      reminder: ReminderSettings.fromMap(
        (map['reminder'] as Map<Object?, Object?>?)?.cast<String, Object?>(),
      ),
      amountChanges: [
        if (changes is List)
          for (final change in changes)
            AmountChange.fromMap(
              (change as Map<Object?, Object?>).cast<String, Object?>(),
            ),
      ],
      handledThrough: handled is String ? CalendarDay.parse(handled) : null,
      accountId: account is num ? account.toInt() : null,
    );
  }

  final int? id;
  final EntryType type;
  final String title;
  final String categoryId;

  /// Az induló összeg; a későbbi változásokat [amountChanges] tartalmazza.
  final int amount;
  final String? note;
  final Frequency frequency;

  /// Ennyi egységenként ismétlődik (pl. 2 = kéthetente / kéthavonta).
  final int interval;

  /// Az első esedékesség napja; a havi ismétlődés ennek a napján történik.
  final CalendarDay startDate;

  /// Az utolsó lehetséges nap (lemondás, lejárat); `null` = nincs vége.
  final CalendarDay? endDate;

  /// Esedékességkor magától rögzíti a tételt; különben jóváhagyásra vár.
  final bool autoBook;
  final ReminderSettings reminder;
  final List<AmountChange> amountChanges;

  /// Az utolsó elkönyvelt vagy kihagyott esedékesség napja.
  final CalendarDay? handledThrough;

  /// A számla, amelyről (amelyre) a tétel megy, ha meg van adva.
  final int? accountId;

  /// Lemondva vagy lejárt a megadott napon.
  bool isEndedOn(CalendarDay day) =>
      endDate != null && endDate!.compareTo(day) < 0;

  RecurringRule copyWith({
    int? id,
    EntryType? type,
    String? title,
    String? categoryId,
    int? amount,
    String? note,
    bool clearNote = false,
    Frequency? frequency,
    int? interval,
    CalendarDay? startDate,
    CalendarDay? endDate,
    bool clearEndDate = false,
    bool? autoBook,
    ReminderSettings? reminder,
    List<AmountChange>? amountChanges,
    CalendarDay? handledThrough,
    bool clearHandledThrough = false,
    int? accountId,
    bool clearAccount = false,
  }) => RecurringRule(
    id: id ?? this.id,
    type: type ?? this.type,
    title: title ?? this.title,
    categoryId: categoryId ?? this.categoryId,
    amount: amount ?? this.amount,
    note: clearNote ? null : (note ?? this.note),
    frequency: frequency ?? this.frequency,
    interval: interval ?? this.interval,
    startDate: startDate ?? this.startDate,
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
    autoBook: autoBook ?? this.autoBook,
    reminder: reminder ?? this.reminder,
    amountChanges: amountChanges ?? this.amountChanges,
    handledThrough: clearHandledThrough
        ? null
        : (handledThrough ?? this.handledThrough),
    accountId: clearAccount ? null : (accountId ?? this.accountId),
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type.storageKey,
    'title': title,
    'category': categoryId,
    'amount': amount,
    'note': note,
    'frequency': frequency.storageKey,
    'interval': interval,
    'start': startDate.toIso(),
    'end': endDate?.toIso(),
    'autoBook': autoBook,
    'reminder': reminder.toMap(),
    'changes': [for (final change in amountChanges) change.toMap()],
    'handled': handledThrough?.toIso(),
    'account': accountId,
  };

  /// Az összeg a megadott napon (a legutóbbi érvényes változás szerint).
  int amountOn(CalendarDay day) {
    var result = amount;
    CalendarDay? best;
    for (final change in amountChanges) {
      if (change.from.compareTo(day) <= 0 &&
          (best == null || change.from.compareTo(best) >= 0)) {
        best = change.from;
        result = change.amount;
      }
    }
    return result;
  }

  /// Az n-edik (0-tól számolt) esedékesség napja.
  CalendarDay occurrenceAt(int index) {
    switch (frequency) {
      case Frequency.weekly:
        return CalendarDay(
          startDate.year,
          startDate.month,
          startDate.day + 7 * interval * index,
        );
      case Frequency.monthly:
        final monthIndex = startDate.month - 1 + interval * index;
        final year = startDate.year + monthIndex ~/ 12;
        final month = monthIndex % 12 + 1;
        final days = YearMonth(year, month).daysInMonth;
        final day = startDate.day > days ? days : startDate.day;
        return CalendarDay(year, month, day);
      case Frequency.yearly:
        final year = startDate.year + interval * index;
        final days = YearMonth(year, startDate.month).daysInMonth;
        final day = startDate.day > days ? days : startDate.day;
        return CalendarDay(year, startDate.month, day);
    }
  }

  /// Esedékességek a [from]–[to] tartományban (mindkettő benne van).
  List<CalendarDay> occurrencesBetween(CalendarDay from, CalendarDay to) {
    final result = <CalendarDay>[];
    if (to.compareTo(from) < 0) return result;
    for (var index = 0; index < 5000; index++) {
      final day = occurrenceAt(index);
      if (day.compareTo(to) > 0) break;
      if (endDate != null && day.compareTo(endDate!) > 0) break;
      if (day.compareTo(from) >= 0) result.add(day);
    }
    return result;
  }

  /// A következő esedékesség a [day] napon vagy utána (vagy `null`, ha vége).
  CalendarDay? nextOccurrence(CalendarDay day) {
    for (var index = 0; index < 5000; index++) {
      final occurrence = occurrenceAt(index);
      if (endDate != null && occurrence.compareTo(endDate!) > 0) return null;
      if (occurrence.compareTo(day) >= 0) return occurrence;
    }
    return null;
  }

  /// Még nem kezelt esedékességek a mai napig.
  List<CalendarDay> dueOccurrences(CalendarDay today) {
    final from = handledThrough == null
        ? startDate
        : CalendarDay(
            handledThrough!.year,
            handledThrough!.month,
            handledThrough!.day + 1,
          );
    return occurrencesBetween(from, today);
  }

  /// A tétel, ami a [day] esedékességkor rögzítendő.
  Transaction transactionFor(CalendarDay day) => Transaction(
    type: type,
    title: title,
    amount: amountOn(day),
    categoryId: categoryId,
    date: day,
    note: note,
    recurringId: id,
    accountId: accountId,
  );

  /// Rövid, emberi leírás: „havonta 5-én”, „kéthetente”, „évente”.
  String describe() {
    final every = switch ((frequency, interval)) {
      (Frequency.weekly, 1) => 'hetente',
      (Frequency.weekly, 2) => 'kéthetente',
      (Frequency.weekly, 3) => 'háromhetente',
      (Frequency.weekly, 4) => 'négyhetente',
      (Frequency.weekly, _) => '$interval hetente',
      (Frequency.monthly, 1) => 'havonta',
      (Frequency.monthly, 2) => 'kéthavonta',
      (Frequency.monthly, 3) => 'negyedévente',
      (Frequency.monthly, 6) => 'félévente',
      (Frequency.monthly, _) => '$interval havonta',
      (Frequency.yearly, 1) => 'évente',
      (Frequency.yearly, 2) => 'kétévente',
      (Frequency.yearly, _) => '$interval évente',
    };
    return switch (frequency) {
      Frequency.weekly => '$every ${weekdayOn(startDate.weekday)}',
      Frequency.monthly => '$every ${dayWithSuffix(startDate.day)}',
      Frequency.yearly =>
        '$every ${monthName(startDate.month)} ${dayWithSuffix(startDate.day)}',
    };
  }
}

/// Az emlékeztetők általános beállításai: főkapcsoló és az új ismétlődő
/// tételek alapértelmezett emlékeztetője.
class ReminderDefaults {
  const ReminderDefaults({
    this.enabled = true,
    this.daysBefore = 1,
    this.hour = 9,
    this.minute = 0,
  });

  factory ReminderDefaults.fromMap(Map<String, Object?> map) =>
      ReminderDefaults(
        enabled: map['enabled'] != false,
        daysBefore: (map['daysBefore'] as num?)?.toInt() ?? 1,
        hour: (map['hour'] as num?)?.toInt() ?? 9,
        minute: (map['minute'] as num?)?.toInt() ?? 0,
      );

  /// Főkapcsoló: kikapcsolva egyetlen emlékeztető sem jelenik meg.
  final bool enabled;
  final int daysBefore;
  final int hour;
  final int minute;

  ReminderDefaults copyWith({
    bool? enabled,
    int? daysBefore,
    int? hour,
    int? minute,
  }) => ReminderDefaults(
    enabled: enabled ?? this.enabled,
    daysBefore: daysBefore ?? this.daysBefore,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
  );

  /// Egy új ismétlődő tétel emlékeztetője ezekkel az alapértékekkel.
  ReminderSettings newRuleSettings({required bool enabled}) => ReminderSettings(
    enabled: enabled,
    daysBefore: daysBefore,
    hour: hour,
    minute: minute,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'enabled': enabled,
    'daysBefore': daysBefore,
    'hour': hour,
    'minute': minute,
  };
}

/// Esedékes, még nem könyvelt tétel egy ismétlődő szabályból.
class PendingOccurrence {
  const PendingOccurrence({required this.rule, required this.date});

  final RecurringRule rule;
  final CalendarDay date;

  int get amount => rule.amountOn(date);
}

/// Egy ütemezendő emlékeztető.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.ruleId,
    required this.at,
    required this.occurrence,
    required this.title,
    required this.body,
  });

  /// Az értesítés azonosítója (szabályonként egyedi).
  final int id;
  final int ruleId;

  /// Helyi idő szerinti időpont.
  final DateTime at;
  final CalendarDay occurrence;
  final String title;
  final String body;
}

/// Az emlékeztető szövege a helyőrzők kitöltésével.
String reminderBody(
  RecurringRule rule,
  CalendarDay occurrence,
  CalendarDay today,
) {
  final amount = formatForint(rule.amountOn(occurrence));
  final date = '${monthName(occurrence.month)} ${occurrence.day}.';
  final daysLeft = DateTime.utc(
    occurrence.year,
    occurrence.month,
    occurrence.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final when = switch (daysLeft) {
    0 => 'ma',
    1 => 'holnap',
    2 => 'holnapután',
    _ => '$daysLeft nap múlva',
  };
  final template = rule.reminder.customText;
  if (template != null && template.trim().isNotEmpty) {
    return template
        .replaceAll('{név}', rule.title)
        .replaceAll('{nev}', rule.title)
        .replaceAll('{összeg}', amount)
        .replaceAll('{osszeg}', amount)
        .replaceAll('{dátum}', date)
        .replaceAll('{datum}', date)
        .replaceAll('{mikor}', when);
  }
  final verb = rule.type == EntryType.expense ? 'esedékes' : 'várható';
  final capitalized = when[0].toUpperCase() + when.substring(1);
  return '$capitalized $verb: ${rule.title} – $amount ($date)';
}

/// A következő [horizonDays] nap emlékeztetői, időrendben, legfeljebb [limit]
/// darab (iOS legfeljebb 64 függő értesítést enged).
List<PlannedReminder> planReminders(
  Iterable<RecurringRule> rules, {
  required DateTime now,
  required bool enabled,
  int horizonDays = 60,
  int limit = 60,
}) {
  if (!enabled) return const [];
  final today = CalendarDay.fromDateTime(now);
  final until = CalendarDay(today.year, today.month, today.day + horizonDays);
  final result = <PlannedReminder>[];
  for (final rule in rules) {
    final id = rule.id;
    if (id == null || !rule.reminder.enabled) continue;
    final daysBefore = rule.reminder.daysBefore;
    final occurrences = rule.occurrencesBetween(
      today,
      CalendarDay(until.year, until.month, until.day + daysBefore),
    );
    var index = 0;
    for (final occurrence in occurrences) {
      if (rule.handledThrough != null &&
          occurrence.compareTo(rule.handledThrough!) <= 0) {
        continue;
      }
      final remindDay = CalendarDay(
        occurrence.year,
        occurrence.month,
        occurrence.day - daysBefore,
      );
      final at = DateTime(
        remindDay.year,
        remindDay.month,
        remindDay.day,
        rule.reminder.hour,
        rule.reminder.minute,
      );
      if (!at.isAfter(now)) continue;
      result.add(
        PlannedReminder(
          id: id * 100 + (index % 100),
          ruleId: id,
          at: at,
          occurrence: occurrence,
          title: rule.type == EntryType.expense
              ? 'Esedékes kiadás'
              : 'Várható bevétel',
          body: reminderBody(rule, occurrence, remindDay),
        ),
      );
      index++;
    }
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result.length > limit ? result.sublist(0, limit) : result;
}
