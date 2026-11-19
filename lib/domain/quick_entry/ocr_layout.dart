import 'dart:math' as math;

/// Egy felismert szövegsor és a helye a képen.
class OcrLine {
  const OcrLine(
    this.text,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.corners,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// A szöveg négy sarka az olvasási irány szerint (bal felső, jobb felső,
  /// jobb alsó, bal alsó), ahogy a szövegfelismerő adja. Elforgatott vagy
  /// ferde képen ebből derül ki a szöveg iránya.
  final List<math.Point<double>>? corners;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;

  List<math.Point<double>> get _points =>
      corners ??
      [
        math.Point(left, top),
        math.Point(right, top),
        math.Point(right, bottom),
        math.Point(left, bottom),
      ];
}

/// A szövegfelismerés sorainak sorokba rendezése a helyük alapján.
///
/// A blokkokon a megnevezés bal oldalt, az összeg jobb oldalt áll; a
/// felismerő ezeket gyakran külön blokkba teszi. Az azonos magasságban lévő
/// darabokat egy sorba fűzzük (balról jobbra), így az „ÖSSZESEN” és a mellette
/// álló összeg egy sorba kerül.
///
/// Ha a blokk a képen el van forgatva (oldalra fordítva, fejjel lefelé) vagy
/// ferde, előbb a szöveg uralkodó iránya szerint „kiegyenesítjük” a sorokat,
/// különben a sorok helyett az oszlopok kerülnének egymás mellé.
String arrangeOcrLines(List<OcrLine> lines) {
  final usable = [...lines.where((line) => line.text.trim().isNotEmpty)];
  final angle = dominantTextAngle(usable);
  final straightened = angle.abs() < 0.01
      ? usable
      : [for (final line in usable) _rotated(line, -angle)];
  final sorted = straightened..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<OcrLine>>[];
  for (final line in sorted) {
    List<OcrLine>? target;
    for (final row in rows.reversed.take(3)) {
      final reference = row.first;
      final tolerance =
          0.55 *
          (line.height < reference.height ? line.height : reference.height);
      if ((line.centerY - _rowCenter(row)).abs() <= tolerance) {
        target = row;
        break;
      }
    }
    if (target == null) {
      rows.add([line]);
    } else {
      target.add(line);
    }
  }
  return rows
      .map(
        (row) => ([...row]..sort((a, b) => a.left.compareTo(b.left)))
            .map((line) => line.text.trim())
            .join('  '),
      )
      .join('\n');
}

/// A szöveg uralkodó iránya radiánban (0: vízszintes, balról jobbra; π/2:
/// lefelé fut, azaz a blokk jobbra van fordítva), a sorok hosszával súlyozva.
double dominantTextAngle(List<OcrLine> lines) {
  var sumX = 0.0;
  var sumY = 0.0;
  for (final line in lines) {
    final points = line.corners;
    if (points == null || points.length < 2) continue;
    // A hosszú sorok iránya megbízhatóbb: a vektor hossza a súly.
    sumX += points[1].x - points[0].x;
    sumY += points[1].y - points[0].y;
  }
  if (sumX == 0 && sumY == 0) return 0;
  return math.atan2(sumY, sumX);
}

OcrLine _rotated(OcrLine line, double angle) {
  final cos = math.cos(angle);
  final sin = math.sin(angle);
  final points = [
    for (final point in line._points)
      math.Point(point.x * cos - point.y * sin, point.x * sin + point.y * cos),
  ];
  final xs = points.map((point) => point.x);
  final ys = points.map((point) => point.y);
  return OcrLine(
    line.text,
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
    corners: points,
  );
}

double _rowCenter(List<OcrLine> row) =>
    row.fold<double>(0, (sum, line) => sum + line.centerY) / row.length;
