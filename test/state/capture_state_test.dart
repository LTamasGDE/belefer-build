import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/capture/captured_event.dart';
import 'package:belefer/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Transaction;

import '../support/test_app.dart';

Map<Object?, Object?> revolutEvent(String title, String text, DateTime at) => {
  'id': '$title$at',
  'source': 'revolut',
  'time': at.millisecondsSinceEpoch,
  'title': title,
  'text': text,
};

void main() {
  group('számlák', () {
    test('alapértelmezett, szűrés és törlés', () async {
      final state = await openTestState();
      final own = await state.saveAccount(
        const Account(
          name: 'Saját',
          kind: AccountKind.personal,
          isDefault: true,
        ),
      );
      final joint = await state.saveAccount(
        const Account(
          name: 'Közös',
          kind: AccountKind.shared,
          matchers: ['Közös'],
        ),
      );
      expect(state.defaultAccount?.id, own.id);

      // Számla nélküli tétel az alapértelmezetthez tartozik.
      await state.saveTransaction(
        expense('Lidl', 4000, 'groceries', CalendarDay(2026, 11, 3)),
      );
      await state.saveTransaction(
        expense(
          'Rezsi',
          30000,
          'utilities',
          CalendarDay(2026, 11, 5),
        ).copyWith(accountId: joint.id),
      );
      expect(state.summary.expense, 34000);

      state.selectAccount(joint.id);
      expect(state.summary.expense, 30000);
      expect(state.transactionsOfSelectedMonth(), hasLength(1));
      state.selectAccount(own.id);
      expect(state.summary.expense, 4000);
      expect(state.usageOfAccount(joint.id!), 1);

      // Új alapértelmezett: a régi elveszti a jelölést.
      await state.saveAccount(
        Account(
          id: joint.id,
          name: 'Közös',
          kind: AccountKind.shared,
          isDefault: true,
        ),
      );
      expect(state.accounts.where((a) => a.isDefault), hasLength(1));
      expect(state.defaultAccount?.id, joint.id);

      await state.deleteAccount(joint.id!);
      expect(state.accounts, hasLength(1));
      expect(state.transactions.every((t) => t.accountId == null), isTrue);
      expect(state.selectedAccountId, own.id);
      await state.close();
    });

    test('a számlák megmaradnak újraindítás után', () async {
      final factory = newDatabaseFactoryMemory();
      final first = await openTestState(factory: factory);
      await first.saveAccount(
        const Account(
          name: 'Megtakarítás',
          kind: AccountKind.savings,
          matchers: ['Persely'],
        ),
      );
      await first.close();
      final second = await openTestState(factory: factory);
      expect(second.accounts.single.name, 'Megtakarítás');
      expect(second.accounts.single.matchers, ['Persely']);
      await second.close();
    });
  });

  group('automatikus rögzítés', () {
    test('a sor feldolgozása AI nélkül', () async {
      final bridge = FakeCaptureBridge();
      final state = await openTestState(capture: bridge);
      bridge.queue.addAll([
        revolutEvent(
          'Lidl',
          'Fizettél 4 590 Ft-ot',
          DateTime(2026, 11, 16, 18),
        ),
        revolutEvent(
          'Revolut',
          'Payment declined: insufficient funds',
          DateTime(2026, 11, 16, 18, 1),
        ),
        revolutEvent(
          'Revolut',
          '10 000 Ft átkerült a Megtakarítás perselybe',
          DateTime(2026, 11, 16, 19),
        ),
      ]);
      final reports = <CaptureReport?>[];
      state.captureReports.addListener(
        () => reports.add(state.captureReports.value),
      );

      final report = await state.processCaptures();
      expect(report!.booked, hasLength(1));
      expect(report.skipped, 2);
      expect(reports.single, same(report));
      expect(report.message, contains('4'));

      final booked = state.transactions.single;
      expect(booked.amount, 4590);
      expect(booked.source, 'revolut');
      expect(booked.date, CalendarDay(2026, 11, 16));

      expect(state.captureLog, hasLength(3));
      // A legújabb elöl.
      expect(state.captureLog.first.outcome, CaptureOutcome.transfer);
      expect(state.captureLog.last.outcome, CaptureOutcome.booked);
      expect(state.captureLog.last.transactionId, booked.id);

      // Üres sor: nincs új jelentés.
      expect(await state.processCaptures(), isNull);
      await state.close();
    });

    test('Apple Pay: a számlát a kártyanévből veszi', () async {
      final bridge = FakeCaptureBridge(supportsNotifications: false);
      final state = await openTestState(capture: bridge);
      await state.saveAccount(
        const Account(
          name: 'Saját',
          kind: AccountKind.personal,
          isDefault: true,
        ),
      );
      final joint = await state.saveAccount(
        const Account(
          name: 'Közös',
          kind: AccountKind.shared,
          matchers: ['Közös'],
        ),
      );
      bridge.queue.add({
        'id': 'ap1',
        'source': 'applepay',
        'time': DateTime(2026, 11, 17, 8, 15).millisecondsSinceEpoch,
        'amount': '1 290 Ft',
        'merchant': 'Costa Coffee',
        'card': 'Közös',
      });
      await state.processCaptures();
      final booked = state.transactions.single;
      expect(booked.title, 'Costa Coffee');
      expect(booked.categoryId, 'dining');
      expect(booked.amount, 1290);
      expect(booked.accountId, joint.id);
      expect(booked.source, 'applepay');
      await state.close();
    });

    test('Revolut kapcsoló és napló megmarad', () async {
      final factory = newDatabaseFactoryMemory();
      final bridge = FakeCaptureBridge();
      final first = await openTestState(factory: factory, capture: bridge);
      bridge.queue.add(
        revolutEvent('Spar', 'Fizettél 2 000 Ft-ot', DateTime(2026, 11, 17)),
      );
      await first.setRevolutCaptureEnabled(true);
      expect(bridge.enabled, isTrue);
      await first.processCaptures();
      await first.close();

      final second = await openTestState(factory: factory);
      expect(second.revolutCaptureEnabled, isTrue);
      expect(second.captureLog, hasLength(1));
      expect(second.transactions.single.source, 'revolut');

      await second.clearAllData();
      expect(second.revolutCaptureEnabled, isFalse);
      expect(second.captureLog, isEmpty);
      await second.close();
    });
  });
}
