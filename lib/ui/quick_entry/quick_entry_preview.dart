import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/categories.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../domain/quick_entry/interpreter.dart';
import '../../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';

/// Egy elvégzett gyorsrögzítés visszajelzése, visszavonással.
class QuickEntryDone {
  const QuickEntryDone(this.message, this.undo, {this.month});

  final String message;
  final Future<void> Function() undo;

  /// A rögzített tétel hónapja (ha nem az éppen látott hónap).
  final YearMonth? month;
}

/// A kérdés rövid szövege.
String questionLabel(QuickQuestion question) => switch (question) {
  QuickQuestion.amount => 'Mennyi?',
  QuickQuestion.what => 'Mire, hol?',
  QuickQuestion.when => 'Mikor?',
  QuickQuestion.type => 'Kiadás vagy bevétel?',
  QuickQuestion.frequency => 'Milyen gyakran?',
  QuickQuestion.which => 'Melyik ismétlődő tétel?',
};

/// A kérdésre adott (vagy alapértelmezett) válasz szövege.
String? questionAnswer(
  QuickQuestion question,
  QuickEntryResult result,
  CalendarDay today,
) {
  final answered = result.isAnswered(question);
  switch (question) {
    case QuickQuestion.amount:
      return answered ? formatForint(result.amount!) : null;
    case QuickQuestion.what:
      if (!answered) return null;
      return result.categoryGuessed
          ? result.title
          : '${result.title} · ${categoryName(result.categoryId)}';
    case QuickQuestion.when:
      final text = formatShortDate(result.date, today);
      return answered ? text : '$text, ha nem írod';
    case QuickQuestion.type:
      final text = result.type == EntryType.expense ? 'kiadás' : 'bevétel';
      return answered ? _capitalize(text) : '$text, ha nem írod';
    case QuickQuestion.frequency:
      if (result.frequency == null) return 'havonta, ha nem írod';
      final rule = result.toRecurringRule();
      return rule?.describe() ?? 'havonta';
    case QuickQuestion.which:
      return result.targetRule?.title;
  }
}

/// Mindig látható, halvány kérdéssor: mire kell válaszolni ahhoz, hogy a
/// tétel automatikusan elkönyvelhető legyen. A megválaszoltak kipipálva.
class QuestionHints extends StatelessWidget {
  const QuestionHints({super.key, required this.result, required this.today});

