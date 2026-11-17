import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/categories.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/month_switcher.dart';
import '../widgets/pill_selector.dart';
import 'transaction_actions.dart';

/// Típusszűrő a Tételek listán.
enum TransactionFilter { all, expense, income }

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  TransactionFilter _filter = TransactionFilter.all;

  EntryType? get _type => switch (_filter) {
    TransactionFilter.all => null,
    TransactionFilter.expense => EntryType.expense,
    TransactionFilter.income => EntryType.income,
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final items = state.transactionsOfSelectedMonth(type: _type);
    final total = items.fold<int>(0, (sum, item) => sum + item.signedAmount);

    final children = <Widget>[
      const MonthSwitcher(),
      const SizedBox(height: Space.sm),
      PillSelector<TransactionFilter>(
        semanticLabel: 'Szűrés típus szerint',
        selected: _filter,
        onChanged: (value) => setState(() => _filter = value),
        options: [
          const PillOption(value: TransactionFilter.all, label: 'Mind'),
          PillOption(
            value: TransactionFilter.expense,
            label: 'Kiadás',
            color: colors.expense,
          ),
          PillOption(
            value: TransactionFilter.income,
            label: 'Bevétel',
            color: colors.income,
          ),
        ],
      ),
    ];

    if (items.isEmpty) {
      children.add(
        EmptyState(
          icon: Icons.receipt_long_rounded,
          title: switch (_filter) {
            TransactionFilter.all => 'Ebben a hónapban még nincs tétel',
            TransactionFilter.expense => 'Ebben a hónapban nincs kiadás',
            TransactionFilter.income => 'Ebben a hónapban nincs bevétel',
          },
          message: 'Az új tételek dátum szerint rendezve jelennek meg itt.',
          actions: [
            FilledButton.icon(
              onPressed: () => openTransactionForm(
                context,
                initialType: _type ?? EntryType.expense,
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Új tétel'),
            ),
          ],
        ),
      );
    } else {
      children.add(
        _TotalLine(filter: _filter, total: total, count: items.length),
      );
      CalendarDay? currentDay;
      for (final item in items) {
        if (item.date != currentDay) {
          currentDay = item.date;
          children.add(_DayHeading(day: item.date));
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: TransactionTile(
              transaction: item,
              onTap: () => openTransactionForm(context, existing: item),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tételek')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-transactions',
        onPressed: () => openTransactionForm(
          context,
          initialType: _type ?? EntryType.expense,
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Új tétel'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 104),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.filter,
    required this.total,
    required this.count,
  });

  final TransactionFilter filter;
  final int total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final label = switch (filter) {
      TransactionFilter.all => 'Egyenleg',
      TransactionFilter.expense => 'Kiadás összesen',
      TransactionFilter.income => 'Bevétel összesen',
    };
    final amount = filter == TransactionFilter.expense ? -total : total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.lg, Space.sm, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label · $count tétel',
              style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ),
          Text(
            formatForint(amount),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.day});

  final CalendarDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = AppScope.of(context).today();
    final String label;
    if (day == today) {
      label = 'Ma · ${formatDayHeading(day)}';
    } else if (day == CalendarDay(today.year, today.month, today.day - 1)) {
      label = 'Tegnap · ${formatDayHeading(day)}';
    } else {
      label = formatDayHeading(day);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
        Space.lg,
        Space.sm,
        Space.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: colors.textMuted),
        ),
      ),
    );
  }
}

/// Egy tétel sora: kategóriaikon, megnevezés, kategória és összeg.
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction, this.onTap});

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final category = categoryName(transaction.categoryId);
    final note = transaction.note;
    final isExpense = transaction.type == EntryType.expense;
    final semantic =
        '${transaction.title}, $category, '
        '${isExpense ? 'kiadás' : 'bevétel'} '
        '${formatForint(transaction.amount)}'
        '${note == null ? '' : ', megjegyzés: $note'}';
    return Semantics(
      button: onTap != null,
      label: semantic,
      excludeSemantics: true,
      child: Panel(
        padding: EdgeInsets.zero,
        radius: 20,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                CategoryAvatar(transaction.categoryId),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note == null ? category : '$category · $note',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                AmountText(amount: transaction.amount, type: transaction.type),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
