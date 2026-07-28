import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/core/limits.dart';
import 'package:fechai/core/utils/balance.dart';
import 'package:fechai/data/models/expense.dart';
import 'package:fechai/data/models/expense_group.dart';
import 'package:fechai/data/models/person.dart';

void main() {
  group('InterestPolicy.accrue (#2)', () {
    test('1% ao mês por 1 mês sobre 100 = 101', () {
      expect(InterestPolicy.accrue(100, 1, 1), 101.0);
    });
    test('sem juros ou sem atraso não muda', () {
      expect(InterestPolicy.accrue(100, 0, 3), 100.0);
      expect(InterestPolicy.accrue(100, 5, 0), 100.0);
    });
    test('interestOnly retorna só o acréscimo', () {
      expect(InterestPolicy.interestOnly(200, 2, 1), 4.0);
    });
    test('disclaimer vermelho já acima de 1% (#3)', () {
      expect(InterestPolicy.warnAbovePct, 1.0);
    });
  });

  group('Acerto de saldo (#4/#5)', () {
    ExpenseGroup groupWith(List<Payment> payments) => ExpenseGroup(
          id: 'g',
          name: 'Teste',
          emoji: '🏠',
          createdAt: DateTime(2026, 7, 20),
          members: const [
            Person(id: 'me', name: 'Você'),
            Person(id: 'a', name: 'Ana'),
          ],
          payments: payments,
          expenses: [
            // Você pagou 100, dividido igual → Ana deve 50 a você.
            Expense.equalSplit(
              id: 'e1',
              description: 'Conta',
              amount: 100,
              paidByPersonId: 'me',
              participantIds: const ['me', 'a'],
              date: DateTime(2026, 7, 20),
            ),
          ],
        );

    test('antes do acerto, Ana deve 50 a você', () {
      final b = BalanceCalculator.netBalances(groupWith(const []));
      expect(b['me'], 50.0);
      expect(b['a'], -50.0);
    });

    test('após Ana pagar 50, tudo zera', () {
      final g = groupWith([
        Payment(id: 'p1', fromId: 'a', toId: 'me', amount: 50, date: DateTime(2026, 7, 20)),
      ]);
      final b = BalanceCalculator.netBalances(g);
      expect(b['me'], 0.0);
      expect(b['a'], 0.0);
      expect(BalanceCalculator.simplify(g), isEmpty);
    });
  });
}
