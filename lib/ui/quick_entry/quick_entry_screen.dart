import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../domain/quick_entry/interpreter.dart';
import '../../domain/recurring.dart';
import '../../services/platform_services.dart';
import '../../state/app_scope.dart';
import '../recurring/recurring_screen.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../transactions/transaction_actions.dart';
import '../transactions/transaction_form_screen.dart';
import '../widgets/common.dart';
import 'quick_entry_preview.dart';
import 'receipt_review_screen.dart';

/// Példamondatok (koppintásra beíródnak).
const List<String> quickEntryExamples = [
  'Lidl 12 450',
  'tegnap kávé 890',
  'megjött a fizetés 420e',
  'Netflix havi 4990',
  'lemondtam a Spotifyt',
  'mostantól 190 ezer a lakbér',
];

/// Megnyitja a gyorsrögzítést, és a könyvelés után visszavonható
/// visszajelzést ad.
Future<void> openQuickEntry(BuildContext context, {ReceiptSource? scan}) async {
  final state = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final done = await Navigator.of(context).push<QuickEntryDone>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => QuickEntryScreen(startScan: scan),
    ),
  );
  if (done == null) return;
  if (done.month != null) state.showMonth(done.month!);
  showQuickEntryDone(messenger, done);
}

/// A könyvelés visszajelzése „Visszavonás” gombbal.
void showQuickEntryDone(ScaffoldMessengerState messenger, QuickEntryDone done) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(done.message),
        duration: const Duration(seconds: 6),
        action: done.undo == null
            ? null
            : SnackBarAction(
                label: 'Visszavonás',
                onPressed: () {
                  done.undo!();
                },
              ),
      ),
    );
}

/// Gyorsrögzítés: egy mondatból kiadás, bevétel vagy ismétlődő tétel.
class QuickEntryScreen extends StatefulWidget {
  const QuickEntryScreen({super.key, this.startScan, this.initialText = ''});

  /// Ha meg van adva, megnyitáskor rögtön blokkbeolvasás indul.
  final ReceiptSource? startScan;
  final String initialText;

