import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/ai/ai_prompt.dart';
import '../../domain/models.dart';
import '../../domain/quick_entry/interpreter.dart';
import '../../domain/recurring.dart';
import '../../services/ai_interpreter.dart';
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
        action: SnackBarAction(
          label: 'Visszavonás',
          onPressed: () {
            done.undo();
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
  QuickEntryResult? _offline;
  bool _busy = false;

  // AI-értelmezés (szünet után, a beírt szövegre).
  Timer? _debounce;
  String? _aiText;
  QuickEntryResult? _aiResult;
  Future<AiOutcome>? _aiPending;
  String? _aiPendingText;
  String? _aiError;

  bool get _aiActive => AppScope.read(context).aiSettings.isActive;

  /// Az érvényes értelmezés: az AI-é, ha a mostani szövegre megvan.
  QuickEntryResult? get _result {
    final text = _text.text.trim();
    if (text.isEmpty) return null;
    if (_aiResult != null && _aiText == text) return _aiResult;
    return _offline;
  }

  bool get _aiWorking =>
      _aiPending != null && _aiPendingText == _text.text.trim();

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
    _debounce?.cancel();
    _text.removeListener(_interpret);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _interpret() {
    final text = _text.text.trim();
    final result = text.isEmpty
        ? null
        : interpretQuickEntry(text, AppScope.read(context).quickEntryContext);
    setState(() {
      _offline = result;
      if (_aiText != text) _aiError = null;
    });
    _debounce?.cancel();
    if (text.length >= 3 && _aiActive && _aiText != text) {
      _debounce = Timer(const Duration(milliseconds: 900), () {
        unawaited(_askAi(text));
      });
    }
  }

  /// AI-értelmezés a [text]-re (egyszerre egy kérés szövegenként).
  Future<AiOutcome?> _askAi(String text) async {
    if (!mounted || !_aiActive) return null;
    final offline = _offline;
    if (offline == null) return null;
    if (_aiPendingText == text && _aiPending != null) return _aiPending;
    final state = AppScope.read(context);
    final future = state.aiInterpreter.interpret(
      text,
      AiInputKind.sentence,
      state.quickEntryContext,
      fallback: offline,
    );
    setState(() {
      _aiPending = future;
      _aiPendingText = text;
    });
    final outcome = await future;
    if (!mounted) return outcome;
    setState(() {
      if (_aiPendingText == text) {
        _aiPending = null;
        _aiPendingText = null;
      }
      if (outcome.usedAi) {
        _aiText = text;
        _aiResult = outcome.result;
        _aiError = null;
      } else {
        _aiError = outcome.error;
      }
    });
    return outcome;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _text.text.trim();
    var result = _result;
    if (result == null) return;
    setState(() => _busy = true);
    // Ha az AI még dolgozik (vagy el sem indult), megvárjuk – legfeljebb
    // néhány másodpercig; utána a beépített értelmezés dönt.
    if (_aiActive && _aiText != text) {
      _debounce?.cancel();
      try {
        final outcome = await _askAi(
          text,
        )?.timeout(const Duration(seconds: 8));
        if (outcome != null && outcome.usedAi && _text.text.trim() == text) {
          result = outcome.result;
        }
      } on TimeoutException {
        // A beépített értelmezés marad.
      }
      if (!mounted) return;
    }
    if (!result!.isComplete) {
      setState(() => _busy = false);
      _focus.requestFocus();
      return;
    }
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
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Nem sikerült beolvasni. Próbáld újra jobb fényben.'),
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
        (result.intent == QuickIntent.record ||
            result.intent == QuickIntent.createRecurring);

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
                  const SizedBox(height: Space.sm),
                  AiStatusLine(
                    active: state.aiSettings.isActive,
                    provider: state.aiSettings.provider.label,
                    working: _aiWorking,
                    usedAi: result?.fromAi ?? false,
                    error: _aiError,
                  ),
                  if (result != null) ...[
                    const SizedBox(height: Space.lg),
                    QuickResultCard(result: result, today: today),
                  ],
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    key: const ValueKey('quick-entry-submit'),
                    onPressed: (complete || _aiWorking) && !_busy
                        ? _submit
                        : null,
                    icon: Icon(
                      complete ? Icons.check_rounded : Icons.help_outline,
                    ),
                    label: Text(
                      _busy
                          ? 'Könyvelés…'
                          : (!complete && _aiWorking
                                ? 'Az AI még gondolkodik…'
                                : quickActionLabel(result)),
                    ),
                  ),
                  if (canOpenDetails) ...[
                    const SizedBox(height: Space.sm),
                    OutlinedButton.icon(
                      key: const ValueKey('quick-entry-details'),
                      onPressed: _busy ? null : _openDetails,
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Részletek megadása űrlapon'),
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
