import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/data/models/expense.dart';

void main() {
  double sum(Map<String, double> m) =>
      double.parse(m.values.fold<double>(0, (a, b) => a + b).toStringAsFixed(2));

  group('computeShares', () {
    test('igual distribui e fecha com a sobra no primeiro', () {
      final s = computeShares(
        amount: 100,
        type: SplitType.equal,
        participantIds: ['a', 'b', 'c'],
      );
      expect(sum(s), 100.0);
      // 100/3 = 33.33 -> primeiro recebe a sobra
      expect(s['a'], 33.34);
      expect(s['b'], 33.33);
      expect(s['c'], 33.33);
    });

    test('porcentagem respeita os pesos e soma o total', () {
      final s = computeShares(
        amount: 200,
        type: SplitType.percentage,
        participantIds: ['a', 'b'],
        inputs: {'a': 25, 'b': 75},
      );
      expect(s['a'], 50.0);
      expect(s['b'], 150.0);
      expect(sum(s), 200.0);
    });

    test('partes (peso) dividem proporcionalmente', () {
      final s = computeShares(
        amount: 90,
        type: SplitType.weight,
        participantIds: ['a', 'b', 'c'],
        inputs: {'a': 1, 'b': 1, 'c': 1},
      );
      expect(sum(s), 90.0);
      expect(s['b'], 30.0);
    });

    test('peso desigual 2:1 divide 60 em 40/20', () {
      final s = computeShares(
        amount: 60,
        type: SplitType.weight,
        participantIds: ['a', 'b'],
        inputs: {'a': 2, 'b': 1},
      );
      expect(s['a'], 40.0);
      expect(s['b'], 20.0);
      expect(sum(s), 60.0);
    });

    test('valor exato usa os inputs diretamente', () {
      final s = computeShares(
        amount: 100,
        type: SplitType.exact,
        participantIds: ['a', 'b'],
        inputs: {'a': 70, 'b': 30},
      );
      expect(s['a'], 70.0);
      expect(s['b'], 30.0);
    });

    test('Expense.create resolve shares e mantém soma == amount', () {
      final e = Expense.create(
        id: 'x',
        description: 'Jantar',
        amount: 123.45,
        paidByPersonId: 'a',
        type: SplitType.percentage,
        participantIds: ['a', 'b', 'c'],
        inputs: {'a': 33.33, 'b': 33.33, 'c': 33.34},
        date: DateTime(2026, 7, 20),
      );
      expect(sum(e.shares), 123.45);
    });
  });

  group('Recorrência da despesa (dia do mês)', () {
    test('dia da recorrência sobrevive ao round-trip de JSON', () {
      final e = Expense.create(
        id: 'r',
        description: 'Aluguel',
        amount: 1000,
        paidByPersonId: 'me',
        type: SplitType.equal,
        participantIds: ['me', 'b'],
        date: DateTime(2026, 7, 20),
        recurrence: Recurrence.monthly,
        recurrenceDay: 5,
      );
      expect(e.isRecurring, isTrue);
      expect(e.recurrenceDay, 5);
      final round = Expense.fromJson(e.toJson());
      expect(round.recurrenceDay, 5);
      expect(round.recurrence, Recurrence.monthly);
    });

    test('despesa não-recorrente não guarda dia', () {
      final e = Expense.create(
        id: 'n',
        description: 'Uber',
        amount: 30,
        paidByPersonId: 'me',
        type: SplitType.equal,
        participantIds: ['me'],
        date: DateTime(2026, 7, 20),
      );
      expect(e.recurrenceDay, isNull);
      expect(Expense.fromJson(e.toJson()).recurrenceDay, isNull);
    });
  });
}
