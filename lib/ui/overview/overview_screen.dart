import 'package:flutter/material.dart';

import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../domain/monthly_summary.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../theme/palette.dart';
import '../transactions/transaction_actions.dart';
import '../accounts/accounts_screen.dart';
import '../widgets/common.dart';
import '../widgets/month_switcher.dart';
import '../tour/tour_keys.dart';
import 'expense_donut.dart';
import 'overview_cards.dart';

/// Áttekintés: havi egyenleg, gyorsműveletek és a kiadások megoszlása.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final summary = state.summary;

    final hero = KeyedSubtree(
      key: TourKeys.balance,
      child: _BalanceCard(summary: summary),
    );
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(key: TourKeys.quickEntry, child: const QuickEntryBar()),
        const SizedBox(height: Space.md),
        const _QuickActions(),
        const PendingSection(),
      ],
    );
    final forecast = state.forecast;
    final showForecast =
        forecast != null &&
        (state.transactions.isNotEmpty || state.rules.isNotEmpty);
    final forecastCard = showForecast
        ? KeyedSubtree(
            key: TourKeys.forecast,
            child: ForecastCard(forecast: forecast),
          )
        : null;
    final insights = state.insights;
    final insightsCard = insights.isEmpty
        ? null
        : InsightsCard(insights: insights);
    final breakdown = Panel(
      key: TourKeys.breakdown,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Kiadások kategóriánként',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: Space.md),
          ExpenseBreakdown(summary: summary),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const _Wordmark(), toolbarHeight: 64),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          if (wide) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                0,
                Space.xl,
                Space.xxl,
              ),
              children: [
                ContentWidth(
                  maxWidth: 1100,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const MonthSwitcher(),
                            const AccountFilterBar(),
                            const SizedBox(height: Space.sm),
                            hero,
                            const SizedBox(height: Space.lg),
                            actions,
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.xl),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: state.accounts.isEmpty ? 56 : 104),
                            if (forecastCard != null) ...[
                              forecastCard,
                              const SizedBox(height: Space.lg),
                            ],
                            if (insightsCard != null) ...[
                              insightsCard,
                              const SizedBox(height: Space.lg),
                            ],
                            breakdown,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              0,
              Space.md,
              Space.xxl,
            ),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MonthSwitcher(),
                    const AccountFilterBar(),
                    const SizedBox(height: Space.sm),
                    hero,
                    const SizedBox(height: Space.lg),
                    actions,
                    const SizedBox(height: Space.lg),
                    if (forecastCard != null) ...[
                      forecastCard,
                      const SizedBox(height: Space.lg),
                    ],
                    if (insightsCard != null) ...[
                      insightsCard,
                      const SizedBox(height: Space.lg),
                    ],
                    breakdown,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.accent, width: 6),
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        Text('Belefér', style: Theme.of(context).textTheme.headlineSmall),
      ],
    );
  }
}

/// A hónap fő száma: mennyi maradt, alatta a bevétel és a kiadás.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});

  final MonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final balance = summary.balance;
    final balanceText = formatForint(balance);
    return Semantics(
      container: true,
      label:
          'Maradt: $balanceText. Bejött: ${formatForint(summary.income)}. '
          'Elment: ${formatForint(summary.expense)}.',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.heroBackground,
          borderRadius: BorderRadius.circular(Radii.hero),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -46,
              top: -46,
              child: _Ring(color: colors.accent.withValues(alpha: 0.22)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.xl,
                Space.xl,
                Space.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Maradt',
                    style: textTheme.titleSmall?.copyWith(
                      color: colors.heroMuted,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      balanceText,
                      key: const ValueKey('balance-amount'),
                      style: textTheme.displaySmall?.copyWith(
                        color: balance < 0
                            ? Color.lerp(colors.expense, Colors.white, 0.35)
                            : colors.heroForeground,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      _FlowChip(
                        label: 'Bejött',
                        amount: summary.income,
                        type: EntryType.income,
                      ),
                      _FlowChip(
                        label: 'Elment',
                        amount: summary.expense,
                        type: EntryType.expense,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 26),
      ),
    );
  }
}

class _FlowChip extends StatelessWidget {
  const _FlowChip({
    required this.label,
    required this.amount,
    required this.type,
  });

  final String label;
  final int amount;
  final EntryType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final isIncome = type == EntryType.income;
    final tint = isIncome ? Palette.mintBright : Palette.coralBright;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 16,
            color: tint,
          ),
          const SizedBox(width: 6),
          Text(
            '$label ',
            style: textTheme.labelMedium?.copyWith(color: colors.heroMuted),
          ),
          Text(
            formatForint(amount),
            style: textTheme.labelLarge?.copyWith(
              color: colors.heroForeground,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final expense = _QuickActionButton(
      key: const ValueKey('quick-expense'),
      label: 'Új kiadás',
      icon: Icons.remove_rounded,
      color: colors.expense,
      onPressed: () =>
          openTransactionForm(context, initialType: EntryType.expense),
    );
    final income = _QuickActionButton(
      key: const ValueKey('quick-income'),
      label: 'Új bevétel',
      icon: Icons.add_rounded,
      color: colors.income,
      onPressed: () =>
          openTransactionForm(context, initialType: EntryType.income),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Nagy betűméretnél vagy keskeny helyen egymás alá kerülnek,
        // hogy a feliratok ne törjenek szó közben.
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        if (constraints.maxWidth < 320 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              expense,
              const SizedBox(height: Space.sm),
              income,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: expense),
            const SizedBox(width: Space.md),
            Expanded(child: income),
          ],
        );
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: colors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: colors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 24,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Palette.ink
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
