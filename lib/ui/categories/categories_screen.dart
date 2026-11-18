import 'package:flutter/material.dart';

import '../../domain/categories.dart';
import '../../domain/models.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../theme/category_style.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/pill_selector.dart';

const Map<String, String> _iconLabels = {
  'star': 'csillag',
  'pets': 'háziállat',
  'fitness': 'edzés',
  'games': 'játék',
  'travel': 'utazás',
  'car': 'autó',
  'phone': 'telefon',
  'wifi': 'internet',
  'book': 'könyv',
  'music': 'zene',
  'coffee': 'kávé',
  'beauty': 'szépség',
  'baby': 'baba',
  'sports': 'sport',
  'savings': 'megtakarítás',
  'work': 'munka',
  'home': 'otthon',
  'basket': 'bevásárlás',
  'restaurant': 'étterem',
  'heart': 'egészség',
  'gift': 'ajándék',
  'school': 'tanulás',
  'payments': 'pénz',
  'more': 'egyéb',
};

const List<String> _colorLabels = [
  'kék',
  'lila',
  'türkiz',
  'sárga',
  'égkék',
  'piros',
  'rózsaszín',
  'narancs',
  'indigó',
  'zöld',
  'bíbor',
  'szürke',
];

/// Saját kategória felvétele vagy szerkesztése. Az új kategória
/// azonosítójával tér vissza (vagy `null`, ha megszakították).
Future<String?> showCategoryEditor(
  BuildContext context, {
  EntryType type = EntryType.expense,
  Category? existing,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryEditor(type: type, existing: existing),
  );
}

/// A kategóriák kezelése: beépítettek és saját kategóriák.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;

    List<Widget> section(EntryType type, String title) => [
      SectionTitle(title),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final category in categoriesFor(type))
              _CategoryRow(
                category: category,
                usage: state.usageOfCategory(category.id),
              ),
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Kategóriák')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-category'),
        heroTag: 'fab-categories',
        onPressed: () => showCategoryEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Új kategória'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 104),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xs,
                    Space.sm,
                    Space.xs,
                    0,
                  ),
                  child: Text(
                    'A saját kategóriáidat szerkesztheted és törölheted; a '
                    'törölt kategória tételei az „Egyéb” kategóriába kerülnek.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
                ...section(EntryType.expense, 'Kiadás'),
                ...section(EntryType.income, 'Bevétel'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.usage});

  final Category category;
  final int usage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final subtitle = [
      if (!category.custom) 'beépített',
      if (usage > 0) '$usage használatban' else 'nincs használatban',
    ].join(' · ');
    return MergeSemantics(
      child: ListTile(
        key: ValueKey('category-row-${category.id}'),
        leading: CategoryAvatar(category.id, size: 40),
        title: Text(category.name, style: textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
        ),
        trailing: category.custom
            ? Icon(Icons.edit_rounded, color: colors.textMuted)
            : null,
        onTap: category.custom
            ? () => showCategoryEditor(
                context,
                type: category.type,
                existing: category,
              )
            : null,
      ),
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.type, this.existing});

  final EntryType type;
  final Category? existing;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late EntryType _type;
  late int _color;
  late String _icon;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _type = existing?.type ?? widget.type;
    final used = AppScope.read(context).customCategories.length;
    _color =
        existing?.colorValue ??
        customCategoryColors[used % customCategoryColors.length];
    _icon = existing?.iconKey ?? customCategoryIcons.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Adj nevet a kategóriának.';
    if (name.length > 24) return 'Legfeljebb 24 karakter.';
    final duplicate = categoriesFor(_type).any(
      (category) =>
          category.id != widget.existing?.id &&
          category.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) return 'Már van ilyen nevű kategória.';
    return null;
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final state = AppScope.read(context);
    final category = Category(
      id: widget.existing?.id ?? '',
      type: _type,
      name: _name.text.trim(),
      colorValue: _color,
      iconKey: _icon,
      custom: true,
    );
    final saved = await state.saveCategory(category);
    if (!mounted) return;
    Navigator.of(context).pop(saved.id);
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final state = AppScope.read(context);
    final usage = state.usageOfCategory(existing.id);
    final confirmed = await confirmAction(
      context,
      title: 'Törlöd a(z) „${existing.name}” kategóriát?',
      message: usage == 0
          ? 'A kategória törlődik.'
          : '$usage tétel, sablon vagy ismétlődő tétel az „Egyéb” '
                'kategóriába kerül.',
      confirmLabel: 'Törlés',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await state.deleteCategory(existing);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final editing = widget.existing != null;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                editing ? 'Kategória szerkesztése' : 'Új kategória',
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: Space.lg),
              if (!editing) ...[
                PillSelector<EntryType>(
                  semanticLabel: 'Típus',
                  selected: _type,
                  onChanged: (value) => setState(() => _type = value),
                  options: [
                    PillOption(
                      value: EntryType.expense,
                      label: 'Kiadás',
                      color: colors.expense,
                    ),
                    PillOption(
                      value: EntryType.income,
                      label: 'Bevétel',
                      color: colors.income,
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
              ],
              TextFormField(
                key: const ValueKey('category-name'),
                controller: _name,
                autofocus: !editing,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Név',
                  hintText: 'Pl. Kutya, Edzés, Utazás',
                  counterText: '',
                ),
                validator: _validate,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: Space.lg),
              Text('Szín', style: textTheme.labelLarge),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final (index, value) in customCategoryColors.indexed)
                    Semantics(
                      button: true,
                      selected: value == _color,
                      label:
                          'Szín: ${_colorLabels[index % _colorLabels.length]}',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = value),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: value == _color
                                  ? colors.text
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: value == _color
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
              Text('Ikon', style: textTheme.labelLarge),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final key in customCategoryIcons)
                    Semantics(
                      button: true,
                      selected: key == _icon,
                      label: 'Ikon: ${_iconLabels[key] ?? key}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _icon = key),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: key == _icon
                                ? Color(
                                    _color,
                                  ).withValues(alpha: isDark ? 0.34 : 0.22)
                                : colors.sunken,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: key == _icon
                                  ? Color(_color)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            categoryIconFor(key),
                            color: key == _icon
                                ? (isDark
                                      ? Color.lerp(
                                          Color(_color),
                                          Colors.white,
                                          0.3,
                                        )
                                      : Color.lerp(
                                          Color(_color),
                                          Colors.black,
                                          0.3,
                                        ))
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.xl),
              FilledButton.icon(
                key: const ValueKey('save-category'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Mentés'),
              ),
              if (editing) ...[
                const SizedBox(height: Space.sm),
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: colors.danger),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Kategória törlése'),
                ),
              ],
              const SizedBox(height: Space.xl),
            ],
          ),
        ),
      ),
    );
  }
}
