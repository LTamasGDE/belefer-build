import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Az [AppState] elérhetővé tétele a widgetfában.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  /// Feliratkozik a változásokra: az állapot frissülésekor újraépít.
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'Nincs AppScope a widgetfában.');
    return scope!.notifier!;
  }

  /// Feliratkozás nélküli elérés, például eseménykezelőkben.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'Nincs AppScope a widgetfában.');
    return scope!.notifier!;
  }
}
