import 'dart:async';

import 'package:flutter/material.dart';

import '../services/platform_services.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import 'overview/overview_screen.dart';
import 'quick_entry/quick_entry_screen.dart';
import 'recurring/recurring_screen.dart';
import 'settings/settings_screen.dart';
import 'templates/templates_screen.dart';
import 'tour/tour_keys.dart';
import 'tour/tour_overlay.dart';
import 'transactions/transactions_screen.dart';

/// Alsó navigáció: Áttekintés, Tételek, Ismétlődő, Sablonok, Beállítások.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  StreamSubscription<Uri>? _links;

  static const _screens = <Widget>[
    OverviewScreen(),
    TransactionsScreen(),
    RecurringScreen(),
    TemplatesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = AppScope.read(context);
      if (!state.tourSeen && !state.tourActive) state.startTour();
      _listenToLinks();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      unawaited(AppScope.read(context).refreshForToday());
    }
  }

  /// A kezdőképernyő-widgetről érkező megnyitások.
  void _listenToLinks() {
    final links = Services.appLinks;
    unawaited(
      links.initialLink().then((uri) {
        if (uri != null && mounted) _handleLink(uri);
      }),
    );
    _links = links.links.listen((uri) {
      if (mounted) _handleLink(uri);
    });
  }

  void _handleLink(Uri uri) {
    final state = AppScope.read(context);
    if (state.tourActive) return;
    // Visszatérés a kezdő lapra, az esetleg nyitott űrlapok bezárásával.
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _index = 0);
    state.showCurrentMonth();
    switch (uri.host) {
      case 'gyors':
        unawaited(openQuickEntry(context));
      case 'blokk':
        unawaited(openQuickEntry(context, scan: ReceiptSource.camera));
    }
  }

  List<TourStep> _tourSteps(AppState state) => [
    TourStep(
      title: 'Üdv a Belefér-ben!',
      body:
          'Egy perc alatt megmutatom, mit hol találsz. Bármikor kihagyhatod, '
          'és később a Beállításokban újraindíthatod. '
          '${state.isDemo ? 'Most bemutató adatokat látsz – ezek nem mentődnek, és a végén eltűnnek.' : 'A saját adataiddal mutatom be – semmi sem változik.'}',
    ),
    TourStep(
      target: TourKeys.balance,
      title: 'A hónap egy pillantásra',
      body:
          'Mennyi jött be, mennyi ment el, és mennyi maradt. Fent a hónapok '
          'között lapozhatsz.',
    ),
    TourStep(
      target: TourKeys.quickEntry,
      title: 'Gyorsrögzítés',
      body:
          'Írd be úgy, ahogy mondanád: „Lidl 4500 tegnap”, „megjött a fizetés '
          '420e”, „Netflix havi 4990”. Halványan mindig látod, mire kell még '
          'válasz; ha minden megvan, egy koppintással könyvelem. Blokkot vagy '
          'e-számlát is beolvashatsz – akár képernyőképről.',
    ),
    TourStep(
      target: TourKeys.forecast,
      optional: true,
      title: 'Előrejelzés',
      body:
          'Az ismétlődő tételekből és az eddigi költésedből megbecsülöm, '
          'mennyi marad a hónap végére.',
    ),
    TourStep(
      target: TourKeys.breakdown,
      title: 'Hová megy a pénz?',
      body:
          'A kiadások kategóriánként. Koppints egy szeletre vagy a '
          'jelmagyarázat egy sorára a részletekért.',
    ),
    TourStep(
      tab: 1,
      target: TourKeys.search,
      title: 'Tételek és keresés',
      body:
          'Itt vannak a hónap tételei, típus szerint szűrhetők. A nagyítóval '
          'minden hónapban kereshetsz – elírva is megtalálom.',
    ),
    const TourStep(
      tab: 2,
      navIndex: 2,
      title: 'Ismétlődő tételek',
      body:
          'Lakbér, fizetés, előfizetések: egyszer felveszed, esedékességkor '
          'maguktól rögzülnek. Kérésre előtte emlékeztetlek – akár saját '
          'szöveggel.',
    ),
    const TourStep(
      tab: 3,
      navIndex: 3,
      title: 'Sablonok',
      body: 'A gyakori tételeket sablonból pár koppintással rögzítheted.',
    ),
    const TourStep(
      tab: 4,
      navIndex: 4,
      title: 'Beállítások',
      body:
          'Saját kategóriák, emlékeztetők, sötét mód – és innen indíthatod '
          'újra ezt a bemutatót. Tipp: tedd ki a Belefér widgetet a '
          'kezdőképernyőre, így mindig látod, mennyi maradt.',
    ),
  ];

  Future<void> _finishTour() async {
    final state = AppScope.read(context);
    setState(() => _index = 0);
    await state.endTour();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scaffold = Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _screens.length; i++)
            TickerMode(
              enabled: i == _index,
              child: ExcludeFocus(excluding: i != _index, child: _screens[i]),
            ),
        ],
      ),
      // Öt fülnél a feliratok nagy betűméretnél szó közben törnének; a
      // navigáció felirata ezért legfeljebb normál méretű (az ikonok és a
      // képernyőolvasó felirata változatlan).
      bottomNavigationBar: KeyedSubtree(
        key: TourKeys.navigation,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1,
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
                icon: Icon(Icons.event_repeat_outlined),
                selectedIcon: Icon(Icons.event_repeat_rounded),
                label: 'Ismétlődő',
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
      ),
    );

    return PopScope(
      // Androidon a rendszer-visszalépés először az Áttekintésre visz;
      // bemutató közben a bemutatót zárja be.
      canPop: _index == 0 && !state.tourActive,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state.tourActive) {
          unawaited(_finishTour());
        } else if (_index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Stack(
        children: [
          // A bemutató alatt a felület nem érhető el a képernyőolvasónak sem.
          ExcludeSemantics(excluding: state.tourActive, child: scaffold),
          if (state.tourActive)
            Positioned.fill(
              child: TourOverlay(
                key: ValueKey('tour-${state.isDemo}'),
                steps: _tourSteps(state),
                onShowTab: (tab) {
                  if (tab != _index) setState(() => _index = tab);
                },
                onFinish: () => unawaited(_finishTour()),
              ),
            ),
        ],
      ),
    );
  }
}