  @override
  State<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends State<QuickEntryScreen> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  QuickEntryResult? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
    _text.addListener(_interpret);
    _interpret();
    final scan = widget.startScan;
    if (scan != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan(scan));
    }
  }

  @override
  void dispose() {
    _text.removeListener(_interpret);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _interpret() {
    final text = _text.text.trim();
    final state = AppScope.read(context);
    final result = text.isEmpty
        ? null
        : interpretQuickEntry(text, state.quickEntryContext);
    setState(() => _result = result);
    // Devizás összeg: forintra váltás a napi árfolyamon.
    if (result != null &&
        !result.hasAmount &&
        result.currency != null &&
        result.foreignAmount != null) {
      final currency = result.currency!;
      final foreign = result.foreignAmount!;
      state.toForint(foreign, currency).then((value) {
        if (!mounted || _result != result) return;
        setState(() {
          _result = value == null
              ? result
              : result.withAmount(
                  value,
                  note:
                      '${formatForeign(foreign, currency)} ≈ '
                      '${formatForint(value)} (EKB napi árfolyam)',
                );
        });
        if (value == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Most nem érem el az árfolyamot – írd be a forintösszeget.',
              ),
            ),
          );
        }
      });
    }
  }

  Future<void> _submit() async {
    final result = _result;
    if (_busy || result == null) return;
    if (result.intent == QuickIntent.question) {
      Navigator.of(context).maybePop();
      return;
    }
    if (!result.isComplete) {
      _focus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    final done = await applyQuickResult(AppScope.read(context), result);
    if (!mounted) return;
    if (done == null) {
      setState(() => _busy = false);
      return;
    }
    Navigator.of(context).pop(done);
  }

  /// Részletes űrlap a felismert adatokkal; mentés után a gyorsrögzítés is
  /// bezárul.
  Future<void> _openDetails() async {
    final result = _result;
    if (result == null) return;
    final navigator = Navigator.of(context);
    final state = AppScope.read(context);
    final bool saved;
    if (result.intent == QuickIntent.createRecurring) {
      saved = await openRecurringForm(
        context,
        prefillHasAmount: result.hasAmount,
        prefill: RecurringRule(
          type: result.type,
          title: result.title ?? '',
          categoryId: result.categoryId,
          amount: result.amount ?? 1,
          frequency: result.frequency ?? Frequency.monthly,
          interval: result.interval,
          startDate: result.date,
          reminder: state.reminderDefaults.newRuleSettings(
            enabled: result.type == EntryType.expense,
          ),
        ),
      );
    } else if (result.intent == QuickIntent.transfer) {
      final route = [?result.transferFrom, ?result.transferTo].join(' → ');
      saved = await openTransactionForm(
        context,
        initialType: EntryType.expense,
        prefill: TransactionDraft(
          type: EntryType.expense,
          date: result.date,
          title: route.isEmpty ? 'Átvezetés' : 'Átvezetés: $route',
          amount: result.amount,
        ),
      );
    } else {
      saved = await openTransactionForm(
        context,
        initialType: result.type,
        prefill: TransactionDraft(
          type: result.type,
          date: result.date,
          title: result.title ?? '',
          amount: result.amount,
          categoryId: result.categoryGuessed ? null : result.categoryId,
        ),
      );
    }
    if (saved && mounted) navigator.pop();
  }

  Future<void> _scan(ReceiptSource source) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final capture = await Services.receiptScanner.capture(source);
      if (!mounted) return;
      setState(() => _busy = false);
      if (capture == null) return;
      final done = await navigator.push<QuickEntryDone>(
        MaterialPageRoute(
          builder: (_) => ReceiptReviewScreen(capture: capture),
        ),
      );
      if (done != null && mounted) navigator.pop(done);
    } on ReceiptScanException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error, stack) {
      // A valódi okot is megmutatjuk (és a naplóba írjuk), ne csak tippeljünk.
      debugPrint('Blokkbeolvasási hiba: $error\n$stack');
      if (!mounted) return;
      setState(() => _busy = false);
      final detail = switch (error) {
        PlatformException(:final code, :final message) =>
          '$code${message == null ? '' : ': $message'}',
        _ => error.toString(),
      };
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Nem sikerült beolvasni a szöveget. (${detail.length > 160 ? '${detail.substring(0, 160)}…' : detail})',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final result = _result;
    final today = state.today();
    final complete = result?.isComplete ?? false;
    final canOpenDetails =
        result != null &&
        !result.isMultiple &&
        (result.intent == QuickIntent.record ||
            result.intent == QuickIntent.createRecurring ||
            result.intent == QuickIntent.transfer);
    String? accountName(int id) {
      for (final account in state.accounts) {
        if (account.id == id) return account.name;
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Bezárás',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Gyorsrögzítés'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxl,
          ),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('quick-entry-field'),
                    controller: _text,
                    focusNode: _focus,
                    autofocus: widget.startScan == null,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: textTheme.titleLarge,
                    decoration: InputDecoration(
                      labelText: 'Mit rögzítsek?',
                      hintText: 'Pl. Lidl 4500 tegnap',
                      counterText: '',
                      prefixIcon: Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.accentText,
                      ),
                      suffixIcon: _text.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Törlés',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _text.clear,
                            ),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  QuestionHints(result: result, today: today),
                  if (result != null) ...[
                    const SizedBox(height: Space.lg),
                    QuickResultCard(
                      result: result,
                      today: today,
                      accountName: accountName,
                    ),
                  ],
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    key: const ValueKey('quick-entry-submit'),
                    onPressed: complete && !_busy ? _submit : null,
                    icon: Icon(
                      result?.intent == QuickIntent.transfer
                          ? Icons.swap_horiz_rounded
                          : complete
                          ? Icons.check_rounded
                          : Icons.help_outline,
                    ),
                    label: Text(quickActionLabel(result)),
                  ),
                  if (canOpenDetails) ...[
                    const SizedBox(height: Space.sm),
                    OutlinedButton.icon(
                      key: const ValueKey('quick-entry-details'),
                      onPressed: _busy ? null : _openDetails,
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(
                        result.intent == QuickIntent.transfer
                            ? 'Mégis rögzítem tételként'
                            : 'Részletek megadása űrlapon',
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  Text('Blokk vagy számla', style: textTheme.titleMedium),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Lefotózod vagy kiválasztod, a telefon kiolvassa, te '
                    'átnézed, és már könyvelem is.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      _ScanButton(
                        key: const ValueKey('scan-camera'),
                        icon: Icons.photo_camera_rounded,
                        label: 'Blokk fotózása',
                        onPressed: _busy
                            ? null
                            : () => _scan(ReceiptSource.camera),
                      ),
                      _ScanButton(
                        key: const ValueKey('scan-gallery'),
                        icon: Icons.image_rounded,
                        label: 'Kép, képernyőkép',
                        onPressed: _busy
                            ? null
                            : () => _scan(ReceiptSource.gallery),
                      ),
                      _ScanButton(
                        key: const ValueKey('scan-file'),
                        icon: Icons.picture_as_pdf_rounded,
                        label: 'E-számla (PDF)',
                        onPressed: _busy
                            ? null
                            : () => _scan(ReceiptSource.file),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: Space.lg),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  const SizedBox(height: Space.xl),
                  Text(
                    'Így is írhatod',
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final example in quickEntryExamples)
                        ActionChip(
                          label: Text(
                            '„$example”',
                            style: TextStyle(color: colors.textMuted),
                          ),
                          backgroundColor: colors.background,
                          side: BorderSide(color: colors.line),
                          onPressed: () {
                            _text.value = TextEditingValue(
                              text: example,
                              selection: TextSelection.collapsed(
                                offset: example.length,
                              ),
                            );
                            _focus.requestFocus();
                          },
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

class _ScanButton extends StatelessWidget {
  const _ScanButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
