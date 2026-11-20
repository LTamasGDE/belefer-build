import 'package:belefer/domain/accounts.dart';
import 'package:belefer/domain/model/belefer_model.dart';
import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/ui/accounts/accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/model.dart';
import '../support/test_app.dart';
import '../support/ui_helpers.dart';

Finder _inFilter(String label) => find.descendant(
  of: find.byType(AccountFilterBar),
  matching: find.text(label),
);

void main() {
  testWidgets('számlák felvétele, szűrés és számla a tételen', (tester) async {
    final state = await pumpBelefer(tester);
    // Számla nélkül nincs szűrő.
    expect(find.byType(AccountFilterBar), findsOneWidget);
    expect(find.text('Összes számla'), findsNothing);

    await goToTab(tester, 'Beállítások');
    await tapVisible(tester, find.byKey(const ValueKey('open-accounts')));
    expect(find.text('Még nincs számla'), findsOneWidget);

    // Az első számla automatikusan alapértelmezett.
    await tapVisible(tester, find.byKey(const ValueKey('add-account')));
    await enterField(tester, 'account-name', 'Saját');
    await tapVisible(tester, find.byKey(const ValueKey('save-account')));
    expect(state.accounts.single.isDefault, isTrue);

    await tapVisible(tester, find.byKey(const ValueKey('add-account')));
    await enterField(tester, 'account-name', 'Közös Revolut');
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(AccountKind.shared.label),
      ),
    );
    await enterField(tester, 'account-matchers', 'Közös, 7710');
    await tapVisible(tester, find.byKey(const ValueKey('save-account')));
    final joint = state.accounts.firstWhere((a) => a.name == 'Közös Revolut');
    expect(joint.kind, AccountKind.shared);
    expect(joint.matchers, ['Közös', '7710']);
    expect(joint.isDefault, isFalse);
    expect(find.textContaining('felismerés: Közös, 7710'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await goToTab(tester, 'Áttekintés');
    expect(_inFilter('Összes számla'), findsOneWidget);

    // Új kiadás a közös számlára.
    await tapVisible(tester, find.byKey(const ValueKey('quick-expense')));
    await enterField(tester, 'field-amount', '30000');
    await enterField(tester, 'field-title', 'Áram');
    await tapVisible(tester, find.text('Rezsi'));
    await tapVisible(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('transaction-account')),
        matching: find.text('Közös Revolut'),
      ),
    );
    await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));
    expect(state.transactions.single.accountId, joint.id);

    await tester.runAsync(
      () => state.saveTransaction(
        expense('Lidl', 4000, 'groceries', CalendarDay(2026, 11, 3)),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.summary.expense, 34000);

    await tapVisible(tester, _inFilter('Közös Revolut'));
    expect(state.summary.expense, 30000);
    await tapVisible(tester, _inFilter('Saját'));
    expect(state.summary.expense, 4000);
    await tapVisible(tester, _inFilter('Összes számla'));
    expect(state.summary.expense, 34000);

    // A Tételek listán a számla neve is látszik.
    await goToTab(tester, 'Tételek');
    expect(find.textContaining('Közös Revolut'), findsWidgets);
  });

  testWidgets('automatikus tétel jelzése és szerkesztése', (tester) async {
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(
      () => state.saveTransaction(
        Transaction(
          type: EntryType.expense,
          title: 'Costa Coffee',
          amount: 1290,
          categoryId: 'dining',
          date: CalendarDay(2026, 11, 17),
          note: 'Apple Pay · Közös',
          source: 'applepay',
        ),
      ),
    );
    await pumpBelefer(tester, state: state);
    await goToTab(tester, 'Tételek');
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);

    await tapVisible(tester, find.text('Costa Coffee'));
    expect(find.text('Automatikusan rögzítve: Apple Pay.'), findsOneWidget);
    await enterField(tester, 'field-amount', '1390');
    await tapVisible(tester, find.byKey(const ValueKey('save-transaction')));
    // A forrás szerkesztés után is megmarad.
    expect(state.transactions.single.amount, 1390);
    expect(state.transactions.single.source, 'applepay');
  });

  testWidgets('saját modell: bemutató és próbamező', (tester) async {
    currentModel = loadTestModel();
    addTearDown(() => currentModel = null);
    final state = (await tester.runAsync(openTestState))!;
    await tester.runAsync(
      () => state.saveTransaction(
        expense('Zongoraóra', 6000, 'education', testToday),
      ),
    );
    await pumpBelefer(tester, state: state);
    await goToTab(tester, 'Beállítások');
    await tapVisible(tester, find.byKey(const ValueKey('open-model')));
    expect(find.text('Saját modell'), findsWidgets);
    // Nem sorolja fel, mit tud rólad; csak annyit mond, hogy tanul.
    expect(find.textContaining('A tételeidből is tanul'), findsOneWidget);
    expect(find.textContaining('megnevezésedet ismeri'), findsNothing);
    expect(find.textContaining('súly'), findsOneWidget);

    await enterField(tester, 'model-try', 'tegnap a hentesnél 6700');
    await tester.pumpAndSettle();
    expect(find.text('Hentes'), findsOneWidget);
    expect(find.text('Élelmiszer'), findsWidgets);
    // A próba nem rögzít semmit.
    expect(state.transactions, hasLength(1));
  });

  testWidgets('automatikus rögzítés: Revolut-kapcsoló és engedély', (
    tester,
  ) async {
    final bridge = FakeCaptureBridge();
    final state = (await tester.runAsync(
      () => openTestState(capture: bridge),
    ))!;
    await pumpBelefer(tester, state: state);
    await goToTab(tester, 'Beállítások');
    await tapVisible(tester, find.byKey(const ValueKey('open-capture')));
    expect(find.text('Revolut-értesítések (Android)'), findsOneWidget);
    expect(find.text('Apple Pay (iPhone)'), findsNothing);

    await tapVisible(tester, find.byKey(const ValueKey('revolut-switch')));
    expect(state.revolutCaptureEnabled, isTrue);
    expect(bridge.enabled, isTrue);
    expect(bridge.settingsOpened, 1);
    expect(find.byKey(const ValueKey('grant-access')), findsOneWidget);

    // Visszatérés a rendszerbeállításokból, megadott engedéllyel.
    bridge.granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('grant-access')), findsNothing);
    expect(
      find.text('Bekapcsolva: a Revolut értesítéseiből rögzít.'),
      findsOneWidget,
    );

    // Beérkező tétel: napló és jelzés.
    bridge.queue.add({
      'id': '1',
      'source': 'revolut',
      'time': DateTime(2026, 11, 17, 11).millisecondsSinceEpoch,
      'title': 'Lidl',
      'text': 'Fizettél 4 590 Ft-ot',
    });
    await tapVisible(tester, find.byKey(const ValueKey('process-now')));
    await tester.pumpAndSettle();
    expect(state.transactions, hasLength(1));
    expect(find.text('Rögzítve'), findsWidgets);
  });

  testWidgets('iPhone: Apple Pay útmutató', (tester) async {
    final state = (await tester.runAsync(
      () => openTestState(
        capture: FakeCaptureBridge(supportsNotifications: false),
      ),
    ))!;
    await pumpBelefer(tester, state: state);
    await goToTab(tester, 'Beállítások');
    await tapVisible(tester, find.byKey(const ValueKey('open-capture')));
    expect(find.text('Apple Pay (iPhone)'), findsOneWidget);
    expect(find.text('Revolut-értesítések (Android)'), findsNothing);
    expect(find.textContaining('Fizetés rögzítése a'), findsOneWidget);
  });
}
