import 'dart:io';
import 'dart:ui' as ui;

import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/domain/quick_entry/receipt_parser.dart';
import 'package:belefer/platform/receipt_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// A telefonon futó szövegfelismerés (ML Kit) valódi próbája: egy
/// blokkszerű képet rajzol, felismerteti, és értelmezi. A CI ezt a kiadási
/// optimalizálóval (R8) fordított változaton is lefuttatja.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('blokk felismerése és értelmezése a telefonon', (tester) async {
    const lines = [
      'KONZOL GAME',
      'Budapest, Üllői út 214.',
      'Dátum: 2026.11.11',
      'PlayStation 4 Slim 1TB   67999,-',
      '3 hónap garancia              0,-',
      'Összesen:          67999 Ft',
      'Köszönjük a vásárlást!',
    ];
    const size = Size(1000, 760);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final painter = TextPainter(
      text: TextSpan(
        text: lines.join('\n'),
        style: const TextStyle(color: Colors.black, fontSize: 46, height: 1.45),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 60);
    painter.paint(canvas, const Offset(30, 30));
    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/belefer_ocr_proba.png');
    await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);

    final text = await MlKitReceiptScanner().recognizeImageFile(file.path);
    debugPrint('Felismert szöveg:\n$text');
    expect(text.toUpperCase(), contains('KONZOL'));
    expect(text, contains('67999'));

    final result = interpretReceipt(
      text,
      QuickEntryContext(today: CalendarDay(2026, 11, 19)),
    );
    expect(result.amount, 67999);
    expect(result.date, CalendarDay(2026, 11, 11));
  });
}
