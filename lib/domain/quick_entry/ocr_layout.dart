/// Egy felismert szövegsor és a helye a képen.
class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

/// A szövegfelismerés sorainak sorokba rendezése a helyük alapján.
///
/// A blokkokon a megnevezés bal oldalt, az összeg jobb oldalt áll; a
/// felismerő ezeket gyakran külön blokkba teszi. Az azonos magasságban lévő
/// darabokat egy sorba fűzzük (balról jobbra), így az „ÖSSZESEN” és a mellette
/// álló összeg egy sorba kerül.
String arrangeOcrLines(List<OcrLine> lines) {
  final sorted = [...lines.where((line) => line.text.trim().isNotEmpty)]
    ..sort((a, b) => a.centerY.compareTo(b.centerY));
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

double _rowCenter(List<OcrLine> row) =>
    row.fold<double>(0, (sum, line) => sum + line.centerY) / row.length;
