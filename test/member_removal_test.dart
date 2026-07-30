import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/core/utils/balance.dart';
import 'package:fechai/data/models/expense.dart';
import 'package:fechai/data/models/expense_group.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/models/subscription.dart';
import 'package:fechai/core/utils/recurrence.dart';
import 'package:fechai/data/repositories/in_memory_repository.dart';
import 'package:fechai/data/repositories/providers.dart';
import 'package:fechai/features/groups/expense_sheet.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Remoção de membro com preservação de histórico.
/// - Só remove quem está zerado.
/// - Nunca teve movimentação → hard delete (some).
/// - Já teve movimentação → soft (mantém no histórico).
void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  const ana = Person(id: 'p_ana', name: 'Ana', phone: '5511911112222');
  const bruno = Person(id: 'p_bruno', name: 'Bruno', phone: '5511933334444');

  group('Modelo — activeMembers / isRemoved', () {
    final g = ExpenseGroup(
      id: 'g',
      name: 'T',
      emoji: '🏠',
      createdAt: DateTime(2026, 7, 20),
      members: const [Person(id: 'me', name: 'Você'), ana, bruno],
      expenses: const [],
      removedMemberIds: const {'p_bruno'},
    );

    test('isRemoved e activeMembers refletem o conjunto de removidos', () {
      expect(g.isRemoved('p_bruno'), isTrue);
      expect(g.isRemoved('p_ana'), isFalse);
      expect(g.activeMembers.map((m) => m.id), ['me', 'p_ana']);
      // membro removido continua acessível para resolver nomes do histórico
      expect(g.memberById('p_bruno')?.name, 'Bruno');
    });

    test('Subscription.activeMembers e filledQuotas ignoram removidos', () {
      final s = Subscription(
        id: 's',
        serviceName: 'Netflix',
        emoji: '🎬',
        totalAmount: 40,
        billingDay: 10,
        quotaCount: 4,
        monthlyInterestPct: 0,
        ownerId: 'me',
        members: const [
          SubscriptionMember(person: Person(id: 'me', name: 'Você'), quota: 10, status: QuotaStatus.paid),
          SubscriptionMember(person: ana, quota: 10, status: QuotaStatus.paid, removed: true),
        ],
      );
      expect(s.activeMembers.map((m) => m.person.id), ['me']);
      expect(s.filledQuotas, 1);
      expect(s.openQuotas, 3);
    });
  });

  group('Grupo — removeMember', () {
    test('sem envolvimento → some de vez (hard delete)', () async {
      final repo = InMemoryRepository();
      final g = await repo.createGroup(name: 'Sem histórico', emoji: '🏠', members: [ana, bruno]);
      final updated = await repo.removeMember(g.id, 'p_ana');
      expect(updated.members.any((m) => m.id == 'p_ana'), isFalse);
      expect(updated.isRemoved('p_ana'), isFalse);
    });

    test('com envolvimento + zerado → mantém histórico (soft)', () async {
      final repo = InMemoryRepository();
      final g = await repo.createGroup(name: 'Com histórico', emoji: '🏠', members: [ana]);
      // Ana pagou e só ela participou → saldo dela = 0, mas há histórico.
      await repo.addExpense(
        g.id,
        Expense.equalSplit(
          id: 'e1',
          description: 'Só da Ana',
          amount: 30,
          paidByPersonId: 'p_ana',
          participantIds: const ['p_ana'],
          date: DateTime(2026, 7, 10),
        ),
      );
      final updated = await repo.removeMember(g.id, 'p_ana');
      expect(updated.members.any((m) => m.id == 'p_ana'), isTrue, reason: 'preserva a linha');
      expect(updated.isRemoved('p_ana'), isTrue);
      expect(updated.activeMembers.any((m) => m.id == 'p_ana'), isFalse);
    });

    test('com saldo em aberto → bloqueia (erro)', () async {
      final repo = InMemoryRepository();
      final g = await repo.createGroup(name: 'Em aberto', emoji: '🏠', members: [ana]);
      // Eu paguei, dividido comigo e a Ana → Ana me deve (saldo ≠ 0).
      await repo.addExpense(
        g.id,
        Expense.equalSplit(
          id: 'e1',
          description: 'Rateado',
          amount: 40,
          paidByPersonId: 'me',
          participantIds: const ['me', 'p_ana'],
          date: DateTime(2026, 7, 10),
        ),
      );
      await expectLater(repo.removeMember(g.id, 'p_ana'), throwsA(isA<StateError>()));
    });

    test('membro removido (soft) não gera transferência no consolidado', () async {
      final repo = InMemoryRepository();
      final g = await repo.createGroup(name: 'G', emoji: '🏠', members: [ana]);
      await repo.addExpense(
        g.id,
        Expense.equalSplit(
          id: 'e1',
          description: 'Só da Ana',
          amount: 30,
          paidByPersonId: 'p_ana',
          participantIds: const ['p_ana'],
          date: DateTime(2026, 7, 10),
        ),
      );
      final updated = await repo.removeMember(g.id, 'p_ana');
      // Ana está zerada → nenhuma sugestão de acerto envolvendo-a.
      expect(BalanceCalculator.simplify(updated), isEmpty);
    });
  });

  group('Recorrência — flag de revisão ao remover', () {
    Future<ExpenseGroup> groupWithRecurring(
      InMemoryRepository repo, {
      required String paidBy,
    }) async {
      final g = await repo.createGroup(name: 'Apê', emoji: '🏢', members: [ana, bruno]);
      // Recorrência mensal dividida entre os 3; paga por [paidBy].
      await repo.addExpense(
        g.id,
        Expense.create(
          id: 'e_rec',
          description: 'Internet',
          amount: 90,
          paidByPersonId: paidBy,
          type: SplitType.equal,
          participantIds: const ['me', 'p_ana', 'p_bruno'],
          date: DateTime(2026, 7, 1),
          recurrence: Recurrence.monthly,
          recurrenceDay: 1,
        ),
      );
      // Zera o Bruno para poder removê-lo (90/3 = 30 cada).
      if (paidBy == 'p_bruno') {
        // Bruno adiantou; os outros devem 30 a ele.
        await repo.settleUp(g.id, fromId: 'me', toId: 'p_bruno', amount: 30);
        await repo.settleUp(g.id, fromId: 'p_ana', toId: 'p_bruno', amount: 30);
      } else {
        // Bruno deve 30 a quem pagou.
        await repo.settleUp(g.id, fromId: 'p_bruno', toId: paidBy, amount: 30);
      }
      return repo.groupById(g.id);
    }

    test('participante do rateio saiu → participantLeft (aviso)', () async {
      final repo = InMemoryRepository();
      final g = await groupWithRecurring(repo, paidBy: 'me');
      final updated = await repo.removeMember(g.id, 'p_bruno');
      final e = updated.expenses.firstWhere((e) => e.id == 'e_rec');
      expect(e.recurrenceReview, RecurrenceReview.participantLeft);
    });

    test('quem pagava saiu → payerLeft (bloqueia)', () async {
      final repo = InMemoryRepository();
      final g = await groupWithRecurring(repo, paidBy: 'p_bruno');
      final updated = await repo.removeMember(g.id, 'p_bruno');
      final e = updated.expenses.firstWhere((e) => e.id == 'e_rec');
      expect(e.recurrenceReview, RecurrenceReview.payerLeft);
    });

    test('editar a despesa limpa o flag', () async {
      final repo = InMemoryRepository();
      final g = await groupWithRecurring(repo, paidBy: 'me');
      await repo.removeMember(g.id, 'p_bruno');
      // Dono revisa: reedita sem o Bruno (rebuild via create → review volta a none).
      final edited = await repo.updateExpense(
        g.id,
        Expense.create(
          id: 'e_rec',
          description: 'Internet',
          amount: 60,
          paidByPersonId: 'me',
          type: SplitType.equal,
          participantIds: const ['me', 'p_ana'],
          date: DateTime(2026, 7, 1),
          recurrence: Recurrence.monthly,
          recurrenceDay: 1,
        ),
      );
      final e = edited.expenses.firstWhere((e) => e.id == 'e_rec');
      expect(e.recurrenceReview, RecurrenceReview.none);
    });
  });

  group('Geração de recorrência (Fase E, item 1)', () {
    ExpenseGroup recGroup({
      required String paidBy,
      SplitType type = SplitType.equal,
      Map<String, double> inputs = const {},
      Set<String> removed = const {},
      DateTime? until,
      int day = 1,
      RecurrenceReview review = RecurrenceReview.none,
    }) =>
        ExpenseGroup(
          id: 'g',
          name: 'Apê',
          emoji: '🏢',
          createdAt: DateTime(2026, 1, 1),
          members: const [
            Person(id: 'me', name: 'Você'),
            Person(id: 'p_ana', name: 'Ana'),
            Person(id: 'p_bruno', name: 'Bruno'),
          ],
          removedMemberIds: removed,
          expenses: [
            Expense.create(
              id: 't1',
              description: 'Internet',
              amount: 90,
              paidByPersonId: paidBy,
              type: type,
              participantIds: const ['me', 'p_ana', 'p_bruno'],
              inputs: inputs,
              date: DateTime(2026, 5, 1),
              recurrence: Recurrence.monthly,
              recurrenceDay: day,
              recurrenceUntil: until,
              recurrenceReview: review,
            ),
          ],
        );

    test('gera só o mês corrente (sem backfill) e é idempotente', () {
      final g = recGroup(paidBy: 'me');
      // molde em maio; em jul/15 gera SÓ julho (junho não é recuperado).
      final r = RecurrenceGenerator.due(g, DateTime(2026, 7, 15));
      expect(r.length, 1);
      expect(r.single.occurrencePeriod!.month, 7);
      expect(r.single.recurrenceParentId, 't1');
      // idempotente: com julho já no grupo, não gera de novo.
      final g2 = g.copyWith(expenses: [...g.expenses, ...r]);
      expect(RecurrenceGenerator.due(g2, DateTime(2026, 7, 15)), isEmpty);
    });

    test('não gera antes de vencer no mês; gera ao chegar o dia', () {
      final g = recGroup(paidBy: 'me', day: 10);
      expect(RecurrenceGenerator.due(g, DateTime(2026, 7, 5)), isEmpty);
      final r = RecurrenceGenerator.due(g, DateTime(2026, 7, 10));
      expect(r.single.occurrencePeriod!.month, 7);
    });

    test('não gera o próprio mês do molde', () {
      final g = recGroup(paidBy: 'me');
      expect(RecurrenceGenerator.due(g, DateTime(2026, 5, 20)), isEmpty);
    });

    test('exclui quem saiu e redivide igual entre os ativos', () {
      final g = recGroup(paidBy: 'me', removed: {'p_bruno'});
      final r = RecurrenceGenerator.due(g, DateTime(2026, 7, 15));
      expect(r.single.shares.containsKey('p_bruno'), isFalse);
      expect(r.single.shares['me'], 45);
      expect(r.single.shares['p_ana'], 45);
    });

    test('split não-igual: redistribui proporcional mantendo o total', () {
      // exato: me=60, ana=20, bruno=10 (total 90). Bruno sai → sobra 80 entre
      // me/ana na mesma proporção (3:1): me=67.5, ana=22.5, total = 90.
      final g = recGroup(
        paidBy: 'me',
        type: SplitType.exact,
        inputs: const {'me': 60, 'p_ana': 20, 'p_bruno': 10},
        removed: {'p_bruno'},
      );
      final r = RecurrenceGenerator.due(g, DateTime(2026, 7, 15));
      final s = r.single.shares;
      expect(s['me']! + s['p_ana']!, 90);
      expect(s['me'], 67.5);
      expect(s['p_ana'], 22.5);
    });

    test('pagador saiu (payerLeft) → bloqueia, não gera', () {
      final g = recGroup(
        paidBy: 'p_bruno',
        removed: {'p_bruno'},
        review: RecurrenceReview.payerLeft,
      );
      expect(RecurrenceGenerator.due(g, DateTime(2026, 7, 15)), isEmpty);
    });

    test('respeita recurrence_until', () {
      final g = recGroup(paidBy: 'me', until: DateTime(2026, 6, 30));
      // junho está dentro do limite → gera.
      expect(RecurrenceGenerator.due(g, DateTime(2026, 6, 15)).single.occurrencePeriod!.month, 6);
      // julho passou do limite → não gera.
      expect(RecurrenceGenerator.due(g, DateTime(2026, 7, 15)), isEmpty);
    });
  });

  group('Folha de despesa — removido não aparece no seletor', () {
    testWidgets('editar recorrência não lista quem saiu e mantém os ativos', (tester) async {
      final group = ExpenseGroup(
        id: 'g',
        name: 'Apê',
        emoji: '🏢',
        createdAt: DateTime(2026, 7, 1),
        members: const [
          Person(id: 'me', name: 'Você'),
          Person(id: 'p_ana', name: 'Ana', lastName: 'Prado'),
          Person(id: 'p_bruno', name: 'Bruno', lastName: 'Lima'),
        ],
        removedMemberIds: const {'p_bruno'},
        expenses: [
          Expense.create(
            id: 'e_rec',
            description: 'Internet',
            amount: 90,
            paidByPersonId: 'me',
            type: SplitType.equal,
            participantIds: const ['me', 'p_ana', 'p_bruno'],
            date: DateTime(2026, 7, 1),
            recurrence: Recurrence.monthly,
            recurrenceDay: 1,
            recurrenceReview: RecurrenceReview.participantLeft,
          ),
        ],
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [usedExpenseCategoriesProvider.overrideWithValue(const [])],
        child: MaterialApp(
          home: Scaffold(body: ExpenseSheet(group: group, existing: group.expenses.first)),
        ),
      ));
      await tester.pumpAndSettle();

      // Bruno (removido) não deve aparecer em lugar nenhum da folha.
      expect(find.textContaining('Bruno'), findsNothing);
      // Ativos seguem presentes (chip "Quem pagou" + linha de participante).
      expect(find.text('Você'), findsWidgets);
      expect(find.textContaining('Ana'), findsWidgets);
      // Aviso de revisão aparece.
      expect(find.textContaining('reequilibr'), findsOneWidget);
    });
  });

  group('Assinatura — removeSubscriptionMember', () {
    Future<Subscription> seed(InMemoryRepository repo, SubscriptionMember member) {
      return repo.createSubscription(Subscription(
        id: 'ignored',
        serviceName: 'Netflix',
        emoji: '🎬',
        totalAmount: 40,
        billingDay: 10,
        quotaCount: 4,
        monthlyInterestPct: 0,
        ownerId: 'me',
        members: [
          const SubscriptionMember(person: Person(id: 'me', name: 'Você'), quota: 10, status: QuotaStatus.paid),
          member,
        ],
      ));
    }

    test('convite pendente → some de vez (hard delete)', () async {
      final repo = InMemoryRepository();
      final s = await seed(repo, const SubscriptionMember(
        person: ana, quota: 10, status: QuotaStatus.pending, inviteStatus: MemberStatus.pending));
      final updated = await repo.removeSubscriptionMember(s.id, 'p_ana');
      expect(updated.members.any((m) => m.person.id == 'p_ana'), isFalse);
    });

    test('aceito + cota quitada → mantém histórico (soft)', () async {
      final repo = InMemoryRepository();
      final s = await seed(repo, const SubscriptionMember(
        person: ana, quota: 10, status: QuotaStatus.paid, inviteStatus: MemberStatus.accepted));
      final updated = await repo.removeSubscriptionMember(s.id, 'p_ana');
      final row = updated.members.firstWhere((m) => m.person.id == 'p_ana');
      expect(row.removed, isTrue);
      expect(updated.activeMembers.any((m) => m.person.id == 'p_ana'), isFalse);
    });

    test('aceito com cota em aberto → bloqueia (erro)', () async {
      final repo = InMemoryRepository();
      final s = await seed(repo, const SubscriptionMember(
        person: ana, quota: 10, status: QuotaStatus.overdue, monthsLate: 1, inviteStatus: MemberStatus.accepted));
      await expectLater(repo.removeSubscriptionMember(s.id, 'p_ana'), throwsA(isA<StateError>()));
    });
  });
}
