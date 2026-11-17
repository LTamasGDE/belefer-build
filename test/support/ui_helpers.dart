import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Váltás az alsó navigáció egyik fülére.
Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// A képernyő közepére görgeti az elemet (hogy ne takarja el például egy
/// SnackBar), majd koppint rá.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await scrollToCenter(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Görgetés úgy, hogy az elem a látható terület közepére kerüljön.
Future<void> scrollToCenter(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
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
  await scrollToCenter(tester, finder);
  await tester.enterText(finder, text);
  await tester.pump();
}
