import 'package:belefer/domain/calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarDay', () {
    test('tárolási formátum oda-vissza', () {
      final day = CalendarDay(2026, 1, 31);
      expect(day.toIso(), '2026-01-31');
      expect(CalendarDay.parse('2026-01-31'), day);
    });

    test('nem létező napot nem fogad el', () {
      expect(() => CalendarDay.parse('2026-02-30'), throwsFormatException);
      expect(() => CalendarDay.parse('2026-2-3'), throwsFormatException);
    });

    test('késő esti időpont a saját napján marad', () {
      final lateEvening = DateTime(2026, 1, 31, 23, 59, 59);
      final day = CalendarDay.fromDateTime(lateEvening);
      expect(day, CalendarDay(2026, 1, 31));
      expect(day.yearMonth, const YearMonth(2026, 1));
    });

    test('szökőnap', () {
      expect(CalendarDay.parse('2028-02-29').toIso(), '2028-02-29');
      expect(const YearMonth(2028, 2).daysInMonth, 29);
      expect(const YearMonth(2026, 2).daysInMonth, 28);
    });

    test('hét napja: 2026. november 17. kedd', () {
      expect(CalendarDay(2026, 11, 17).weekday, DateTime.tuesday);
    });
  });

  group('YearMonth', () {
    test('évhatáron átlépés előre és vissza', () {
      expect(const YearMonth(2026, 12).next, const YearMonth(2027, 1));
      expect(const YearMonth(2027, 1).previous, const YearMonth(2026, 12));
    });

    test('csak a saját napjait tartalmazza', () {
      const month = YearMonth(2026, 2);
      expect(month.contains(CalendarDay(2026, 2, 1)), isTrue);
      expect(month.contains(CalendarDay(2026, 2, 28)), isTrue);
      expect(month.contains(CalendarDay(2026, 1, 31)), isFalse);
      expect(month.contains(CalendarDay(2026, 3, 1)), isFalse);
      expect(month.contains(CalendarDay(2025, 2, 10)), isFalse);
    });
  });
}
