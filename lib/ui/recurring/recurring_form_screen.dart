import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../domain/recurring.dart';
import '../../state/app_scope.dart';
import '../entry_form/entry_fields.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/date_field.dart';
import '../widgets/rows.dart';

/// A gyakoriság előre megadott lehetőségei.
const List<(Frequency, int, String)> frequencyPresets = [
  (Frequency.weekly, 1, 'Hetente'),
  (Frequency.weekly, 2, 'Kéthetente'),
  (Frequency.monthly, 1, 'Havonta'),
  (Frequency.monthly, 2, 'Kéthavonta'),
  (Frequency.monthly, 3, 'Negyedévente'),
  (Frequency.monthly, 6, 'Félévente'),
  (Frequency.yearly, 1, 'Évente'),
];

const List<(int, String)> _daysBeforeOptions = [
  (0, 'Aznap'),
  (1, '1 nappal előtte'),
  (2, '2 nappal'),
  (3, '3 nappal'),
  (7, '1 héttel'),
];

const List<String> _placeholders = ['{név}', '{összeg}', '{dátum}', '{mikor}'];

/// Ismétlődő tétel felvétele, szerkesztése, lemondása és törlése.
class RecurringFormScreen extends StatefulWidget {
  const RecurringFormScreen({
    super.key,
    this.existing,
    this.prefill,
    this.prefillHasAmount = true,
  });

  final RecurringRule? existing;

  /// Új ismétlődő tétel előre kitöltött adatai.
  final RecurringRule? prefill;

  /// Az előtöltésben szerepel-e már összeg.
  final bool prefillHasAmount;

