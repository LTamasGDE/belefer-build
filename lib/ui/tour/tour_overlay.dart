import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import 'tour_keys.dart';

/// A körbevezetés egy lépése.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.tab = 0,
    this.target,
    this.navIndex,
    this.optional = false,
  });

  final String title;
  final String body;

  /// Melyik fül legyen látható.
  final int tab;

  /// A kiemelendő elem (vagy `null`: középre igazított kártya).
  final GlobalKey? target;

  /// Az alsó navigáció kiemelendő eleme.
  final int? navIndex;

  /// Ha a kiemelendő elem nem látszik, a lépés kimarad.
  final bool optional;
}

/// Sötétített réteg kivágással és magyarázó kártyával. A felület alatta nem
/// érinthető; a lépések között a fülek maguktól váltanak.
class TourOverlay extends StatefulWidget {
  const TourOverlay({
    super.key,
    required this.steps,
    required this.onShowTab,
    required this.onFinish,
    this.navCount = 5,
  });

  final List<TourStep> steps;
  final ValueChanged<int> onShowTab;

  /// Kihagyáskor és a végén is meghívódik.
  final VoidCallback onFinish;
  final int navCount;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  final _overlayKey = GlobalKey();
  final _nextFocus = FocusNode();
  int _index = 0;
  Rect? _hole;
  int _generation = 0;

  TourStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _go(0, forward: true);
    });
  }

  @override
  void dispose() {
    _nextFocus.dispose();
    super.dispose();
  }

  Future<void> _go(int index, {required bool forward}) async {
    final generation = ++_generation;
    setState(() {
      _index = index;
      _hole = null;
    });
    final step = widget.steps[index];
    widget.onShowTab(step.tab);
    await _nextFrame();
    if (!mounted || generation != _generation) return;

    final target = step.target;
    final targetContext = target?.currentContext;
    if (target != null && step.navIndex == null) {
      if (targetContext == null || !targetContext.mounted) {
        if (step.optional) {
          final next = forward ? index + 1 : index - 1;
          if (next >= 0 && next < widget.steps.length) {
            unawaited(_go(next, forward: forward));
          } else {
            widget.onFinish();
          }
          return;
        }
      } else {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.25,
          duration: const Duration(milliseconds: 250),
        );
        await _nextFrame();
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() => _hole = _measure(step));
    _nextFocus.requestFocus();
  }

  Future<void> _nextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    WidgetsBinding.instance.scheduleFrame();
    return completer.future;
  }

  Rect? _measure(TourStep step) {
    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final key = step.navIndex != null ? TourKeys.navigation : step.target;
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || box == null || !box.attached || !box.hasSize) {
      return null;
    }
    final topLeft = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
    var rect = topLeft & box.size;
    final navIndex = step.navIndex;
    if (navIndex != null) {
      final width = rect.width / widget.navCount;
      rect = Rect.fromLTWH(
        rect.left + width * navIndex,
        rect.top,
        width,
        rect.height,
      );
    }
    return rect.inflate(6);
  }

  void _next() {
    if (_index + 1 >= widget.steps.length) {
      widget.onFinish();
    } else {
      _go(_index + 1, forward: true);
    }
  }

  void _back() {
    if (_index > 0) _go(_index - 1, forward: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final last = _index == widget.steps.length - 1;
    final hole = _hole;

    final card = Material(
      color: colors.raised,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.lg,
          Space.lg,
          Space.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_index + 1} / ${widget.steps.length}',
              style: textTheme.labelMedium?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: Space.xs),
            Semantics(
              liveRegion: true,
              header: true,
              child: Text(
                _step.title,
                key: const ValueKey('tour-title'),
                style: textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: Space.sm),
            Text(_step.body, style: textTheme.bodyMedium),
            const SizedBox(height: Space.md),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.xs,
              children: [
                if (!last)
                  TextButton(
                    key: const ValueKey('tour-skip'),
                    onPressed: widget.onFinish,
                    child: const Text('Kihagyás'),
                  ),
                if (_index > 0)
                  OutlinedButton(
                    key: const ValueKey('tour-back'),
                    onPressed: _back,
                    child: const Text('Vissza'),
                  ),
                FilledButton(
                  key: const ValueKey('tour-next'),
                  focusNode: _nextFocus,
                  onPressed: _next,
                  child: Text(last ? 'Kezdjük!' : 'Tovább'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onFinish,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _back,
      },
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Bemutató',
        child: LayoutBuilder(
          key: _overlayKey,
          builder: (context, constraints) {
            final size = constraints.biggest;
            final padding = MediaQuery.paddingOf(context);
            const margin = Space.lg;
            final maxCardWidth = (size.width - 2 * margin).clamp(0, 440);
            Widget positioned;
            if (hole == null) {
              positioned = Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxCardWidth.toDouble(),
                  ),
                  child: card,
                ),
              );
            } else {
              // A kártya a kiemelt elem alá vagy fölé kerül; ha egyik helyen
              // sem fér el (nagy elem), a képernyő aljára.
              const needed = 250.0;
              final spaceBelow = size.height - hole.bottom - padding.bottom;
              final spaceAbove = hole.top - padding.top;
              final double? top;
              final double? bottom;
              if (spaceBelow >= needed ||
                  (spaceBelow >= spaceAbove && spaceBelow >= needed * 0.8)) {
                top = hole.bottom + Space.md;
                bottom = null;
              } else if (spaceAbove >= needed) {
                top = null;
                bottom = size.height - hole.top + Space.md;
              } else {
                top = null;
                bottom = padding.bottom + margin;
              }
              positioned = Positioned(
                left: margin,
                right: margin,
                top: top,
                bottom: bottom,
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxCardWidth.toDouble(),
                    ),
                    child: card,
                  ),
                ),
              );
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        painter: _DimPainter(
                          hole: hole,
                          color: Colors.black.withValues(alpha: 0.62),
                          ring: colors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                positioned,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DimPainter extends CustomPainter {
  const _DimPainter({
    required this.hole,
    required this.color,
    required this.ring,
  });

  final Rect? hole;
  final Color color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = this.hole;
    if (hole == null) {
      canvas.drawPath(full, Paint()..color = color);
      return;
    }
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(22));
    final cut = Path()..addRRect(rrect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, cut),
      Paint()..color = color,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_DimPainter oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.color != color ||
      oldDelegate.ring != ring;
}
