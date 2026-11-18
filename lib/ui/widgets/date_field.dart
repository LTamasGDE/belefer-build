import 'package:flutter/material.dart';

import '../../domain/calendar.dart';
import '../../domain/formatting.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';

/// Dátummező: koppintásra dátumválasztó nyílik.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.date,
    required this.onTap,
    this.label = 'Dátum',
    this.fieldKey = const ValueKey('field-date'),
    this.valueText,
  });

  final String label;
  final Key fieldKey;

  /// A dátum helyett megjelenítendő szöveg (pl. „Nincs záró dátum”).
  final String? valueText;

  final CalendarDay date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final value = valueText ?? formatFullDate(date);
    return Semantics(
      container: true,
      button: true,
      onTap: onTap,
      label: '$label: $value. Módosítás',
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
          key: fieldKey,
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
                        label,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(value, style: textTheme.bodyLarge),
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