  @override
  State<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends State<RecurringFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final EntryFieldsController _fields;
  late final TextEditingController _reminderText;
  late Frequency _frequency;
  late int _interval;
  late CalendarDay _start;
  CalendarDay? _end;
  late bool _autoBook;
  late ReminderSettings _reminder;
  bool _bookPast = false;
  bool _saving = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    final source = widget.existing ?? widget.prefill;
    _fields = EntryFieldsController(
      type: source?.type ?? EntryType.expense,
      title: source?.title ?? '',
      amount:
          source == null ||
              (widget.existing == null && !widget.prefillHasAmount)
          ? null
          : (widget.existing != null
                ? source.amountOn(state.today())
                : source.amount),
      categoryId: source?.categoryId,
      note: source?.note,
    );
    _frequency = source?.frequency ?? Frequency.monthly;
    _interval = source?.interval ?? 1;
    _start = source?.startDate ?? state.today();
    _end = source?.endDate;
    _autoBook = source?.autoBook ?? true;
    _reminder =
        source?.reminder ??
        state.reminderDefaults.newRuleSettings(enabled: true);
    _reminderText = TextEditingController(text: _reminder.customText ?? '');
    _fields.addListener(_refresh);
    _reminderText.addListener(_refresh);
  }

  @override
  void dispose() {
    _fields.removeListener(_refresh);
    _reminderText.removeListener(_refresh);
    _fields.dispose();
    _reminderText.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  RecurringRule _buildRule() {
    final text = _reminderText.text.trim();
    final base = widget.existing;
    final rule = RecurringRule(
      id: base?.id,
      type: _fields.type,
      title: _fields.trimmedTitle.isEmpty ? 'Tétel' : _fields.trimmedTitle,
      categoryId: _fields.categoryId ?? '',
      amount: _fields.parsedAmount ?? 1,
      note: _fields.normalizedNote,
      frequency: _frequency,
      interval: _interval,
      startDate: _start,
      endDate: _end,
      autoBook: _autoBook,
      reminder: _reminder.copyWith(
        customText: text.isEmpty ? null : text,
        clearCustomText: text.isEmpty,
      ),
      amountChanges: base?.amountChanges ?? const [],
      handledThrough: base?.handledThrough,
    );
    return rule;
  }

  int get _pastCount {
    final today = AppScope.read(context).today();
    if (_isEditing || _start.compareTo(today) >= 0) return 0;
    return _buildRule()
        .occurrencesBetween(
          _start,
          CalendarDay(today.year, today.month, today.day - 1),
        )
        .length;
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.toLocalDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Első esedékesség',
    );
    if (picked != null && mounted) {
      setState(() => _start = CalendarDay.fromDateTime(picked));
    }
  }

  Future<void> _pickEnd() async {
    final initial = _end ?? _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toLocalDateTime(),
      firstDate: _start.toLocalDateTime(),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Utolsó esedékesség',
    );
    if (picked != null && mounted) {
      setState(() => _end = CalendarDay.fromDateTime(picked));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminder.hour, minute: _reminder.minute),
      helpText: 'Emlékeztető időpontja',
    );
    if (picked != null && mounted) {
      setState(
        () => _reminder = _reminder.copyWith(
          hour: picked.hour,
          minute: picked.minute,
        ),
      );
    }
  }

  void _insertPlaceholder(String placeholder) {
    final text = _reminderText.text;
    final selection = _reminderText.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final updated = text.replaceRange(start, end, placeholder);
    _reminderText.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + placeholder.length),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    final state = AppScope.read(context);
    final existing = widget.existing;
    var rule = _buildRule();

    // Meglévő tétel új összege: mikortól érvényes?
    if (existing != null) {
      final today = state.today();
      final oldAmount = existing.amountOn(today);
      final newAmount = _fields.parsedAmount!;
      if (newAmount != oldAmount) {
        final next = existing.nextOccurrence(
          existing.handledThrough != null &&
                  existing.handledThrough!.compareTo(today) >= 0
              ? CalendarDay(
                  existing.handledThrough!.year,
                  existing.handledThrough!.month,
                  existing.handledThrough!.day + 1,
                )
              : today,
        );
        final fromNext = await _askAmountScope(next);
        if (fromNext == null || !mounted) return;
        if (fromNext && next != null) {
          rule = rule.copyWith(
            amount: existing.amount,
            amountChanges: [
              for (final change in existing.amountChanges)
                if (change.from.compareTo(next) < 0) change,
              AmountChange(from: next, amount: newAmount),
            ],
          );
        } else {
          rule = rule.copyWith(amount: newAmount, amountChanges: const []);
        }
      }
    }

    setState(() => _saving = true);
    try {
      final saved = await state.saveRule(rule, bookPast: _bookPast);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nem sikerült menteni. Próbáld újra.')),
      );
    }
  }

  /// Igaz: a következő esedékességtől; hamis: minden esedékességre.
  Future<bool?> _askAmountScope(CalendarDay? next) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Mikortól érvényes az új összeg?'),
        children: [
          if (next != null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'A következő esedékességtől (${formatFullDate(next)})',
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Minden esedékességre (a már rögzített tételek nem változnak)',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _endOrResume() async {
    final existing = widget.existing!;
    final state = AppScope.read(context);
    final ended = existing.isEndedOn(state.today());
    if (ended) {
      await state.resumeRule(existing);
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Lemondod?',
      message:
          'A „${existing.title}” mától nem rögzül többé, és emlékeztető '
          'sem jön róla. A már rögzített tételek megmaradnak.',
      confirmLabel: 'Lemondás',
    );
    if (!confirmed || !mounted) return;
    await state.endRule(existing);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final confirmed = await confirmAction(
      context,
      title: 'Törlöd az ismétlődő tételt?',
      message:
          'A „${existing.title}” szabálya törlődik. A már rögzített tételek '
          'a Tételek között megmaradnak.',
      confirmLabel: 'Törlés',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await AppScope.read(context).deleteRule(existing.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final rule = _buildRule();
    final today = state.today();
    final next = rule.nextOccurrence(today);
    final pastCount = _pastCount;
    final remindersOff = !state.reminderDefaults.enabled;
    final existing = widget.existing;
    final ended = existing?.isEndedOn(today) ?? false;

    final frequencyPanel = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Gyakoriság', style: textTheme.titleMedium),
          const SizedBox(height: Space.md),
          ChoiceWrap<(Frequency, int)>(
            semanticLabel: 'Gyakoriság',
            options: [
              for (final (frequency, interval, label) in frequencyPresets)
                ((frequency, interval), label),
            ],
            selected: (_frequency, _interval),
            onSelected: (value) => setState(() {
              _frequency = value.$1;
              _interval = value.$2;
            }),
          ),
          const SizedBox(height: Space.lg),
          DateField(
            label: 'Első esedékesség',
            fieldKey: const ValueKey('field-start'),
            date: _start,
            onTap: _pickStart,
          ),
          const SizedBox(height: Space.md),
          DateField(
            label: 'Utolsó esedékesség',
            fieldKey: const ValueKey('field-end'),
            date: _end ?? _start,
            valueText: _end == null ? 'Nincs, határozatlan ideig' : null,
            onTap: _pickEnd,
          ),
          if (_end != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _end = null),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Záró dátum törlése'),
              ),
            ),
          const SizedBox(height: Space.md),
          Text(
            next == null
                ? 'Nincs több esedékesség.'
                : '${_capitalize(rule.describe())} · következő: '
                      '${formatShortDate(next, today)}',
            key: const ValueKey('recurring-preview'),
            style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );

    final reminderPanel = Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToggleRow(
            icon: Icons.bolt_rounded,
            title: 'Automatikus rögzítés',
            subtitle: _autoBook
                ? 'Esedékességkor magától bekerül a tételek közé.'
                : 'Esedékességkor jóváhagyást kér (az összeg módosítható).',
            value: _autoBook,
            switchKey: const ValueKey('autobook-switch'),
            onChanged: (value) => setState(() => _autoBook = value),
          ),
          const RowDivider(),
          ToggleRow(
            icon: Icons.notifications_active_outlined,
            title: 'Emlékeztető',
            subtitle: remindersOff
                ? 'Az emlékeztetők ki vannak kapcsolva a Beállításokban.'
                : 'Értesítés az esedékesség előtt.',
            value: _reminder.enabled,
            switchKey: const ValueKey('reminder-switch'),
            onChanged: (value) =>
                setState(() => _reminder = _reminder.copyWith(enabled: value)),
          ),
          if (_reminder.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChoiceWrap<int>(
                    semanticLabel: 'Mikor emlékeztessen',
                    options: _daysBeforeOptions,
                    selected: _reminder.daysBefore,
                    onSelected: (value) => setState(
                      () => _reminder = _reminder.copyWith(daysBefore: value),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  OutlinedButton.icon(
                    key: const ValueKey('reminder-time'),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(
                      'Időpont: ${_reminder.hour.toString().padLeft(2, '0')}:'
                      '${_reminder.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  TextField(
                    key: const ValueKey('reminder-text'),
                    controller: _reminderText,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 160,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Saját értesítésszöveg (nem kötelező)',
                      hintText: 'Pl. Ne felejtsd: {név}, {összeg} – {mikor}!',
                    ),
                  ),
                  Wrap(
                    spacing: Space.xs,
                    children: [
                      for (final placeholder in _placeholders)
                        ActionChip(
                          label: Text(placeholder),
                          onPressed: () => _insertPlaceholder(placeholder),
                          tooltip: 'Beszúrás: $placeholder',
                        ),
                    ],
                  ),
                  if (next != null) ...[
                    const SizedBox(height: Space.md),
                    _ReminderPreview(
                      text: reminderBody(
                        rule,
                        next,
                        CalendarDay(
                          next.year,
                          next.month,
                          next.day - _reminder.daysBefore,
                        ),
                      ),
                      title: rule.type == EntryType.expense
                          ? 'Esedékes kiadás'
                          : 'Várható bevétel',
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Bezárás',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_isEditing ? 'Ismétlődő tétel' : 'Új ismétlődő tétel'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Törlés',
              icon: const Icon(Icons.delete_outline_rounded),
              color: colors.danger,
              onPressed: _saving ? null : _delete,
            ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
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
                    EntryFields(controller: _fields, amountRequired: true),
                    const SizedBox(height: Space.xl),
                    frequencyPanel,
                    if (pastCount > 0) ...[
                      const SizedBox(height: Space.md),
                      Panel(
                        padding: EdgeInsets.zero,
                        child: ToggleRow(
                          icon: Icons.history_rounded,
                          title: 'Korábbi esedékességek rögzítése',
                          subtitle:
                              '$pastCount korábbi alkalom is bekerül a '
                              'tételek közé.',
                          value: _bookPast,
                          switchKey: const ValueKey('book-past-switch'),
                          onChanged: (value) =>
                              setState(() => _bookPast = value),
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.md),
                    reminderPanel,
                    const SizedBox(height: Space.xl),
                    FilledButton.icon(
                      key: const ValueKey('save-recurring'),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(_isEditing ? 'Módosítás mentése' : 'Mentés'),
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: Space.sm),
                      OutlinedButton.icon(
                        key: const ValueKey('end-recurring'),
                        onPressed: _saving ? null : _endOrResume,
                        icon: Icon(
                          ended
                              ? Icons.play_arrow_rounded
                              : Icons.stop_circle_outlined,
                        ),
                        label: Text(ended ? 'Újraindítás' : 'Lemondás'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderPreview extends StatelessWidget {
  const _ReminderPreview({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: 'Előnézet: $title. $text',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: colors.sunken,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.heroBackground,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.donut_large_rounded,
                size: 18,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Belefér · $title',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    key: const ValueKey('reminder-preview'),
                    style: textTheme.bodyMedium,
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

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
