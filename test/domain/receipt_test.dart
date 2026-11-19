import 'dart:math' as math;

import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/domain/quick_entry/ocr_layout.dart';
import 'package:belefer/domain/quick_entry/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final context = QuickEntryContext(today: CalendarDay(2026, 11, 17));

  group('blokkok', () {
    test('ferde fotó: összeg a felirat előtt, „ára” nem Zara', () {
      // A Konzol Game blokk felismert szövege: a jobb oldali „67999 Ft.” a
      // ferdeség miatt az „Összesen:” elé került, a „Termék ára” külön sorba.
      const text = '''
Sorszám: 2/6af488a2dba34/2026
Dátum: 2026.11.11
KonzolGAME
Konzol Game
Budapest XIX., Üllői út 214/3.
Tel.: +36 20 257 8581
Termék neve Termék
ára
Sony Playstation 4 (PS4) 67999,-
Slim 1 TB + 2db
Dualshock 4 vezeték
nélküli Controller [93055/]
9714341
3 hónap garancia 0,-
[66890/]
67999 Ft.
Összesen:
Köszönjük a vásárlást!
P.H.
''';
      final result = interpretReceipt(text, context);
      expect(result.amount, 67999);
      expect(result.date, CalendarDay(2026, 11, 11));
      expect(result.title, isNot('Zara'));
      expect(result.title, startsWith('Konzol'));
      expect(result.categoryId, isNot('clothing'));
    });

    test('összeg és felirat egy sorban, sorszám nem összeg', () {
      const text = '''
Sorszám: 2/6af488a2dba34/2026
Dátum: 2026.11.11
Konzol Game
Termék neve Termék ára
3 hónap garancia 0,-
Összesen: 67999 Ft.
''';
      final result = interpretReceipt(text, context);
      expect(result.amount, 67999);
      expect(result.title, 'Konzol Game');
    });

    test('Lidl-blokk: kereskedő, végösszeg, dátum', () {
      const text = '''
LIDL Magyarország Bt.
1037 Budapest, Bécsi út 154.
ADÓSZÁM: 12345678-2-44
TEJ 2,8% 1L              389
KENYÉR                   649
BANÁN 1,2 kg x 499      599
ÖSSZESEN:              1 637
BANKKÁRTYA             1 637
2026.11.15 18:42
NYUGTASZÁM: 0042/01234
''';
      final result = interpretReceipt(text, context);
      expect(result.amount, 1637);
      expect(result.title, 'Lidl');
      expect(result.categoryId, 'groceries');
      expect(result.date, CalendarDay(2026, 11, 15));
      expect(result.isComplete, isTrue);
    });

    test('szövegfelismerési hibákkal (0SSZESEN, elírt kereskedő)', () {
      const text = '''
TESC0 GLOBAL Zrt.
ÁFA 27% 1 200
0SSZESEN 5 490 Ft
26.11.14
''';
      final result = interpretReceipt(text, context);
      expect(result.amount, 5490);
      expect(result.categoryId, 'groceries');
      expect(result.date, CalendarDay(2026, 11, 14));
    });

    test(
      'ismeretlen bolt: az első sor a megnevezés, a tételsorokból kategória',
      () {
        const text = '''
SARKI KÁVÉZÓ KFT
1 x Cappuccino  890
1 x Croissant   650
Fizetendő összeg: 1 540 Ft
''';
        final result = interpretReceipt(text, context);
        expect(result.amount, 1540);
        expect(result.title, 'Sarki Kávézó');
        expect(result.categoryId, 'dining');
      },
    );

    test('elektronikus számla', () {
      const text = '''
SZÁMLA
Eladó: Magyar Telekom Nyrt.
Vevő: Minta Anna
Számla kelte: 2026.11.05
Teljesítés dátuma: 2026.11.05
Nettó összeg: 4 717 Ft
ÁFA (27%): 1 273 Ft
Bruttó végösszeg: 5 990 Ft
''';
      final result = interpretReceipt(text, context);
      expect(result.amount, 5990);
      expect(result.title, 'Telekom');
      expect(result.categoryId, 'utilities');
      expect(result.date, CalendarDay(2026, 11, 5));
    });

    test('végösszeg nélkül a legnagyobb forintos összeget javasolja', () {
      const text = '''
Piaci árus
Alma 1 200 Ft
Körte 900 Ft
''';
      final result = interpretReceipt(text, context);
      expect(result.amount, 1200);
      expect(result.notes, isNotEmpty);
    });
  });

  test('elforgatott fotó felismert, összekevert szövege (valódi eset)', () {
    // A 26.11.3 így rakta össze a 90°-kal elfordított Konzol Game blokkot.
    const text = '''
ára  0.-
Termék  67999,-  67999 Ft.
VBZS
nprdeccuuzss  VASARLAS BIZONAT
Sorszam 2/6af488a2dba34/2026  Dalum:
2026.11.11  KonzolAME  Konzol Game
Budapest XIX., Üllöi út 214/3.  Tel.: +36
20 257 8581  Terimék neve  Sony
Playstation 4 (PS4)  nélkiuli Controller
93055/1]  Köszönjik a vásárlástt  PH
Slim 1 TB + 2db  Dualshock 4 vezeték  3
hónap garancia  OsSzesen:
9714341  |66890/|
''';
    final result = interpretReceipt(text, context);
    expect(result.amount, 67999);
    expect(result.date, CalendarDay(2026, 11, 11));
    expect(result.title, isNot('Zara'));
    expect(result.categoryId, isNot('clothing'));
  });

  group('elforgatott és ferde blokk sorai', () {
    // Álló blokk: bal oldalt a megnevezések, jobb oldalt az összegek.
    const upright = [
      ('Konzol Game', 100.0, 50.0, 400.0, 80.0),
      ('Budapest XIX., Üllői út 214/3.', 60.0, 92.0, 460.0, 122.0),
      ('Sony Playstation 4 (PS4)', 40.0, 200.0, 330.0, 230.0),
      ('67999,-', 400.0, 200.0, 480.0, 230.0),
      ('3 hónap garancia', 40.0, 250.0, 260.0, 280.0),
      ('0,-', 440.0, 250.0, 480.0, 280.0),
      ('Összesen:', 40.0, 400.0, 160.0, 430.0),
      ('67999 Ft.', 380.0, 400.0, 480.0, 430.0),
      ('Köszönjük a vásárlást!', 80.0, 480.0, 420.0, 510.0),
    ];
    const expected =
        'Konzol Game\n'
        'Budapest XIX., Üllői út 214/3.\n'
        'Sony Playstation 4 (PS4)  67999,-\n'
        '3 hónap garancia  0,-\n'
        'Összesen:  67999 Ft.\n'
        'Köszönjük a vásárlást!';

    List<OcrLine> photographed(double angle) {
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      math.Point<double> turn(double x, double y) =>
          math.Point(x * cos - y * sin + 700, x * sin + y * cos + 700);
      return [
        for (final (text, l, t, r, b) in upright.reversed)
          () {
            final corners = [turn(l, t), turn(r, t), turn(r, b), turn(l, b)];
            final xs = corners.map((p) => p.x);
            final ys = corners.map((p) => p.y);
            return OcrLine(
              text,
              xs.reduce(math.min),
              ys.reduce(math.min),
              xs.reduce(math.max),
              ys.reduce(math.max),
              corners: corners,
            );
          }(),
      ];
    }

    for (final (name, angle) in [
      ('álló', 0.0),
      ('jobbra fordított (90°)', math.pi / 2),
      ('fejjel lefelé (180°)', math.pi),
      ('balra fordított (270°)', -math.pi / 2),
      ('kicsit ferde (+3°)', 0.052),
      ('kicsit ferde (−4°)', -0.07),
    ]) {
      test(name, () {
        final text = arrangeOcrLines(photographed(angle));
        expect(text, expected);
        final result = interpretReceipt(text, context);
        expect(result.amount, 67999);
        expect(result.title, 'Konzol Game');
      });
    }
  });

  test('a felismert darabok sorokba rendeződnek', () {
    final text = arrangeOcrLines(const [
      OcrLine('1 637', 300, 102, 360, 120),
      OcrLine('ÖSSZESEN:', 10, 100, 120, 118),
      OcrLine('LIDL', 10, 10, 80, 30),
      OcrLine('BANKKÁRTYA', 10, 130, 140, 148),
      OcrLine('1 637', 300, 131, 360, 149),
    ]);
    expect(text, 'LIDL\nÖSSZESEN:  1 637\nBANKKÁRTYA  1 637');
  });
}
