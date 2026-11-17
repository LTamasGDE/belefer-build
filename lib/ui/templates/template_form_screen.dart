import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../state/app_scope.dart';
import '../entry_form/entry_fields.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';

/// Sablon létrehozása, szerkesztése és törlése.
///
/// Ugyanazokat a mezőket és ellenőrzéseket használja, mint a tételűrlap,
/// csak az összeg elhagyható, és nincs dátum.
class TemplateFormScreen extends StatefulWidget {
  const TemplateFormScreen({
    super.key,
    this.existing,
    this.initialType = EntryType.expense,
  });

  final EntryTemplate? existing;
  final EntryType initialType;

  bool get isEditing => existing != null;

  @override
  State<TemplateFormScreen> createState() => _TemplateFormScreenState();
}

class _TemplateFormScreenState extends State<TemplateFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final EntryFieldsController _fields;
  bool _saving = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _fields = existing != null
        ? EntryFieldsController.fromTemplate(existing)
        : EntryFieldsController(type: widget.initialType);
  }

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
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
    final template = EntryTemplate(
      id: widget.existing?.id,
      type: _fields.type,
      title: _fields.trimmedTitle,
      categoryId: _fields.categoryId!,
      amount: _fields.parsedAmount,
      note: _fields.normalizedNote,
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppScope.read(context).saveTemplate(template);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('„${template.title}” sablon mentve')),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Nem sikerült menteni. Próbáld újra.')),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final confirmed = await confirmAction(
      context,
      title: 'Törlöd a sablont?',
      message:
          'A(z) „${existing.title}” sablon törlődik. A belőle korábban '
          'rögzített tételek megmaradnak.',
      confirmLabel: 'Törlés',
      destructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    await AppScope.read(context).deleteTemplate(existing.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(const SnackBar(content: Text('Sablon törölve')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Bezárás',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.isEditing ? 'Sablon szerkesztése' : 'Új sablon'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Sablon törlése',
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
                    EntryFields(
                      controller: _fields,
                      amountRequired: false,
                      titleLabel: 'Sablon neve (a tétel megnevezése)',
                    ),
                    const SizedBox(height: Space.xl),
                    FilledButton.icon(
                      key: const ValueKey('save-template'),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Sablon mentése'),
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
