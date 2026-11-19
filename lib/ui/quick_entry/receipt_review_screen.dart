import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/ai/ai_prompt.dart';
import '../../domain/models.dart';
import '../../domain/quick_entry/interpreter.dart';
import '../../domain/quick_entry/receipt_parser.dart';
import '../../services/platform_services.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../transactions/transaction_actions.dart';
import '../transactions/transaction_form_screen.dart';
import '../widgets/common.dart';
import 'quick_entry_preview.dart';

/// A beolvasott blokk vagy számla átnézése: a felismert szöveg javítható,
/// az értelmezés élőben frissül, majd egy koppintással könyvelhető.
class ReceiptReviewScreen extends StatefulWidget {
  const ReceiptReviewScreen({super.key, required this.capture});

  final ReceiptCapture capture;

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  late final TextEditingController _text;
  late QuickEntryResult _result;
  bool _busy = false;
  bool _showText = false;
  bool _aiWorking = false;
  String? _aiError;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.capture.text);
    _text.addListener(_onEdited);
    _result = _parse();
    // Ha a felismerés hiányos, a szöveg rögtön látszik a javításhoz.
    _showText = !_result.isComplete;
    WidgetsBinding.instance.addPostFrameCallback((_) => _askAi());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.removeListener(_onEdited);
    _text.dispose();
    super.dispose();
  }

  QuickEntryResult _parse() =>
      interpretReceipt(_text.text, AppScope.read(context).quickEntryContext);

  void _onEdited() {
    setState(() => _result = _parse());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), _askAi);
  }

  /// A felismert szöveg értelmezése AI-val (ha be van kapcsolva).
  Future<void> _askAi() async {
    if (!mounted) return;
    final state = AppScope.read(context);
    if (!state.aiSettings.isActive || _text.text.trim().isEmpty) return;
    final generation = ++_generation;
    setState(() => _aiWorking = true);
    final outcome = await state.aiInterpreter.interpret(
      _text.text,
      AiInputKind.receipt,
      state.quickEntryContext,
      fallback: _parse(),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _aiWorking = false;
      if (outcome.usedAi) {
        _result = outcome.result;
        _aiError = null;
      } else {
        _aiError = outcome.error;
      }
    });
  }

  Future<void> _book() async {
    if (_busy || !_result.isComplete) return;
    setState(() => _busy = true);
    final done = await applyQuickResult(AppScope.read(context), _result);
    if (!mounted) return;
    if (done == null) {
      setState(() => _busy = false);
      return;
    }
    Navigator.of(context).pop(done);
  }

  Future<void> _openForm() async {
    final navigator = Navigator.of(context);
    final saved = await openTransactionForm(
      context,
      prefill: TransactionDraft(
        type: EntryType.expense,
        date: _result.date,
        title: _result.title ?? '',
        amount: _result.amount,
        categoryId: _result.categoryGuessed ? null : _result.categoryId,
      ),
    );
    if (saved && mounted) {
      // A gyorsrögzítés is bezárul (az űrlap már visszajelzett).
      navigator
        ..pop()
        ..maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final today = state.today();
    final imagePath = widget.capture.imagePath;
    final empty = widget.capture.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Blokk átnézése')),
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
                  if (imagePath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.card),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Image.file(
                          File(imagePath),
                          fit: BoxFit.cover,
                          semanticLabel: 'A beolvasott kép',
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    )
                  else if (widget.capture.fileName != null)
                    Text(
                      widget.capture.fileName!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  const SizedBox(height: Space.lg),
                  if (empty)
                    Text(
                      'Nem találtam szöveget a képen. Írd be a lényeget '
                      'alább (pl. „Lidl összesen 4 590”), vagy próbáld újra '
                      'élesebb fotóval.',
                      style: textTheme.bodyMedium,
                    ),
                  QuestionHints(result: _result, today: today),
                  const SizedBox(height: Space.sm),
                  AiStatusLine(
                    active: state.aiSettings.isActive,
                    provider: state.aiSettings.provider.label,
                    working: _aiWorking,
                    usedAi: _result.fromAi,
                    error: _aiError,
                  ),
                  const SizedBox(height: Space.lg),
                  QuickResultCard(result: _result, today: today),
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    key: const ValueKey('receipt-book'),
                    onPressed: _result.isComplete && !_busy ? _book : null,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(quickActionLabel(_result)),
                  ),
                  const SizedBox(height: Space.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('receipt-form'),
                    onPressed: _busy ? null : _openForm,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Javítás űrlapon'),
                  ),
                  const SizedBox(height: Space.xl),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: const Text('Felismert szöveg'),
                          subtitle: const Text(
                            'Ha valamit rosszul olvasott ki, itt javíthatod.',
                          ),
                          trailing: Icon(
                            _showText
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                          onTap: () => setState(() => _showText = !_showText),
                        ),
                        if (_showText)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.lg,
                              0,
                              Space.lg,
                              Space.lg,
                            ),
                            child: TextField(
                              key: const ValueKey('receipt-text'),
                              controller: _text,
                              minLines: 4,
                              maxLines: 14,
                              style: textTheme.bodyMedium?.copyWith(
                                fontFeatures: tabularFigures,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'A blokk szövege',
                              ),
                            ),
                          ),
                      ],
                    ),
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
