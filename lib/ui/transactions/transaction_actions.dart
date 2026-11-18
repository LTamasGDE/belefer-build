import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../state/app_scope.dart';
import 'transaction_form_screen.dart';

/// Megnyitja a tételűrlapot, és visszajelzést ad a mentésről vagy törlésről.
/// Igaz, ha mentés vagy törlés történt.
Future<bool> openTransactionForm(
  BuildContext context, {
  Transaction? existing,
  EntryType initialType = EntryType.expense,
  EntryTemplate? template,
  TransactionDraft? prefill,
}) async {
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final result = await Navigator.of(context).push<TransactionFormResult>(
    MaterialPageRoute(
      fullscreenDialog: existing == null,
      builder: (_) => TransactionFormScreen(
        existing: existing,
        initialType: initialType,
        template: template,
        prefill: prefill,
      ),
    ),
  );
  if (result == null) return false;

  final transaction = result.transaction;
  messenger.hideCurrentSnackBar();
  if (result.outcome == TransactionFormOutcome.deleted) {
    messenger.showSnackBar(const SnackBar(content: Text('Tétel törölve')));
    return true;
  }

  final kind = transaction.type == EntryType.expense ? 'Kiadás' : 'Bevétel';
  final month = YearMonth.of(transaction.date);
  final otherMonth = month != state.selectedMonth;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        otherMonth ? '$kind mentve: ${formatYearMonth(month)}' : '$kind mentve',
      ),
      action: otherMonth
          ? SnackBarAction(
              label: 'Megnézem',
              onPressed: () => state.showMonth(month),
            )
          : null,
    ),
  );
  return true;
}
