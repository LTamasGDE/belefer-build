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
