import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/amount_parser.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:belefer/domain/recurring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Egy elvárt értelmezés; csak a megadott mezőket ellenőrizzük.
class _Case {
  const _Case(
    this.text, {
    this.amount,
    this.type,
    this.category,
    this.title,
    this.intent = QuickIntent.record,
    this.date,
    this.frequency,
    this.complete,
  });

  final String text;
  final int? amount;
  final EntryType? type;
  final String? category;
  final String? title;
  final QuickIntent intent;
  final CalendarDay? date;
  final Frequency? frequency;
  final bool? complete;
}

// 2026. november 17., kedd.
final CalendarDay _today = CalendarDay(2026, 11, 17);

final List<RecurringRule> _rules = [
  RecurringRule(
    id: 1,
    type: EntryType.expense,
    title: 'Netflix',
    categoryId: 'subscriptions',
    amount: 4990,
    startDate: CalendarDay(2026, 10, 5),
  ),
  RecurringRule(
    id: 2,
    type: EntryType.expense,
    title: 'Lakbér',
    categoryId: 'housing',
    amount: 180000,
    startDate: CalendarDay(2026, 1, 1),
  ),
  RecurringRule(
    id: 3,
    type: EntryType.expense,
    title: 'Spotify',
    categoryId: 'subscriptions',
    amount: 1990,
    startDate: CalendarDay(2026, 3, 12),
  ),
  RecurringRule(
    id: 4,
    type: EntryType.income,
    title: 'Fizetés',
    categoryId: 'salary',
    amount: 420000,
    startDate: CalendarDay(2026, 1, 10),
  ),
];

const EntryType _out = EntryType.expense;
const EntryType _in = EntryType.income;

