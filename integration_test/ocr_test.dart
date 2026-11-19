import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/domain/quick_entry/receipt_parser.dart';
import 'package:belefer/platform/receipt_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Egy kitalált blokk: soronként bal oldali szöveg és jobb oldali összeg.
class _Receipt {
  const _Receipt(this.name, this.rows, {required this.amount, this.title});

  final String name;
  final List<(String, String)> rows;
  final int amount;
  final String? title;
}

const _receipts = [
  _Receipt(
    'Konzol Game',
    [
      ('Sorszám: 2/6af488a2dba34/2026', ''),
      ('Dátum: 2026.11.11', ''),
      ('Konzol Game', ''),
      ('Budapest XIX., Üllői út 214/3.', ''),
      ('Termék neve', 'Termék ára'),
      ('Sony Playstation 4 (PS4)', '67999,-'),
      ('Slim 1 TB + 2db Dualshock 4', ''),
      ('3 hónap garancia', '0,-'),
      ('Összesen:', '67999 Ft.'),
      ('Köszönjük a vásárlást!', ''),
    ],
    amount: 67999,
    title: 'Konzol Game',
  ),
  _Receipt(
    'Lidl',
    [
      ('LIDL Magyarország Bt.', ''),
      ('1037 Budapest, Bécsi út 154.', ''),
      ('ADÓSZÁM: 12345678-2-44', ''),
      ('TEJ 2,8% 1L', '389'),
      ('KENYÉR', '649'),
      ('BANÁN 1,2 kg x 499', '599'),
      ('ÖSSZESEN:', '1 637'),
      ('BANKKÁRTYA', '1 637'),
      ('2026.11.15 18:42', ''),
    ],
    amount: 1637,
    title: 'Lidl',
  ),
  _Receipt(
    'kávézó',
    [
      ('Bambi Presszó', ''),
      ('1027 Budapest, Frankel Leó út 2.', ''),
      ('2 x Cappuccino', '1 780'),
      ('Túrós rétes', '990'),
      ('Szervizdíj 12%', '332'),
      ('Fizetendő:', '3 102 Ft'),
      ('Köszönjük!', ''),
    ],
    amount: 3102,
    title: 'Bambi Presszó',
  ),
  _Receipt('MOL', [
    ('MOL Nyrt.', ''),
    ('1117 Budapest, Október 23. utca 6.', ''),
    ('EVO 95 BENZIN 32,5 l', '20 443'),
    ('ÖSSZESEN:', '20 443 Ft'),
    ('Bankkártya', '20 443'),
  ], amount: 20443),
];

/// A blokk képe a megadott szögben elforgatva (mint egy ferdén vagy oldalra
/// fordítva lefotózott blokk).
Future<String> _photograph(_Receipt receipt, double angle, String file) async {
  const width = 900.0;
  const rowHeight = 64.0;
  final height = 60 + receipt.rows.length * rowHeight;
  final side = math.sqrt(width * width + height * height) + 80;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()..color = const Color(0xFFE6E2DA),
    )
    ..translate(side / 2, side / 2)
    ..rotate(angle)
    ..translate(-width / 2, -height / 2)
    ..drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );
  const style = TextStyle(color: Colors.black, fontSize: 38);
  for (final (index, (left, right)) in receipt.rows.indexed) {
    final y = 30 + index * rowHeight;
    final leftPainter = TextPainter(
      text: TextSpan(text: left, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width * 0.62);
    leftPainter.paint(canvas, Offset(30, y));
    if (right.isNotEmpty) {
      final rightPainter = TextPainter(
        text: TextSpan(text: right, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      rightPainter.paint(canvas, Offset(width - 30 - rightPainter.width, y));
    }
  }
  final image = await recorder.endRecording().toImage(
    side.toInt(),
    side.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final directory = await getTemporaryDirectory();
  final out = File('${directory.path}/$file.png');
  await out.writeAsBytes(png!.buffer.asUint8List(), flush: true);
  return out.path;
}

/// A telefonon futó szövegfelismerés (ML Kit) valódi próbája: kitalált
/// blokkokat rajzol álló, oldalra fordított és ferde helyzetben, felismerteti
/// és értelmezi őket. A CI a kiadási optimalizálóval (R8) fordított
/// változaton is lefuttatja.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final scanner = MlKitReceiptScanner();
  final context = QuickEntryContext(today: CalendarDay(2026, 11, 19));

  for (final receipt in _receipts) {
    for (final (label, angle) in [
      ('álló', 0.0),
      ('jobbra fordított', math.pi / 2),
      ('balra fordított', -math.pi / 2),
      ('ferde +4°', 0.07),
      ('ferde −5°', -0.087),
    ]) {
      testWidgets('${receipt.name}, $label', (tester) async {
        final text = (await tester.runAsync(() async {
          final path = await _photograph(
            receipt,
            angle,
            'blokk_${receipt.name.hashCode}_${angle.toStringAsFixed(2)}',
          );
          return scanner.recognizeImageFile(path);
        }))!;
        debugPrint('${receipt.name}, $label – felismert szöveg:\n$text');
        final result = interpretReceipt(text, context);
        expect(result.amount, receipt.amount, reason: text);
        if (receipt.title != null) {
          expect(result.title, receipt.title, reason: text);
        }
      });
    }
  }
}
