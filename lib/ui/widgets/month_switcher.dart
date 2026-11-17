import 'package:flutter/material.dart';

import '../../domain/formatting.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';

/// Hónapváltó: előző / aktuális hónap / következő.
///
/// Az Áttekintés és a Tételek képernyő ugyanazt a hónapot mutatja.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final label = formatYearMonth(state.selectedMonth);
    return Row(
      children: [
        IconButton(
          onPressed: state.showPreviousMonth,
          tooltip: 'Előző hónap',
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: 'Kiválasztott hónap: $label',
            excludeSemantics: true,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        if (!state.isCurrentMonth)
          IconButton(
            onPressed: state.showCurrentMonth,
            tooltip: 'Ugrás az aktuális hónapra',
            color: colors.accentText,
            icon: const Icon(Icons.today_rounded),
          ),
        IconButton(
          onPressed: state.showNextMonth,
          tooltip: 'Következő hónap',
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// Kis vízszintes térköz a képernyőszéltől.
const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: Space.page);
