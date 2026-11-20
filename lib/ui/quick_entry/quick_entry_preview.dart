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

  /// Visszavonás; `null`, ha nem történt változás (pl. átvezetésnél).
  final Future<void> Function()? undo;

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
      if (!answered) return null;
      if (result.hasAmount) {
        return '${formatForint(result.amount!)}'
            '${result.amountFromHabit ? ' (szokásos)' : ''}';
      }
      return formatForeign(result.foreignAmount!, result.currency!);
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
    final guessed = current?.guessed ?? const <QuickQuestion>{};
    final String headline;
    if (current?.intent == QuickIntent.question) {
      return const SizedBox.shrink();
    } else if (current?.intent == QuickIntent.transfer) {
      headline =
          'Saját pénzed mozgatása: nem bevétel és nem kiadás, ezért nem '
          'könyvelem.';
    } else if (current != null && current.isMultiple) {
      headline = current.isSure
          ? '${current.items.length} tételt találtam, mehet a könyvelés.'
          : '${current.items.length} tételt találtam – nézd át őket.';
    } else if (missing.isNotEmpty) {
      headline = 'Az automatikus könyveléshez ezekre kell válasz:';
    } else if (guessed.length == 1 &&
        guessed.contains(QuickQuestion.amount) &&
        current!.amountFromHabit) {
      headline =
          'A szokásos összeget írtam be – ha most más volt, írd hozzá.';
    } else if (guessed.isNotEmpty) {
      headline =
          'Ellenőrizd: ${guessed.map(questionLabel).join(' ')} – erre csak '
          'tippelni tudtam.';
    } else {
      headline = 'Minden megvan, mehet a könyvelés.';
    }
    final showPills =
        current == null ||
        (!current.isMultiple && current.intent != QuickIntent.transfer);
    return Semantics(
      container: true,
      label: headline,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: textTheme.labelMedium?.copyWith(
              color: colors.textMuted.withValues(alpha: 0.8),
            ),
          ),
          if (showPills) ...[
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
                    guess: guessed.contains(question),
                  ),
              ],
            ),
          ],
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
    this.guess = false,
  });

  final String question;
  final String? answer;
  final bool done;
  final bool required;

  /// Csak tipp: kérdőjellel, hogy érdemes ellenőrizni.
  final bool guess;

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
            guess && done
                ? Icons.help_rounded
                : done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
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
                      text:
                          ' $answer'
                          '${guess && done && !answer!.endsWith(')') ? ' (tipp)' : ''}',
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
  const QuickResultCard({
    super.key,
    required this.result,
    required this.today,
    this.accountName,
  });

  final QuickEntryResult result;
  final CalendarDay today;

  /// A szövegben megnevezett számla neve („a közösről” → Közös).
  final String? Function(int id)? accountName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    if (result.intent == QuickIntent.question) {
      return _AnswerCard(answer: result.answer ?? '');
    }
    if (result.intent == QuickIntent.transfer) {
      return _TransferCard(result: result);
    }
    if (result.isMultiple) {
      return _MultiCard(result: result, today: today);
    }
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
      QuickIntent.transfer => ('Átvezetés', Icons.swap_horiz_rounded),
      QuickIntent.question => ('Válasz', Icons.question_answer_rounded),
    };

    final details = <String>[];
    switch (result.intent) {
      case QuickIntent.record:
        details.add(formatFullDate(result.date));
        final account = result.accountId == null
            ? null
            : accountName?.call(result.accountId!);
        if (account != null) {
          details.add(
            'Számla: $account${result.accountFromHabit ? ' (szokásos)' : ''}',
          );
        }
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
      case QuickIntent.transfer || QuickIntent.question:
        break;
    }
    if (!result.hasAmount && result.currency != null) {
      details.add(
        '${formatForeign(result.foreignAmount!, result.currency!)} – '
        'forintra váltom a napi EKB-árfolyamon…',
      );
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
    if (result.missing.isEmpty) return 'Átváltás…';
    return 'Még kell: ${result.missing.map(questionLabel).join(' ')}';
  }
  if (result.isMultiple) return '${result.items.length} tétel elkönyvelése';
  return switch (result.intent) {
    QuickIntent.record => 'Elkönyvelés',
    QuickIntent.createRecurring => 'Ismétlődő tétel létrehozása',
    QuickIntent.cancelRecurring => 'Lemondás',
    QuickIntent.changeRecurring => 'Új összeg mentése',
    QuickIntent.transfer => 'Rendben, nem könyvelem',
    QuickIntent.question => 'Bezárás',
  };
}

/// Devizás összeg: „25 €”, „30 USD”.
String formatForeign(double amount, String currency) {
  final number = amount == amount.roundToDouble()
      ? groupDigits(amount.round())
      : amount.toStringAsFixed(2).replaceAll('.', ',');
  final symbol = switch (currency) {
    'EUR' => '€',
    'USD' => r'$',
    'GBP' => '£',
    _ => currency,
  };
  return '$number$nbsp$symbol';
}

