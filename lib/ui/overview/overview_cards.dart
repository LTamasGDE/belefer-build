import 'package:flutter/material.dart';

import '../../domain/forecast.dart';
import '../../domain/formatting.dart';
import '../../domain/insights.dart';
import '../../services/platform_services.dart';
import '../../state/app_scope.dart';
import '../quick_entry/quick_entry_screen.dart';
import '../recurring/recurring_screen.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';

/// A gyorsrögzítés belépője az Áttekintésen: halványan mindig mutatja, mire
/// kell válaszolni az automatikus könyveléshez.
class QuickEntryBar extends StatelessWidget {
  const QuickEntryBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colors.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: colors.accent.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label:
                  'Gyorsrögzítés. Írd be, mennyi, mire és mikor, például: '
                  'Lidl 4500 tegnap.',
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('quick-entry-bar'),
                onTap: () => openQuickEntry(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.md,
                    Space.sm,
                    Space.md,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.accentText,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gyorsrögzítés', style: textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              'Mennyi? · Mire? · Mikor? – pl. „Lidl 4500 tegnap”',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.textMuted.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('quick-entry-scan'),
            tooltip: 'Blokk fotózása',
            icon: const Icon(Icons.document_scanner_rounded),
            onPressed: () =>
                openQuickEntry(context, scan: ReceiptSource.camera),
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
    );
  }
}

/// Előrejelzés a hónap végére: mennyi marad várhatóan.
class ForecastCard extends StatelessWidget {
  const ForecastCard({super.key, required this.forecast});

  final Forecast forecast;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final today = state.today();
    final f = forecast;
    final projected = f.projectedBalance;
    final variable = f.projectedVariableExpense;
    final upcoming = f.upcoming.take(3).toList();
    final isCurrent = state.isCurrentMonth;

    final total = [
      f.projectedIncome,
      f.projectedExpense,
      1,
    ].reduce((a, b) => a > b ? a : b);

    final summaryLabel =
        'Előrejelzés a hónap végére: várhatóan ${formatForint(projected)} '
        'marad. Még várható ${formatForint(f.upcomingIncome)} bevétel, '
        '${formatForint(f.upcomingExpense)} ismétlődő kiadás és kb. '
        '${formatForint(variable)} egyéb költés.';

    return Panel(
      key: const ValueKey('forecast-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: summaryLabel,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      size: 20,
                      color: colors.accentText,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        isCurrent
                            ? 'Előrejelzés a hónap végére'
                            : 'Előrejelzés erre a hónapra',
                        style: textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                Text(
                  'Várhatóan marad',
                  style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '≈ ${formatForint(projected)}',
                    key: const ValueKey('forecast-amount'),
                    style: textTheme.headlineSmall?.copyWith(
                      color: projected < 0 ? colors.expense : colors.text,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
                const SizedBox(height: Space.md),
                _ForecastBar(
                  income: f.projectedIncome,
                  spent: f.actualExpense,
                  recurring: f.upcomingExpense,
                  variable: variable,
                  total: total,
                ),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.md,
                  runSpacing: Space.xs,
                  children: [
                    _Legend(
                      color: colors.expense,
                      label: 'Eddig ${formatForint(f.actualExpense)}',
                    ),
                    _Legend(
                      color: colors.expense.withValues(alpha: 0.55),
                      label: 'Ismétlődő ${formatForint(f.upcomingExpense)}',
                    ),
                    _Legend(
                      color: colors.expense.withValues(alpha: 0.25),
                      label: 'Egyéb kb. ${formatForint(variable)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Divider(height: 1, color: colors.line),
            const SizedBox(height: Space.sm),
            for (final item in upcoming)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        formatShortDate(item.date, today),
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.learned
                            ? '${item.rule.title} (szokás szerint)'
                            : item.rule.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    AmountText(
                      amount: item.amount,
                      type: item.type,
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            if (f.upcoming.length > upcoming.length)
              Text(
                '+${f.upcoming.length - upcoming.length} további',
                style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
          ],
          if (f.basedOnHistory) ...[
            const SizedBox(height: Space.sm),
            Text(
              'Az egyéb költést az előző hónapok átlagából becsültem.',
              style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ForecastBar extends StatelessWidget {
  const _ForecastBar({
    required this.income,
    required this.spent,
    required this.recurring,
    required this.variable,
    required this.total,
  });

  final int income;
  final int spent;
  final int recurring;
  final int variable;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          double w(int value) => total <= 0 ? 0 : width * value / total;
          return SizedBox(
            height: 22,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: colors.sunken,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    children: [
                      Container(width: w(spent), color: colors.expense),
                      Container(
                        width: w(recurring),
                        color: colors.expense.withValues(alpha: 0.55),
                      ),
                      Container(
                        width: w(variable),
                        color: colors.expense.withValues(alpha: 0.25),
                      ),
                    ],
                  ),
                ),
                // A várható bevétel jelölője.
                if (income > 0)
                  Positioned(
                    left: (w(income) - 2).clamp(0, width - 3).toDouble(),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 3, color: colors.income),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// Jóváhagyásra váró ismétlődő tételek az Áttekintésen.
class PendingSection extends StatelessWidget {
  const PendingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final pending = AppScope.of(context).pending;
    if (pending.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Jóváhagyásra vár'),
        for (final occurrence in pending.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: PendingCard(occurrence: occurrence),
          ),
      ],
    );
  }
}

/// „Mi van, mi lesz”: az eddigi költés üteme, a szokatlan kategória és a
/// következő napok várható tételei – a tanult szokásokból.
class InsightsCard extends StatelessWidget {
  const InsightsCard({super.key, required this.insights});

  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      key: const ValueKey('insights-card'),
      child: Semantics(
        container: true,
        label: 'Mi van, mi lesz: ${insights.map((i) => i.text).join(' ')}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 20,
                  color: colors.accentText,
                ),
                const SizedBox(width: Space.sm),
                Text('Mi van, mi lesz', style: textTheme.titleMedium),
              ],
            ),
            for (final insight in insights) ...[
              const SizedBox(height: Space.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (insight.kind) {
                      InsightKind.pace => Icons.speed_rounded,
                      InsightKind.unusual => Icons.trending_up_rounded,
                      InsightKind.upcoming => Icons.event_rounded,
                    },
                    size: 18,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(insight.text, style: textTheme.bodyMedium),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
