import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/formatting.dart';
import '../../domain/monthly_summary.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../theme/category_style.dart';

/// A hónap kiadásai kategóriánként: összesítő sor, interaktív gyűrűdiagram
/// és jelmagyarázat.
///
/// Egy szeletre vagy jelmagyarázati sorra koppintva kiemeli a kategóriát.
/// A jelmagyarázat billentyűzettel és képernyőolvasóval is használható, és
/// ugyanazt az információt adja, mint a diagram.
class ExpenseBreakdown extends StatefulWidget {
  const ExpenseBreakdown({super.key, required this.summary});

  final MonthlySummary summary;

  @override
  State<ExpenseBreakdown> createState() => _ExpenseBreakdownState();
}

class _ExpenseBreakdownState extends State<ExpenseBreakdown> {
  String? _selectedId;

  @override
  void didUpdateWidget(ExpenseBreakdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stillPresent = widget.summary.expenseSlices.any(
      (slice) => slice.categoryId == _selectedId,
    );
    if (widget.summary.month != oldWidget.summary.month || !stillPresent) {
      _selectedId = null;
    }
  }

  void _toggle(String categoryId) {
    setState(() {
      _selectedId = _selectedId == categoryId ? null : categoryId;
    });
  }

  CategorySlice? get _selected {
    for (final slice in widget.summary.expenseSlices) {
      if (slice.categoryId == _selectedId) return slice;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final slices = summary.expenseSlices;
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryLine(
          percentTenths: summary.expenseTotalPercentTenths,
          amount: summary.expense,
        ),
        const SizedBox(height: Space.lg),
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, 260.0);
              return SizedBox.square(
                dimension: size,
                child: _DonutChart(
                  slices: slices,
                  selectedId: _selectedId,
                  onSliceTap: _toggle,
                  center: _CenterLabel(summary: summary, selected: selected),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.lg),
        if (slices.isEmpty)
          Text(
            'Ebben a hónapban még nincs kiadás. Rögzíts egyet, és itt '
            'látod, mire megy el a pénz.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
          )
        else
          for (final slice in slices)
            _LegendRow(
              slice: slice,
              selected: slice.categoryId == _selectedId,
              dimmed: _selectedId != null && slice.categoryId != _selectedId,
              onTap: () => _toggle(slice.categoryId),
            ),
      ],
    );
  }
}

/// `100% | 124 500 Ft` – a teljes havi kiadás.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.percentTenths, required this.amount});

  final int percentTenths;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final percent = formatPercentTenths(percentTenths);
    final total = formatForint(amount);
    return Semantics(
      container: true,
      label: 'Havi kiadás összesen: $percent, $total',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: percent,
              style: TextStyle(color: colors.textMuted),
            ),
            TextSpan(
              text: ' | ',
              style: TextStyle(color: colors.line),
            ),
            TextSpan(text: total),
          ],
        ),
        key: const ValueKey('expense-summary-line'),
        textAlign: TextAlign.center,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }
}

class _CenterLabel extends StatelessWidget {
  const _CenterLabel({required this.summary, required this.selected});

  final MonthlySummary summary;
  final CategorySlice? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final slice = selected;

    final Widget content;
    if (slice != null) {
      content = Column(
        key: ValueKey('center-${slice.categoryId}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            slice.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(color: colors.textMuted),
          ),
          Text(
            formatPercentTenths(slice.percentTenths),
            style: textTheme.headlineMedium?.copyWith(
              color: categoryStyle(slice.categoryId).color,
              fontFeatures: tabularFigures,
            ),
          ),
          Text(
            formatForint(slice.amount),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      );
    } else if (summary.hasExpense) {
      content = Column(
        key: const ValueKey('center-total'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Kiadás',
            style: textTheme.titleSmall?.copyWith(color: colors.textMuted),
          ),
          Text(
            formatForint(summary.expense),
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(fontFeatures: tabularFigures),
          ),
          Text(
            '${summary.expenseSlices.length} kategória',
            style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      );
    } else {
      content = Column(
        key: const ValueKey('center-empty'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Nincs kiadás', style: textTheme.titleMedium),
          Text(
            'ebben a hónapban',
            style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(48),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Semantics(
          liveRegion: true,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.slices,
    required this.selectedId,
    required this.onSliceTap,
    required this.center,
  });

  final List<CategorySlice> slices;
  final String? selectedId;
  final ValueChanged<String> onSliceTap;
  final Widget center;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            // A diagram rajza; a tartalmát a jelmagyarázat mondja el.
            Semantics(
              label: slices.isEmpty
                  ? 'Gyűrűdiagram: nincs kiadás'
                  : 'Gyűrűdiagram a kiadások kategóriánkénti megoszlásáról. '
                        'A részletek a jelmagyarázatban.',
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('expense-donut'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final id = _DonutPainter.sliceAt(
                    slices,
                    size,
                    details.localPosition,
                  );
                  if (id != null) onSliceTap(id);
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => CustomPaint(
                    painter: _DonutPainter(
                      slices: slices,
                      selectedId: selectedId,
                      progress: progress,
                      trackColor: colors.sunken,
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(child: center),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.selectedId,
    required this.progress,
    required this.trackColor,
  });

  final List<CategorySlice> slices;
  final String? selectedId;
  final double progress;
  final Color trackColor;

  static const double _thicknessRatio = 0.16;
  static const double _selectedExtra = 10;
  static const double _gap = 0.035;

  static double _radius(Size size) =>
      size.shortestSide / 2 - _selectedExtra / 2 - 2;

  /// Melyik szeletre esett a koppintás (vagy `null`).
  static String? sliceAt(
    List<CategorySlice> slices,
    Size size,
    Offset position,
  ) {
    if (slices.isEmpty) return null;
    final center = size.center(Offset.zero);
    final delta = position - center;
    final distance = delta.distance;
    final radius = _radius(size);
    final thickness = size.shortestSide * _thicknessRatio;
    if (distance < radius - thickness / 2 - 16 ||
        distance > radius + thickness / 2 + 16) {
      return null;
    }
    // 0 a 12 óránál, az óramutató járásával megegyezően.
    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    final fraction = angle / (2 * math.pi);
    var start = 0.0;
    for (final slice in slices) {
      final end = start + slice.percentTenths / 1000;
      if (fraction >= start && fraction < end) return slice.categoryId;
      start = end;
    }
    return slices.last.categoryId;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = _radius(size);
    final thickness = size.shortestSide * _thicknessRatio;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = trackColor,
    );
    if (slices.isEmpty) return;

    final gap = slices.length > 1 ? _gap : 0.0;
    final total = 2 * math.pi * progress;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep = total * slice.percentTenths / 1000;
      final isSelected = slice.categoryId == selectedId;
      final dimmed = selectedId != null && !isSelected;
      final color = categoryStyle(slice.categoryId).color;
      final visibleSweep = math.max(0.0, sweep - gap);
      if (visibleSweep > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          visibleSweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? thickness + _selectedExtra : thickness
            ..color = dimmed ? color.withValues(alpha: 0.32) : color,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final CategorySlice slice;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final color = categoryStyle(slice.categoryId).color;
    final percent = formatPercentTenths(slice.percentTenths);
    final amount = formatForint(slice.amount);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      onTap: onTap,
      label: '${slice.label}: $percent, $amount',
      hint: selected ? 'Kiemelés megszüntetése' : 'Kiemelés a diagramon',
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: dimmed ? 0.55 : 1,
        child: Material(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('legend-${slice.categoryId}'),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        slice.label,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      percent,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.textMuted,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Text(
                      amount,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
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
