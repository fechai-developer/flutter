import 'package:flutter_test/flutter_test.dart';

import 'package:fechai/data/models/caixinha.dart';
import 'package:fechai/data/models/expense.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/repositories/in_memory_repository.dart';

/// Desfazer pelo histórico (item 1): acerto de conta e movimentações da
/// caixinha não têm tela de edição — quando saem errados ("marquei que paguei
/// sem querer"), o dono apaga o lançamento e a situação volta ao que era.
void main() {
  const ana = Person(id: 'ana', name: 'Ana', phone: '11999990001');

  group('Conta — desfazer acerto', () {
    test('acerto desfeito some do histórico e a dívida reaparece', () async {
      final repo = InMemoryRepository();
      var g = await repo.createGroup(name: 'Viagem', emoji: '🏖️', members: [ana]);
      final anaId = g.members.firstWhere((m) => m.id != 'me').id;

      g = await repo.addExpense(
        g.id,
        Expense.equalSplit(
          id: 'e1',
          description: 'Hotel',
          amount: 200,
          paidByPersonId: 'me',
          date: DateTime(2026, 1, 5),
          participantIds: ['me', anaId],
        ),
      );

      g = await repo.settleUp(g.id, fromId: anaId, toId: 'me', amount: 100);
      expect(g.payments, hasLength(1));

      g = await repo.undoPayment(g.id, g.payments.first.id);
      expect(g.payments, isEmpty, reason: 'o acerto sai do extrato');
      // A despesa segue lá — desfazer o acerto não mexe no que foi gasto.
      expect(g.expenses, hasLength(1));
    });

    test('desfazer um acerto não derruba os outros', () async {
      final repo = InMemoryRepository();
      var g = await repo.createGroup(name: 'Rep', emoji: '🏠', members: [ana]);
      final anaId = g.members.firstWhere((m) => m.id != 'me').id;

      g = await repo.settleUp(g.id, fromId: anaId, toId: 'me', amount: 50);
      g = await repo.settleUp(g.id, fromId: anaId, toId: 'me', amount: 70);
      final alvo = g.payments.first.id;

      g = await repo.undoPayment(g.id, alvo);
      expect(g.payments, hasLength(1));
      expect(g.payments.single.id, isNot(alvo));
    });
  });

  group('Caixinha — desfazer movimentação', () {
    Future<(InMemoryRepository, Caixinha)> nova() async {
      final repo = InMemoryRepository();
      final c = await repo.createCaixinha(
        name: 'Família',
        emoji: '🐷',
        defaultInterestPct: 1,
        monthlyQuota: 100,
        members: [ana],
      );
      return (repo, c);
    }

    test('aporte desfeito sai do histórico e do patrimônio', () async {
      final (repo, c0) = await nova();
      var c = await repo.addContribution(c0.id, personId: 'me', amount: 500, date: DateTime(2026, 1, 10));
      expect(c.patrimony, 500);

      final mov = c.movements.single;
      expect(mov.kind, MovementKind.contribution);

      c = await repo.undoMovement(c.id, kind: mov.kind, sourceId: mov.sourceId);
      expect(c.movements, isEmpty);
      expect(c.patrimony, 0);
    });

    test('rendimento desfeito devolve o patrimônio, preservando os aportes', () async {
      final (repo, c0) = await nova();
      var c = await repo.addContribution(c0.id, personId: 'me', amount: 1000, date: DateTime(2026, 1, 10));
      c = await repo.addEarning(c.id, amount: 80, source: EarningSource.investment, date: DateTime(2026, 1, 31));
      expect(c.patrimony, 1080);

      final rendimento = c.movements.firstWhere((m) => m.kind == MovementKind.earning);
      c = await repo.undoMovement(c.id, kind: rendimento.kind, sourceId: rendimento.sourceId);

      expect(c.patrimony, 1000);
      expect(c.movements, hasLength(1));
      expect(c.movements.single.kind, MovementKind.contribution);
    });

    test('ajuste manual desfeito volta o saldo ao que era', () async {
      final (repo, c0) = await nova();
      var c = await repo.addContribution(c0.id, personId: 'me', amount: 300, date: DateTime(2026, 1, 10));
      c = await repo.adjustBalance(c.id, 'me', delta: -50, note: 'errei', date: DateTime(2026, 1, 12));
      expect(c.patrimony, 250);

      final ajuste = c.movements.firstWhere((m) => m.kind == MovementKind.adjustment);
      c = await repo.undoMovement(c.id, kind: ajuste.kind, sourceId: ajuste.sourceId);
      expect(c.patrimony, 300);
    });

    test('saída desfeita traz o participante de volta', () async {
      final (repo, c0) = await nova();
      final anaId = c0.members.firstWhere((m) => m.person.id != 'me').person.id;
      var c = await repo.addContribution(c0.id, personId: anaId, amount: 400, date: DateTime(2026, 1, 10));

      c = await repo.exitMember(c.id, anaId, refund: 400);
      expect(c.exits, hasLength(1));
      expect(c.patrimony, 0);

      final saida = c.movements.firstWhere((m) => m.kind == MovementKind.exit);
      c = await repo.undoMovement(c.id, kind: saida.kind, sourceId: saida.sourceId);

      expect(c.exits, isEmpty);
      expect(c.patrimony, 400, reason: 'a pessoa volta com a posição que tinha');
    });

    test('cada movimentação carrega o id do lançamento de origem', () async {
      final (repo, c0) = await nova();
      var c = await repo.addContribution(c0.id, personId: 'me', amount: 100, date: DateTime(2026, 1, 5));
      c = await repo.addEarning(c.id, amount: 10, source: EarningSource.investment, date: DateTime(2026, 1, 6));

      final ids = c.movements.map((m) => m.sourceId).toList();
      expect(ids.every((id) => id.isNotEmpty), isTrue);
      expect(ids.toSet(), hasLength(ids.length), reason: 'ids não se repetem entre lançamentos');
      expect(ids, contains(c.contributions.single.id));
      expect(ids, contains(c.earnings.single.id));
    });
  });
}
