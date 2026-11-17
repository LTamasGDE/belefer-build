import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/categories.dart';
import '../../domain/models.dart';
import '../../domain/validation.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../theme/category_style.dart';
import '../widgets/pill_selector.dart';
import 'amount_input_formatter.dart';

/// A tétel- és a sablonűrlap közös mezőinek állapota.
class EntryFieldsController extends ChangeNotifier {
  EntryFieldsController({
    EntryType type = EntryType.expense,
    String title = '',
    int? amount,
    String? categoryId,
    String? note,
  }) : _type = type,
       _categoryId = categoryId,
       title = TextEditingController(text: title),
       amount = TextEditingController(
         text: amount == null ? '' : AmountInputFormatter.format('$amount'),
       ),
       note = TextEditingController(text: note ?? '');

  factory EntryFieldsController.fromTransaction(Transaction transaction) =>
      EntryFieldsController(
        type: transaction.type,
        title: transaction.title,
        amount: transaction.amount,
        categoryId: transaction.categoryId,
        note: transaction.note,
      );

  factory EntryFieldsController.fromTemplate(EntryTemplate template) =>
      EntryFieldsController(
        type: template.type,
        title: template.title,
        amount: template.amount,
        categoryId: template.categoryId,
        note: template.note,
      );

  final TextEditingController title;
  final TextEditingController amount;
  final TextEditingController note;

  EntryType _type;
  String? _categoryId;

  EntryType get type => _type;
  String? get categoryId => _categoryId;

  set type(EntryType value) {
    if (value == _type) return;
    _type = value;
    if (_categoryId != null && categoryById(_categoryId!)?.type != value) {
      _categoryId = null;
    }
    notifyListeners();
  }

  set categoryId(String? value) {
    if (value == _categoryId) return;
    _categoryId = value;
    notifyListeners();
  }

  /// Sablon adatainak betöltése a mezőkbe (mentés előtt mind szerkeszthető).
  void applyTemplate(EntryTemplate template) {
    _type = template.type;
    _categoryId = template.categoryId;
    title.text = template.title;
    amount.text = template.amount == null
        ? ''
        : AmountInputFormatter.format('${template.amount}');
    note.text = template.note ?? '';
    notifyListeners();
  }

  String get trimmedTitle => title.text.trim();
  int? get parsedAmount => EntryRules.parseAmount(amount.text);
  String? get normalizedNote => EntryRules.normalizeNote(note.text);

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }
}

/// A közös mezők: típus, összeg, megnevezés, kategória és megjegyzés.
///
/// A tételűrlapon az összeg kötelező, a sablonűrlapon elhagyható; minden
/// más mező és ellenőrzés azonos.
class EntryFields extends StatelessWidget {
  const EntryFields({
    super.key,
    required this.controller,
    required this.amountRequired,
    this.titleLabel = 'Megnevezés',
    this.afterTitle,
  });

  final EntryFieldsController controller;
  final bool amountRequired;
  final String titleLabel;

  /// A megnevezés után beillesztendő további mező (pl. dátum).
  final Widget? afterTitle;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final colors = context.colors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PillSelector<EntryType>(
              semanticLabel: 'Típus',
              selected: controller.type,
              onChanged: (value) => controller.type = value,
              options: [
                PillOption(
                  value: EntryType.expense,
                  label: 'Kiadás',
                  icon: Icons.north_east_rounded,
                  color: colors.expense,
                ),
                PillOption(
                  value: EntryType.income,
                  label: 'Bevétel',
                  icon: Icons.south_west_rounded,
                  color: colors.income,
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            AmountField(
              controller: controller.amount,
              isRequired: amountRequired,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              key: const ValueKey('field-title'),
              controller: controller.title,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLength: EntryRules.titleMaxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: InputDecoration(
                labelText: titleLabel,
                counterText: '',
              ),
              validator: EntryRules.validateTitle,
            ),
            if (afterTitle != null) ...[
              const SizedBox(height: Space.lg),
              afterTitle!,
            ],
            const SizedBox(height: Space.xl),
            CategoryField(
              key: ValueKey('field-category-${controller.type.storageKey}'),
              type: controller.type,
              value: controller.categoryId,
              onChanged: (value) => controller.categoryId = value,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              key: const ValueKey('field-note'),
              controller: controller.note,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              maxLength: EntryRules.noteMaxLength,
              decoration: const InputDecoration(
                labelText: 'Megjegyzés (nem kötelező)',
              ),
              validator: EntryRules.validateNote,
            ),
          ],
        );
      },
    );
  }
}

/// Összegmező: csak számjegy, hármas csoportosítás, „Ft” utótag.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.isRequired,
  });

  final TextEditingController controller;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TextFormField(
      key: const ValueKey('field-amount'),
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: const [AmountInputFormatter()],
      style: textTheme.headlineSmall?.copyWith(fontFeatures: tabularFigures),
      decoration: InputDecoration(
        labelText: isRequired ? 'Összeg' : 'Összeg (nem kötelező)',
        suffixText: 'Ft',
        helperText: isRequired ? null : 'Üresen hagyva használatkor adod meg.',
      ),
      validator: (value) =>
          EntryRules.validateAmount(value, required: isRequired),
    );
  }
}

/// Kategóriaválasztó a típushoz tartozó induló kategóriákkal.
class CategoryField extends FormField<String> {
  CategoryField({
    super.key,
    required EntryType type,
    required String? value,
    required ValueChanged<String> onChanged,
  }) : super(
         initialValue: value,
         validator: (selected) => EntryRules.validateCategory(selected, type),
         builder: (field) {
           final context = field.context;
           final colors = context.colors;
           final textTheme = Theme.of(context).textTheme;
           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Padding(
                 padding: const EdgeInsets.only(
                   left: Space.xs,
                   bottom: Space.sm,
                 ),
                 child: Text(
                   'Kategória',
                   style: textTheme.labelLarge?.copyWith(
                     color: field.hasError ? colors.danger : colors.textMuted,
                   ),
                 ),
               ),
               Wrap(
                 spacing: Space.sm,
                 runSpacing: Space.sm,
                 children: [
                   for (final category in categoriesFor(type))
                     _CategoryChip(
                       category: category,
                       selected: field.value == category.id,
                       onTap: () {
                         field.didChange(category.id);
                         onChanged(category.id);
                       },
                     ),
                 ],
               ),
               if (field.hasError)
                 Padding(
                   padding: const EdgeInsets.only(
                     left: Space.xs,
                     top: Space.sm,
                   ),
                   child: Text(
                     field.errorText!,
                     style: textTheme.bodySmall?.copyWith(
                       color: colors.danger,
                       fontWeight: FontWeight.w500,
                     ),
                   ),
                 ),
             ],
           );
         },
       );

  @override
  FormFieldState<String> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends FormFieldState<String> {
  @override
  void didUpdateWidget(CategoryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sablon betöltésekor kívülről érkező érték átvétele.
    if (widget.initialValue != value) {
      setValue(widget.initialValue);
    }
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = categoryStyle(category.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = selected
        ? style.color.withValues(alpha: isDark ? 0.34 : 0.22)
        : colors.raised;
    final border = selected ? style.color : colors.line;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
        color: background,
        shape: StadiumBorder(
          side: BorderSide(color: border, width: selected ? 2 : 1),
        ),
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
                  ExcludeSemantics(
                    child: Icon(
                      selected ? Icons.check_rounded : style.icon,
                      size: 18,
                      color: isDark
                          ? Color.lerp(style.color, Colors.white, 0.3)
                          : Color.lerp(style.color, Colors.black, 0.3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    category.name,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.text,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
