import 'package:belefer/domain/calendar.dart';
import 'package:belefer/domain/models.dart';
import 'package:belefer/domain/quick_entry/interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final history = [
    Transaction(
      type: EntryType.expense,
      title: 'Lidl',
      amount: 4500,
      categoryId: 'groceries',
      date: CalendarDay(2026, 11, 3),
    ),
    Transaction(
      type: EntryType.expense,
      title: 'MOL',
      amount: 20000,
      categoryId: 'transport',
      date: CalendarDay(2026, 10, 12),
    ),
    Transaction(
      type: EntryType.income,
      title: 'Fizetés',
      amount: 450000,
      categoryId: 'salary',
      date: CalendarDay(2026, 11, 5),
    ),
  ];
  final context = QuickEntryContext(
    today: CalendarDay(2026, 11, 20),
    history: history,
  );
  String? answer(String text) => interpretQuickEntry(text, context).answer;

  test('költés, bevétel és maradék a hónapban', () {
    expect(
      answer('mennyit költöttem ebben a hónapban?'),
      'Novemberben eddig 4 500 Ft ment el.',
    );
    expect(answer('mennyi maradt?'), contains('445 500 Ft maradt'));
    expect(
      answer('mennyi volt a bevételem novemberben?'),
      'Novemberben eddig 450 000 Ft jött be.',
    );
  });

  test('múlt hónap és kategória', () {
    expect(
      answer('mennyi ment el benzinre a múlt hónapban'),
      'Októberben (Közlekedés) 20 000 Ft ment el.',
    );
  });

  test('súgókérdés', () {
    expect(answer('hogyan tudok sablont létrehozni?'), startsWith('Sablont'));
  });
}
