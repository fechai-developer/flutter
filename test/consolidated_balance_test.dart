import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/core/utils/consolidated_balance.dart';
import 'package:fechai/data/models/expense.dart';
import 'package:fechai/data/models/expense_group.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/models/subscription.dart';

void main() {
  // Mesmo Bruno em grupos diferentes tem ids de membro diferentes, mas o mesmo
  // telefone — a consolidação precisa uni-los numa só pessoa.
  ExpenseGroup groupOwesMe(String id, String memberId, double total) => ExpenseGroup(
        id: id,
        name: 'Grupo $id',
        emoji: '🏠',
        createdAt: DateTime(2026, 7, 20),
        members: [
          const Person(id: 'me', name: 'Você'),
          Person(id: memberId, name: 'Bruno', phone: '5511999998888'),
        ],
        expenses: [
          Expense.equalSplit(
            id: 'e_$id',
            description: 'Conta',
            amount: total,
            paidByPersonId: 'me',
            participantIds: ['me', memberId],
            date: DateTime(2026, 7, 20),
          ),
        ],
      );

  test('consolida a mesma pessoa (por telefone) somando vários grupos', () {
    // G1: Bruno deve 50; G2: Bruno deve 30.
    final people = ConsolidatedBalances.compute(
      [groupOwesMe('g1', 'b1', 100), groupOwesMe('g2', 'b2', 60)],
      [],
    );
    expect(people.length, 1);
    final bruno = people.first;
    expect(bruno.person.name, 'Bruno');
    expect(bruno.count, 2); // duas pendências, uma por grupo
    expect(bruno.theyOweMe, 80.0);
    expect(bruno.net, 80.0);
  });

  test('netá direções opostas (me deve x me devem) mantendo os itens separados', () {
    // Bruno me deve 50 (g1). Eu devo 20 ao Bruno (g3).
    final iOwe = ExpenseGroup(
      id: 'g3',
      name: 'Grupo g3',
      emoji: '🍺',
      createdAt: DateTime(2026, 7, 20),
      members: [
        const Person(id: 'me', name: 'Você'),
        const Person(id: 'b3', name: 'Bruno', phone: '5511999998888'),
      ],
      expenses: [
        Expense.equalSplit(
          id: 'e_g3',
          description: 'Bar',
          amount: 40,
          paidByPersonId: 'b3',
          participantIds: ['me', 'b3'],
          date: DateTime(2026, 7, 20),
        ),
      ],
    );
    final people = ConsolidatedBalances.compute([groupOwesMe('g1', 'b1', 100), iOwe], []);
    expect(people.length, 1);
    final bruno = people.first;
    expect(bruno.theyOweMe, 50.0);
    expect(bruno.iOweThem, 20.0);
    expect(bruno.net, 30.0);
    expect(bruno.count, 2);
  });

  test('inclui cota de assinatura de quem sou dono na mesma pessoa', () {
    final sub = Subscription(
      id: 's1',
      serviceName: 'Netflix',
      emoji: '🎬',
      totalAmount: 40,
      billingDay: 10,
      quotaCount: 2,
      monthlyInterestPct: 0,
      ownerId: 'me',
      members: const [
        SubscriptionMember(person: Person(id: 'me', name: 'Você'), quota: 20, status: QuotaStatus.paid),
        SubscriptionMember(
          person: Person(id: 'bsub', name: 'Bruno', phone: '5511999998888'),
          quota: 20,
          status: QuotaStatus.pending,
        ),
      ],
    );
    final people = ConsolidatedBalances.compute([groupOwesMe('g1', 'b1', 100)], [sub]);
    expect(people.length, 1);
    final bruno = people.first;
    // 50 (grupo) + 20 (cota Netflix)
    expect(bruno.theyOweMe, 70.0);
    expect(bruno.count, 2);
  });
}
