import 'package:flutter/material.dart';

import '../../domain/categories.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../transactions/transaction_actions.dart';
import '../widgets/common.dart';
import 'template_form_screen.dart';

Future<void> openTemplateForm(
  BuildContext context, {
  EntryTemplate? existing,
  EntryType initialType = EntryType.expense,
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: existing == null,
      builder: (_) =>
          TemplateFormScreen(existing: existing, initialType: initialType),
    ),
  );
}

/// Sablonok: létrehozás, szerkesztés, törlés és használat.
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final expenses = state.templatesOf(EntryType.expense);
    final incomes = state.templatesOf(EntryType.income);
    final isEmpty = expenses.isEmpty && incomes.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Sablonok')),
      floatingActionButton: isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab-templates',
              onPressed: () => openTemplateForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Új sablon'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 104),
        children: [
          ContentWidth(
            child: isEmpty
                ? EmptyState(
                    icon: Icons.bolt_rounded,
                    title: 'Rögzíts gyorsabban sablonokkal',
                    message:
                        'Például Lakbér vagy Fizetés: egy koppintásra kitöltött '
                        'űrlapot kapsz, amit mentés előtt még módosíthatsz.',
                    actions: [
                      FilledButton.icon(
                        onPressed: () => openTemplateForm(context),
                        icon: const Icon(Icons.north_east_rounded),
                        label: const Text('Kiadási sablon'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => openTemplateForm(
                          context,
                          initialType: EntryType.income,
                        ),
                        icon: const Icon(Icons.south_west_rounded),
                        label: const Text('Bevételi sablon'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TemplateSection(
                        title: 'Kiadási sablonok',
                        type: EntryType.expense,
                        templates: expenses,
                      ),
                      _TemplateSection(
                        title: 'Bevételi sablonok',
                        type: EntryType.income,
                        templates: incomes,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TemplateSection extends StatelessWidget {
  const _TemplateSection({
    required this.title,
    required this.type,
    required this.templates,
  });

  final String title;
  final EntryType type;
  final List<EntryTemplate> templates;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title,
          trailing: TextButton.icon(
            onPressed: () => openTemplateForm(context, initialType: type),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(
              'Új',
              semanticsLabel: type == EntryType.expense
                  ? 'Új kiadási sablon'
                  : 'Új bevételi sablon',
            ),
          ),
        ),
        if (templates.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.sm),
            child: Text(
              type == EntryType.expense
                  ? 'Még nincs kiadási sablon.'
                  : 'Még nincs bevételi sablon.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ),
        for (final template in templates)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: TemplateCard(template: template),
          ),
      ],
    );
  }
}

/// Sablonkártya: koppintásra szerkesztés, a „Használat” gombbal tétel.
class TemplateCard extends StatelessWidget {
  const TemplateCard({super.key, required this.template});

  final EntryTemplate template;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final amount = template.amount;
    final details = [
      categoryName(template.categoryId),
      amount == null ? 'összeg használatkor' : formatForint(amount),
    ].join(' · ');
    return Panel(
      padding: EdgeInsets.zero,
      radius: 20,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              onTap: () => openTemplateForm(context, existing: template),
              label: '${template.title} sablon szerkesztése, $details',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => openTemplateForm(context, existing: template),
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(
                    children: [
                      CategoryAvatar(template.categoryId),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              template.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: Space.md),
            child: FilledButton(
              key: ValueKey('use-template-${template.id}'),
              onPressed: () => openTransactionForm(context, template: template),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(
                'Használat',
                semanticsLabel: '${template.title} sablon használata',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
