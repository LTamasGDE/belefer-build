import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../domain/recurring.dart';
import '../../state/app_scope.dart';
import '../entry_form/amount_input_formatter.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import 'recurring_form_screen.dart';

/// Megnyitja az ismétlődő tétel űrlapját, és visszajelzést ad.
/// Igaz, ha mentés történt.
Future<bool> openRecurringForm(
  BuildContext context, {
  RecurringRule? existing,
  RecurringRule? prefill,
  bool prefillHasAmount = true,
}) async {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final state = AppScope.read(context);
  final before = state.transactions.length;
  final saved = await Navigator.of(context).push<RecurringRule>(
    MaterialPageRoute(
      fullscreenDialog: existing == null,
      builder: (_) => RecurringFormScreen(
        existing: existing,
        prefill: prefill,
        prefillHasAmount: prefillHasAmount,
      ),
    ),
  );
  if (saved == null) return false;
  final booked = state.transactions.length - before;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        booked > 0
            ? '${saved.title} mentve, $booked tétel rögzítve'
            : '${saved.title} mentve',
      ),
    ),
  );
  return true;
}

/// Az összeg havi átlagban (a fejléc összesítőjéhez).
int monthlyEquivalent(RecurringRule rule, CalendarDay today) {
  final amount = rule.amountOn(today);
  return switch (rule.frequency) {
    Frequency.weekly => (amount * 52 / 12 / rule.interval).round(),
    Frequency.monthly => (amount / rule.interval).round(),
    Frequency.yearly => (amount / 12 / rule.interval).round(),
  };
}

/// Az ismétlődő tételek lapja: jóváhagyásra várók, aktívak és lezártak.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  bool _showEnded = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final today = state.today();
    final pending = state.pending;
    final active = [...state.activeRules]
      ..sort((a, b) {
        final nextA = a.nextOccurrence(today);
        final nextB = b.nextOccurrence(today);
        if (nextA == null || nextB == null) {
          return nextA == null ? 1 : -1;
        }
        return nextA.compareTo(nextB);
      });
    final ended = state.endedRules;

    final children = <Widget>[];
    if (pending.isNotEmpty) {
      children
        ..add(const SectionTitle('Jóváhagyásra vár'))
        ..addAll([
          for (final occurrence in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: PendingCard(occurrence: occurrence),
            ),
        ]);
    }

    if (active.isEmpty && ended.isEmpty) {
      children.add(
        EmptyState(
          icon: Icons.event_repeat_rounded,
          title: 'Még nincs ismétlődő tétel',
          message:
              'A lakbért, a fizetést vagy az előfizetéseket egyszer kell '
              'felvenned, utána esedékességkor maguktól rögzülnek. '
              'Gyorsrögzítéssel is megy: „Netflix havi 4990”.',
          actions: [
            FilledButton.icon(
              onPressed: () => openRecurringForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Új ismétlődő tétel'),
            ),
          ],
        ),
      );
    } else {
      var monthlyExpense = 0;
      var monthlyIncome = 0;
      for (final rule in active) {
        final value = monthlyEquivalent(rule, today);
        if (rule.type == EntryType.expense) {
          monthlyExpense += value;
        } else {
          monthlyIncome += value;
        }
      }
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, 0),
          child: Text(
            'Havonta átlagosan ${formatForint(monthlyIncome)} bevétel és '
            '${formatForint(monthlyExpense)} kiadás ismétlődik.',
            key: const ValueKey('recurring-totals'),
            style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
          ),
        ),
      );
      if (active.isNotEmpty) {
        children.add(const SectionTitle('Aktív'));
        for (final rule in active) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: RecurringTile(
                rule: rule,
                onTap: () => openRecurringForm(context, existing: rule),
              ),
            ),
          );
        }
      }
      if (ended.isNotEmpty) {
        children.add(
          SectionTitle(
            'Lemondott (${ended.length})',
            trailing: TextButton(
              onPressed: () => setState(() => _showEnded = !_showEnded),
              child: Text(_showEnded ? 'Elrejtés' : 'Mutasd'),
            ),
          ),
        );
        if (_showEnded) {
          for (final rule in ended) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: RecurringTile(
                  rule: rule,
                  onTap: () => openRecurringForm(context, existing: rule),
                ),
              ),
            );
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ismétlődő tételek')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-recurring',
        onPressed: () => openRecurringForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Új ismétlődő'),
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