  /// Az értelmezés; üres szövegnél `null`.
  final QuickEntryResult? result;
  final CalendarDay today;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final current = result;
    final questions =
        current?.questions ??
        const [
          QuickQuestion.amount,
          QuickQuestion.what,
          QuickQuestion.when,
          QuickQuestion.type,
        ];
    final missing =
        current?.missing ?? const [QuickQuestion.amount, QuickQuestion.what];
    return Semantics(
      container: true,
      label: missing.isEmpty
          ? 'Minden megvan az automatikus könyveléshez.'
          : 'Az automatikus könyveléshez még kell: '
                '${missing.map(questionLabel).join(', ')}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            missing.isEmpty
                ? 'Minden megvan, mehet a könyvelés.'
                : 'Az automatikus könyveléshez ezekre kell válasz:',
            style: textTheme.labelMedium?.copyWith(
              color: colors.textMuted.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final question in questions)
                _HintPill(
                  key: ValueKey('hint-${question.name}'),
                  question: questionLabel(question),
                  answer: current == null
                      ? null
                      : questionAnswer(question, current, today),
                  done: current?.isAnswered(question) ?? false,
                  required: missing.contains(question),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({
    super.key,
    required this.question,
    required this.answer,
    required this.done,
    required this.required,
  });

  final String question;
  final String? answer;
  final bool done;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final faint = colors.textMuted.withValues(alpha: required ? 0.75 : 0.55);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: done
            ? colors.accent.withValues(alpha: 0.14)
            : colors.sunken.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: done
              ? colors.accent.withValues(alpha: 0.5)
              : colors.line.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 16,
            color: done ? colors.accentText : faint,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: question,
                    style: TextStyle(color: done ? colors.textMuted : faint),
                  ),
                  if (answer != null)
                    TextSpan(
                      text: ' $answer',
                      style: TextStyle(
                        color: done ? colors.text : faint,
                        fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                ],
              ),
              style: textTheme.labelMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Az értelmezés előnézete: mi fog történni a könyveléskor.
class QuickResultCard extends StatelessWidget {
  const QuickResultCard({super.key, required this.result, required this.today});

  final QuickEntryResult result;
  final CalendarDay today;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final target = result.targetRule;
    final (String heading, IconData icon) = switch (result.intent) {
      QuickIntent.record => (
        result.type == EntryType.expense ? 'Kiadás' : 'Bevétel',
        result.type == EntryType.expense
            ? Icons.north_east_rounded
            : Icons.south_west_rounded,
      ),
      QuickIntent.createRecurring => (
        'Új ismétlődő tétel',
        Icons.event_repeat_rounded,
      ),
      QuickIntent.cancelRecurring => (
        'Ismétlődő tétel lemondása',
        Icons.stop_circle_outlined,
      ),
      QuickIntent.changeRecurring => (
        'Ismétlődő tétel új összege',
        Icons.edit_calendar_rounded,
      ),
    };

    final details = <String>[];
    switch (result.intent) {
      case QuickIntent.record:
        details.add(formatFullDate(result.date));
      case QuickIntent.createRecurring:
        final rule = result.toRecurringRule();
        if (rule != null) {
          details.add(
            '${_capitalize(rule.describe())}, első: '
            '${formatShortDate(result.date, today)}',
          );
        }
      case QuickIntent.cancelRecurring:
        if (target != null) {
          details.add(
            '${_capitalize(target.describe())} · ${formatForint(target.amountOn(today))}'
            ' – mától nem rögzül többé.',
          );
        } else {
          details.add('Nem találom, melyik ismétlődő tételről van szó.');
        }
      case QuickIntent.changeRecurring:
        if (target != null) {
          details.add(
            'Eddig ${formatForint(target.amountOn(today))}, '
            '${formatFromDate(result.date, today)} az új összeg érvényes.',
          );
        }
    }

    final categoryId = target?.categoryId ?? result.categoryId;
    final title = result.title ?? 'Megnevezés nélkül';
    final showAmount =
        result.hasAmount && result.intent != QuickIntent.cancelRecurring;

    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '$heading: $title'
          '${showAmount ? ', ${formatForint(result.amount!)}' : ''}'
          ', ${categoryName(categoryId)}. ${details.join('. ')}'
          '${result.notes.isEmpty ? '' : '. ${result.notes.join('. ')}'}',
      excludeSemantics: true,
      child: Panel(
        key: const ValueKey('quick-result'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: colors.accentText),
                const SizedBox(width: 6),
                Text(
                  heading,
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.accentText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                CategoryAvatar(categoryId),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: result.hasWhat ? null : colors.textMuted,
                        ),
                      ),
                      Text(
                        categoryName(categoryId),
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showAmount) ...[
                  const SizedBox(width: Space.sm),
                  AmountText(
                    amount: result.amount!,
                    type: target?.type ?? result.type,
                  ),
                ],
              ],
            ),
            for (final detail in details) ...[
              const SizedBox(height: Space.sm),
              Text(
                detail,
                style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
              ),
            ],
            for (final note in result.notes) ...[
              const SizedBox(height: Space.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.text,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(note, style: textTheme.bodySmall)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A fő gomb felirata az értelmezés szerint.
String quickActionLabel(QuickEntryResult? result) {
  if (result == null) return 'Elkönyvelés';
  if (!result.isComplete) {
    return 'Még kell: ${result.missing.map(questionLabel).join(' ')}';
  }
  return switch (result.intent) {
    QuickIntent.record => 'Elkönyvelés',
    QuickIntent.createRecurring => 'Ismétlődő tétel létrehozása',
    QuickIntent.cancelRecurring => 'Lemondás',
    QuickIntent.changeRecurring => 'Új összeg mentése',
  };
}

/// Az értelmezés végrehajtása. `null`, ha nem volt mit tenni.
Future<QuickEntryDone?> applyQuickResult(
  AppState state,
  QuickEntryResult result,
) async {
  if (!result.isComplete) return null;
  final today = state.today();
  switch (result.intent) {
    case QuickIntent.record:
      final transaction = result.toTransaction();
      if (transaction == null) return null;
      // Gyorsrögzítésnél a kiválasztott (vagy alapértelmezett) számlára.
      final accountId = state.selectedAccountId ?? state.defaultAccount?.id;
      final saved = await state.saveTransaction(
        accountId == null
            ? transaction
            : transaction.copyWith(accountId: accountId),
      );
      final kind = saved.type == EntryType.expense ? 'Kiadás' : 'Bevétel';
      final month = YearMonth.of(saved.date);
      return QuickEntryDone(
        '$kind rögzítve: ${saved.title}, ${formatForint(saved.amount)}'
        '${saved.date == today ? '' : ' (${formatShortDate(saved.date, today)})'}',
        () => state.deleteTransaction(saved.id!),
        month: month == state.selectedMonth ? null : month,
      );
    case QuickIntent.createRecurring:
      final rule = result.toRecurringRule(
        reminder: state.reminderDefaults.newRuleSettings(
          enabled: result.type == EntryType.expense,
        ),
      );
      if (rule == null) return null;
      final before = {for (final t in state.transactions) t.id};
      final ruleAccount = state.selectedAccountId ?? state.defaultAccount?.id;
      final saved = await state.saveRule(
        ruleAccount == null ? rule : rule.copyWith(accountId: ruleAccount),
      );
      final booked = [
        for (final t in state.transactions)
          if (t.recurringId == saved.id && !before.contains(t.id)) t,
      ];
      return QuickEntryDone(
        '${saved.title}: ${saved.describe()}, ${formatForint(saved.amount)}'
        '${booked.isEmpty ? '' : ' – a mai is rögzítve'}',
        () async {
          for (final transaction in booked) {
            await state.deleteTransaction(transaction.id!);
          }
          await state.deleteRule(saved.id!);
        },
      );
    case QuickIntent.cancelRecurring:
      final target = result.targetRule;
      if (target == null) return null;
      await state.endRule(target);
      return QuickEntryDone(
        '${target.title} lemondva',
        () => state.restoreRule(target),
      );
    case QuickIntent.changeRecurring:
      final target = result.targetRule;
      if (target == null || !result.hasAmount) return null;
      await state.changeRuleAmount(
        target,
        amount: result.amount!,
        from: result.date,
      );
      return QuickEntryDone(
        '${target.title}: ${formatForint(result.amount!)} '
        '${formatFromDate(result.date, today)}',
        () => state.restoreRule(target),
      );
  }
}

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
