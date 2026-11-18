import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/categories.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:belefer/services/platform_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Transaction;

import '../support/test_app.dart';

class _RecordingScheduler implements ReminderScheduler {
  List<PlannedReminder> last = const [];
  int permissionRequests = 0;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    last = reminders;
  }

  @override
  Future<void> showNow({required String title, required String body}) async {}
}

class _RecordingWidget implements WidgetPublisher {
  HomeWidgetData? last;

  @override
  Future<void> publish(HomeWidgetData data) async {
    last = data;
  }
}

RecurringRule _rent({
  CalendarDay? start,
  bool autoBook = true,
  ReminderSettings reminder = const ReminderSettings(),
}) => RecurringRule(
  type: EntryType.expense,
  title: 'Lakbér',
  categoryId: 'housing',
  amount: 180000,
  startDate: start ?? CalendarDay(2026, 11, 17),
  autoBook: autoBook,
  reminder: reminder,
);

void main() {
  test('a mai esedékesség azonnal rögzül, a múltbeliek nem', () async {
    final state = await openTestState();
    await state.saveRule(_rent(start: CalendarDay(2026, 8, 17)));
    expect(state.transactions, hasLength(1));
    expect(state.transactions.single.date, testToday);
    expect(state.transactions.single.recurringId, isNotNull);
  });

  test('kérésre a múltbeli esedékességek is rögzülnek', () async {
    final state = await openTestState();
    await state.saveRule(
      _rent(start: CalendarDay(2026, 8, 17)),
      bookPast: true,
    );
    expect(state.transactions, hasLength(4));
  });

  test('a jövőbeli ismétlődő tétel újranyitás után is megvan', () async {
    final factory = newDatabaseFactoryMemory();
    final first = await openTestState(factory: factory);
    await first.saveRule(_rent(start: CalendarDay(2026, 12, 1)));
    expect(first.transactions, isEmpty);
    await first.close();

    final reopened = await openTestState(factory: factory);
    expect(reopened.transactions, isEmpty);
    expect(reopened.rules.single.title, 'Lakbér');
  });

  test('jóváhagyásra váró tétel rögzítése és kihagyása', () async {
    final state = await openTestState();
    await state.saveRule(_rent(autoBook: false));
    expect(state.transactions, isEmpty);
    expect(state.pending, hasLength(1));

    await state.bookPending(state.pending.single, amount: 175000);
    expect(state.transactions.single.amount, 175000);
    expect(state.pending, isEmpty);

    await state.saveRule(
      _rent(autoBook: false).copyWith(title: 'Edzőterem', amount: 15000),
    );
    await state.skipPending(state.pending.single);
    expect(state.pending, isEmpty);
    expect(state.transactions, hasLength(1));
  });

  test('lemondás és összegváltozás', () async {
    final state = await openTestState();
    final rule = await state.saveRule(_rent(start: CalendarDay(2026, 12, 1)));
    await state.changeRuleAmount(
      rule,
      amount: 200000,
      from: CalendarDay(2027, 1, 1),
    );
    final changed = state.rules.single;
    expect(changed.amountOn(CalendarDay(2026, 12, 1)), 180000);
    expect(changed.amountOn(CalendarDay(2027, 1, 1)), 200000);

    await state.endRule(changed);
    expect(state.activeRules, isEmpty);
    expect(state.endedRules, hasLength(1));
  });

  test('emlékeztetők ütemezése a főkapcsolóval', () async {
    final scheduler = _RecordingScheduler();
    final state = await openTestState(reminders: scheduler);
    await state.saveRule(
      _rent(
        start: CalendarDay(2026, 11, 25),
        reminder: const ReminderSettings(enabled: true),
      ),
    );
    await pumpEventQueue();
    expect(scheduler.permissionRequests, 1);
    expect(scheduler.last, isNotEmpty);
    expect(scheduler.last.first.occurrence, CalendarDay(2026, 11, 25));

    await state.setReminderDefaults(
      state.reminderDefaults.copyWith(enabled: false),
    );
    await pumpEventQueue();
    expect(scheduler.last, isEmpty);
  });

  test('a widget a havi összesítést és a következő tételt kapja', () async {
    final widget = _RecordingWidget();
    final state = await openTestState(widget: widget);
    await state.saveTransaction(
      income('Fizetés', 400000, 'salary', CalendarDay(2026, 11, 5)),
    );
    await state.saveRule(_rent(start: CalendarDay(2026, 11, 25)));
    await pumpEventQueue();
    expect(widget.last!.monthLabel, '2026. november');
    expect(widget.last!.balance, ft(400000));
    expect(widget.last!.nextDue, contains('Lakbér'));
    expect(widget.last!.nextDue, contains('nov. 25.'));
  });

  group('saját kategóriák', () {
    test('mentés, újranyitás és törlés az Egyéb kategóriába', () async {
      final factory = newDatabaseFactoryMemory();
      final state = await openTestState(factory: factory);
      final dog = await state.saveCategory(
        const Category(
          id: '',
          type: EntryType.expense,
          name: 'Kutya',
          colorValue: 0xFF14B8A6,
          iconKey: 'pets',
          custom: true,
        ),
      );
      expect(dog.id, startsWith('custom_'));
      expect(categoryName(dog.id), 'Kutya');
      await state.saveTransaction(
        expense('Táp', 8000, dog.id, CalendarDay(2026, 11, 10)),
      );
      await state.close();

      final reopened = await openTestState(factory: factory);
      expect(categoryName(dog.id), 'Kutya');
      expect(reopened.usageOfCategory(dog.id), 1);

      await reopened.deleteCategory(reopened.customCategories.single);
      expect(reopened.transactions.single.categoryId, 'other_expense');
      expect(categoryById(dog.id), isNull);
    });
  });

  group('körbevezetés', () {
    test('adat nélkül bemutató adatokat mutat, majd eltünteti', () async {
      final state = await openTestState(showTour: true);
      expect(state.tourSeen, isFalse);
      state.startTour();
      expect(state.isDemo, isTrue);
      expect(state.transactions, isNotEmpty);
      await state.endTour();
      expect(state.isDemo, isFalse);
      expect(state.transactions, isEmpty);
      expect(state.tourSeen, isTrue);
    });

    test('a saját adatokat nem bántja', () async {
      final state = await openTestState(showTour: true);
      await state.saveTransaction(
        expense('Kávé', 900, 'dining', CalendarDay(2026, 11, 16)),
      );
      state.startTour();
      expect(state.isDemo, isFalse);
      expect(state.transactions.single.title, 'Kávé');
      await state.endTour();
      expect(state.transactions.single.title, 'Kávé');
    });

    test('a teljes törlés után a bemutató nem jön újra', () async {
      final factory = newDatabaseFactoryMemory();
      final state = await openTestState(factory: factory);
      await state.clearAllData();
      await state.close();
      final reopened = await openTestState(factory: factory, showTour: true);
      expect(reopened.tourSeen, isTrue);
    });
  });
}
