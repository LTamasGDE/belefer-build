import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Váltás az alsó navigáció egyik fülére.
Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Látható helyre görget, majd koppint.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Egy kulccsal azonosított szövegmező aktuális tartalma.
String fieldText(WidgetTester tester, String key) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    ),
  );
  return editable.controller.text;
}

/// Szöveg beírása egy kulccsal azonosított mezőbe.
Future<void> enterField(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}
