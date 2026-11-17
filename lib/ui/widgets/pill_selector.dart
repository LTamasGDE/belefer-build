import 'package:flutter/material.dart';

import '../theme/belefer_colors.dart';

/// Egy választási lehetőség a [PillSelector]-ban.
class PillOption<T> {
  const PillOption({
    required this.value,
    required this.label,
    this.icon,
    this.color,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// A kijelölt állapot színe; alapból az akcentusszín.
  final Color? color;
}

/// Egymás melletti, egyforma szélességű kapcsológombok (szegmentált vezérlő).
class PillSelector<T> extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<PillOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.sunken,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            for (final option in options)
              Expanded(
                child: _Pill<T>(
                  option: option,
                  selected: option.value == selected,
                  onTap: () => onChanged(option.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill<T> extends StatelessWidget {
  const _Pill({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final PillOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = option.color ?? colors.accent;
    final foreground = selected
        ? (option.color == null ? colors.onAccent : Colors.white)
        : colors.textMuted;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (option.icon != null) ...[
                        Icon(option.icon, size: 18, color: foreground),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(color: foreground),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
