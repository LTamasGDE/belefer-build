import 'package:flutter/material.dart';

import 'overview/overview_screen.dart';
import 'settings/settings_screen.dart';
import 'templates/templates_screen.dart';
import 'transactions/transactions_screen.dart';

/// Alsó navigáció: Áttekintés, Tételek, Sablonok, Beállítások.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = <Widget>[
    OverviewScreen(),
    TransactionsScreen(),
    TemplatesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Androidon a rendszer-visszalépés először az Áttekintésre visz.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _screens.length; i++)
              TickerMode(
                enabled: i == _index,
                child: ExcludeFocus(
                  excluding: i != _index,
                  child: _screens[i],
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.donut_large_outlined),
              selectedIcon: Icon(Icons.donut_large_rounded),
              label: 'Áttekintés',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Tételek',
            ),
            NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt_rounded),
              label: 'Sablonok',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Beállítások',
            ),
          ],
        ),
      ),
    );
  }
}
