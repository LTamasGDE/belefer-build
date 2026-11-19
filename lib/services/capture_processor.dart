import '../domain/accounts.dart';
import '../domain/capture/captured_event.dart';
import '../domain/models.dart';
import '../domain/quick_entry/interpreter.dart';
import '../domain/text_fold.dart';
import 'exchange_rates.dart';

/// Döntés egy beérkezett eseményről.
class CaptureDecision {
  const CaptureDecision({
    required this.outcome,
    required this.log,
    this.transaction,
  });

  final CaptureOutcome outcome;

  /// Rögzítendő tétel ([CaptureOutcome.booked] esetén).
  final Transaction? transaction;

  /// A naplóbejegyzés (a tétel azonosítója mentés után kerül bele).
  final CaptureLogEntry log;
}

/// A Revolut-értesítések és az Apple Pay-fizetések feldolgozása a telefonon
/// (a saját modellel és a szabályalapú értelmezővel): a sikertelen
/// fizetések, a saját számlák közötti mozgások és az ismétlődő értesítések
/// kiszűrésével, számla-hozzárendeléssel, devizás összeg átváltásával.
class CaptureProcessor {
  const CaptureProcessor({required this.rates, required this.accounts});

  final ExchangeRates rates;
  final List<Account> accounts;

  /// Ennyi időn belül az azonos összegű, azonos kereskedőjű esemény
  /// ugyanannak számít (pl. elutasított, majd megismételt Apple Pay).
  static const Duration duplicateWindow = Duration(minutes: 10);

  Future<CaptureDecision> decide(
    CapturedEvent event,
    QuickEntryContext context, {
    required List<CaptureLogEntry> recent,
  }) async {
    final reading = classifyOffline(event, context);
    var result = reading.result;
    final notes = <String>[...result.notes];
    if (event.source == CaptureSource.applePay &&
        event.amountText != null &&
        reading.currency == 'HUF') {
      final huf = parseHufAmount(event.amountText!);
      if (huf != null) result = _withAmount(result, huf);
    }

    // Devizás összeg: átváltás a napi árfolyamon.
    String? conversionProblem;
    if (reading.currency != 'HUF') {
      result = _withAmount(result, null);
      final foreign = reading.foreignAmount;
      if (foreign != null) {
        final rate = await rates.hufPer(reading.currency);
        if (rate != null) {
          final huf = (foreign * rate).round();
          result = _withAmount(result, huf);
          notes.add(currencyNote(foreign, reading.currency, huf));
        } else {
          conversionProblem =
              'Nem sikerült átváltani: ${foreign.toStringAsFixed(2)} '
              '${reading.currency}. Rögzítsd kézzel forintban.';
        }
      }
    }

    final merchantKey = foldForMatching(result.title ?? event.merchant ?? '');
    CaptureLogEntry log(CaptureOutcome outcome, String detail) =>
        CaptureLogEntry(
          time: event.receivedAt,
          source: event.source,
          raw: event.description,
          outcome: outcome,
          detail: detail,
          amount: result.amount,
          merchantKey: merchantKey,
        );

    switch (reading.status) {
      case 'failed':
        return CaptureDecision(
          outcome: CaptureOutcome.failed,
          log: log(CaptureOutcome.failed, _detail(result)),
        );
      case 'internal_transfer':
        return CaptureDecision(
          outcome: CaptureOutcome.transfer,
          log: log(CaptureOutcome.transfer, _detail(result)),
        );
      case 'not_a_transaction':
        return CaptureDecision(
          outcome: CaptureOutcome.ignored,
          log: log(CaptureOutcome.ignored, ''),
        );
    }

    if (!result.hasAmount) {
      return CaptureDecision(
        outcome: CaptureOutcome.unclear,
        log: log(
          CaptureOutcome.unclear,
          conversionProblem ?? 'Rögzítsd kézzel, ha valódi fizetés volt.',
        ),
      );
    }

    // Apple Pay: elutasított, majd megismételt fizetés ugyanannak számít
    // (az automatizmus az elutasított érintésnél is elindul).
    for (final previous in event.source == CaptureSource.applePay
        ? recent
        : const <CaptureLogEntry>[]) {
      if (previous.source == event.source &&
          previous.amount == result.amount &&
          previous.merchantKey == merchantKey &&
          previous.outcome == CaptureOutcome.booked &&
          previous.time.difference(event.receivedAt).abs() <= duplicateWindow) {
        return CaptureDecision(
          outcome: CaptureOutcome.duplicate,
          log: log(CaptureOutcome.duplicate, _detail(result)),
        );
      }
    }

    final account = matchAccount(accounts, event.accountText);
    final title = (result.title ?? event.merchant ?? event.source.label).trim();
    final noteParts = [
      event.source.label,
      if (event.card != null) event.card!,
      ...notes,
    ];
    final transaction = Transaction(
      type: result.type,
      title: title.length > 40 ? title.substring(0, 40).trim() : title,
      amount: result.amount!,
      categoryId: result.categoryId,
      date: event.day,
      note: noteParts.join(' · '),
      accountId: account?.id,
      source: event.source.storageKey,
    );
    return CaptureDecision(
      outcome: CaptureOutcome.booked,
      transaction: transaction,
      log: log(
        CaptureOutcome.booked,
        '${_detail(result)}${account == null ? '' : ' · ${account.name}'}',
      ),
    );
  }
}

/// Megjegyzés a devizás összeg átváltásáról.
String currencyNote(double amount, String currency, int huf) =>
    'Eredetileg ${amount.toStringAsFixed(2).replaceAll('.', ',')} $currency '
    '(≈ $huf Ft, napi árfolyamon)';

String _detail(QuickEntryResult result) => [
  ?result.title,
  if (result.amount != null) '${result.amount} Ft',
].join(', ');

QuickEntryResult _withAmount(QuickEntryResult result, int? amount) =>
    QuickEntryResult(
      intent: result.intent,
      type: result.type,
      typeExplicit: result.typeExplicit,
      amount: amount,
      title: result.title,
      merchant: result.merchant,
      categoryId: result.categoryId,
      categoryGuessed: result.categoryGuessed,
      date: result.date,
      dateExplicit: result.dateExplicit,
      frequency: result.frequency,
      interval: result.interval,
      targetRule: result.targetRule,
      notes: result.notes,
    );
