import '../domain/accounts.dart';
import '../domain/ai/ai_prompt.dart';
import '../domain/capture/captured_event.dart';
import '../domain/models.dart';
import '../domain/quick_entry/interpreter.dart';
import '../domain/text_fold.dart';
import 'ai_interpreter.dart';

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

/// A Revolut-értesítések és az Apple Pay-fizetések feldolgozása: AI-val
/// (ha elérhető), különben a beépített besorolással; a sikertelen fizetések,
/// a saját számlák közötti mozgások és az ismétlődő értesítések kiszűrésével,
/// számla-hozzárendeléssel.
class CaptureProcessor {
  const CaptureProcessor({required this.interpreter, required this.accounts});

  final AiInterpreter interpreter;
  final List<Account> accounts;

  /// Ennyi időn belül az azonos összegű, azonos kereskedőjű esemény
  /// ugyanannak számít (pl. elutasított, majd megismételt Apple Pay).
  static const Duration duplicateWindow = Duration(minutes: 10);

  Future<CaptureDecision> decide(
    CapturedEvent event,
    QuickEntryContext context, {
    required List<CaptureLogEntry> recent,
  }) async {
    final offline = classifyOffline(event, context);
    final kind = event.source == CaptureSource.applePay
        ? AiInputKind.applePay
        : AiInputKind.notification;

    var fallback = offline.result;
    if (event.source == CaptureSource.applePay && event.amountText != null) {
      final huf = offline.currency == 'HUF'
          ? parseHufAmount(event.amountText!)
          : null;
      if (huf != null) fallback = _withAmount(fallback, huf);
    }
    if (offline.currency != 'HUF') fallback = _withAmount(fallback, null);

    final outcome = await interpreter.interpret(
      event.description,
      kind,
      context,
      fallback: fallback,
    );
    var status = outcome.usedAi ? outcome.status : offline.status;
    var result = outcome.result;
    final notes = <String>[...result.notes];

    // Devizás összeg AI nélkül: átváltás a beépített felismerés alapján.
    if (!outcome.usedAi &&
        offline.currency != 'HUF' &&
        offline.foreignAmount != null) {
      final rate = await interpreter.rates.hufPer(offline.currency);
      if (rate != null) {
        final huf = (offline.foreignAmount! * rate).round();
        result = _withAmount(result, huf);
        notes.add(currencyNote(offline.foreignAmount!, offline.currency, huf));
      }
    }
    if (event.source == CaptureSource.applePay && status != 'failed') {
      status = 'ok';
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

    switch (status) {
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
          outcome.error ?? 'Rögzítsd kézzel, ha valódi fizetés volt.',
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

    final hint = outcome.reading?.accountHint;
    final account = matchAccount(
      accounts,
      [event.accountText, ?hint].join(' '),
    );
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
        '${_detail(result)}${account == null ? '' : ' · ${account.name}'}'
        '${outcome.usedAi ? ' · AI' : ''}',
      ),
    );
  }
}

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
      fromAi: result.fromAi,
    );
