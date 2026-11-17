import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/formatting.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/validation.dart';
import 'package:belefer/ui/entry_form/amount_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('magyar formázás', () {
    test('forint hármas csoportokkal, nem törhető szóközzel', () {
      expect(formatForint(0), '0 Ft');
      expect(formatForint(999), '999 Ft');
      expect(formatForint(124500), '124 500 Ft');
      expect(formatForint(1234567), '1 234 567 Ft');
    });

    test('előjeles forint', () {
      expect(formatForint(-12500), '−12 500 Ft');
      expect(formatForint(312000, signed: true), '+312 000 Ft');
      expect(formatForint(0, signed: true), '0 Ft');
    });

    test('százalék tizedesvesszővel', () {
      expect(formatPercentTenths(1000), '100%');
      expect(formatPercentTenths(0), '0%');
      expect(formatPercentTenths(452), '45,2%');
      expect(formatPercentTenths(5), '0,5%');
    });

    test('dátumok és hónapok', () {
      expect(formatYearMonth(const YearMonth(2026, 11)), '2026. november');
      expect(formatYearMonth(const YearMonth(2027, 1)), '2027. január');
      expect(
        formatFullDate(CalendarDay(2026, 11, 17)),
        '2026. november 17., kedd',
      );
      expect(formatDayHeading(CalendarDay(2026, 3, 1)), 'március 1., vasárnap');
    });
  });

  group('közös mezőszabályok', () {
    test('megnevezés kötelező és korlátos hosszú', () {
      expect(EntryRules.validateTitle(''), isNotNull);
      expect(EntryRules.validateTitle('   '), isNotNull);
      expect(EntryRules.validateTitle('Lakbér'), isNull);
      expect(EntryRules.validateTitle('x' * 41), isNotNull);
    });

    test('tételnél kötelező, sablonnál elhagyható összeg', () {
      expect(EntryRules.validateAmount('', required: true), isNotNull);
      expect(EntryRules.validateAmount('', required: false), isNull);
      expect(EntryRules.validateAmount('0', required: false), isNotNull);
      expect(EntryRules.validateAmount('124 500', required: true), isNull);
      expect(
        EntryRules.validateAmount('1234567890', required: true),
        isNotNull,
      );
      expect(EntryRules.parseAmount('124 500'), 124500);
      expect(EntryRules.parseAmount(''), isNull);
      expect(EntryRules.parseAmount('0'), isNull);
    });

    test('kategória csak a típusához tartozhat', () {
      expect(EntryRules.validateCategory(null, EntryType.expense), isNotNull);
      expect(EntryRules.validateCategory('housing', EntryType.expense), isNull);
      expect(EntryRules.validateCategory('salary', EntryType.expense), isNotNull);
      expect(EntryRules.validateCategory('salary', EntryType.income), isNull);
    });

    test('üres megjegyzésből nem lesz tárolt szöveg', () {
      expect(EntryRules.normalizeNote('  '), isNull);
      expect(EntryRules.normalizeNote(' közös ebéd '), 'közös ebéd');
    });
  });

  group('összegmező formázója', () {
    const formatter = AmountInputFormatter();

    TextEditingValue type(String oldText, String newText, [int? cursor]) {
      return formatter.formatEditUpdate(
        TextEditingValue(
          text: oldText,
          selection: TextSelection.collapsed(offset: oldText.length),
        ),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: cursor ?? newText.length),
        ),
      );
    }

    test('csoportosít és csak számjegyet enged', () {
      expect(type('12 450', '12 4500').text, '124 500');
      expect(type('', 'a1b2').text, '12');
      expect(type('', '007').text, '7');
    });

    test('kilenc számjegynél hosszabbat nem enged', () {
      const full = '999 999 999';
      expect(type(full, '${full}9').text, full);
    });

    test('elválasztó törlésekor az előtte álló számjegy törlődik', () {
      // „1 234” → a szóköz törlése után „234”.
      final result = type('1 234', '1234', 1);
      expect(result.text, '234');
    });
  });
}
