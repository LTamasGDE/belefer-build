import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../state/app_scope.dart';
import '../entry_form/entry_fields.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';

/// Az űrlap eredménye a hívó képernyő számára.
enum TransactionFormOutcome { saved, deleted }

class TransactionFormResult {
  const TransactionFormResult(this.outcome, this.transaction);

  final TransactionFormOutcome outcome;
  final Transaction transaction;
}

/// Új tétel rögzítése, sablon alkalmazása, illetve meglévő tétel
/// megtekintése, szerkesztése és törlése.
class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.existing,
    this.initialType = EntryType.expense,
    this.template,
  });

  /// Szerkesztendő tétel; `null` esetén új tétel készül.
  final Transaction? existing;
  final EntryType initialType;

  /// Ha meg van adva, az űrlap ennek adataival nyílik meg, mai dátummal.
  final EntryTemplate? template;

  bool get isEditing => existing != null;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final EntryFieldsController _fields;
  late CalendarDay _date;
  int? _appliedTemplateId;
  bool _saving = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final template = widget.template;
    if (existing != null) {
      _fields = EntryFieldsController.fromTransaction(existing);
      _date = existing.date;
    } else if (template != null) {
      _fields = EntryFieldsController.fromTemplate(template);
      _appliedTemplateId = template.id;
      _date = AppScope.read(context).today();
    } else {
      _fields = EntryFieldsController(type: widget.initialType);
      _date = AppScope.read(context).today();
    }
    _fields.addListener(_onFieldsChanged);
  }

  @override
  void dispose() {
    _fields.removeListener(_onFieldsChanged);
    _fields.dispose();
    super.dispose();
  }

  void _onFieldsChanged() => setState(() {});

  String get _title {
    if (widget.isEditing) return 'Tétel szerkesztése';
    return _fields.type == EntryType.expense ? 'Új kiadás' : 'Új bevétel';
  }

  void _applyTemplate(EntryTemplate template) {
    _fields.applyTemplate(template);
    setState(() {
      _appliedTemplateId = template.id;
      _date = AppScope.read(context).today();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toLocalDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Válassz dátumot',
    );
    if (picked != null && mounted) {
      setState(() => _date = CalendarDay.fromDateTime(picked));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    setState(() => _saving = true);
    final transaction = Transaction(
      id: widget.existing?.id,
      type: _fields.type,
      title: _fields.trimmedTitle,
      amount: _fields.parsedAmount!,
      categoryId: _fields.categoryId!,
      date: _date,
      note: _fields.normalizedNote,
    );
    try {
      final saved = await AppScope.read(context).saveTransaction(transaction);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(TransactionFormResult(TransactionFormOutcome.saved, saved));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nem sikerült menteni. Próbáld újra.')),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final confirmed = await confirmAction(
      context,
      title: 'Törlöd a tételt?',
      message:
          '„${existing.title}” (${formatForint(existing.amount)}) végleg '
          'törlődik erről a készülékről.',
      confirmLabel: 'Törlés',
      destructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;
    setState(() => _saving = true);
    await AppScope.read(context).deleteTransaction(existing.id!);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(TransactionFormResult(TransactionFormOutcome.deleted, existing));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = AppScope.of(context);
    final templates = widget.isEditing
        ? const <EntryTemplate>[]
        : state.templatesOf(_fields.type);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Bezárás',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_title),
        actions: [
          if (widget.isEditing)
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
                    if (templates.isNotEmpty) ...[
                      _TemplateStrip(
                        templates: templates,
                        selectedId: _appliedTemplateId,
                        onSelected: _applyTemplate,
                      ),
                      const SizedBox(height: Space.lg),
                    ],
                    EntryFields(
                      controller: _fields,
                      amountRequired: true,
                      afterTitle: _DateField(date: _date, onTap: _pickDate),
                    ),
                    const SizedBox(height: Space.xl),
                    FilledButton.icon(
                      key: const ValueKey('save-transaction'),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: colors.textMuted,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        widget.isEditing ? 'Módosítás mentése' : 'Mentés',
                      ),
                    ),
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

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap});

  final CalendarDay date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final label = formatFullDate(date);
    return Semantics(
      button: true,
      label: 'Dátum: $label. Módosítás',
      excludeSemantics: true,
      child: Material(
        color: colors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('field-date'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: colors.textMuted),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dátum',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(label, style: textTheme.bodyLarge),
                    ],
                  ),
                ),
                Icon(Icons.edit_rounded, size: 18, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateStrip extends StatelessWidget {
  const _TemplateStrip({
    required this.templates,
    required this.selectedId,
    required this.onSelected,
  });

  final List<EntryTemplate> templates;
  final int? selectedId;
  final ValueChanged<EntryTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Text(
            'Kitöltés sablonból',
            style: textTheme.labelLarge?.copyWith(color: colors.textMuted),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final template in templates) ...[
                _TemplateChip(
                  template: template,
                  selected: template.id == selectedId,
                  onTap: () => onSelected(template),
                ),
                const SizedBox(width: Space.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final EntryTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Sablon: ${template.title}',
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.accent : colors.sunken,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 18,
                    color: selected ? colors.onAccent : colors.accentText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    template.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? colors.onAccent : colors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
