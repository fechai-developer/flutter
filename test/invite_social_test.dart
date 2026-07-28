import 'package:flutter_test/flutter_test.dart';
import 'package:fechai/data/models/expense_group.dart';
import 'package:fechai/data/models/person.dart';
import 'package:fechai/data/models/subscription.dart';
import 'package:fechai/data/repositories/in_memory_repository.dart';

void main() {
  group('MemberStatus no grupo (Etapa C)', () {
    ExpenseGroup groupWith(Map<String, MemberStatus> status) => ExpenseGroup(
          id: 'g',
          name: 'Teste',
          emoji: '🏠',
          createdAt: DateTime(2026, 7, 20),
          members: const [
            Person(id: 'me', name: 'Você'),
            Person(id: 'p_ana', name: 'Ana'),
            Person(id: 'p_bru', name: 'Bruno'),
          ],
          expenses: const [],
          memberStatus: status,
        );

    test('membro sem registro é considerado aceito', () {
      final g = groupWith(const {});
      expect(g.isAccepted('p_ana'), isTrue);
      expect(g.statusOf('p_ana'), MemberStatus.accepted);
    });

    test('"me" é sempre aceito na própria visão', () {
      final g = groupWith(const {'me': MemberStatus.pending});
      expect(g.isAccepted('me'), isTrue);
    });

    test('pendente e recusado contam como não-aceitos', () {
      final g = groupWith(const {
        'p_ana': MemberStatus.pending,
        'p_bru': MemberStatus.declined,
      });
      expect(g.isPending('p_ana'), isTrue);
      expect(g.notAccepted('p_ana'), isTrue);
      expect(g.isDeclined('p_bru'), isTrue);
      expect(g.notAccepted('p_bru'), isTrue);
      expect(g.isAccepted('p_ana'), isFalse);
    });
  });

  group('inviteStatus da assinatura (Etapa C)', () {
    test('accepted é o padrão', () {
      const m = SubscriptionMember(person: Person(id: 'p', name: 'X'), quota: 10);
      expect(m.inviteAccepted, isTrue);
      expect(m.invitePending, isFalse);
      expect(m.inviteDeclined, isFalse);
    });

    test('getters derivam do enum', () {
      const m = SubscriptionMember(
        person: Person(id: 'p', name: 'X'),
        quota: 10,
        inviteStatus: MemberStatus.declined,
      );
      expect(m.inviteAccepted, isFalse);
      expect(m.inviteDeclined, isTrue);
    });
  });

  group('Ciclo de convite no InMemoryRepository (itens 5/6)', () {
    test('recusar mantém o convite listado como declined; aceitar o remove', () async {
      final repo = InMemoryRepository();
      final before = await repo.pendingInvites();
      expect(before, isNotEmpty);
      final groupInvite = before.firstWhere((i) => i.kind == 'group');
      expect(groupInvite.status, MemberStatus.pending);

      // Recusar: continua na lista, agora como recusado (pode aceitar depois).
      await repo.declineInvite(groupInvite);
      final afterDecline = await repo.pendingInvites();
      final declined = afterDecline.firstWhere((i) => i.membershipId == groupInvite.membershipId);
      expect(declined.status, MemberStatus.declined);
      expect(declined.isDeclined, isTrue);

      // Aceitar (mesmo tendo recusado antes): sai da lista de convites.
      await repo.acceptInvite(declined);
      final afterAccept = await repo.pendingInvites();
      expect(afterAccept.any((i) => i.membershipId == groupInvite.membershipId), isFalse);
    });

    test('o seed já traz um convite recusado para demonstrar o estado', () async {
      final repo = InMemoryRepository();
      final invites = await repo.pendingInvites();
      expect(invites.any((i) => i.isDeclined), isTrue);
    });
  });
}
