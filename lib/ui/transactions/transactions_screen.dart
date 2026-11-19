import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/categories.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../state/app_scope.dart';
import '../accounts/accounts_screen.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/month_switcher.dart';
import '../tour/tour_keys.dart';
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
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _startSearch() => setState(() => _searching = true);

  void _stopSearch() {
    _searchController.clear();
    setState(() => _searching = false);
  }

  EntryType? get _type => switch (_filter) {
    TransactionFilter.all => null,
    TransactionFilter.expense => EntryType.expense,
    TransactionFilter.income => EntryType.income,
  };

  @override
  Widget build(BuildContext context) {
    if (_searching) return _buildSearch(context);
    final state = AppScope.of(context);
    final colors = context.colors;
    final items = state.transactionsOfSelectedMonth(type: _type);
    final total = items.fold<int>(0, (sum, item) => sum + item.signedAmount);

    final children = <Widget>[
      const MonthSwitcher(),
      const AccountFilterBar(),
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
      appBar: AppBar(
        title: const Text('Tételek'),
        actions: [
          IconButton(
            key: TourKeys.search,
            tooltip: 'Keresés',
            icon: const Icon(Icons.search_rounded),
            onPressed: _startSearch,
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
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

extension on _TransactionsScreenState {
  Widget _buildSearch(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final query = _searchController.text;
    final results = state.search(query);
    final total = results.fold<int>(0, (sum, item) => sum + item.signedAmount);
    final children = <Widget>[];
    if (query.trim().isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Text(
            'Kereshetsz megnevezésre, megjegyzésre, kategóriára, összegre '
            'vagy dátumra – minden hónapban. Pl. „kávé”, „lakbér október”, '
            '„12450”.',
            style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
          ),
        ),
      );
    } else if (results.isEmpty) {
      children.add(
        const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Nincs találat',
          message: 'Próbáld rövidebb vagy más szóval.',
        ),
      );
    } else {
      children.add(
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${results.length} találat',
                    key: const ValueKey('search-count'),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
                Text(
                  formatForint(total),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      CalendarDay? currentDay;
      for (final item in results) {
        if (item.date != currentDay) {
          currentDay = item.date;
          children.add(_DayHeading(day: item.date, withYear: true));
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Keresés bezárása',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _stopSearch,
          ),
          title: TextField(
            key: const ValueKey('search-field'),
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Keresés a tételek között',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
          actions: [
            if (query.isNotEmpty)
              IconButton(
                tooltip: 'Törlés',
                icon: const Icon(Icons.close_rounded),
                onPressed: _searchController.clear,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xxl),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
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
  const _DayHeading({required this.day, this.withYear = false});

  final CalendarDay day;
  final bool withYear;

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
      label = withYear && day.year != today.year
          ? '${day.year}. ${formatDayHeading(day)}'
          : formatDayHeading(day);
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
    final state = AppScope.of(context);
    final category = categoryName(transaction.categoryId);
    // Az összes számla nézetben a tétel számláját is mutatjuk.
    final account = state.accounts.length > 1 && state.selectedAccountId == null
        ? state.accountById(state.effectiveAccountId(transaction.accountId))
        : null;
    final note = transaction.note;
    final auto = transaction.source != null;
    final details = [category, ?account?.name, ?note].join(' · ');
    final isExpense = transaction.type == EntryType.expense;
    // Nagy betűméretnél az összeg a megnevezés alá kerül.
    final compact = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3;
    final amount = AmountText(
      amount: transaction.amount,
      type: transaction.type,
    );
    final semantic =
        '${transaction.title}, $category, '
        '${account == null ? '' : '${account.name} számla, '}'
        '${isExpense ? 'kiadás' : 'bevétel'} '
        '${formatForint(transaction.amount)}'
        '${auto ? ', automatikusan rögzítve' : ''}'
        '${note == null ? '' : ', megjegyzés: $note'}';
    return Semantics(
      container: true,
      button: onTap != null,
      onTap: onTap,
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
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                CategoryAvatar(transaction.categoryId),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (auto) ...[
                            Icon(
                              Icons.bolt_rounded,
                              size: 16,
                              color: colors.accentText,
                            ),
                            const SizedBox(width: 2),
                          ],
                          Flexible(
                            child: Text(
                              transaction.title,
                              maxLines: compact ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      if (compact) ...[
                        const SizedBox(height: Space.xs),
                        amount,
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[const SizedBox(width: Space.sm), amount],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