/// Egy ismétlődő tétel sora: mikor esedékes legközelebb és mennyi.
class RecurringTile extends StatelessWidget {
  const RecurringTile({super.key, required this.rule, this.onTap});

  final RecurringRule rule;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final today = state.today();
    final ended = rule.isEndedOn(today);
    final next = ended ? null : rule.nextOccurrence(today);
    final amount = rule.amountOn(next ?? today);
    final detail = [
      rule.describe(),
      if (next != null) 'következő: ${formatShortDate(next, today)}',
      if (ended) 'lemondva',
    ].join(' · ');
    final semantic =
        '${rule.title}, ${formatForint(amount)}, $detail'
        '${rule.reminder.enabled ? ', emlékeztetővel' : ''}'
        '${rule.autoBook ? '' : ', jóváhagyással'}';
    return Semantics(
      container: true,
      button: onTap != null,
      onTap: onTap,
      label: semantic,
      excludeSemantics: true,
      child: Opacity(
        opacity: ended ? 0.6 : 1,
        child: Panel(
          padding: EdgeInsets.zero,
          radius: 20,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                children: [
                  CategoryAvatar(rule.categoryId),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                rule.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium,
                              ),
                            ),
                            if (rule.reminder.enabled) ...[
                              const SizedBox(width: Space.xs),
                              Icon(
                                Icons.notifications_active_outlined,
                                size: 16,
                                color: colors.textMuted,
                              ),
                            ],
                            if (!rule.autoBook) ...[
                              const SizedBox(width: Space.xs),
                              Icon(
                                Icons.back_hand_outlined,
                                size: 16,
                                color: colors.textMuted,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  AmountText(amount: amount, type: rule.type),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Jóváhagyásra váró esedékesség: rögzítés (módosítható összeggel) vagy
/// kihagyás.
class PendingCard extends StatelessWidget {
  const PendingCard({super.key, required this.occurrence});

  final PendingOccurrence occurrence;

  Future<void> _book(BuildContext context, {bool edit = false}) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    int? amount;
    if (edit) {
      amount = await _askAmount(context, occurrence.amount);
      if (amount == null) return;
    }
    final saved = await state.bookPending(occurrence, amount: amount);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${occurrence.rule.title} rögzítve: '
            '${formatForint(saved?.amount ?? occurrence.amount)}',
          ),
        ),
      );
  }

  Future<int?> _askAmount(BuildContext context, int initial) {
    final controller = TextEditingController(
      text: AmountInputFormatter.format('$initial'),
    );
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final value = int.tryParse(
            controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
          );
          if (value != null && value > 0) {
            Navigator.of(dialogContext).pop(value);
          }
        }

        return AlertDialog(
          title: Text(occurrence.rule.title),
          content: TextField(
            key: const ValueKey('pending-amount'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [AmountInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Összeg',
              suffixText: 'Ft',
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Mégse'),
            ),
            FilledButton(onPressed: submit, child: const Text('Rögzítés')),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final rule = occurrence.rule;
    final when = formatShortDate(occurrence.date, state.today());
    return Panel(
      padding: const EdgeInsets.all(Space.md),
      color: colors.accent.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar(rule.categoryId, size: 40),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.title, style: textTheme.titleMedium),
                    Text(
                      'Esedékes: $when',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AmountText(amount: occurrence.amount, type: rule.type),
            ],
          ),
          const SizedBox(height: Space.sm),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: Space.xs,
            children: [
              TextButton(
                onPressed: () => state.skipPending(occurrence),
                child: const Text('Kihagyás'),
              ),
              IconButton(
                tooltip: 'Rögzítés más összeggel',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => _book(context, edit: true),
              ),
              FilledButton(
                key: ValueKey('book-pending-${rule.id}'),
                onPressed: () => _book(context),
                child: const Text('Rögzítés'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
