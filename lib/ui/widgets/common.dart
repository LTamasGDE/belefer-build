import 'package:flutter/material.dart';

import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../theme/category_style.dart';

/// Középre igazított, korlátozott szélességű tartalom széles kijelzőn.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// A Belefér kártyája: lekerekített, finoman keretezett felület.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.color,
    this.radius = Radii.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: color ?? colors.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Kisebb szakaszcím a kártyák fölött.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: style),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Kategória ikonja a kategória színével.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.categoryId, {super.key, this.size = 44});

  final String categoryId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(categoryId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: isDark ? 0.22 : 0.16),
          borderRadius: BorderRadius.circular(size * 0.36),
        ),
        child: Icon(
          style.icon,
          size: size * 0.5,
          color: isDark
              ? Color.lerp(style.color, Colors.white, 0.25)
              : Color.lerp(style.color, Colors.black, 0.25),
        ),
      ),
    );
  }
}

/// Előjeles, típus szerint színezett összeg.
class AmountText extends StatelessWidget {
  const AmountText({
    super.key,
    required this.amount,
    required this.type,
    this.style,
  });

  final int amount;
  final EntryType type;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isExpense = type == EntryType.expense;
    final base = style ?? Theme.of(context).textTheme.titleMedium!;
    return Text(
      formatForint(isExpense ? -amount : amount, signed: true),
      maxLines: 1,
      style: base.copyWith(
        color: isExpense ? colors.expense : colors.income,
        fontWeight: FontWeight.w700,
        fontFeatures: tabularFigures,
      ),
    );
  }
}

/// Üres állapot rövid magyarázattal és opcionális művelettel.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent.withValues(alpha: 0.18),
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: Icon(icon, size: 34, color: colors.accentText),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: Space.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
