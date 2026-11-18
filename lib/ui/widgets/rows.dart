import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';

/// Kapcsolós sor ikonnal, címmel és opcionális magyarázattal.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.switchKey,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.textMuted),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Switch(key: switchKey, value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Koppintható sor (továbblépés, művelet).
class LinkRow extends StatelessWidget {
  const LinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  Icon(icon, color: color ?? colors.textMuted),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(color: color),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ??
                      Icon(Icons.chevron_right_rounded, color: colors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vékony elválasztó a panelek sorai között.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 52, color: context.colors.line);
}

/// Választható lehetőségek tördelődő sora (pl. gyakoriság).
class ChoiceWrap<T> extends StatelessWidget {
  const ChoiceWrap({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.semanticLabel,
  });

  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final (value, label) in options)
            ChoiceChip(
              key: ValueKey('choice-$label'),
              label: Text(label),
              selected: value == selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(value),
              selectedColor: colors.accent,
              labelStyle: TextStyle(
                color: value == selected ? colors.onAccent : colors.text,
                fontWeight: value == selected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
              side: BorderSide(
                color: value == selected ? colors.accent : colors.line,
              ),
              backgroundColor: colors.raised,
              shape: const StadiumBorder(),
            ),
        ],
      ),
    );
  }
}
