import '../../data/models/expense_group.dart';
import '../../data/models/person.dart';
import '../../data/models/subscription.dart';
import 'balance.dart';

/// Uma pendência individual que compõe o saldo com uma pessoa. Guarda o que é
/// preciso para **acertar** aquela origem (grupo ou assinatura) isoladamente.
class DebtItem {
  final String sourceId; // id do grupo ou da assinatura
  final String sourceName; // nome exibido (grupo/serviço)
  final bool isSubscription;
  final double amount; // sempre positivo
  final bool theyOweMe; // true: a pessoa me deve; false: eu devo a ela
  final String otherId; // id da contraparte NAQUELA origem (para settleUp do grupo)
  final String? quotaPersonId; // assinatura: de quem é a cota a marcar como paga
  final bool overdue;

  const DebtItem({
    required this.sourceId,
    required this.sourceName,
    required this.isSubscription,
    required this.amount,
    required this.theyOweMe,
    required this.otherId,
    this.quotaPersonId,
    this.overdue = false,
  });
}

/// Saldo consolidado com UMA pessoa, somando pendências de todos os grupos e
/// assinaturas. É a base da tela "Acertar" (quitação de uma vez só).
class PersonBalance {
  final Person person; // representa a contraparte (nome/telefone p/ exibir e cobrar)
  final List<DebtItem> items;
  const PersonBalance({required this.person, required this.items});

  double get theyOweMe =>
      _round(items.where((i) => i.theyOweMe).fold(0.0, (a, i) => a + i.amount));
  double get iOweThem =>
      _round(items.where((i) => !i.theyOweMe).fold(0.0, (a, i) => a + i.amount));
  double get net => _round(theyOweMe - iOweThem);
  bool get hasOverdue => items.any((i) => i.overdue);
  int get count => items.length;

  static double _round(double v) => double.parse(v.toStringAsFixed(2));
}

/// Consolida os saldos por pessoa a partir de todos os grupos e assinaturas.
/// Usa a mesma simplificação de transferências dos grupos (me ↔ pessoa) e
/// agrupa a MESMA pessoa entre origens pelo telefone (fallback: nome).
class ConsolidatedBalances {
  ConsolidatedBalances._();

  static List<PersonBalance> compute(
    List<ExpenseGroup> groups,
    List<Subscription> subs,
  ) {
    final builders = <String, _Builder>{};
    _Builder builderFor(Person p) {
      final key = (p.phone != null && p.phone!.trim().isNotEmpty)
          ? 'ph:${p.phone}'
          : 'nm:${p.fullName.toLowerCase()}';
      return builders.putIfAbsent(key, () => _Builder(p));
    }

    // ---- Grupos: pega as transferências simplificadas que me envolvem ----
    for (final g in groups) {
      for (final s in BalanceCalculator.simplify(g)) {
        if (s.toPersonId == 'me') {
          final other = g.memberById(s.fromPersonId);
          if (other != null) {
            builderFor(other).items.add(DebtItem(
                  sourceId: g.id,
                  sourceName: g.name,
                  isSubscription: false,
                  amount: s.amount,
                  theyOweMe: true,
                  otherId: other.id,
                ));
          }
        } else if (s.fromPersonId == 'me') {
          final other = g.memberById(s.toPersonId);
          if (other != null) {
            builderFor(other).items.add(DebtItem(
                  sourceId: g.id,
                  sourceName: g.name,
                  isSubscription: false,
                  amount: s.amount,
                  theyOweMe: false,
                  otherId: other.id,
                ));
          }
        }
      }
    }

    // ---- Assinaturas ----
    for (final sub in subs) {
      if (sub.ownerId == 'me') {
        // Sou dono: cada cota não paga é uma pessoa que me deve. Ex-participantes
        // (removidos) não entram — já estavam quitados ao sair.
        for (final m in sub.activeMembers) {
          if (m.person.id == 'me' || m.status == QuotaStatus.paid) continue;
          builderFor(m.person).items.add(DebtItem(
                sourceId: sub.id,
                sourceName: sub.serviceName,
                isSubscription: true,
                amount: m.amountDue(sub.monthlyInterestPct),
                theyOweMe: true,
                otherId: m.person.id,
                quotaPersonId: m.person.id,
                overdue: m.status == QuotaStatus.overdue,
              ));
        }
      } else {
        // Sou participante: se minha cota não está paga, devo ao dono. Se fui
        // removido, não apareço em activeMembers → nenhuma pendência.
        final mine = sub.activeMembers.where((m) => m.person.id == 'me');
        final owner = sub.activeMembers.where((m) => m.person.id == sub.ownerId);
        if (mine.isNotEmpty && owner.isNotEmpty && mine.first.status != QuotaStatus.paid) {
          final m = mine.first;
          builderFor(owner.first.person).items.add(DebtItem(
                sourceId: sub.id,
                sourceName: sub.serviceName,
                isSubscription: true,
                amount: m.amountDue(sub.monthlyInterestPct),
                theyOweMe: false,
                otherId: owner.first.person.id,
                quotaPersonId: 'me',
                overdue: m.status == QuotaStatus.overdue,
              ));
        }
      }
    }

    final result = builders.values
        .map((b) => PersonBalance(person: b.person, items: b.items))
        .where((pb) => pb.items.isNotEmpty && pb.net.abs() > 0.009)
        .toList();

    // Atrasos primeiro; depois maior saldo absoluto.
    result.sort((a, b) {
      if (a.hasOverdue != b.hasOverdue) return a.hasOverdue ? -1 : 1;
      return b.net.abs().compareTo(a.net.abs());
    });
    return result;
  }
}

class _Builder {
  final Person person;
  final List<DebtItem> items = [];
  _Builder(this.person);
}