/// Az értelmezés végrehajtása. `null`, ha nem volt mit tenni.
///
/// A [text] a beírt mondat: a könyvelt tételből lecke lesz, így legközelebb
/// ugyanígy érti.
Future<QuickEntryDone?> applyQuickResult(
  AppState state,
  QuickEntryResult result, {
  String? text,
}) async {
  if (!result.isComplete) return null;
  final today = state.today();
  if (result.isMultiple) {
    final saved = <Transaction>[];
    for (final transaction in result.toTransactions()) {
      final accountId =
          transaction.accountId ??
          state.selectedAccountId ??
          state.defaultAccount?.id;
      saved.add(
        await state.saveTransaction(transaction.copyWith(accountId: accountId)),
      );
    }
    if (saved.isEmpty) return null;
    final total = saved.fold<int>(0, (sum, t) => sum + t.amount);
    return QuickEntryDone(
      '${saved.length} tétel rögzítve, összesen ${formatForint(total)}',
      () async {
        for (final transaction in saved) {
          await state.deleteTransaction(transaction.id!);
        }
      },
    );
  }
  switch (result.intent) {
    case QuickIntent.transfer:
      return const QuickEntryDone(
        'Átvezetés – nem könyveltem, mert nem bevétel és nem kiadás.',
        null,
      );
    case QuickIntent.question:
      return null;
    case QuickIntent.record:
      final transaction = result.toTransaction();
      if (transaction == null) return null;
      // A szövegben megnevezett, a kiválasztott vagy az alapértelmezett
      // számlára.
      final accountId =
          result.accountId ??
          state.selectedAccountId ??
          state.defaultAccount?.id;
      final saved = await state.saveTransaction(
        accountId == null
            ? transaction
            : transaction.copyWith(accountId: accountId),
      );
      if (text != null) await state.learnFrom(text, saved);
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

/// Válasz egy kérdésre („mennyit költöttem ebben a hónapban?”).
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});

  final String answer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Válasz: $answer',
      excludeSemantics: true,
      child: Panel(
        key: const ValueKey('quick-result'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.question_answer_rounded,
                  size: 16,
                  color: colors.accentText,
                ),
                const SizedBox(width: 6),
                Text(
                  'Válasz',
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.accentText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Text(answer, style: textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Saját számlák közötti átvezetés: honnan hová, mennyi – nem könyveljük.
class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.result});

  final QuickEntryResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final from = result.transferFrom;
    final to = result.transferTo;
    final route = from != null && to != null
        ? '$from → $to'
        : to != null
        ? 'Ide: $to'
        : from != null
        ? 'Innen: $from'
        : 'Saját számlák között';
    final amount = result.hasAmount
        ? formatForint(result.amount!)
        : result.currency != null
        ? formatForeign(result.foreignAmount!, result.currency!)
        : null;
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          'Átvezetés: $route${amount == null ? '' : ', $amount'}. '
          'Nem bevétel és nem kiadás, nem kerül a tételek közé.',
      excludeSemantics: true,
      child: Panel(
        key: const ValueKey('quick-result'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 16,
                  color: colors.accentText,
                ),
                const SizedBox(width: 6),
                Text(
                  'Átvezetés',
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.accentText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(child: Text(route, style: textTheme.titleMedium)),
                if (amount != null) Text(amount, style: textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              'A saját pénzed egyik helyről a másikra került: ez nem bevétel '
              'és nem kiadás, ezért nem kerül a tételek közé, és a havi '
              'egyenlegedet sem változtatja. Ha mégis tételként szeretnéd, '
              'add meg az űrlapon.',
              style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Több tétel egy mondatban.
class _MultiCard extends StatelessWidget {
  const _MultiCard({required this.result, required this.today});

  final QuickEntryResult result;
  final CalendarDay today;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${result.items.length} tétel: '
          '${result.items.map((item) => '${item.title}, ${formatForint(item.amount!)}').join('; ')}',
      excludeSemantics: true,
      child: Panel(
        key: const ValueKey('quick-result'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.playlist_add_check_rounded,
                  size: 16,
                  color: colors.accentText,
                ),
                const SizedBox(width: 6),
                Text(
                  '${result.items.length} tétel',
                  style: textTheme.labelLarge?.copyWith(
                    color: colors.accentText,
                  ),
                ),
              ],
            ),
            for (final item in result.items) ...[
              const SizedBox(height: Space.md),
              Row(
                children: [
                  CategoryAvatar(item.categoryId),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.title}${item.isSure ? '' : ' (tipp)'}',
                          style: textTheme.titleMedium,
                        ),
                        Text(
                          '${categoryName(item.categoryId)} · '
                          '${formatShortDate(item.date, today)}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AmountText(amount: item.amount!, type: item.type),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
