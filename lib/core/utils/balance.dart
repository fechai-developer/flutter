import '../../data/models/expense_group.dart';

/// Uma transferência sugerida: [from] paga [amount] para [to].
class Settlement {
  final String fromPersonId;
  final String toPersonId;
  final double amount;

  const Settlement({
    required this.fromPersonId,
    required this.toPersonId,
    required this.amount,
  });
}

/// Cálculo de saldos consolidados de um grupo, com simplificação de
/// transações (quem paga pra quem) — igual ao Splitwise. PRD seção 5.2.
class BalanceCalculator {
  BalanceCalculator._();

  /// Saldo líquido por pessoa: positivo = tem a receber, negativo = deve.
  static Map<String, double> netBalances(ExpenseGroup group) {
    final balances = <String, double>{for (final m in group.members) m.id: 0.0};

    for (final e in group.expenses) {
      // quem pagou fica credor do valor total
      balances[e.paidByPersonId] = (balances[e.paidByPersonId] ?? 0) + e.amount;
      // cada um fica devedor da sua parte
      e.shares.forEach((personId, share) {
        balances[personId] = (balances[personId] ?? 0) - share;
      });
    }

    // Acertos: quem pagou (from) reduz a dívida; quem recebeu (to) reduz o crédito.
    for (final p in group.payments) {
      balances[p.fromId] = (balances[p.fromId] ?? 0) + p.amount;
      balances[p.toId] = (balances[p.toId] ?? 0) - p.amount;
    }

    // arredonda para evitar ruído de ponto flutuante
    return balances.map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(2))));
  }

  /// Minimiza o número de transferências: casa maiores credores com maiores
  /// devedores de forma gulosa.
  static List<Settlement> simplify(ExpenseGroup group) {
    final balances = netBalances(group);

    final creditors = <MapEntry<String, double>>[];
    final debtors = <MapEntry<String, double>>[];
    balances.forEach((id, value) {
      // Ex-membros são, por contrato, sempre zerados ao sair — nunca sugerimos
      // acerto de/para eles (evita saldo "fantasma" se uma despesa antiga em que
      // se envolveram for reeditada depois da saída).
      if (group.isRemoved(id)) return;
      if (value > 0.009) creditors.add(MapEntry(id, value));
      if (value < -0.009) debtors.add(MapEntry(id, -value));
    });

    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final settlements = <Settlement>[];
    int i = 0, j = 0;
    final credit = creditors.map((e) => e.value).toList();
    final debit = debtors.map((e) => e.value).toList();

    while (i < creditors.length && j < debtors.length) {
      final pay = credit[i] < debit[j] ? credit[i] : debit[j];
      final rounded = double.parse(pay.toStringAsFixed(2));
      if (rounded > 0) {
        settlements.add(Settlement(
          fromPersonId: debtors[j].key,
          toPersonId: creditors[i].key,
          amount: rounded,
        ));
      }
      credit[i] -= pay;
      debit[j] -= pay;
      if (credit[i] < 0.009) i++;
      if (debit[j] < 0.009) j++;
    }

    return settlements;
  }
}