final List<_Case> _cases = [
  // --- Bevásárlás, kereskedők, sorrend, elírás ---
  const _Case(
    'Lidlben vettem kenyeret 850-ért',
    amount: 850,
    type: _out,
    category: 'groceries',
    title: 'Lidl',
  ),
  const _Case('lidl 12 450', amount: 12450, category: 'groceries', title: 'Lidl'),
  const _Case('12450 ft lidl', amount: 12450, category: 'groceries'),
  const _Case('lild 3200', amount: 3200, category: 'groceries', title: 'Lidl'),
  const _Case('LIDL 3200FT', amount: 3200, title: 'Lidl'),
  const _Case(
    'tesco bevásárlás 23.580 Ft',
    amount: 23580,
    category: 'groceries',
    title: 'Tesco',
  ),
  const _Case('Tescóban 5e', amount: 5000, title: 'Tesco'),
  const _Case('teszkóban 5e', amount: 5000, category: 'groceries'),
  const _Case('aldi 2,5k', amount: 2500, title: 'Aldi'),
  const _Case('spar 1 234 ft', amount: 1234, title: 'Spar'),
  const _Case('penny marketben 4560', amount: 4560, title: 'Penny'),
  const _Case('heti nagybevásárlás 32000', amount: 32000, category: 'groceries'),
  const _Case('bevasarlas 8900', amount: 8900, category: 'groceries'),
  const _Case('bevásároltam 6700-ért', amount: 6700, category: 'groceries'),
  const _Case('kenyér 650', amount: 650, title: 'Kenyér', category: 'groceries'),
  const _Case('tej 389', amount: 389, title: 'Tej'),
  const _Case('piac 4200', amount: 4200, title: 'Piac'),
  const _Case('pékség 1200', amount: 1200, title: 'Pékség'),
  const _Case(
    'tegnap 3 kg krumpli 1200',
    amount: 1200,
    title: 'Krumpli',
    category: 'groceries',
  ),
  const _Case('2 db sör 900 ft', amount: 900, category: 'groceries'),
  const _Case('rossmann 3450', amount: 3450, title: 'Rossmann'),
  const _Case('dm 2100', amount: 2100, title: 'dm'),
  // --- Étterem, kávé ---
  const _Case('kávé 890', amount: 890, title: 'Kávé', category: 'dining'),
  const _Case('890 kávé', amount: 890, title: 'Kávé', category: 'dining'),
  const _Case('kave 890ft', amount: 890, category: 'dining'),
  const _Case('kvae 890', amount: 890, category: 'dining'),
  const _Case('ebéd a menzán 1450', amount: 1450, category: 'dining'),
  const _Case('ebed 2490', amount: 2490, title: 'Ebéd'),
  const _Case('vacsora 12000 forint', amount: 12000, title: 'Vacsora'),
  const _Case('pizza 4500', amount: 4500, title: 'Pizza'),
  const _Case('mekiben 2990', amount: 2990, title: 'McDonald’s'),
  const _Case('mcdonalds 3200', amount: 3200, category: 'dining'),
  const _Case('wolt 5600', amount: 5600, title: 'Wolt'),
  const _Case('rendeltem woltról 6500-ért', amount: 6500, title: 'Wolt'),
  const _Case('starbucks 1990', amount: 1990, title: 'Starbucks'),
  const _Case('fagyi 900', amount: 900, category: 'dining'),
  const _Case('kocsmában 3500', amount: 3500, category: 'dining'),
  // --- Közlekedés ---
  const _Case('benzin 15e', amount: 15000, title: 'Benzin', category: 'transport'),
  const _Case('tankoltam 20000', amount: 20000, category: 'transport'),
  const _Case('tankoltam a molnál 18 500', amount: 18500, title: 'MOL'),
  const _Case('omv 12000', amount: 12000, category: 'transport'),
  const _Case('bérlet 8950', amount: 8950, title: 'Bérlet', category: 'transport'),
  const _Case('kifizettem a havi bérletet 8950', amount: 8950, category: 'transport'),
  const _Case('taxi 4300', amount: 4300, category: 'transport'),
  const _Case('uber 3800', amount: 3800, title: 'Uber'),
  const _Case('parkolás 600', amount: 600, category: 'transport'),
  const _Case('vonatjegy 3500', amount: 3500, category: 'transport'),
  const _Case('máv 2990', amount: 2990, title: 'MÁV'),
  const _Case('autópálya matrica 6000', amount: 6000, category: 'transport'),
  // --- Lakhatás, rezsi ---
  const _Case('fizettem a lakbért 180000', amount: 180000, category: 'housing'),
  const _Case('albérlet 150 ezer', amount: 150000, category: 'housing'),
  const _Case('közös költség 12000', amount: 12000, category: 'housing'),
  const _Case('villanyszámla 9800', amount: 9800, category: 'utilities'),
  const _Case('villany 9800', amount: 9800, category: 'utilities'),
  const _Case('gázszámla 7500', amount: 7500, category: 'utilities'),
  const _Case('internet 6990', amount: 6990, category: 'utilities'),
  const _Case('telefonszámla 5990', amount: 5990, category: 'utilities'),
  const _Case('telekom 5990', amount: 5990, title: 'Telekom'),
  const _Case('rezsi 25000', amount: 25000, category: 'utilities'),
  // --- Egészség, ruházat, szórakozás, tanulás, ajándék ---
  const _Case('gyógyszer 3400', amount: 3400, category: 'health'),
  const _Case('patikában 2800', amount: 2800, category: 'health'),
  const _Case('fogorvos 25000', amount: 25000, category: 'health'),
  const _Case('cipő 24990', amount: 24990, category: 'clothing'),
  const _Case('vettem egy kabátot 32000', amount: 32000, category: 'clothing'),
  const _Case('zara 12990', amount: 12990, title: 'Zara'),
  const _Case('mozi 2800', amount: 2800, category: 'entertainment'),
  const _Case('cinema city 3600', amount: 3600, title: 'Cinema City'),
  const _Case('koncertjegy 15000', amount: 15000, category: 'entertainment'),
  const _Case('steam 4500', amount: 4500, title: 'Steam'),
  const _Case('tankönyv 6500', amount: 6500, category: 'education'),
  const _Case('könyv 4200', amount: 4200, category: 'education'),
  const _Case('libri 3990', amount: 3990, title: 'Libri'),
  const _Case('ajándék anyának 8000', amount: 8000, category: 'gifts'),
  const _Case('virág 5000', amount: 5000, category: 'gifts'),
  const _Case('ikea 45000', amount: 45000, title: 'IKEA'),
  const _Case('fodrász 7000', amount: 7000, category: 'other_expense'),
  // --- Összeg-formák ---
  const _Case('kávé 1.5k', amount: 1500),
  const _Case('ebéd kétezer-ötszáz forint', amount: 2500),
  const _Case('ebéd kétezerötszáz', amount: 2500),
  const _Case('ebéd ötezer', amount: 5000),
  const _Case('lakbér másfél millió', amount: 1500000),
  const _Case('mozi 3 ezer', amount: 3000),
  const _Case('kávé 990,-', amount: 990),
  const _Case('benzin 15 000 Ft-ért', amount: 15000),
  const _Case('benzin 15000HUF', amount: 15000),
  const _Case('HUF 4500 kávé', amount: 4500),
  const _Case('4 500,00 Ft kávé', amount: 4500),
  const _Case('ruha 12.990', amount: 12990),
  // --- Dátumok ---
  _Case('tegnap kávé 900', date: CalendarDay(2026, 11, 16)),
  _Case('tegnapelőtt ebéd 2500', date: CalendarDay(2026, 11, 15)),
  _Case('pénteken mozi 3000', date: CalendarDay(2026, 11, 13)),
  _Case('múlt pénteken mozi 3000', date: CalendarDay(2026, 11, 13)),
  _Case('hétfőn 4500 bolt', date: CalendarDay(2026, 11, 16)),
  _Case('kedden kávé 800', date: CalendarDay(2026, 11, 17)),
  _Case('nov 3 lidl 4500', amount: 4500, date: CalendarDay(2026, 11, 3)),
  _Case('november 3-án lidl 4500', amount: 4500, date: CalendarDay(2026, 11, 3)),
  _Case('2026.11.03 lidl 4500', amount: 4500, date: CalendarDay(2026, 11, 3)),
  _Case('2026-11-03 lidl 4500', amount: 4500, date: CalendarDay(2026, 11, 3)),
  _Case('11.03. lidl 4500', amount: 4500, date: CalendarDay(2026, 11, 3)),
  _Case('5-én lidl 4500', amount: 4500, date: CalendarDay(2026, 11, 5)),
  _Case('20-án vacsora 9000', amount: 9000, date: CalendarDay(2026, 10, 20)),
  _Case('3 napja ebéd 2500', amount: 2500, date: CalendarDay(2026, 11, 14)),
  _Case('egy hete mozi 2800', amount: 2800, date: CalendarDay(2026, 11, 10)),
  _Case('okt 28 ruha 9990', amount: 9990, date: CalendarDay(2026, 10, 28)),
  _Case('december 24 ajándék 15000', amount: 15000, date: CalendarDay(2025, 12, 24)),
  _Case('kávé 900', date: CalendarDay(2026, 11, 17)),
  // --- Bevételek ---
  const _Case(
    'megjött a fizetés 420000',
    amount: 420000,
    type: _in,
    category: 'salary',
    title: 'Fizetés',
  ),
  const _Case('fizetés 420e', amount: 420000, type: _in, category: 'salary'),
  const _Case('fizu 380 ezer', amount: 380000, type: _in),
  const _Case('kaptam 5000-et anyától', amount: 5000, type: _in),
  const _Case('zsebpénz 10000', amount: 10000, type: _in, category: 'gift_income'),
  const _Case('ösztöndíj 45000', amount: 45000, type: _in, category: 'scholarship'),
  const _Case('osztondij 45000', amount: 45000, type: _in, category: 'scholarship'),
  const _Case('visszakaptam a kauciót 150000', amount: 150000, type: _in),
  const _Case('eladtam a biciklit 40000', amount: 40000, type: _in, category: 'side_income'),
  const _Case('nyertem 20000', amount: 20000, type: _in, category: 'other_income'),
  const _Case('korrepetálás 6000', amount: 6000, type: _in, category: 'side_income'),
  const _Case('diákmunka 85000', amount: 85000, type: _in),
  // --- Ismétlődő: új ---
  const _Case(
    'Netflix havi 4990',
    amount: 4990,
    intent: QuickIntent.createRecurring,
    title: 'Netflix',
    frequency: Frequency.monthly,
    category: 'subscriptions',
  ),
  const _Case(
    'előfizettem a spotifyra 1990',
    amount: 1990,
    intent: QuickIntent.createRecurring,
    title: 'Spotify',
    frequency: Frequency.monthly,
  ),
  const _Case(
    'elofizettem hbo max 3490 havonta',
    amount: 3490,
    intent: QuickIntent.createRecurring,
    title: 'HBO Max',
  ),
  const _Case(
    'edzőterem bérlet havonta 15000',
    amount: 15000,
    intent: QuickIntent.createRecurring,
    category: 'health',
    frequency: Frequency.monthly,
  ),
  const _Case(
    'hetente takarítás 8000',
    amount: 8000,
    intent: QuickIntent.createRecurring,
    frequency: Frequency.weekly,
  ),
  const _Case(
    'évente autópálya matrica 57000',
    amount: 57000,
    intent: QuickIntent.createRecurring,
    frequency: Frequency.yearly,
  ),
  _Case(
    'minden hónap 5-én lakbér 180000',
    amount: 180000,
    intent: QuickIntent.createRecurring,
    category: 'housing',
    date: CalendarDay(2026, 12, 5),
  ),
  const _Case(
    'iCloud 1,99 havi',
    intent: QuickIntent.createRecurring,
    title: 'iCloud',
  ),
  const _Case(
    'Spotify 1990 Ft/hó',
    amount: 1990,
    intent: QuickIntent.createRecurring,
  ),
  // --- Ismétlődő: lemondás és módosítás ---
  const _Case(
    'lemondtam a netflixet',
    intent: QuickIntent.cancelRecurring,
    title: 'Netflix',
    complete: true,
  ),
  const _Case(
    'Lemondtam a Spotifyt',
    intent: QuickIntent.cancelRecurring,
    title: 'Spotify',
  ),
  const _Case(
    'megszüntettem a netflix előfizetést',
    intent: QuickIntent.cancelRecurring,
    title: 'Netflix',
  ),
  const _Case(
    'elköltöztem, mostantól 150 ezer a lakbér',
    amount: 150000,
    intent: QuickIntent.changeRecurring,
    title: 'Lakbér',
  ),
  const _Case(
    'a lakbér 200000 lett',
    amount: 200000,
    intent: QuickIntent.changeRecurring,
    title: 'Lakbér',
  ),
  const _Case(
    'drágult a netflix 5490',
    amount: 5490,
    intent: QuickIntent.changeRecurring,
    title: 'Netflix',
  ),
  // --- Hiányos mondatok ---
  const _Case('3500', amount: 3500, complete: false),
  const _Case('lidl', title: 'Lidl', complete: false),
  const _Case('valami', complete: false),
];

