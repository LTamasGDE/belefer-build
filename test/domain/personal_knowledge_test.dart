import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/insights.dart';
import 'package:belefer/domain/model/personal_knowledge.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(
  String title,
  int amount,
  String category,
  CalendarDay day, {
  EntryType type = EntryType.expense,
  int? account,
}) => Transaction(
  type: type,
  title: title,
  amount: amount,
  categoryId: category,
  date: day,
  accountId: account,
);

const _accounts = [
  Account(id: 1, name: 'Saját', matchers: ['revolut'], isDefault: true),
  Account(id: 2, name: 'Megtakarítás', kind: AccountKind.savings),
  Account(id: 3, name: 'Közös', kind: AccountKind.shared),
];

void main() {
  final today = CalendarDay(2026, 11, 20);
  final history = <Transaction>[
    for (final m in [7, 8, 9, 10, 11])
      _t(
        'Fizetés',
        450000,
        'salary',
        CalendarDay(2026, m, 10),
        type: EntryType.income,
        account: 1,
      ),
    for (final m in [8, 9, 10, 11])
      _t('Spotify', 1990, 'subscriptions', CalendarDay(2026, m, 3), account: 1),
    for (var d = 1; d <= 19; d += 3)
      _t('Kávé', 950, 'dining', CalendarDay(2026, 11, d), account: 1),
    for (var d = 2; d <= 20; d += 6)
      _t(
        'Lidl',
        4000 + d * 300,
        'groceries',
        CalendarDay(2026, 11, d),
        account: 3,
      ),
    for (var d = 2; d <= 28; d += 9)
      _t(
        'Lidl',
        5000 + d * 100,
        'groceries',
        CalendarDay(2026, 10, d),
        account: 3,
      ),
    for (var d = 4; d <= 28; d += 8)
      _t(
        'Lidl',
        5200 + d * 100,
        'groceries',
        CalendarDay(2026, 9, d),
        account: 3,
      ),
  ];
  final context = QuickEntryContext(
    today: today,
    history: history,
    accounts: _accounts,
  );

  group('szokások és ismétlődések', () {
    test('szokásos összeg és számla', () {
      final knowledge = context.knowledge;
      expect(knowledge.habitFor('kávé')!.usualAmount, 950);
      expect(knowledge.habitFor('Lidl')!.usualAmount, isNull);
      expect(knowledge.habitFor('Lidl')!.usualAccountId, 3);
    });

    test('a fizetést és a Spotifyt ismétlődésként ismeri fel', () {
      final patterns = context.knowledge.patterns;
      final salary = patterns.firstWhere((p) => p.title == 'Fizetés');
      expect(salary.next, CalendarDay(2026, 12, 10));
      expect(salary.rhythm, 'minden hónap 10-én');
      final spotify = patterns.firstWhere((p) => p.title == 'Spotify');
      expect(spotify.next, CalendarDay(2026, 12, 3));
      expect(patterns.any((p) => p.title == 'Kávé'), isFalse);
    });

    test('abbamaradt ismétlődést nem vár', () {
      final old = [
        for (final m in [3, 4, 5])
          _t('Edzőterem', 15000, 'health', CalendarDay(2026, m, 1)),
      ];
      final knowledge = PersonalKnowledge.from(old, today: today);
      expect(knowledge.patterns, isEmpty);
    });
  });

  group('kérdezés nélkül', () {
    test('a szokásos összeget és számlát beírja tippként', () {
      final result = interpretQuickEntry('kávé', context);
      expect(result.amount, 950);
      expect(result.amountFromHabit, isTrue);
      expect(result.accountId, 1);
      expect(result.guessed, contains(QuickQuestion.amount));
      expect(result.isComplete, isTrue);
    });

    test('a Lidl a szokásos Közös számlára megy', () {
      final result = interpretQuickEntry('Lidl 6200', context);
      expect(result.amount, 6200);
      expect(result.accountId, 3);
      expect(result.accountFromHabit, isTrue);
    });

    test('a szövegben megnevezett számla erősebb a szokásnál', () {
      final result = interpretQuickEntry('Lidl 6200 a sajátról', context);
      expect(result.accountId, 1);
      expect(result.accountFromHabit, isFalse);
    });
  });

  group('leckék', () {
    test('a saját szavaidat a javításod szerint érti', () {
      final lesson = Lesson(
        words: lessonWords('pötyi 1200'),
        title: 'Pöttyös kisbolt',
        categoryId: 'groceries',
        type: EntryType.expense,
        accountId: 3,
        day: today,
      );
      final withLesson = QuickEntryContext(
        today: today,
        history: history,
        accounts: _accounts,
        lessons: [lesson],
      );
      final result = interpretQuickEntry('pötyiben 1500', withLesson);
      expect(result.title, 'Pöttyös kisbolt');
      expect(result.categoryId, 'groceries');
      expect(result.accountId, 3);
    });

    test('új lecke felülírja a régit, és van felső korlát', () {
      var lessons = <Lesson>[];
      for (var i = 0; i < maxLessons + 20; i++) {
        lessons = addLesson(
          lessons,
          Lesson(
            words: ['szo$i'],
            title: 'T$i',
            categoryId: 'groceries',
            type: EntryType.expense,
            day: today,
          ),
        );
      }
      expect(lessons, hasLength(maxLessons));
      lessons = addLesson(
        lessons,
        Lesson(
          words: ['szo${maxLessons + 19}'],
          title: 'Új',
          categoryId: 'dining',
          type: EntryType.expense,
          day: today,
        ),
      );
      expect(lessons.first.title, 'Új');
      expect(
        lessons.where((l) => l.words.first == 'szo${maxLessons + 19}'),
        hasLength(1),
      );
      expect(Lesson.fromMap(lessons.first.toMap()).title, 'Új');
    });
  });

  group('mi van, mi lesz', () {
    String? answer(String text) => interpretQuickEntry(text, context).answer;

    test('mikor jön a fizetés', () {
      expect(answer('mikor jön a fizetés?'), contains('minden hónap 10-én'));
      expect(answer('mikor jön a fizetés?'), contains('dec. 10.'));
    });

    test('mi várható', () {
      expect(answer('mi várható a következő két hétben?'), contains('Spotify'));
    });

    test('hónap végére', () {
      expect(answer('mennyi marad a hónap végére?'), contains('várhatóan'));
    });

    test('szokásos ár', () {
      expect(answer('mennyibe kerül általában a kávé?'), contains('950'));
    });

    test('megállapítások a hónapról', () {
      final insights = buildInsights(
        transactions: history,
        rules: const [],
        knowledge: context.knowledge,
        today: today,
      );
      expect(insights.any((i) => i.kind == InsightKind.pace), isTrue);
    });
  });
}