void main() {
  final context = QuickEntryContext(today: _today, rules: _rules);

  group('gyorsrögzítés – mondatok', () {
    for (final c in _cases) {
      test(c.text, () {
        final result = interpretQuickEntry(c.text, context);
        final description =
            'amount=${result.amount} type=${result.type.name} '
            'category=${result.categoryId} title=${result.title} '
            'intent=${result.intent.name} date=${result.date} '
            'freq=${result.frequency?.name}';
        if (c.amount != null) {
          expect(result.amount, c.amount, reason: description);
        }
        if (c.type != null) expect(result.type, c.type, reason: description);
        if (c.category != null) {
          expect(result.categoryId, c.category, reason: description);
        }
        if (c.title != null) {
          expect(result.title, c.title, reason: description);
        }
        expect(result.intent, c.intent, reason: description);
        if (c.date != null) expect(result.date, c.date, reason: description);
        if (c.frequency != null) {
          expect(result.frequency, c.frequency, reason: description);
        }
        if (c.complete != null) {
          expect(result.isComplete, c.complete, reason: description);
        }
      });
    }
  });

  group('gyorsrögzítés – viselkedés', () {
    test('a teljes mondat azonnal könyvelhető, a hiányos nem', () {
      final full = interpretQuickEntry('lidl 4500', context);
      expect(full.isComplete, isTrue);
      expect(full.toTransaction()!.amount, 4500);
      expect(full.dateExplicit, isFalse);

      final noAmount = interpretQuickEntry('lidlben vásároltam', context);
      expect(noAmount.missing, [QuickQuestion.amount]);
      expect(noAmount.toTransaction(), isNull);

      final noWhat = interpretQuickEntry('4500', context);
      expect(noWhat.missing, [QuickQuestion.what]);
    });

    test('a korábbi tételekből tanul', () {
      final learning = QuickEntryContext(
        today: _today,
        history: [
          Transaction(
            id: 1,
            type: EntryType.expense,
            title: 'Bagett Bisztró',
            amount: 3200,
            categoryId: 'dining',
            date: CalendarDay(2026, 11, 2),
          ),
          Transaction(
            id: 2,
            type: EntryType.expense,
            title: 'Zöldséges',
            amount: 2100,
            categoryId: 'groceries',
            date: CalendarDay(2026, 11, 3),
          ),
        ],
      );
      final first = interpretQuickEntry('bagett 2900', learning);
      expect(first.categoryId, 'dining');
      expect(first.title, 'Bagett Bisztró');
      final second = interpretQuickEntry('zoldseges 1800', learning);
      expect(second.categoryId, 'groceries');
    });

    test('ismétlődő tétel szabállyá alakítható', () {
      final result = interpretQuickEntry('Netflix havi 4990', context);
      final rule = result.toRecurringRule()!;
      expect(rule.title, 'Netflix');
      expect(rule.frequency, Frequency.monthly);
      expect(rule.amount, 4990);
    });

    test('lemondásnál az érintett szabályt találja meg', () {
      final result = interpretQuickEntry('lemondtam a netflixet', context);
      expect(result.targetRule?.id, 1);
    });

    test('módosításnál a következő esedékességtől érvényes', () {
      final result = interpretQuickEntry(
        'mostantól 5490 a netflix',
        context,
      );
      expect(result.intent, QuickIntent.changeRecurring);
      expect(result.targetRule?.id, 1);
      expect(result.date, CalendarDay(2026, 12, 5));
    });
  });

  group('magyar számnevek', () {
    test('összetett számnevek', () {
      expect(parseHungarianNumberWord('ketezerotszaz'), 2500);
      expect(parseHungarianNumberWord('otszaz'), 500);
      expect(parseHungarianNumberWord('ezerketszaz'), 1200);
      expect(parseHungarianNumberWord('harmincketezer'), 32000);
      expect(parseHungarianNumberWord('masfelmillio'), 1500000);
      expect(parseHungarianNumberWord('egymillioketszazezer'), 1200000);
      expect(parseHungarianNumberWord('tizenotezer'), 15000);
      expect(parseHungarianNumberWord('huszonotezer'), 25000);
      expect(parseHungarianNumberWord('kave'), isNull);
    });
  });
}
